#!/usr/bin/env python3
"""
AWS Bedrock Cost & Usage Report
Pulls actual billing data from Cost Explorer and token metrics from CloudWatch.
Includes per-agent attribution using OpenClaw session transcripts.

Usage:
  python3 bedrock-costs.py [--month] [--days N] [--granularity DAILY|MONTHLY] [--region REGION]
"""

import argparse
import glob
import json
import os
import warnings
from collections import defaultdict
from datetime import date, datetime, timedelta

warnings.filterwarnings("ignore")

try:
    import boto3
except ImportError:
    print("boto3 not installed. Run: pip install boto3")
    raise SystemExit(1)

AGENTS_DIR = os.path.expanduser("~/.openclaw/agents")


def parse_args():
    p = argparse.ArgumentParser(description="AWS Bedrock cost & usage report")
    p.add_argument("--days", type=int, default=30, help="Look back N days (default: 30)")
    p.add_argument("--month", action="store_true", help="Current calendar month to date")
    p.add_argument("--region", default="ap-southeast-2", help="AWS region for CloudWatch metrics")
    p.add_argument("--granularity", choices=["DAILY", "MONTHLY"], default="DAILY")
    return p.parse_args()


def get_date_range(args):
    today = date.today()
    start = today.replace(day=1) if args.month else today - timedelta(days=args.days)
    end = today + timedelta(days=1)
    return str(start), str(end), str(today)


def get_bedrock_costs_by_day(start, end):
    ce = boto3.client("ce", region_name="us-east-1")
    try:
        resp = ce.get_cost_and_usage(
            TimePeriod={"Start": start, "End": end},
            Granularity="DAILY",
            Filter={
                "Dimensions": {
                    "Key": "SERVICE",
                    "Values": [
                        "Claude Sonnet 4.6 (Amazon Bedrock Edition)",
                        "Claude Haiku 4.5 (Amazon Bedrock Edition)",
                        "Claude Opus 4.6 (Amazon Bedrock Edition)",
                        "Amazon Bedrock",
                    ],
                }
            },
            Metrics=["UnblendedCost"],
            GroupBy=[{"Type": "DIMENSION", "Key": "SERVICE"}],
        )
        return resp.get("ResultsByTime", [])
    except Exception as e:
        print(f"  ⚠️  Cost Explorer error: {e}")
        return []


def get_total_bedrock_cost(start, end):
    """Total Bedrock costs across all model service names."""
    ce = boto3.client("ce", region_name="us-east-1")
    try:
        resp = ce.get_cost_and_usage(
            TimePeriod={"Start": start, "End": end},
            Granularity="MONTHLY",
            Metrics=["UnblendedCost"],
            GroupBy=[{"Type": "DIMENSION", "Key": "SERVICE"}],
        )
        total = 0.0
        for result in resp.get("ResultsByTime", []):
            for g in result.get("Groups", []):
                svc = g["Keys"][0]
                if any(k in svc for k in ("Bedrock", "Claude", "Titan", "Nova")):
                    total += float(g["Metrics"]["UnblendedCost"]["Amount"])
        return total
    except Exception as e:
        print(f"  ⚠️  Cost Explorer (total) error: {e}")
        return 0.0


def get_token_metrics_by_model(start_dt, end_dt, region):
    cw = boto3.client("cloudwatch", region_name=region)
    period_seconds = max(int((end_dt - start_dt).total_seconds()), 86400)

    model_ids = set()
    try:
        paginator = cw.get_paginator("list_metrics")
        for page in paginator.paginate(Namespace="AWS/Bedrock", MetricName="InputTokenCount"):
            for m in page["Metrics"]:
                for dim in m.get("Dimensions", []):
                    if dim["Name"] == "ModelId":
                        model_ids.add(dim["Value"])
    except Exception as e:
        print(f"  ⚠️  CloudWatch list metrics error: {e}")
        return {}

    model_data = {}
    for model_id in model_ids:
        d = {"InputTokenCount": 0, "OutputTokenCount": 0, "InvocationCount": 0}
        for metric in ["InputTokenCount", "OutputTokenCount", "InvocationCount"]:
            try:
                resp = cw.get_metric_statistics(
                    Namespace="AWS/Bedrock",
                    MetricName=metric,
                    Dimensions=[{"Name": "ModelId", "Value": model_id}],
                    StartTime=start_dt,
                    EndTime=end_dt,
                    Period=period_seconds,
                    Statistics=["Sum"],
                )
                d[metric] = int(sum(dp["Sum"] for dp in resp["Datapoints"]))
            except Exception:
                pass
        model_data[model_id] = d
    return model_data


