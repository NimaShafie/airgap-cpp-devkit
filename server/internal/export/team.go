package export

import (
	"encoding/json"
	"time"
)

// ProfileExport mirrors api.Profile but lives in this package to avoid circular imports.
type ProfileExport struct {
	ID          string   `json:"id"`
	Name        string   `json:"name"`
	Description string   `json:"description"`
	ToolIDs     []string `json:"tool_ids"`
	Color       string   `json:"color"`
}

type TeamConfig struct {
	ExportedAt string                   `json:"exported_at"`
	TeamName   string                   `json:"team_name"`
	OrgName    string                   `json:"org_name"`
	DevkitName string                   `json:"devkit_name"`
	Profile    string                   `json:"profile"`
	ToolIDs    []string                 `json:"tool_ids"`
	Prefix     string                   `json:"prefix"`
	Profiles   map[string]ProfileExport `json:"profiles,omitempty"`
}

func Build(teamName, orgName, devkitName, profile string, toolIDs []string, prefix string, profiles map[string]ProfileExport) TeamConfig {
	return TeamConfig{
		ExportedAt: time.Now().UTC().Format(time.RFC3339),
		TeamName:   teamName,
		OrgName:    orgName,
		DevkitName: devkitName,
		Profile:    profile,
		ToolIDs:    toolIDs,
		Prefix:     prefix,
		Profiles:   profiles,
	}
}

func Marshal(tc TeamConfig) ([]byte, error) {
	return json.MarshalIndent(tc, "", "  ")
}

func Unmarshal(data []byte) (TeamConfig, error) {
	var tc TeamConfig
	err := json.Unmarshal(data, &tc)
	return tc, err
}
