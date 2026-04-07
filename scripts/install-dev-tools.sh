#!/bin/bash
#
# install-dev-tools.sh — Init container script for OpenClaw dev tools
#
# Installs development tools to the PVC-backed bin directory so they
# persist across container restarts and survive read-only root filesystems.
#
# Usage: Run as an init container with the PVC mounted at /data
#   The main container should have ~/.openclaw/bin on its PATH.
#
# Tools installed:
#   - go (Go compiler + toolchain)
#   - gh (GitHub CLI)
#   - kubectl (Kubernetes CLI)
#   - helm (Kubernetes package manager)
#   - aws (AWS CLI v2)
#   - op (1Password CLI)
#   - jq (JSON processor)
#   - yq (YAML processor)
#   - terraform (Infrastructure as Code)
#   - kustomize (Kubernetes manifest customization)
#   - codex (OpenAI Codex CLI for AI-assisted coding)
#
# Version pinning: Update the variables below to change versions.
# Architecture: x86_64 (amd64) — update if running on ARM.
#

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────
INSTALL_DIR="/data/bin"
TOOLS_DIR="/data/tools"       # For tools that need more than a single binary (Go, AWS CLI)
MARKER_DIR="/data/.tool-versions"
ARCH="amd64"
OS="linux"

# ── Version Pins ───────────────────────────────────────────────────
GO_VERSION="1.24.1"
GH_VERSION="2.69.0"
KUBECTL_VERSION="1.34.6"
HELM_VERSION="3.17.3"
AWS_CLI_VERSION="2.34.12"     # AWS CLI v2 (pinned)
OP_VERSION="2.30.3"
JQ_VERSION="1.7.1"
YQ_VERSION="4.45.1"
TERRAFORM_VERSION="1.11.3"
KUSTOMIZE_VERSION="5.6.0"

# ── Helpers ────────────────────────────────────────────────────────
log() { echo "[init-tools] $(date -u +%H:%M:%S) $*"; }

need_install() {
    local tool="$1" version="$2"
    local marker="$MARKER_DIR/${tool}.version"
    if [ -f "$marker" ] && [ "$(cat "$marker")" = "$version" ]; then
        return 1  # Already installed at this version
    fi
    return 0
}

mark_installed() {
    local tool="$1" version="$2"
    mkdir -p "$MARKER_DIR"
    echo "$version" > "$MARKER_DIR/${tool}.version"
}

# ── Setup ──────────────────────────────────────────────────────────
mkdir -p "$INSTALL_DIR" "$TOOLS_DIR" "$MARKER_DIR"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

log "Starting dev tools installation to $INSTALL_DIR"
log "Temp dir: $TMPDIR"

# ── jq ─────────────────────────────────────────────────────────────
if need_install jq "$JQ_VERSION"; then
    log "Installing jq $JQ_VERSION..."
    curl -fsSL "https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-${OS}-${ARCH}" \
        -o "$INSTALL_DIR/jq"
    chmod +x "$INSTALL_DIR/jq"
    mark_installed jq "$JQ_VERSION"
    log "jq $JQ_VERSION ✓"
else
    log "jq $JQ_VERSION already installed, skipping"
fi

# ── yq ─────────────────────────────────────────────────────────────
if need_install yq "$YQ_VERSION"; then
    log "Installing yq $YQ_VERSION..."
    curl -fsSL "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_${OS}_${ARCH}" \
        -o "$INSTALL_DIR/yq"
    chmod +x "$INSTALL_DIR/yq"
    mark_installed yq "$YQ_VERSION"
    log "yq $YQ_VERSION ✓"
else
    log "yq $YQ_VERSION already installed, skipping"
fi

# ── kubectl ────────────────────────────────────────────────────────
if need_install kubectl "$KUBECTL_VERSION"; then
    log "Installing kubectl $KUBECTL_VERSION..."
    curl -fsSL "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/${OS}/${ARCH}/kubectl" \
        -o "$INSTALL_DIR/kubectl"
    chmod +x "$INSTALL_DIR/kubectl"
    mark_installed kubectl "$KUBECTL_VERSION"
    log "kubectl $KUBECTL_VERSION ✓"
else
    log "kubectl $KUBECTL_VERSION already installed, skipping"
fi

# ── helm ───────────────────────────────────────────────────────────
if need_install helm "$HELM_VERSION"; then
    log "Installing helm $HELM_VERSION..."
    curl -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-${OS}-${ARCH}.tar.gz" \
        | tar -xzf - -O "${OS}-${ARCH}/helm" > "$INSTALL_DIR/helm"
    chmod +x "$INSTALL_DIR/helm"
    mark_installed helm "$HELM_VERSION"
    log "helm $HELM_VERSION ✓"
else
    log "helm $HELM_VERSION already installed, skipping"
fi

# ── gh (GitHub CLI) ────────────────────────────────────────────────
if need_install gh "$GH_VERSION"; then
    log "Installing gh $GH_VERSION..."
    curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_${OS}_${ARCH}.tar.gz" \
        | tar -xzf - -O "gh_${GH_VERSION}_${OS}_${ARCH}/bin/gh" > "$INSTALL_DIR/gh"
    chmod +x "$INSTALL_DIR/gh"
    mark_installed gh "$GH_VERSION"
    log "gh $GH_VERSION ✓"
