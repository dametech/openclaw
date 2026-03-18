# Miner Error Code Reference

Common error codes seen in AU01 fleet (MicroBT Whatsminer M66S).

## Chip / Hashboard Errors

| Code | Description | Severity | Notes |
|------|-------------|----------|-------|
| 540 | Slot0 chip id error | High — miner stopped | Slot 0 hashboard not responding |
| 541 | Slot1 chip id error | High — miner stopped | Slot 1 hashboard not responding |
| 542 | Slot2 chip id error | High — miner stopped | Slot 2 hashboard not responding |
| 543 | Slot3 chip id error | High — miner stopped | Slot 3 hashboard not responding |

Multiple slot errors (e.g. 540+541) indicate multiple dead hashboards — likely hardware failure.

## Temperature Errors

| Code | Description | Severity | Notes |
|------|-------------|----------|-------|
| 5079 | Temp delta inlet/outlet too large | Medium — miner running | Cooling issue; check coolant flow and temp |

## Pool / Network Errors

| Code | Description | Severity | Notes |
|------|-------------|----------|-------|
| 2010 | All pools disabled | High — miner stopped | Connectivity or pool config issue |

## Power / System Errors

| Code | Description | Severity | Notes |
|------|-------------|----------|-------|
| 219 | Power iin error | High — reduced performance | Input power issue; check PDU/cabling |
| 9100 | Process blocked | High — miner degraded | Internal process hang; restart recommended |

## Hashrate Errors

| Code | Description | Severity | Notes |
|------|-------------|----------|-------|
| 2310 | Hashrate too low | Low — miner running | Actual hashrate significantly below expected |

## Miner Status

| Status | Meaning |
|--------|---------|
| Running | Healthy, hashing |
| Stopped | Halted — usually due to chip/pool error |
| Paused | Temporarily paused |
| Offline | Not responding to API |
