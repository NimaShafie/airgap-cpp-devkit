package api

import (
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
)

type Layout struct {
	CategoryOrder []string            `json:"category_order"`
	CategoryNames map[string]string   `json:"category_names"`
	ToolOrder     map[string][]string `json:"tool_order"`
}

func (s *Server) layoutPath() string {
	return filepath.Join(s.RepoRoot, "layout.json")
}

func emptyLayout() Layout {
	return Layout{
		CategoryOrder: []string{},
		CategoryNames: map[string]string{},
		ToolOrder:     map[string][]string{},
	}
}

func (s *Server) handleGetLayout(w http.ResponseWriter, r *http.Request) {
	data, err := os.ReadFile(s.layoutPath())
	if err != nil {
		jsonOK(w, emptyLayout())
		return
	}
	var l Layout
	if json.Unmarshal(data, &l) != nil {
		jsonOK(w, emptyLayout())
		return
	}
	if l.CategoryOrder == nil {
		l.CategoryOrder = []string{}
	}
	if l.CategoryNames == nil {
		l.CategoryNames = map[string]string{}
	}
	if l.ToolOrder == nil {
		l.ToolOrder = map[string][]string{}
	}
	jsonOK(w, l)
}

func (s *Server) handleSaveLayout(w http.ResponseWriter, r *http.Request) {
	var l Layout
	if err := json.NewDecoder(r.Body).Decode(&l); err != nil {
		jsonErr(w, "invalid layout", 400)
		return
	}
	for cat, ids := range l.ToolOrder {
		var kept []string
		for _, id := range ids {
			if t, ok := s.findTool(id); !ok || t.Source != "user" {
				kept = append(kept, id)
			}
		}
		l.ToolOrder[cat] = kept
	}
	data, _ := json.MarshalIndent(l, "", "  ")
	if err := os.WriteFile(s.layoutPath(), data, 0o600); err != nil {
		jsonErr(w, err.Error(), 500)
		return
	}
	jsonOK(w, map[string]any{"ok": true})
}

func (s *Server) handleResetLayout(w http.ResponseWriter, r *http.Request) {
	_ = os.Remove(s.layoutPath())
	jsonOK(w, map[string]any{"ok": true})
}
