# OpenClaw PVC Backup — Restore Runbook

## Overview

Agent PVC data is backed up daily at **02:00 UTC** to:

```
s3://dame-openclaw-backup/openclaw-backups/au01-0/<agent>/<agent>/<timestamp>.tar.gz
```

Each agent has its own backup path:

| Agent | S3 Prefix |
|-------|-----------|
| openclaw | `openclaw-backups/au01-0/openclaw/openclaw/` |
| oc-marc | `openclaw-backups/au01-0/oc-marc/oc-marc/` |
| oc-sm | `openclaw-backups/au01-0/oc-sm/oc-sm/` |

Backups contain `~/.openclaw/` excluding: `bin`, `tools`, `go`, `node_modules`, `.cache`, `chromium`, `sessions`, `.tool-versions`.

---

## Prerequisites

- `kubectl` access to the `au01-0` cluster (`openclaw` namespace)
- AWS credentials with read access to `dame-openclaw-backup` bucket
- Target agent pod running (PVC must be mounted)

---

## Step 1 — Identify the backup to restore

```bash
# List available backups for an agent (e.g. openclaw)
aws s3 ls s3://dame-openclaw-backup/openclaw-backups/au01-0/openclaw/openclaw/ \
  --region ap-southeast-2 | sort

# Pick the most recent or a specific timestamp
# Example: 2026-04-07T030154Z.tar.gz
```

---

## Step 2 — Scale down the agent (prevent data corruption)

```bash
kubectl scale deployment openclaw -n openclaw --replicas=0
# Wait for pod to terminate
kubectl wait --for=delete pod -l app.kubernetes.io/name=openclaw -n openclaw --timeout=60s
```

Repeat for other agents as needed (`oc-marc`, `oc-sm`).

---

## Step 3 — Run a restore job

Spin up a temporary pod with the agent's PVC mounted and restore from S3:

```bash
BACKUP_KEY="openclaw-backups/au01-0/openclaw/openclaw/2026-04-07T030154Z.tar.gz"
AGENT="openclaw"

kubectl run restore-${AGENT} \
  --image=amazon/aws-cli:latest \
  --restart=Never \
  --rm -it \
  --overrides="{
    \"spec\": {
      \"volumes\": [{
        \"name\": \"data\",
        \"persistentVolumeClaim\": {\"claimName\": \"${AGENT}-data\"}
      }],
      \"containers\": [{
        \"name\": \"restore\",
        \"image\": \"amazon/aws-cli:latest\",
        \"command\": [\"/bin/sh\", \"-c\"],
        \"args\": [\"aws s3 cp s3://dame-openclaw-backup/${BACKUP_KEY} /tmp/backup.tar.gz --region ap-southeast-2 && cd /data && tar -xzf /tmp/backup.tar.gz --strip-components=3 && echo DONE\"],
        \"env\": [
          {\"name\": \"AWS_ACCESS_KEY_ID\", \"valueFrom\": {\"secretKeyRef\": {\"name\": \"openclaw-backup-aws\", \"key\": \"AWS_ACCESS_KEY_ID\"}}},
          {\"name\": \"AWS_SECRET_ACCESS_KEY\", \"valueFrom\": {\"secretKeyRef\": {\"name\": \"openclaw-backup-aws\", \"key\": \"AWS_SECRET_ACCESS_KEY\"}}}
        ],
        \"volumeMounts\": [{\"name\": \"data\", \"mountPath\": \"/data\"}]
      }]
    }
  }" -n openclaw
```

> **Note:** The tar archive is rooted at `home/node/.openclaw/` (3 components). Adjust `--strip-components` if the path differs — verify with `tar -tzf backup.tar.gz | head`.

---

## Step 4 — Scale the agent back up

```bash
kubectl scale deployment openclaw -n openclaw --replicas=1
kubectl rollout status deployment/openclaw -n openclaw
```

---

## Step 5 — Verify

```bash
# Check the pod is healthy
kubectl get pods -n openclaw

# Tail logs to confirm agent started cleanly
kubectl logs -n openclaw deployment/openclaw -f --tail=50
```

---

## Quick restore (exec into existing pod)

If the pod is still running and you only need to restore specific files:

```bash
# Download backup to pod
kubectl exec -n openclaw deployment/openclaw -- \
  aws s3 cp s3://dame-openclaw-backup/openclaw-backups/au01-0/openclaw/openclaw/2026-04-07T030154Z.tar.gz \
  /tmp/backup.tar.gz --region ap-southeast-2

# Preview contents
kubectl exec -n openclaw deployment/openclaw -- \
  tar -tzf /tmp/backup.tar.gz | head -30

# Extract specific files (e.g. workspace)
kubectl exec -n openclaw deployment/openclaw -- \
  tar -xzf /tmp/backup.tar.gz -C / --strip-components=2 home/node/.openclaw/workspace-openclaw
```

---

## Triggering a manual backup

```bash
# Run the backup dispatcher job now
kubectl create job manual-backup-$(date +%s) \
  --from=cronjob/openclaw-pvc-backup-dispatcher \
  -n openclaw

# Watch progress
kubectl get jobs -n openclaw --sort-by=.metadata.creationTimestamp -w
```

---

## Troubleshooting

| Symptom | Check |
|---------|-------|
| Job fails at S3 upload | Verify `openclaw-backup-aws` secret has valid credentials |
| Wrong files restored | Check `--strip-components` value against `tar -tzf` output |
| PVC not found | Confirm PVC name with `kubectl get pvc -n openclaw` |
| Agent won't start after restore | Check logs; `bin/` and `tools/` are excluded — they're reinstalled by init container |
