---
name: dame-asx-prices
description: Query and analyse ASX Australian electricity futures prices stored in InfluxDB. Use when asked about futures prices, settlement prices, ASX electricity contracts, base or cap futures, contract years or quarters, futures price history, or implied cap pricing for NEM regions (NSW, VIC, QLD, SA). Triggers on phrases like "show me futures prices", "what are the Q3 2026 VIC base futures", "ASX electricity prices", "futures settlement history", "cap futures", etc.
---

# DAME ASX Prices Skill

Query and analyse ASX electricity futures data stored in InfluxDB.

## Data Source

- **Bucket:** `asx`
- **Measurement:** `futures`
- **Granularity:** Daily (one row per contract per snapshot date)
- **Coverage:** April 2020 – December 2024
- **InfluxDB org ID:** `c4789450c487eeba` (always use `orgID`, not org name)

> ⚠️ Always query using `orgID=c4789450c487eeba`. Never use `org=Dame`.

## Schema

### Tags (filter dimensions)

| Tag | Values | Notes |
|-----|--------|-------|
| `contract_code` | e.g. `BNM2025F`, `GVZ2026F` | ASX contract ticker |
| `product_type` | `base`, `cap` | Base load or cap ($300) contract |
| `region` | `NSW`, `VIC`, `QLD`, `SA` | NEM region (no trailing "1") |
| `quarter` | `Q1`, `Q2`, `Q3`, `Q4` | Contract quarter |
| `contract_year` | `2020`–`2028` | Settlement year |
| `expiry_date` | `YYYY-MM-DD` | Contract expiry |

### Fields

| Field | Description |
|-------|-------------|
| `settlement_price` | Daily ASX end-of-day settlement price ($/MWh) |

### Timestamps
`_time` is UTC midnight on the `snapshot_date` (the date the price was recorded).

## Flux Query Patterns

### Latest settlement price per contract (most recent snapshot)
```flux
from(bucket: "asx")
  |> range(start: 2024-01-01T00:00:00Z)
  |> filter(fn: (r) => r._measurement == "futures" and r._field == "settlement_price")
  |> filter(fn: (r) => r.product_type == "base")
  |> last()
  |> keep(columns: ["_time", "_value", "region", "quarter", "contract_year", "contract_code"])
```

### Price history for a specific contract
```flux
from(bucket: "asx")
  |> range(start: 2023-01-01T00:00:00Z)
  |> filter(fn: (r) =>
      r._measurement == "futures" and
      r._field == "settlement_price" and
      r.region == "VIC" and
      r.quarter == "Q3" and
      r.contract_year == "2025" and
      r.product_type == "base"
  )
  |> keep(columns: ["_time", "_value", "contract_code"])
```

### All base futures for a region, latest price per contract
```flux
from(bucket: "asx")
  |> range(start: 2024-01-01T00:00:00Z)
  |> filter(fn: (r) =>
      r._measurement == "futures" and
      r._field == "settlement_price" and
      r.region == "NSW" and
      r.product_type == "base"
  )
  |> last()
  |> keep(columns: ["_time", "_value", "quarter", "contract_year", "expiry_date"])
  |> sort(columns: ["contract_year", "quarter"])
```

### Compare base futures across regions for a specific quarter/year
```flux
from(bucket: "asx")
  |> range(start: 2024-01-01T00:00:00Z)
  |> filter(fn: (r) =>
      r._measurement == "futures" and
      r._field == "settlement_price" and
      r.product_type == "base" and
      r.quarter == "Q2" and
      r.contract_year == "2026"
  )
  |> last()
  |> keep(columns: ["_time", "_value", "region"])
```

### Cap futures — all regions, latest price
```flux
from(bucket: "asx")
  |> range(start: 2024-01-01T00:00:00Z)
  |> filter(fn: (r) =>
      r._measurement == "futures" and
      r._field == "settlement_price" and
      r.product_type == "cap"
  )
  |> last()
  |> keep(columns: ["_time", "_value", "region", "quarter", "contract_year"])
```

### Price trend over time — monthly average for a contract
```flux
from(bucket: "asx")
  |> range(start: 2023-01-01T00:00:00Z)
  |> filter(fn: (r) =>
      r._measurement == "futures" and
      r._field == "settlement_price" and
      r.region == "VIC" and
      r.product_type == "base" and
      r.contract_year == "2025"
  )
  |> group(columns: ["quarter"])
  |> aggregateWindow(every: 1mo, fn: mean, createEmpty: false)
  |> keep(columns: ["_time", "_value", "quarter"])
```

### Forward curve — all base contracts for a region at a point in time
```flux
from(bucket: "asx")
  |> range(start: 2024-12-01T00:00:00Z, stop: 2024-12-13T00:00:00Z)
  |> filter(fn: (r) =>
      r._measurement == "futures" and
      r._field == "settlement_price" and
      r.region == "VIC" and
      r.product_type == "base"
  )
  |> last()
  |> keep(columns: ["_time", "_value", "quarter", "contract_year", "expiry_date"])
  |> sort(columns: ["contract_year", "quarter"])
```

## Analysis Patterns

1. **Forward curve** → filter by region + product_type + `last()` across all contracts, sort by expiry
2. **Price history** → filter specific contract, full time range, no aggregation
3. **Cross-region comparison** → filter quarter/year/product_type, `last()`, group by region
4. **Base vs cap** → run two queries filtering `product_type == "base"` and `product_type == "cap"` side by side
5. **Price trajectory** → monthly `aggregateWindow` over a contract's lifetime

## NEM Context

- **Base futures** settle against the arithmetic mean of all 30-min trading prices in the quarter
- **Cap futures** pay out when spot exceeds $300/MWh — price reflects the market's expectation of spike frequency/severity
- **Regions:** NSW, VIC, QLD, SA (WA is a separate market, not on ASX NEM futures)
- **Data ends Dec 2024** — no live/current futures prices; use for historical analysis

## Presentation Tips

- Always show `contract_year` + `quarter` together (e.g. "VIC Q3 2025")
- Round prices to 2 decimal places ($/MWh)
- For forward curves, sort by expiry date ascending
- Cap prices are typically $5–$30/MWh (much lower than base) — clarify units when presenting both
- When comparing regions, present as a table with regions as columns