def get_agent_tokens_from_transcripts():
    """Read per-agent token usage from OpenClaw session transcripts."""
    agent_tokens = defaultdict(lambda: {
        "sessions": 0, "input": 0, "output": 0, "cache_read": 0, "cache_write": 0
    })
    for jsonl in glob.glob(f"{AGENTS_DIR}/*/sessions/*.jsonl"):
        agent = jsonl.split("/agents/")[1].split("/")[0]
        session_counted = False
        with open(jsonl, "r", errors="ignore") as f:
            for line in f:
                try:
                    obj = json.loads(line.strip())
                    if obj.get("type") == "session" and not session_counted:
                        agent_tokens[agent]["sessions"] += 1
                        session_counted = True
                    if obj.get("type") == "message":
                        u = obj.get("usage") or obj.get("message", {}).get("usage")
                        if u:
                            agent_tokens[agent]["input"]       += u.get("input",       u.get("inputTokens", 0))
                            agent_tokens[agent]["output"]      += u.get("output",      u.get("outputTokens", 0))
                            agent_tokens[agent]["cache_read"]  += u.get("cacheRead",   u.get("cacheReadInputTokens", 0))
                            agent_tokens[agent]["cache_write"] += u.get("cacheWrite",  u.get("cacheWriteInputTokens", 0))
                except Exception:
                    pass
    return agent_tokens


def weighted_cost_units(d):
    """Estimate relative cost weight using Sonnet pricing ratios."""
    return d["input"] * 3 + d["output"] * 15 + d["cache_read"] * 0.3 + d["cache_write"] * 3.75


def fmt(n):
    if n >= 1_000_000:
        return f"{n/1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n/1_000:.0f}K"
    return str(int(n))


def short_model(name):
    return (
        name.replace(" (Amazon Bedrock Edition)", "")
        .replace("Amazon Bedrock - ", "")
        .replace("Amazon Bedrock", "Bedrock (other)")
    )