else
    log "gh $GH_VERSION already installed, skipping"
fi

# ── Go ─────────────────────────────────────────────────────────────
if need_install go "$GO_VERSION"; then
    log "Installing Go $GO_VERSION..."
    curl -fsSL "https://go.dev/dl/go${GO_VERSION}.${OS}-${ARCH}.tar.gz" \
        | tar -xzf - -C "$TOOLS_DIR"
    # Symlink the go and gofmt binaries
    ln -sf "$TOOLS_DIR/go/bin/go" "$INSTALL_DIR/go"
    ln -sf "$TOOLS_DIR/go/bin/gofmt" "$INSTALL_DIR/gofmt"
    mark_installed go "$GO_VERSION"
    log "Go $GO_VERSION ✓"
else
    log "Go $GO_VERSION already installed, skipping"
fi

# ── terraform ──────────────────────────────────────────────────────
if need_install terraform "$TERRAFORM_VERSION"; then
    log "Installing terraform $TERRAFORM_VERSION..."
    curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_${OS}_${ARCH}.zip" \
        -o "$TMPDIR/terraform.zip"
    (cd "$TMPDIR" && unzip -q terraform.zip)
    mv "$TMPDIR/terraform" "$INSTALL_DIR/terraform"
    chmod +x "$INSTALL_DIR/terraform"
    mark_installed terraform "$TERRAFORM_VERSION"
    log "terraform $TERRAFORM_VERSION ✓"
else
    log "terraform $TERRAFORM_VERSION already installed, skipping"
fi

# ── kustomize ──────────────────────────────────────────────────────
if need_install kustomize "$KUSTOMIZE_VERSION"; then
    log "Installing kustomize $KUSTOMIZE_VERSION..."
    curl -fsSL "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_${OS}_${ARCH}.tar.gz" \
        | tar -xzf - -O "kustomize" > "$INSTALL_DIR/kustomize"
    chmod +x "$INSTALL_DIR/kustomize"
    mark_installed kustomize "$KUSTOMIZE_VERSION"
    log "kustomize $KUSTOMIZE_VERSION ✓"
else
    log "kustomize $KUSTOMIZE_VERSION already installed, skipping"
fi

# ── 1Password CLI (op) ────────────────────────────────────────────
if need_install op "$OP_VERSION"; then
    log "Installing 1Password CLI $OP_VERSION..."
    curl -fsSL "https://cache.agilebits.com/dist/1P/op2/pkg/v${OP_VERSION}/op_${OS}_${ARCH}_v${OP_VERSION}.zip" \
        -o "$TMPDIR/op.zip"
    (cd "$TMPDIR" && unzip -q op.zip)
    mv "$TMPDIR/op" "$INSTALL_DIR/op"
    chmod +x "$INSTALL_DIR/op"
    mark_installed op "$OP_VERSION"
    log "op $OP_VERSION ✓"
else
    log "op $OP_VERSION already installed, skipping"
fi

# ── AWS CLI v2 ─────────────────────────────────────────────────────
if need_install aws "$AWS_CLI_VERSION"; then
    log "Installing AWS CLI v2..."
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-${OS}-x86_64-${AWS_CLI_VERSION}.zip" \
        -o "$TMPDIR/awscliv2.zip"
    (cd "$TMPDIR" && unzip -q awscliv2.zip)
    # Clean previous install to avoid --update ambiguity
    rm -rf "$TOOLS_DIR/aws-cli"
    "$TMPDIR/aws/install" --install-dir "$TOOLS_DIR/aws-cli" --bin-dir "$INSTALL_DIR"
    mark_installed aws "$AWS_CLI_VERSION"
    log "AWS CLI v2 ✓"
else
    log "AWS CLI v2 already installed, skipping"
fi

# ── OpenAI Codex CLI ───────────────────────────────────────────────
CODEX_VERSION="0.115.0"
if need_install codex "$CODEX_VERSION"; then
    log "Installing OpenAI Codex CLI $CODEX_VERSION..."
    NPM_PREFIX="$TOOLS_DIR/npm-global"
    mkdir -p "$NPM_PREFIX"
    npm install -g "@openai/codex@$CODEX_VERSION" --prefix "$NPM_PREFIX" 2>&1 | tail -1
    ln -sf "$NPM_PREFIX/bin/codex" "$INSTALL_DIR/codex"
    mark_installed codex "$CODEX_VERSION"
    log "Codex CLI $CODEX_VERSION ✓"
else
    log "Codex CLI $CODEX_VERSION already installed, skipping"
fi

# ── Summary ────────────────────────────────────────────────────────
log ""
log "Installation complete. Installed versions:"
shopt -s nullglob
for marker in "$MARKER_DIR"/*.version; do
    tool=$(basename "$marker" .version)
    version=$(cat "$marker")
    log "  $tool: $version"
done
shopt -u nullglob

log ""
log "Tools directory: $INSTALL_DIR"
log "Ensure PATH includes $INSTALL_DIR in the main container."
log "Done."
