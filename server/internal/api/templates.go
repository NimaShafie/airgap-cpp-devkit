package api

import (
	"encoding/json"
	"html/template"
	"io/fs"
	"net/http"
	"strings"

	"golang.org/x/text/cases"
	"golang.org/x/text/language"
)

var baseFuncMap = template.FuncMap{
	"lower":      strings.ToLower,
	"title":      cases.Title(language.English).String,
	"join":       strings.Join,
	"hasPrefix":  strings.HasPrefix,
	"trimPrefix": strings.TrimPrefix,
	"toJSON": func(v any) template.JS {
		b, err := json.Marshal(v)
		if err != nil {
			return template.JS("null")
		}
		s := strings.ReplaceAll(string(b), "</", `<\/`)
		// json.Marshal escapes <, >, & but leaves the U+2028/U+2029 line
		// separators, which terminate a JS string literal in older engines and
		// can break out of a <script> context. Escape them to their JS unicode
		// form so the embedded JSON stays inside its string literal.
		s = strings.ReplaceAll(s, " ", `\u2028`)
		s = strings.ReplaceAll(s, " ", `\u2029`)
		return template.JS(s)
	},
}

func renderTemplate(webFS fs.FS, name string, w http.ResponseWriter, r *http.Request, data any) error {
	nonce := nonceFromCtx(r.Context())
	fm := template.FuncMap{}
	for k, v := range baseFuncMap {
		fm[k] = v
	}
	fm["nonce"] = func() string { return nonce }

	tmpl, err := template.New(name).Funcs(fm).ParseFS(webFS, "templates/"+name)
	if err != nil {
		return err
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	return tmpl.Execute(w, data)
}
