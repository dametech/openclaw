#!/usr/bin/env python3
"""
DAME Apps Deploy Script
Syncs a local directory to S3 and invalidates CloudFront.

Usage:
  python3 deploy.py --agent marc --app my-dashboard --dir ./build
  python3 deploy.py --agent nick --app crm-report --dir ./dist --dry-run
"""

import argparse
import mimetypes
import os
import subprocess
import sys

# ── Config ────────────────────────────────────────────────────────────────────
S3_BUCKET         = "dame-openclaw-apps-assets"
CLOUDFRONT_ID     = "E3E6WNA6XSI1YS"
BASE_URL          = "https://apps.dametech.net"

KNOWN_AGENTS = ["marc", "nick", "jack", "luc", "brad", "eliza", "caroline", "scrumm4st3r", "4ndr3w"]

# ── Helpers ───────────────────────────────────────────────────────────────────

def run(cmd, dry_run=False):
    print(f"  $ {' '.join(cmd)}")
    if not dry_run:
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"  ERROR: {result.stderr.strip()}", file=sys.stderr)
            sys.exit(1)
        return result.stdout.strip()
    return ""

def content_type(filepath):
    ct, _ = mimetypes.guess_type(filepath)
    return ct or "application/octet-stream"

# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Deploy a static app to DAME Apps (S3 + CloudFront)")
    parser.add_argument("--agent", required=True, help="Agent name (e.g. marc, nick)")
    parser.add_argument("--app",   required=True, help="App name slug (e.g. energy-dashboard)")
    parser.add_argument("--dir",   required=True, help="Local directory to deploy")
    parser.add_argument("--dry-run", action="store_true", help="Print commands without executing")
    args = parser.parse_args()

    agent    = args.agent.lower().strip("/")
    app      = args.app.lower().strip("/").replace(" ", "-")
    src_dir  = os.path.abspath(args.dir)
    dry_run  = args.dry_run
    s3_prefix = f"{agent}/{app}"
    s3_uri    = f"s3://{S3_BUCKET}/{s3_prefix}/"
    live_url  = f"{BASE_URL}/{s3_prefix}/"

    # Validate
    if not os.path.isdir(src_dir):
        print(f"ERROR: Directory not found: {src_dir}", file=sys.stderr)
        sys.exit(1)

    index_path = os.path.join(src_dir, "index.html")
    if not os.path.exists(index_path):
        print(f"ERROR: index.html not found in {src_dir}", file=sys.stderr)
        print("Every app must have an index.html at the root.", file=sys.stderr)
        sys.exit(1)

    if args.agent not in KNOWN_AGENTS:
        print(f"WARNING: '{agent}' is not a known agent name. Known: {', '.join(KNOWN_AGENTS)}")
        print("Proceeding anyway...")

    print(f"\n🚀 Deploying {agent}/{app}")
    print(f"   Source : {src_dir}")
    print(f"   Target : {s3_uri}")
    if dry_run:
        print("   Mode   : DRY RUN (no changes made)\n")
    else:
        print()

    # Sync to S3
    print("📦 Syncing files to S3...")
    run([
        "aws", "s3", "sync", src_dir, s3_uri,
        "--delete",
        "--cache-control", "max-age=300,public",
        "--region", "ap-southeast-2",
    ], dry_run)

    # Set cache-control: no-cache on index.html so browsers always get fresh version
    print("📄 Setting no-cache on index.html...")
    run([
        "aws", "s3", "cp",
        os.path.join(src_dir, "index.html"),
        f"{s3_uri}index.html",
        "--content-type", "text/html",
        "--cache-control", "no-cache,no-store,must-revalidate",
        "--metadata-directive", "REPLACE",
        "--region", "ap-southeast-2",
    ], dry_run)

    # Invalidate CloudFront
    print("🔄 Invalidating CloudFront cache...")
    run([
        "aws", "cloudfront", "create-invalidation",
        "--distribution-id", CLOUDFRONT_ID,
        "--paths", f"/{s3_prefix}/*",
    ], dry_run)

    print(f"\n✅ Done!")
    print(f"   Live at: {live_url}")
    print(f"   (CloudFront propagation takes ~30 seconds)\n")


if __name__ == "__main__":
    main()
