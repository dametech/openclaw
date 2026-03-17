---
name: dame-prices
description: Get AEMO NEM energy prices, spot prices, dispatch prices, and FCAS prices from InfluxDB. Use when asked about electricity prices, NEM spot prices, regional energy prices (NSW, QLD, SA, TAS, VIC, WA), dispatch intervals, or Australian electricity market data.
---

# DAME NEM Prices Skill

Use this skill when asked about AEMO energy prices, NEM dispatch prices, spot prices, FCAS prices, or anything related to the Australian electricity market price data held in InfluxDB.

## Data Source

- **Bucket:** `dispatch` (also `dispatchdev` for dev/test)
- **Measurement:** `Price`
- **Granularity:** 5-minute dispatch intervals
- **InfluxDB org ID:** `c4789450c487eeba` (use `orgID` param, not org name — org name lookup is broken on this instance)

> ⚠️ **Important:** Always query using `orgID=c4789450c487eeba` in the URL, NOT `org=Dame`. The org name lookup fails on this Timestream instance.

## Schema

### Tags (filter dimensions)

| Tag | Values | Notes |
|-----|--------|-------|
| `RegionID` | `NSW1`, `QLD1`, `SA1`, `TAS1`, `VIC1`, `WA1` | NEM region |
| `ENV` | `DEV` | Environment tag (currently only DEV data) |

### Fields (`_field` values)

| Field | Description |
|-------|-------------|
| `RRP` | **Regional Reference Price** — the main 5-min spot price ($/MWh) |
| `RAISE6SECRRP` | Raise 6-second FCAS price |
| `RAISE60SECRRP` | Raise 60-second FCAS price |
| `RAISE5MINRRP` | Raise 5-minute FCAS price |
| `RAISEREGRRP` | Raise regulation FCAS price |
| `RAISEREGROP` | Raise regulation FCAS recovery price |
| `LOWER6SECRRP` | Lower 6-second FCAS price |
| `LOWER60SECRRP` | Lower 60-second FCAS price |
| `LOWER5MINRRP` | Lower 5-minute FCAS price |
| `LOWERREGRRP` | Lower regulation FCAS price |
| `LOWERREGROP` | Lower regulation FCAS recovery price |
| `LOWER1SECRRP` | Lower 1-second FCAS price |
| `RAISE1SECRRP` | Raise 1-second FCAS price |

### Timestamps

| Column | Format | Notes |
|--------|--------|-------|
| `_time` | RFC3339 UTC | InfluxDB native timestamp — use for ranging/windowing |
| `RunDateTime` | `YYYY/MM/DD HH:MM:SS` AEST/AEDT string | NEM interval end time (local time) — informational only |

> `_time` is in UTC. NEM operates in AEST (UTC+10) / AEDT (UTC+11). The `RunDateTime` tag shows the local NEM time for human reference.

## Flux Query Patterns

### RRP spot prices — all regions, last hour
```flux
from(bucket: "dispatch")
  |> range(start: -1h)
  |> filter(fn: (r) => r._measurement == "Price" and r._field == "RRP")
  |> keep(columns: ["_time", "_value", "RegionID", "RunDateTime"])
  |> sort(columns: ["_time"])
```

### RRP for a specific region
```flux
from(bucket: "dispatch")
  |> range(start: -24h)
  |> filter(fn: (r) =>
      r._measurement == "Price" and
      r._field == "RRP" and
      r.RegionID == "VIC1"
  )
  |> keep(columns: ["_time", "_value", "RegionID", "RunDateTime"])
```

### Compare RRP across all regions at the same time
```flux
from(bucket: "dispatch")
  |> range(start: -3h)
  |> filter(fn: (r) => r._measurement == "Price" and r._field == "RRP")
  |> group(columns: ["RegionID"])
  |> keep(columns: ["_time", "_value", "RegionID"])
```

