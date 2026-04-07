# OpenClaw PVC Backup — Restore Runbook

## Overview

Agent PVC data is backed up on a schedule to S3. The default backup path structure is:

```
s3://${S3_BUCKET}/${BACKUP_PREFIX}/<timestamp>.tar.gz
```

Each agent has its own backup prefix, configured via the `BACKUP_PREFIX` environment variable
in the backup CronJob. Check your deployment's CronJob or Kubernetes secret for the values
in use.

Backups contain `~/.openclaw/` excluding: `bin`, `tools`, `go`, `node_modules`, `.cache`,
`chromium`, `sessions`, `.tool-versions`.

---

## Prerequisites

- `kubectl` access to the cluster and namespace where OpenClaw is deployed
- AWS credentials with read access to the S3 backup bucket
- Target agent pod running (PVC must be mounted)

Set these environment variables before running the commands below:

```bash
export S3_BUCKET=<your-backup-bucket>
export BACKUP_PREFIX=<your-backup-prefix>   # e.g. openclaw-backups/my-cluster/openclaw
export AWS_REGION=ap-southeast-2            # adjust for your region
export NAMESPACE=openclaw                   # adjust if different
export AGENT=openclaw                       # agent deployment name
```

---

## Step 1 — Identify the backup to restore

```bash
# List available backups
aws s3 ls s3://${S3_BUCKET}/${BACKUP_PREFIX}/ --region ${AWS_REGION} | sort

# Pick the most recent or a specific timestamp
# Example: 2026-04-07T030154Z.tar.gz
export BACKUP_KEY="${BACKUP_PREFIX}/<timestamp>.tar.gz"
```

---

## Step 2 — Scale down the agent (prevent data corruption)

```bash
kubectl scale deployment ${AGENT} -n ${NAMESPACE} --replicas=0
# Wait for pod to terminate
kubectl wait --for=delete pod -l app.kubernetes.io/name=${AGENT} -n ${NAMESPACE} --timeout=60s
```

Repeat for any other agents sharing the same backup run.

---

## Step 3 — Run a restore job

Spin up a temporary pod with the agent's PVC mounted and restore from S3:

```bash
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
        \"args\": [\"aws s3 cp s3://${S3_BUCKET}/${BACKUP_KEY} /tmp/backup.tar.gz --region ${AWS_REGION} && cd /data && tar -xzf /tmp/backup.tar.gz --strip-components=1 && echo DONE\"],
        \"env\": [
          {\"name\": \"AWS_ACCESS_KEY_ID\", \"valueFrom\": {\"secretKeyRef\": {\"name\": \"openclaw-backup-aws\", \"key\": \"AWS_ACCESS_KEY_ID\"}}},
          {\"name\": \"AWS_SECRET_ACCESS_KEY\", \"valueFrom\": {\"secretKeyRef\": {\"name\": \"openclaw-backup-aws\", \"key\": \"AWS_SECRET_ACCESS_KEY\"}}}
        ],
        \"volumeMounts\": [{\"name\": \"data\", \"mountPath\": \"/data\"}]
      }]
    }
  }" -n ${NAMESPACE}
```

> **Note:** The tar archive is rooted at `openclaw/` (1 component). Use `--strip-components=1` to extract contents into `/data`. Verify with `tar -tzf backup.tar.gz | head` before extracting.

---

## Step 4 — Scale the agent back up

```bash
kubectl scale deployment ${AGENT} -n ${NAMESPACE} --replicas=1
kubectl rollout status deployment/${AGENT} -n ${NAMESPACE}
```

---

## Step 5 — Verify

```bash
# Check the pod is healthy
kubectl get pods -n ${NAMESPACE}

# Tail logs to confirm agent started cleanly
kubectl logs -n ${NAMESPACE} deployment/${AGENT} -f --tail=50
```

---

## Quick restore (exec into existing pod)

If the pod is still running and you only need to restore specific files:

```bash
# Download backup to pod
kubectl exec -n ${NAMESPACE} deployment/${AGENT} -- \
  aws s3 cp s3://${S3_BUCKET}/${BACKUP_KEY} /tmp/backup.tar.gz --region ${AWS_REGION}

# Preview contents
kubectl exec -n ${NAMESPACE} deployment/${AGENT} -- \
  tar -tzf /tmp/backup.tar.gz | head -30

# Extract specific directory (e.g. workspace)
kubectl exec -n ${NAMESPACE} deployment/${AGENT} -- \
  tar -xzf /tmp/backup.tar.gz -C /home/node/.openclaw --strip-components=1 openclaw/workspace-openclaw
```

---

## kubectl Quick Reference — Backup Monitoring

```bash
# Check the cronjob schedule, last run time, and suspend status
kubectl get cronjob -n ${NAMESPACE}

# Full detail (schedule, last successful time, events)
kubectl describe cronjob openclaw-pvc-backup -n ${NAMESPACE}

# List all backup jobs and their status
kubectl get job -n ${NAMESPACE} --sort-by=.metadata.creationTimestamp

# Watch jobs in real time
kubectl get job -n ${NAMESPACE} --sort-by=.metadata.creationTimestamp -w

# Tail logs from a specific backup job
kubectl logs -n ${NAMESPACE} job/openclaw-pvc-backup-<job-id>

# Check backup pod status
kubectl get pods -n ${NAMESPACE} --sort-by=.metadata.creationTimestamp | grep backup
```

---

## Triggering a manual backup

```bash
# Run the backup job now
kubectl create job manual-backup-$(date +%s) \
  --from=cronjob/openclaw-pvc-backup \
  -n ${NAMESPACE}

# Watch progress
kubectl get jobs -n ${NAMESPACE} --sort-by=.metadata.creationTimestamp -w
```

---

## Troubleshooting

| Symptom | Check |
|---------|-------|
| Job fails at S3 upload | Verify `openclaw-backup-aws` secret has valid credentials and correct bucket name |
| Wrong files restored | Check `--strip-components` value against `tar -tzf` output |
| PVC not found | Confirm PVC name with `kubectl get pvc -n ${NAMESPACE}` |
| Agent won't start after restore | Check logs; `bin/` and `tools/` are excluded — they're reinstalled by the init container |
