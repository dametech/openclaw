# Daily Miner Scan — AU01

Run at 8:15 AM AEDT daily via cron. Follow these steps to run manually.

## Steps

1. **Run scans on both subnets:**
   ```bash
   /home/ssm-user/.openclaw/workspace-4ndr3w/miner-cli/miner-cli scan 10.45.78.0/24 --check-errors
   /home/ssm-user/.openclaw/workspace-4ndr3w/miner-cli/miner-cli scan 10.45.79.0/24 --check-errors
   ```

2. **Collect all miners listed under ERROR CODES DETECTED** — note each IP + MAC address.

3. **Fetch tank location data:**
   ```bash
   curl -s https://control-tank-lookup.au01-1a.dametech.net/au01-1
   ```
   For each error miner, look up MAC in the JSON response to get:
   - `rackId` → tank name
   - `row` → row number
   - `index` → position within row

4. **Read error trend baseline:**
   ```
   /home/ssm-user/.openclaw/workspace-4ndr3w/memory/error-trend.json
   ```

5. **Post to Teams** — target conversation:
   ```
   19:meeting_N2VmZWY4MmUtYTA3MC00MjZiLWJiMDctMzk0MGI1MTJjZWRi@thread.v2
   ```
   Use `message(action=send, channel=msteams, target='conversation:19:...')`.

## Teams Message Format

```
🔍 Daily Miner Scan — AU01 | {date} {time} AEDT

⚠️ ERROR CODES DETECTED — {N} miners with errors

| IP | MAC | Location | Errors |
|----|-----|----------|--------|
| 10.45.78.x | aa:bb:cc:dd:ee:ff | Tank-3 Row 2 Pos 14 | [541] Slot1 chip id error |
...

📊 Error trend: {N} errors (▲/▼/= vs yesterday's {M})

📦 Summary by tank:
- Tank-3: 3 faults
- Tank-7: 2 faults

⚡ Fleet stats:
- Total miners: {T} | Active: {A} | Stopped: {S}
- Total hashrate: {H} TH/s
- Total power: {P} kW
```

## Update Error Trend File

After posting, update `memory/error-trend.json` with today's count:
```json
{
  "date": "2026-03-17",
  "errorCount": 14,
  "stoppedCount": 8
}
```

## Test Run (no Teams post)

Just run the scan commands and display output inline. Do **not** call `message(action=send)`.
The cron job handles the real post — test runs are for manual review only.
