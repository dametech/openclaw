# Container Tools Requirements

Comprehensive list of tools needed in the OpenClaw container, based on audit of all `dametech` repos (64 repos) and agent roles.

## Already in Container

| Tool | Version | Notes |
|------|---------|-------|
| git | 2.39.5 | ✅ |
| node | 24.14.0 | ✅ |
| npm | 11.9.0 | ✅ |
| python3 | 3.11.2 | ✅ |
| curl | 7.88.1 | ✅ |
| wget | 1.21.3 | ✅ |
| ssh | OpenSSH | ✅ |
| make | 4.3 | ✅ |
| gcc/g++ | 12.2.0 | ✅ |

## Required Tools

### Tier 1: Essential (needed by most agents)

| Tool | Why | Used by |
|------|-----|---------|
| **go** | 24 repos are Go — largest language in the org | Sanjay, Eddie, Jett, Davo |
| **gh** | GitHub CLI — PRs, issues, CI, code review | All dev agents |
| **jq** | JSON processing — used everywhere | All agents |
| **yq** | YAML processing — K8s manifests, Helm values | Davo, all devs |
| **kubectl** | Kubernetes management | Davo, Sanjay, Mia (deployments) |
| **helm** | K8s package management | Davo |
| **aws** | AWS CLI — Lambda, S3, CloudFormation, IAM | Sanjay, Davo |
| **op** | 1Password CLI — secrets management | All agents (via Claw) |
| **pip3** | Python package manager | All Python agents |

### Tier 2: Important (needed for specific workflows)

| Tool | Why | Used by |
|------|-----|---------|
| **terraform** | 2 HCL repos (vpp-infra, fortigate-tf) | Davo |
| **kustomize** | K8s manifest management | Davo |
| **docker** | Container builds (if building in-cluster) | Davo |
| **protoc** | gRPC/protobuf (braiinsgrpcclient) | Jett |
| **golangci-lint** | Go linting | All Go developers |
| **pytest** | Python testing | All Python developers |
| **eslint/prettier** | TypeScript/JS linting | Mia |

### Tier 3: Nice to have

| Tool | Why | Used by |
|------|-----|---------|
| **argocd** | GitOps CLI (if using ArgoCD) | Davo |
| **flux** | GitOps CLI (if using Flux) | Davo |
| **k9s** | K8s terminal UI | Davo |
| **stern** | Multi-pod log tailing | Davo |
| **grpcurl** | gRPC debugging | Eddie, Jett |
| **mosquitto_pub/sub** | MQTT testing | Eddie |
| **modbus CLI tools** | Modbus debugging | Eddie |
| **jupyter** | Notebook support (3 repos) | Sanjay |
| **java/maven** | Voltron repo (1 Java repo) | Sanjay |
| **dart** | openclaw_client (sinkers repo) | Not needed in container |

## Language Breakdown (dametech org)

```
Go                  24 repos  ██████████████████████████████  37%
Python              14 repos  █████████████████               22%
TypeScript           4 repos  █████                            6%
Jupyter Notebook     3 repos  ████                             5%
Shell                3 repos  ████                             5%
HCL (Terraform)      2 repos  ███                              3%
Smarty               2 repos  ███                              3%
Java                 1 repo   █                                2%
C++                  1 repo   █                                2%
Dockerfile           1 repo   █                                2%
HTML                 1 repo   █                                2%
unknown              8 repos  ██████████                      12%
```

## Recommended Init Container Script

```bash
#!/bin/sh
set -e

TOOLS_DIR="${1:-/tools}"
mkdir -p "$TOOLS_DIR"
ARCH="amd64"

echo "Installing tools to $TOOLS_DIR..."

# Go
GO_VERSION="1.22.5"
wget -qO- "https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz" | tar xz -C "$TOOLS_DIR"
ln -sf "$TOOLS_DIR/go/bin/go" "$TOOLS_DIR/go-bin"

# GitHub CLI
GH_VERSION="2.62.0"
wget -qO- "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${ARCH}.tar.gz" | tar xz -C "$TOOLS_DIR"
ln -sf "$TOOLS_DIR/gh_${GH_VERSION}_linux_${ARCH}/bin/gh" "$TOOLS_DIR/gh"

# kubectl
KUBECTL_VERSION="v1.33.0"
wget -qO "$TOOLS_DIR/kubectl" "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl"
chmod +x "$TOOLS_DIR/kubectl"

# Helm
HELM_VERSION="v3.17.0"
wget -qO- "https://get.helm.sh/helm-${HELM_VERSION}-linux-${ARCH}.tar.gz" | tar xz -C "$TOOLS_DIR" --strip-components=1 linux-${ARCH}/helm

# AWS CLI
wget -qO "/tmp/awscliv2.zip" "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
unzip -qo /tmp/awscliv2.zip -d /tmp
/tmp/aws/install --install-dir "$TOOLS_DIR/aws-cli" --bin-dir "$TOOLS_DIR"
rm -rf /tmp/aws /tmp/awscliv2.zip

# 1Password CLI
OP_VERSION="2.30.3"
wget -qO- "https://cache.agilebits.com/dist/1P/op2/pkg/v${OP_VERSION}/op_linux_${ARCH}_v${OP_VERSION}.zip" > /tmp/op.zip
unzip -qo /tmp/op.zip -d "$TOOLS_DIR" op
chmod +x "$TOOLS_DIR/op"
rm /tmp/op.zip

# jq
JQ_VERSION="1.7.1"
wget -qO "$TOOLS_DIR/jq" "https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-${ARCH}"
chmod +x "$TOOLS_DIR/jq"

# yq
YQ_VERSION="v4.44.6"
wget -qO "$TOOLS_DIR/yq" "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${ARCH}"
chmod +x "$TOOLS_DIR/yq"

# Terraform
TF_VERSION="1.10.3"
wget -qO "/tmp/terraform.zip" "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_${ARCH}.zip"
unzip -qo /tmp/terraform.zip -d "$TOOLS_DIR"
rm /tmp/terraform.zip

# kustomize
KUSTOMIZE_VERSION="v5.5.0"
wget -qO- "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize/${KUSTOMIZE_VERSION}/kustomize_${KUSTOMIZE_VERSION}_linux_${ARCH}.tar.gz" | tar xz -C "$TOOLS_DIR"

# golangci-lint
GOLINT_VERSION="v1.62.2"
wget -qO- "https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh" | sh -s -- -b "$TOOLS_DIR" "$GOLINT_VERSION"

echo "All tools installed to $TOOLS_DIR"
ls -la "$TOOLS_DIR"
```

