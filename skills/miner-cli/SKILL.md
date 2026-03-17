---
name: miner-cli
description: Manage, scan, monitor, and report on Bitcoin miner fleets using the miner-cli tool. Use when asked to scan miners, check miner status, look up error codes, run the daily miner scan, post miner status to Teams, restart miners, switch pools, or do anything related to the AU01 mining operation. Triggers on phrases like "run a miner scan", "check the miners", "how many miners are down", "run the daily scan", "what errors do we have", "restart the miners", "post miner status", etc.
---

# miner-cli Skill

## Binary Location

```
/home/ssm-user/.openclaw/workspace-4ndr3w/miner-cli/miner-cli
```

Rebuild if needed: `cd /home/ssm-user/.openclaw/workspace-4ndr3w/miner-cli && go build -o miner-cli .`

## AU01 Subnets

| Subnet | Site |
|--------|------|
| 10.45.78.0/24 | AU01-1a MDC1 |
| 10.45.79.0/24 | AU01-1a MDC2 |

## Common Commands

```bash
# Scan subnet with error detection (standard daily use)
miner-cli scan 10.45.78.0/24 --check-errors
miner-cli scan 10.45.79.0/24 --check-errors

# Restart miners
miner-cli restart 10.45.78.0/24

# Pool management
miner-cli pools 10.45.78.0/24
miner-cli switchpool 10.45.78.0/24 --pool 1

# JSON output for scripting
miner-cli scan 10.45.78.0/24 -o json
```

## Error Code Format

After the scan update (2026-03-17), error codes appear **at the top of output** formatted as `[CODE] description` — e.g. `[541] Slot1 chip id error`.

See `references/error-codes.md` for the full error code reference.

## Daily Miner Scan — AU01

The daily scan runs via cron at **8:15 AM AEDT** (cron id: `a7276b20-9d5e-45df-91a8-68cd25d71b7e`).

To run manually and post to Ops Stand Up, follow the steps in `references/daily-scan.md`.

To run as a **test** (no Teams post), just run the scan commands directly and show output inline.

## Location Lookup

Tank/row/position data for AU01:

```bash
curl -sk https://control-tank-lookup.au01-1a.dametech.net/au01-1
```

Returns JSON with MAC → `{rackId (tank name), row, index (position)}` mapping.

## Error Trend Tracking

Yesterday's error baseline is stored at:
```
/home/ssm-user/.openclaw/workspace-4ndr3w/memory/error-trend.json
```

Read before posting daily report to include trend line (e.g. "14 errors ▲ +2 vs yesterday's 12").
