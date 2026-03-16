# Team Definition

Define the agent team that should be provisioned on a fresh OpenClaw deployment.

## TODO

- [ ] Create a declarative team definition format (YAML/JSON) that describes:
  - Agent ID, display name, emoji
  - Role description and specialisations
  - SOUL.md personality/operating principles
  - Required skills and tool access
  - GitHub repos they need access to
  - Slack app configuration
  - Model preferences (e.g. Opus for deep work, Sonnet for fast tasks)
- [ ] Build a provisioning script that reads the team definition and:
  - Creates all agents and workspaces
  - Generates workspace files (SOUL.md, IDENTITY.md, AGENTS.md, USER.md)
  - Creates Slack apps via Manifest API
  - Outputs install links for the manual OAuth/token steps
  - Wires Slack accounts and bindings into openclaw.json
  - Sets up git identities and credential access
  - Configures coding standards in each workspace
  - Runs verification (clone test, Slack probe)
- [ ] Support incremental updates (add/remove agents without rebuilding everything)
- [ ] Support team export (dump current running team to definition format)

## Proposed Format

```yaml
# team.yaml
team:
  domain: example.com          # Email domain for git identities
  github:
    orgs: [myorg]              # GitHub orgs agents can access
    users: [myuser]            # GitHub user repos agents can access
  
  coding_standards:
    branch_only: true
    pr_required: true
    reviewer: gemini
    ci_must_pass: true
    coverage_never_decreases: true

  agents:
    - id: devops
      name: Davo
      emoji: "⎈"
      role: DevOps specialist
      description: "Kubernetes, Helm, Terraform, CI/CD pipelines"
      skills:
        - kubernetes
        - terraform
        - ci-cd
      model: anthropic/claude-opus-4-6
      repos:              # Optional: restrict to specific repos
        - myorg/infra
        - myorg/deployments

    - id: backend
      name: Sanjay
      emoji: "🔧"
      role: Backend cloud developer
      description: "Go and Python on AWS Lambdas, serverless architecture"
      skills:
        - go
        - python
        - aws
      repos: all          # Access to all repos

    - id: frontend
      name: Mia
      emoji: "🎨"
      role: Frontend developer
      description: "React, TypeScript, admin UIs, dashboards"
      skills:
        - react
        - typescript
        - ui-design
      repos: all
```

## Provisioning Flow

```
team.yaml → provision.sh → Running agent team
                │
                ├── Create OpenClaw agents
                ├── Generate workspace files
                ├── Create Slack apps (API)
                ├── Output: manual token steps
                ├── Wire config + bindings
                ├── Setup git access
                └── Verify all agents
```

## Notes

- Slack app creation via API requires a config token (`xoxe.xoxp-...`)
- Slack app install + token generation still requires manual UI steps (Slack limitation)
- The provisioning script should be idempotent — safe to re-run
- Team definition should live in this repo as the source of truth
- On container restart, the PVC retains agent state, but a fresh deploy needs reprovisioning

## Skills & Tools TODO

Each integration should ideally be packaged as an OpenClaw skill for clean, reusable access across agents.

### Current integrations and skill status

| Integration | Current Setup | Skill Available | TODO |
|-------------|--------------|-----------------|------|
| **GitHub** | HTTPS + PAT + wrapper | ✅ `github` + `gh-issues` (bundled, needs `gh` CLI) | Install `gh` CLI, configure auth, enable skill |
| **Jira** | API token + `jira-api.sh` wrapper | ❌ None bundled | Create `jira` skill (based on `trello` skill pattern) |
| **Slack** | Socket Mode per agent | ✅ `slack` (bundled) | Already active |
| **1Password** | Not yet deployed | ✅ `1password` (bundled) | Deploy when secrets migration happens |

### Best practices for skills vs tools

**Use a skill when:**
- The integration has a well-defined API or CLI
- Multiple agents need the same access pattern
- You want structured instructions the model can follow (e.g. "create a Jira issue with these fields")
- The skill can be shared across agents via `~/.openclaw/skills/`

**Use raw exec/wrapper when:**
- It's a one-off script or quick automation
- The integration is simple enough that a wrapper script suffices
- You're prototyping before packaging as a proper skill

**Skill distribution:**
- **Per-agent skills:** `<workspace>/skills/` — only that agent sees them
- **Shared skills:** `~/.openclaw/skills/` — all agents on the instance
- **Bundled skills:** Ship with OpenClaw — always available
- **ClawHub:** Public registry at https://clawhub.com — install with `clawhub install <slug>`

### Action items

- [ ] **GitHub skill:** Install `gh` CLI in container, run `gh auth login` with PAT, enable bundled `github` skill
- [ ] **Jira skill:** Author a `jira` skill (model: REST API via curl, similar to bundled `trello` skill). Publish to ClawHub if generic enough.
- [ ] **1Password skill:** Enable bundled skill when secrets management is deployed
- [ ] **AWS skill:** Evaluate need — Sanjay works heavily with AWS. Check if a skill exists or create one.
- [ ] **Kubernetes skill:** Evaluate need — Davo works with K8s. `kubectl` is likely enough but a skill could add structured guidance.
- [ ] **EdgeX skill:** Create for Eddie — structured guidance for EdgeX Foundry API, device profiles, Modbus config.