### Average hourly RRP per region (last 24h)
```flux
from(bucket: "dispatch")
  |> range(start: -24h)
  |> filter(fn: (r) => r._measurement == "Price" and r._field == "RRP")
  |> aggregateWindow(every: 1h, fn: mean, createEmpty: false)
  |> group(columns: ["RegionID"])
  |> keep(columns: ["_time", "_value", "RegionID"])
```

### All FCAS prices for a region
```flux
from(bucket: "dispatch")
  |> range(start: -1h)
  |> filter(fn: (r) =>
      r._measurement == "Price" and
      r.RegionID == "SA1" and
      r._field != "RRP"
  )
  |> keep(columns: ["_time", "_value", "_field", "RegionID"])
  |> sort(columns: ["_time", "_field"])
```

### Specific FCAS markets
```flux
from(bucket: "dispatch")
  |> range(start: -6h)
  |> filter(fn: (r) =>
      r._measurement == "Price" and
      r.RegionID == "NSW1" and
      (r._field == "RAISE6SECRRP" or r._field == "LOWER6SECRRP")
  )
  |> keep(columns: ["_time", "_value", "_field", "RegionID"])
```

### High price detection (price spikes > $300/MWh)
```flux
from(bucket: "dispatch")
  |> range(start: -24h)
  |> filter(fn: (r) => r._measurement == "Price" and r._field == "RRP")
  |> filter(fn: (r) => r._value > 300.0)
  |> keep(columns: ["_time", "_value", "RegionID", "RunDateTime"])
  |> sort(columns: ["_value"], desc: true)
```

### Latest price per region (most recent interval)
```flux
from(bucket: "dispatch")
  |> range(start: -15m)
  |> filter(fn: (r) => r._measurement == "Price" and r._field == "RRP")
  |> last()
  |> keep(columns: ["_time", "_value", "RegionID", "RunDateTime"])
```

### Daily min/max/mean RRP per region
```flux
from(bucket: "dispatch")
  |> range(start: -7d)
  |> filter(fn: (r) => r._measurement == "Price" and r._field == "RRP")
  |> aggregateWindow(every: 1d, fn: mean, createEmpty: false)
  |> group(columns: ["RegionID"])
```

## Analysis Workflow

1. **Current prices** → query last 15–30 min with `last()` per region
2. **Price trends** → query last 24h with `aggregateWindow` (hourly mean)
3. **Price spikes** → filter `_value > 300` (or MPC threshold ~$17,500)
4. **FCAS analysis** → filter out `_field == "RRP"`, group by `_field`
5. **Cross-region comparison** → group by `RegionID`, pivot or present side by side
6. **Historical analysis** → extend range (e.g. `-30d`), use daily aggregation to keep result sets manageable

## NEM Context

- **Market Price Cap (MPC):** ~$17,500/MWh — maximum possible price
- **Market Floor Price:** -$1,000/MWh — minimum possible price (negative prices occur during high renewable/low demand)
- **Dispatch interval:** 5 minutes (each `_time` is the end of a 5-min interval)
- **Settlement:** Prices settle as 30-min trading intervals (average of 6 dispatch prices)
- **Regions:** NSW1 (New South Wales), QLD1 (Queensland), SA1 (South Australia), TAS1 (Tasmania), VIC1 (Victoria), WA1 (Western Australia — separate market, SWIS)
- **FCAS markets:** Frequency Control Ancillary Services — 8 markets (Raise/Lower × 1sec/6sec/60sec/5min + Raise/Lower Reg)

## Presentation Tips

- Always convert `_time` (UTC) to AEST/AEDT for human-readable output (UTC+10 or +11 during daylight saving)
- Round price values to 2 decimal places for readability (prices are $/MWh)
- When showing multi-region data, present as a table with regions as columns
- Negative prices are valid and common — don't treat them as errors
- For FCAS, clarify whether "Raise" = pay to increase frequency (generators) and "Lower" = pay to decrease frequency
