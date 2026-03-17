---
name: miner-cli
description: Manage, scan, monitor, and report on Bitcoin miner fleets using the miner-cli tool. Use when asked to scan miners, check miner status, look up error codes, run the daily miner scan, post miner status to Teams, restart miners, switch pools, or anything related to mining operations. Supports site-name-based scanning (e.g. "scan au01-1" maps to the correct IP ranges automatically). Triggers on phrases like "run a miner scan", "scan au01", "check the miners", "how many miners are down", "run the daily scan", "what errors do we have", "restart the miners", "post miner status", etc.
---

# miner-cli Skill

## Binary

```
/home/ssm-user/.openclaw/workspace-4ndr3w/miner-cli/miner-cli
```

## Installation

**Clone and build (first time):**
```bash
git clone https://github.com/sinkers/miner-cli /home/ssm-user/.openclaw/workspace-4ndr3w/miner-cli
cd /home/ssm-user/.openclaw/workspace-4ndr3w/miner-cli
make build
```

**Rebuild after code changes:**
```bash
cd /home/ssm-user/.openclaw/workspace-4ndr3w/miner-cli
make build
# or directly:
go build -o miner-cli .
```

**Install to GOPATH/bin (optional, makes it available system-wide):**
```bash
cd /home/ssm-user/.openclaw/workspace-4ndr3w/miner-cli
make install
# binary lands at $(go env GOPATH)/bin/miner-cli
```

**Pre-push checks (run before committing changes):**
```bash
make check   # fmt + vet + lint + test
```

Requires Go 1.24+. Module: `github.com/sinkers/miner-cli`

## Site Map

When a user names a site, expand to the corresponding IP ranges automatically:

| Site Name | IP Ranges | Description |
|-----------|-----------|-------------|
| au01-1 | 10.45.78.0/24 10.45.79.0/24 | AU01-1 — MDC1 + MDC2 |
| au01-1a | 10.45.78.0/24 | AU01-1a — MDC1 only |
| au01-1b | 10.45.79.0/24 | AU01-1b — MDC2 only |

Example: "run a miner scan on au01-1" →
```bash
miner-cli scan 10.45.78.0/24 10.45.79.0/24 --check-errors
```

## Scan Command (primary use)

```bash
# Standard scan with error detection — always use --check-errors
miner-cli scan <IP_RANGES...> --check-errors

# With verbose output
miner-cli scan 10.45.78.0/24 --check-errors -v

# With switch port mapping (SNMP)
miner-cli scan 10.45.78.0/24 --check-errors --switch <switch-ip> --community public

# With Braiins auth for MAC retrieval
miner-cli scan 10.45.78.0/24 --check-errors --braiins-user root --braiins-pass root

# JSON output for scripting
miner-cli scan 10.45.78.0/24 --check-errors -o json

# With chip temps (slower)
miner-cli scan 10.45.78.0/24 --check-errors --scan-temps
```

## Other Commands

```bash
miner-cli summary <IPs>          # Mining summary stats
miner-cli devs <IPs>             # Device/hashboard info
miner-cli pools <IPs>            # Pool config and status
miner-cli stats <IPs>            # Detailed statistics
miner-cli restart <IPs>          # Restart miners
miner-cli quit <IP>              # Stop a miner (use with caution)
miner-cli switchpool <IPs> --pool <id>   # Switch active pool
miner-cli addpool <IPs> --url <url> --user <u> --pass <p>
miner-cli enablepool / disablepool / removepool <IPs> --pool <id>
```

## Global Flags

| Flag | Default | Description |
|------|---------|-------------|
| `-o` | color | Output format: color, json, table |
| `-t` | 2 | Connection timeout (seconds) |
| `-w` | 255 | Concurrent workers |
| `-v` | false | Verbose output |
| `--show-mac` | false | Display MAC addresses |
| `-p` | 4028 | CGMiner API port |

## Error Codes

After the 2026-03-17 update, errors appear at the **top** of scan output as `[CODE] description`.
See `references/error-codes.md` for the full reference.

## Daily Scan

The automated daily scan runs at **8:15 AM AEDT**. For manual runs and the Teams posting workflow, see `references/daily-scan.md`.

**Test run** (no Teams post): just run the scan commands and show output inline.
**Live run**: follow the full workflow in `references/daily-scan.md`.
