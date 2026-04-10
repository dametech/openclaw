---
name: aws-bedrock-costs
description: Show AWS Bedrock usage costs and token metrics. Use when any user asks about Bedrock costs, AWS AI spending, model usage, token counts, or cost breakdowns by model or date. Triggers on phrases like "show me the Bedrock costs", "how much are we spending on AI", "AWS Bedrock usage", "what's the Bedrock bill", "show me AI costs", "cost by model", etc.
---

# AWS Bedrock Costs

Pull actual cost and token usage data from AWS Cost Explorer and CloudWatch.

## Prerequisites

The EC2 instance role needs:
- `ce:GetCostAndUsage` (Cost Explorer)
- `cloudwatch:GetMetricStatistics` + `cloudwatch:ListMetrics` (CloudWatch)

These are included in `AWSBillingReadOnlyAccess` and `CloudWatchReadOnlyAccess` managed policies.

## Usage

Run the script directly:

```bash
# Current calendar month (default)
python3 scripts/bedrock-costs.py --month

# Last N days
python3 scripts/bedrock-costs.py --days 7

# Daily breakdown (default) or monthly rollup
python3 scripts/bedrock-costs.py --month --granularity MONTHLY
```

## Workflow

1. Run `scripts/bedrock-costs.py` with appropriate flags
2. Present the output — daily cost table, per-model token breakdown, summary
3. Call out any cost spikes (days >2× the average) and which models are driving them
4. If requested, project monthly spend based on current daily average

## Output Sections

The script produces:
- **Cost by day** — per-model daily USD cost from Cost Explorer
- **Token usage by model** — input/output token counts from CloudWatch
- **Summary** — total, daily average, projected monthly

## Notes

- Cost Explorer data lags ~24h; today's costs may be incomplete
- CloudWatch token metrics are region-specific — default is `ap-southeast-2`
- boto3 must be installed: `pip install boto3`
