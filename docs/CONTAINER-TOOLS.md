# Container Dev Tools

## Problem

The OpenClaw container runs with a **read-only root filesystem** (good security practice), which means we can't `apt-get install` or drop binaries into `/usr/local/bin` at runtime. But agents need dev tools — `kubectl`, `helm`, `go`, `gh`, `aws`, `terraform`, etc.

## Solution: Init Container + PVC

We use a Kubernetes init container to install tools to the **PVC-backed** `~/.openclaw/` directory before the main container starts.

### Why init container over custom image?

| Factor | Init Container | Custom Image |
|--------|---------------|--------------|
| Time to ship | Minutes (Helm values change) | Hours (Dockerfile, CI/CD, registry) |
| Startup time | ~60-90s first run, ~5s cached | Instant (baked in) |
| Maintenance | Update version pins in script | Rebuild + push image |
| Image size | Base image unchanged | Larger image |
| Flexibility | Per-deploy tool selection | Fixed at build time |
| CI/CD needed | No | Yes (image build pipeline) |

**Decision: Init container.** Pod restarts are rare, tools are cached on PVC (only re-downloaded on version bumps), and we avoid maintaining a custom image build pipeline.

If startup time becomes critical later, we can migrate to a custom image — the tool list and version pins are already documented.

## Architecture

```
Pod Start
  │
  ├─ init-dev-tools (debian:bookworm-slim)
  │    ├─ Reads install-dev-tools.sh from ConfigMap
  │    ├─ Checks .tool-versions/ markers on PVC
  │    ├─ Downloads only missing/outdated tools
  │    └─ Writes to PVC: bin/, tools/, .tool-versions/
  │
  └─ main (openclaw container)
       ├─ PATH includes ~/.openclaw/bin
       ├─ GOPATH = ~/.openclaw/go
       └─ GOROOT = ~/.openclaw/tools/go
```

### PVC Layout

```
~/.openclaw/
├── bin/                    # Single-binary tools (kubectl, helm, jq, etc.)
│   ├── kubectl
│   ├── helm
│   ├── gh
│   ├── jq
│   ├── yq
│   ├── terraform
│   ├── kustomize
│   ├── op
│   ├── go -> ../tools/go/bin/go
│   ├── gofmt -> ../tools/go/bin/gofmt
│   ├── aws (symlink from AWS CLI installer)
│   └── ... (existing: git-askpass.sh, git-password.sh, jira-api.sh)
├── tools/                  # Multi-file tool installations
│   ├── go/                 # Go SDK
│   └── aws-cli/            # AWS CLI v2
├── .tool-versions/         # Version markers (for idempotent installs)
│   ├── kubectl.version     # Contains "1.33.0"
│   ├── helm.version        # Contains "3.17.3"
│   └── ...
├── go/                     # GOPATH (module cache, built binaries)
├── workspace-*/            # Agent workspaces (UNTOUCHED)
├── openclaw.json           # Config (UNTOUCHED)
└── ...
```

**PVC safety:** The script writes ONLY to `bin/`, `tools/`, and `.tool-versions/`. It never modifies agent workspaces, configs, or session data.

## Tools Installed

| Tool | Version | Size (approx) | Purpose |
|------|---------|---------------|---------|
| go | 1.24.1 | ~500MB (SDK) | 24 Go repos in the org |
| gh | 2.69.0 | ~50MB | GitHub CLI for PRs, issues |
| kubectl | 1.33.0 | ~50MB | Kubernetes cluster management |
| helm | 3.17.3 | ~50MB | Kubernetes package manager |
| aws | v2 (latest) | ~200MB | AWS Lambda, IAM, etc. |
| op | 2.30.3 | ~30MB | 1Password credential injection |
| jq | 1.7.1 | ~2MB | JSON processing |
| yq | 4.45.1 | ~10MB | YAML processing |
| terraform | 1.11.3 | ~80MB | Infrastructure as Code |
| kustomize | 5.6.0 | ~20MB | Kubernetes manifest customization |

**Total: ~1GB** on PVC (7.5GB free currently)

## Files

| File | Purpose |
|------|---------|
| `scripts/install-dev-tools.sh` | Init container installation script |
| `helm/values-dev-tools.yaml` | Helm values overlay for the init container |
| `docs/CONTAINER-TOOLS.md` | This document |

## Deployment

### Option A: Merge into deploy script

Update `openclaw-deploy.sh` to include the dev tools values:

```bash
helm upgrade openclaw openclaw-community/openclaw \
    --namespace openclaw \
    --values /tmp/openclaw-values.yaml \
    --values helm/values-dev-tools.yaml \
    --set-file 'app-template.configMaps.dev-tools-script.data.install-dev-tools\.sh=scripts/install-dev-tools.sh'
```

### Option B: Separate overlay

Apply as an additional values file without modifying the base deploy:

```bash
helm upgrade openclaw openclaw-community/openclaw \
    --namespace openclaw \
    --reuse-values \
    --values helm/values-dev-tools.yaml \
    --set-file 'app-template.configMaps.dev-tools-script.data.install-dev-tools\.sh=scripts/install-dev-tools.sh'
```

## Updating Tool Versions

1. Edit version pins in `scripts/install-dev-tools.sh`
2. Commit and push
3. Restart the pod (or `kubectl rollout restart deployment/openclaw -n openclaw`)
4. Init container detects version mismatch via `.tool-versions/` markers and re-downloads

## Testing Locally

You can test the install script in a Docker container:

```bash
docker run --rm -v /tmp/test-pvc:/data debian:bookworm-slim bash -c \
    "apt-get update -qq && apt-get install -y -qq curl unzip tar gzip && \
     bash /dev/stdin < scripts/install-dev-tools.sh"
ls -la /tmp/test-pvc/bin/
```

## Future Considerations

- **Custom image:** If pod startup time becomes a problem, bake tools into a custom image. The version pins and tool list here serve as the Dockerfile spec.
- **Java/Maven/Gradle:** Not included in initial rollout (only 1 Java repo). Add when needed.
- **Python pip:** Already available in base image as `python3`. Add `pip3` if Python package management is needed.
- **Tool-specific config:** `kubectl` needs kubeconfig, `aws` needs credentials, `op` needs service account token — those are separate from tool installation.