def main():
    args = parse_args()
    start_str, end_str, today_str = get_date_range(args)
    start_dt = datetime.strptime(start_str, "%Y-%m-%d")
    end_dt = datetime.strptime(end_str, "%Y-%m-%d")
    days_in_range = (end_dt - start_dt).days
    billing_days = max(days_in_range, 1)

    print(f"\n{'═'*72}")
    print(f"  AWS Bedrock Cost & Usage Report")
    print(f"  Period : {start_str} → {today_str}  ({days_in_range} days)")
    print(f"  Region : {args.region}")
    print(f"{'═'*72}\n")

    # ── 1. Cost by day ────────────────────────────────────────────────────────
    print("💰 COST BY DAY (Cost Explorer)")
    print("─" * 72)

    daily_results = get_bedrock_costs_by_day(start_str, end_str)
    all_models = {g["Keys"][0] for r in daily_results for g in r.get("Groups", [])}
    model_totals = defaultdict(float)
    grand_total = 0.0
    daily_totals = []

    if daily_results:
        models_sorted = sorted(all_models, key=lambda x: -sum(
            float(g["Metrics"]["UnblendedCost"]["Amount"])
            for r in daily_results for g in r.get("Groups", [])
            if g["Keys"][0] == x
        ))
        col_w = 14
        header = f"  {'Date':<12}" + "".join(f" {short_model(m):>{col_w}}" for m in models_sorted) + f"  {'Total':>10}"
        print(header)
        print(f"  {'─'*12}" + f" {'─'*col_w}" * len(models_sorted) + f"  {'─'*10}")

        for result in daily_results:
            day = result["TimePeriod"]["Start"]
            day_costs = {g["Keys"][0]: float(g["Metrics"]["UnblendedCost"]["Amount"]) for g in result.get("Groups", [])}
            day_total = sum(day_costs.values())
            grand_total += day_total
            if day_total > 0:
                daily_totals.append(day_total)
                row = f"  {day:<12}"
                for m in models_sorted:
                    amt = day_costs.get(m, 0.0)
                    model_totals[m] += amt
                    row += f" ${amt:>{col_w-1}.2f}"
                row += f"  ${day_total:>9.2f}"
                print(row)

        print(f"  {'─'*12}" + f" {'─'*col_w}" * len(models_sorted) + f"  {'─'*10}")
        totals_row = f"  {'TOTAL':<12}" + "".join(f" ${model_totals[m]:>{col_w-1}.2f}" for m in models_sorted) + f"  ${grand_total:>9.2f}"
        print(totals_row)

        if len(daily_totals) > 2:
            avg = sum(daily_totals) / len(daily_totals)
            spikes = [
                (r["TimePeriod"]["Start"], sum(float(g["Metrics"]["UnblendedCost"]["Amount"]) for g in r.get("Groups", [])))
                for r in daily_results
                if sum(float(g["Metrics"]["UnblendedCost"]["Amount"]) for g in r.get("Groups", [])) > avg * 2
            ]
            if spikes:
                print(f"\n  ⚠️  Cost spikes (>2× daily avg of ${avg:.2f}):")
                for day, cost in spikes:
                    print(f"     {day}  ${cost:.2f}  ({cost/avg:.1f}× avg)")
    else:
        print("  No cost data returned.")

    # ── 2. CloudWatch token usage by model ────────────────────────────────────
    print(f"\n\n🔢 TOKEN USAGE BY MODEL (CloudWatch — {args.region})")
    print("─" * 72)

    model_data = get_token_metrics_by_model(start_dt, end_dt, args.region)
    cw_total_in = cw_total_out = 0
    if model_data:
        print(f"  {'Model':<48} {'Input':>9} {'Output':>9} {'Calls':>7}")
        print(f"  {'─'*48} {'─'*9} {'─'*9} {'─'*7}")
        for model_id, d in sorted(model_data.items(), key=lambda x: -(x[1]["InputTokenCount"] + x[1]["OutputTokenCount"])):
            if d["InputTokenCount"] + d["OutputTokenCount"] > 0:
                print(f"  {model_id:<48} {fmt(d['InputTokenCount']):>9} {fmt(d['OutputTokenCount']):>9} {fmt(d['InvocationCount']):>7}")
                cw_total_in += d["InputTokenCount"]
                cw_total_out += d["OutputTokenCount"]
        print(f"  {'─'*48} {'─'*9} {'─'*9} {'─'*7}")
        print(f"  {'TOTAL':<48} {fmt(cw_total_in):>9} {fmt(cw_total_out):>9}")
    else:
        print("  No CloudWatch data available.")

    # ── 3. Per-agent attribution ───────────────────────────────────────────────
    print(f"\n\n🤖 COST ATTRIBUTION BY AGENT  (transcript proportions × actual AWS cost)")
    print("─" * 100)

    agent_tokens = get_agent_tokens_from_transcripts()
    total_weight = sum(weighted_cost_units(d) for d in agent_tokens.values())

    # Coverage stats
    tx_total_in = sum(d["input"] for d in agent_tokens.values())
    tx_total_out = sum(d["output"] for d in agent_tokens.values())
    tx_total_cr = sum(d["cache_read"] for d in agent_tokens.values())
    tx_total_cw = sum(d["cache_write"] for d in agent_tokens.values())
    coverage = tx_total_in / cw_total_in if cw_total_in else 0

    print(f"  Transcript coverage: {coverage:.0%} of actual AWS input token volume  "
          f"({fmt(tx_total_in)} transcript vs {fmt(cw_total_in)} CloudWatch)")
    print()
    print(f"  {'Agent':<14} {'Sess':>5} {'Input':>9} {'Output':>9} {'Cache Read':>11} {'Cache Write':>12} {'Share':>6} {'Attributed':>11} {'$/day':>7}")
    print(f"  {'─'*14} {'─'*5} {'─'*9} {'─'*9} {'─'*11} {'─'*12} {'─'*6} {'─'*11} {'─'*7}")

    attr_total = 0.0
    for agent, d in sorted(agent_tokens.items(), key=lambda x: -weighted_cost_units(x[1])):
        if d["sessions"] == 0:
            continue
        share = weighted_cost_units(d) / total_weight if total_weight else 0
        attr = share * grand_total
        per_day = attr / billing_days
        attr_total += attr
        print(
            f"  {agent:<14} {d['sessions']:>5} {fmt(d['input']):>9} {fmt(d['output']):>9} "
            f"{fmt(d['cache_read']):>11} {fmt(d['cache_write']):>12} {share:>5.1%} "
            f"${attr:>10.2f} ${per_day:>6.2f}"
        )

    print(f"  {'─'*14} {'─'*5} {'─'*9} {'─'*9} {'─'*11} {'─'*12} {'─'*6} {'─'*11} {'─'*7}")
    sess_total = sum(d["sessions"] for d in agent_tokens.values())
    print(
        f"  {'TOTAL':<14} {sess_total:>5} {fmt(tx_total_in):>9} {fmt(tx_total_out):>9} "
        f"{fmt(tx_total_cr):>11} {fmt(tx_total_cw):>12} {'100%':>6} "
        f"${grand_total:>10.2f} ${grand_total/billing_days:>6.2f}"
    )

    # Cache savings
    cache_savings = tx_total_cr * (3.0 - 0.3) / 1_000_000
    without_cache = grand_total + cache_savings
    print(f"\n  💡 Cache read tokens ({fmt(tx_total_cr)}) saved ~${cache_savings:,.2f} vs full input price")
    print(f"     Without caching the bill would be ~${without_cache:,.2f}  (cache reads = $0.30/1M vs $3.00/1M)")

    # ── 4. Summary ────────────────────────────────────────────────────────────
    print(f"\n\n📋 SUMMARY")
    print("─" * 72)
    print(f"  Period          : {start_str} → {today_str}")
    print(f"  Total cost      : ${grand_total:,.2f} USD")
    if daily_totals:
        avg_daily = grand_total / len(daily_totals)
        print(f"  Daily avg       : ${avg_daily:.2f} USD/day")
        print(f"  Projected/month : ${avg_daily * 30:,.2f} USD/month")
    print(f"  Cache savings   : ~${cache_savings:,.2f} USD (prompt caching)")
    print(f"{'═'*72}\n")


if __name__ == "__main__":
    main()
