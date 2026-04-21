package tools

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

type Tool struct {
	ID           string   `json:"id"`
	Name         string   `json:"name"`
	Version      string   `json:"version"`
	Category     string   `json:"category"`
	Platform     string   `json:"platform"`
	Description  string   `json:"description"`
	Setup        string   `json:"setup"`
	ReceiptName  string   `json:"receipt_name"`
	CheckCmd     string   `json:"check_cmd"`
	Estimate     string   `json:"estimate"`
	UsesPrebuilt bool     `json:"uses_prebuilt"`
	SortOrder    int      `json:"sort_order"`
	SetupArgs    []string `json:"setup_args"`
	VersionLabel string   `json:"version_label"`
	Source       string   `json:"source"`
	UploadedBy   string   `json:"uploaded_by,omitempty"`
	UploadedAt   string   `json:"uploaded_at,omitempty"`
	Homepage     string   `json:"homepage,omitempty"`
	License      string   `json:"license,omitempty"`
	GithubRepo   string   `json:"github_repo,omitempty"`
	AssetMatch   string   `json:"asset_match,omitempty"`
}

var scanPatterns = []struct {
	glob   string
	source string
}{
	{"tools/dev-tools/*/devkit.json", "builtin"},
	{"tools/dev-tools/*/*/devkit.json", "builtin"},
	{"tools/build-tools/*/devkit.json", "builtin"},
	{"tools/languages/*/devkit.json", "builtin"},
	{"tools/toolchains/*/devkit.json", "builtin"},
	{"tools/toolchains/*/*/devkit.json", "builtin"},
	{"tools/toolchains/*/*/*/devkit.json", "builtin"},
	{"tools/frameworks/*/devkit.json", "builtin"},
	{"packages/*/devkit.json", "builtin"},
	{"user-packages/*/devkit.json", "user"},
}

func Load(repoRoot string) ([]Tool, error) {
	var tools []Tool
	seen := map[string]bool{}

	for _, pat := range scanPatterns {
		matches, err := filepath.Glob(filepath.Join(repoRoot, filepath.FromSlash(pat.glob)))
		if err != nil {
			continue
		}
		sort.Strings(matches)
		for _, path := range matches {
			data, err := os.ReadFile(path)
			if err != nil {
				fmt.Fprintf(os.Stderr, "[devkit] warning: cannot read %s: %v\n", path, err)
				continue
			}
			var t Tool
			if err := json.Unmarshal(data, &t); err != nil {
				fmt.Fprintf(os.Stderr, "[devkit] warning: cannot parse %s: %v\n", path, err)
				continue
			}
			if t.ID == "" || seen[t.ID] {
				continue
			}
			seen[t.ID] = true

			// Resolve setup path relative to the devkit.json directory
			if t.Setup != "" {
				abs := filepath.Join(filepath.Dir(path), t.Setup)
				rel, err := filepath.Rel(repoRoot, abs)
				if err == nil {
					t.Setup = filepath.ToSlash(rel)
				}
			}
			t.Source = pat.source
			if t.Platform == "" {
				t.Platform = "both"
			}
			if t.Category == "" {
				t.Category = "Developer Tools"
			}
			if t.Estimate == "" {
				t.Estimate = "~1min"
			}
			if t.ReceiptName == "" {
				t.ReceiptName = t.ID
			}
			if t.SetupArgs == nil {
				t.SetupArgs = []string{}
			}
			tools = append(tools, t)
		}
	}

	sort.Slice(tools, func(i, j int) bool {
		if tools[i].SortOrder != tools[j].SortOrder {
			return tools[i].SortOrder < tools[j].SortOrder
		}
		if tools[i].Category != tools[j].Category {
			return tools[i].Category < tools[j].Category
		}
		return strings.ToLower(tools[i].Name) < strings.ToLower(tools[j].Name)
	})
	return tools, nil
}
