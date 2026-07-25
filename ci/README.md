# CI/CD Integration — AirGap DevKit

This directory contains configuration and integration scripts for running the devkit through Jenkins, GitLab CI/CD, and the Atlassian suite.

---

## Pipeline Files

| File | Platform | Location |
|------|----------|----------|
| `Jenkinsfile` | Jenkins | repo root |
| `.gitlab-ci.yml` | GitLab | repo root |

Both pipelines implement the same logical stages and expose the same set of configurable options. Choose whichever platform your team uses.

---

## Stages (both platforms)

```
Validate → Configure → Install → Server Operations → Smoke Tests → Atlassian
```

| Stage | What it does |
|-------|-------------|
| **Validate** | Checks all `devkit.json` + `manifest.json` files for syntax and required fields |
| **Configure** | Patches `devkit.config.json` with pipeline parameters (team, profile, port, etc.) |
| **Install** | Runs `scripts/internal/install-cli.sh --yes --profile <PROFILE>` on Linux and/or Windows agents |
| **Server Operations** | Starts the devkit server, pushes team identity via API, handles package uploads / team config import-export |
| **Smoke Tests** | Runs `tests/run-tests.sh` to verify all installed tools are functional |
| **Atlassian** | Posts build results to Jira issue; overwrites Confluence status page |

---

## Key Configurable Options

All options are exposed as Jenkins parameters or GitLab CI variables and can be set per-run via the GUI or API.

| Option | Default | Description |
|--------|---------|-------------|
| `PROFILE` | `minimal` | Install profile: `minimal`, `cpp-dev`, `devops`, `full` |
| `TARGET_OS` | `linux` | `linux`, `windows`, or `both` |
| `TEAM_NAME` | `My Team` | Written to the devkit UI config |
| `UPLOAD_PACKAGE` | `false` | Upload a `.zip` bundle to the running server |
| `EXPORT_TEAM_CONFIG` | `false` | Archive the current team config as a build artifact |
| `IMPORT_TEAM_CONFIG` | _(blank)_ | Paste `team-config.json` JSON to import into the server |
| `SAVE_PROFILE_JSON` | _(blank)_ | JSON to create/update a custom install profile |
| `ATLASSIAN_UPDATE` | `false` | Push build status to Jira + Confluence |

---

## Directory Layout

```
ci/
├── README.md                       ← this file
├── build.sh                        ← build the Go server binary
├── test.sh                         ← run manifest validation suite
├── lint.sh                         ← syntax-check all shell scripts
├── release.sh                      ← thin wrapper around scripts/internal/release.sh
├── smoke.sh                        ← server health check (used by ci.yml)
├── Dockerfile.linux-test           ← RHEL/Rocky 8/9/10 (UBI) integration test image
├── jenkins/
│   └── SETUP.md                    ← Jenkins setup instructions + parameter reference
├── gitlab/
│   └── SETUP.md                    ← GitLab CI/CD setup instructions + variable reference
└── atlassian/
    ├── README.md                   ← Atlassian integration guide
    ├── atlassian.config.json       ← Config template (fill in, do NOT commit secrets)
    ├── jira-update.sh              ← Posts build result to a Jira issue
    └── confluence-update.sh        ← Overwrites a Confluence page with status table
```

---

## Quick Start

### Jenkins

1. Create a **Pipeline** job pointing at this repo
2. Run once to seed parameters, then use **Build with Parameters**
3. See [jenkins/SETUP.md](jenkins/SETUP.md)

### GitLab

1. Register a runner with tag `linux`
2. Go to **CI/CD → Pipelines → Run pipeline** and add variable overrides
3. See [gitlab/SETUP.md](gitlab/SETUP.md)

### Atlassian

1. Generate an API token at id.atlassian.com
2. Add `ATLASSIAN_BASE_URL`, `ATLASSIAN_USER_EMAIL`, `ATLASSIAN_API_TOKEN` as secrets
3. Set `ATLASSIAN_UPDATE=true` and supply `JIRA_ISSUE_KEY` / `CONFLUENCE_PAGE_ID` at run time
4. See [atlassian/README.md](atlassian/README.md)

---

## Triggering via API

### Jenkins
```bash
curl -X POST "https://jenkins.example.com/job/airgap-devkit/buildWithParameters" \
  --user "user:api-token" \
  --data "PROFILE=cpp-dev&TEAM_NAME=Backend+Team&ATLASSIAN_UPDATE=true&JIRA_ISSUE_KEY=DEVKIT-42"
```

### GitLab
```bash
curl -X POST "https://gitlab.example.com/api/v4/projects/PROJECT_ID/trigger/pipeline" \
  --form "token=TRIGGER_TOKEN" --form "ref=main" \
  --form "variables[PROFILE]=cpp-dev" \
  --form "variables[TEAM_NAME]=Backend Team"
```