## Helm Values for Init Container

```yaml
app-template:
  controllers:
    main:
      initContainers:
        init-tools:
          image:
            repository: alpine
            tag: "3.20"
          command: ['sh', '-c']
          args:
            - |
              apk add --no-cache wget unzip
              /scripts/install-tools.sh /home/node/.openclaw/tools
          volumeMounts:
            - name: data
              mountPath: /home/node/.openclaw
            - name: scripts
              mountPath: /scripts
      containers:
        main:
          env:
            - name: PATH
              value: "/home/node/.openclaw/tools:/home/node/.openclaw/tools/go/bin:/usr/local/bin:/usr/bin:/bin"
            - name: GOPATH
              value: "/home/node/.openclaw/go"
            - name: XDG_CONFIG_HOME
              value: "/home/node/.openclaw"
```

## Alternative: Custom Docker Image

For faster startup (no download on every pod creation):

```dockerfile
FROM ghcr.io/openclaw/openclaw:latest

USER root

# System packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    jq unzip zip \
    python3-pip python3-venv \
    protobuf-compiler \
    && rm -rf /var/lib/apt/lists/*

# Go
ARG GO_VERSION=1.22.5
RUN wget -qO- https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz | tar xz -C /usr/local
ENV PATH="/usr/local/go/bin:${PATH}"

# GitHub CLI
ARG GH_VERSION=2.62.0
RUN wget -qO- https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz \
    | tar xz -C /usr/local --strip-components=1

# kubectl
ARG KUBECTL_VERSION=v1.33.0
RUN wget -qO /usr/local/bin/kubectl https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl \
    && chmod +x /usr/local/bin/kubectl

# Helm
ARG HELM_VERSION=v3.17.0
RUN wget -qO- https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz \
    | tar xz -C /usr/local/bin --strip-components=1 linux-amd64/helm

# AWS CLI
RUN wget -qO /tmp/awscliv2.zip https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip \
    && unzip -qo /tmp/awscliv2.zip -d /tmp && /tmp/aws/install && rm -rf /tmp/aws*

# 1Password CLI
ARG OP_VERSION=2.30.3
RUN wget -qO /tmp/op.zip https://cache.agilebits.com/dist/1P/op2/pkg/v${OP_VERSION}/op_linux_amd64_v${OP_VERSION}.zip \
    && unzip -qo /tmp/op.zip -d /usr/local/bin op && chmod +x /usr/local/bin/op && rm /tmp/op.zip

# yq
ARG YQ_VERSION=v4.44.6
RUN wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64 \
    && chmod +x /usr/local/bin/yq

# Terraform
ARG TF_VERSION=1.10.3
RUN wget -qO /tmp/tf.zip https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_amd64.zip \
    && unzip -qo /tmp/tf.zip -d /usr/local/bin && rm /tmp/tf.zip

# kustomize
ARG KUSTOMIZE_VERSION=v5.5.0
RUN wget -qO- https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize/${KUSTOMIZE_VERSION}/kustomize_${KUSTOMIZE_VERSION}_linux_amd64.tar.gz \
    | tar xz -C /usr/local/bin

# golangci-lint
RUN wget -qO- https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b /usr/local/bin v1.62.2

USER node
```

## TODO

- [ ] Decide: init container vs custom image (trade-off: startup time vs image build pipeline)
- [ ] Test init container script in staging
- [ ] Set up container image CI/CD if going custom image route
- [ ] Add Python dev tools (pytest, black, mypy, ruff) via pip in container
- [ ] Add Node.js dev tools (eslint, prettier, typescript) via npm
- [ ] Evaluate Java/Maven need (only 1 repo — `voltron`)
- [ ] Add container image version to deployment docs
