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
