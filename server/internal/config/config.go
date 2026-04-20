package config

import (
	"encoding/json"
	"os"
	"path/filepath"
)

type Config struct {
	TeamName       string `json:"team_name"`
	OrgName        string `json:"org_name"`
	DevkitName     string `json:"devkit_name"`
	ThemeColor     string `json:"theme_color"`
	DashboardTitle string `json:"dashboard_title"`
	Hostname       string `json:"hostname"`
	Port           int    `json:"port"`
	DefaultProfile string `json:"default_profile"`
}

func Load(repoRoot string) Config {
	cfg := Config{
		TeamName:       "My Team",
		OrgName:        "",
		DevkitName:     "AirGap DevKit",
		ThemeColor:     "#2563eb",
		DashboardTitle: "Tool Dashboard",
		Hostname:       "127.0.0.1",
		Port:           8080,
		DefaultProfile: "minimal",
	}
	path := filepath.Join(repoRoot, "devkit.config.json")
	data, err := os.ReadFile(path)
	if err != nil {
		return cfg
	}
	_ = json.Unmarshal(data, &cfg)
	return cfg
}

func Save(repoRoot string, cfg Config) error {
	path := filepath.Join(repoRoot, "devkit.config.json")
	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0o644)
}
