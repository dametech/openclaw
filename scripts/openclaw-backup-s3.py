#!/usr/bin/env python3
"""
OpenClaw PVC config backup to S3.
Pure stdlib — no boto3 required.

Usage:
  export AWS_ACCESS_KEY_ID=AKIA...
  export AWS_SECRET_ACCESS_KEY=...
  export AWS_REGION=ap-southeast-2      # optional, defaults to ap-southeast-2
  export S3_BUCKET=your-bucket-name
  export BACKUP_PREFIX=openclaw-backups/au01-0  # optional
  python3 openclaw-backup-s3.py [--dry-run] [--verbose]

Creates a tar.gz of ~/.openclaw/ config files (excluding tools, bin, go,
node_modules, .tool-versions, and large reproducible dirs) and uploads
to s3://<bucket>/<prefix>/<timestamp>.tar.gz

Exit codes:
  0 — success
  1 — configuration error
  2 — archive creation failed
  3 — archive integrity check failed
  4 — upload failed (after retries)
"""

import argparse
import datetime
import hashlib
import hmac
import json
import os
import sys
import tarfile
import tempfile
import time
import urllib.request
import urllib.error

# ── Config ─────────────────────────────────────────────────────────
OPENCLAW_DIR = os.path.expanduser("~/.openclaw")
DEFAULT_BACKUP_PREFIX = "openclaw-backups/au01-0"
UPLOAD_MAX_RETRIES = 3
UPLOAD_RETRY_BACKOFF = [5, 15, 30]  # seconds between retries

# Top-level directories to EXCLUDE (reproducible or large)
EXCLUDE_DIRS = {
    "bin", "tools", "go", ".tool-versions",
    "node_modules", ".cache", "chromium",
    "sessions",       # session data can be large, not config
}

# Individual filenames to EXCLUDE (any depth)
EXCLUDE_FILES = {
    ".git-credentials",
}


# ── Logging ────────────────────────────────────────────────────────
def log(msg, level="INFO"):
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    print(f"[{now}] [{level}] {msg}", flush=True)


def log_json(event, **kwargs):
    """Emit a structured JSON event for machine-readable log parsing."""
    payload = {"event": event, **kwargs,
               "ts": datetime.datetime.now(datetime.timezone.utc).isoformat()}
    print(json.dumps(payload), flush=True)


# ── AWS SigV4 Signing ─────────────────────────────────────────────
def _hmac(key, msg):
    return hmac.new(key, msg.encode("utf-8"), hashlib.sha256).digest()

def _get_signature_key(secret, date_stamp, region, service):
    k_date    = _hmac(("AWS4" + secret).encode("utf-8"), date_stamp)
    k_region  = _hmac(k_date, region)
    k_service = _hmac(k_region, service)
    return _hmac(k_service, "aws4_request")

def s3_put(bucket, key, filepath, region, access_key, secret_key):
    """Upload a file to S3 using PUT with SigV4 auth.

    Reads the file from disk rather than holding it all in memory.
    """
    service = "s3"
    host = f"{bucket}.s3.{region}.amazonaws.com"
    endpoint = f"https://{host}/{key}"

    with open(filepath, "rb") as f:
        data = f.read()

    now        = datetime.datetime.now(datetime.timezone.utc)
    amz_date   = now.strftime("%Y%m%dT%H%M%SZ")
    date_stamp = now.strftime("%Y%m%d")

    content_hash = hashlib.sha256(data).hexdigest()

    canonical_uri         = "/" + key
    canonical_querystring = ""
    canonical_headers     = (
        f"host:{host}\n"
        f"x-amz-content-sha256:{content_hash}\n"
        f"x-amz-date:{amz_date}\n"
    )
    signed_headers  = "host;x-amz-content-sha256;x-amz-date"
    canonical_request = (
        f"PUT\n{canonical_uri}\n{canonical_querystring}\n"
        f"{canonical_headers}\n{signed_headers}\n{content_hash}"
    )

    credential_scope = f"{date_stamp}/{region}/{service}/aws4_request"
    string_to_sign   = (
        f"AWS4-HMAC-SHA256\n{amz_date}\n{credential_scope}\n"
        + hashlib.sha256(canonical_request.encode("utf-8")).hexdigest()
    )

    signing_key = _get_signature_key(secret_key, date_stamp, region, service)
    signature   = hmac.new(
        signing_key, string_to_sign.encode("utf-8"), hashlib.sha256
    ).hexdigest()

    authorization = (
        f"AWS4-HMAC-SHA256 Credential={access_key}/{credential_scope}, "
        f"SignedHeaders={signed_headers}, Signature={signature}"
    )

    headers = {
        "Host":                 host,
        "x-amz-date":          amz_date,
        "x-amz-content-sha256": content_hash,
        "Authorization":        authorization,
        "Content-Type":         "application/gzip",
        "Content-Length":       str(len(data)),
    }

    req = urllib.request.Request(endpoint, data=data, headers=headers, method="PUT")
    try:
        resp = urllib.request.urlopen(req)
        return resp.status, resp.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


# ── Archive creation ───────────────────────────────────────────────
def create_backup_archive(source_dir, dest_path, verbose=False):
    """Create a tar.gz at dest_path from source_dir.

    Returns a dict with stats: excluded_dirs, excluded_files, total_files.
    """
    stats = {"excluded_dirs": [], "excluded_files": [], "total_files": 0}

    def exclude_filter(tarinfo):
        # Archive paths are like "openclaw/subdir/file" — split on sep
        # and examine components after the top-level archive name.
        parts = tarinfo.name.split(os.sep)
        if len(parts) <= 1:
            return tarinfo

        rel_parts = parts[1:]  # relative to archive root

        # Skip excluded top-level directories
        if rel_parts[0] in EXCLUDE_DIRS:
            if rel_parts[0] not in stats["excluded_dirs"]:
                stats["excluded_dirs"].append(rel_parts[0])
            return None

        # Skip excluded individual files (any depth)
        if tarinfo.isreg() and rel_parts[-1] in EXCLUDE_FILES:
            stats["excluded_files"].append(tarinfo.name)
            return None

        # Skip .git directories inside workspace clones (can be large)
        if ".git" in rel_parts:
            idx = rel_parts.index(".git")
            if idx > 0 and rel_parts[idx - 1].startswith("workspace-"):
                return None

        if tarinfo.isreg():
            stats["total_files"] += 1
        return tarinfo

    with tarfile.open(dest_path, mode="w:gz") as tar:
        tar.add(source_dir, arcname="openclaw", filter=exclude_filter)

    if verbose:
        log(f"Excluded dirs:  {sorted(stats['excluded_dirs'])}")
        log(f"Excluded files: {stats['excluded_files']}")

    return stats


def verify_archive(path):
    """Verify the tar.gz can be opened and listed without errors.

    Returns (ok: bool, member_count: int, error: str|None).
    """
    try:
        with tarfile.open(path, "r:gz") as tar:
            members = tar.getmembers()
        return True, len(members), None
    except Exception as e:
        return False, 0, str(e)


# ── Upload with retry ─────────────────────────────────────────────
def upload_with_retry(bucket, s3_key, filepath, region, access_key, secret_key):
    """Upload with exponential backoff retry. Returns (ok, status_code)."""
    for attempt in range(UPLOAD_MAX_RETRIES):
        status, body = s3_put(bucket, s3_key, filepath, region, access_key, secret_key)
        if status in (200, 201):
            return True, status
        log(f"Upload attempt {attempt + 1}/{UPLOAD_MAX_RETRIES} failed: HTTP {status}", level="WARN")
        if verbose_global and body:
            log(f"Response: {body[:500]}", level="WARN")
        if attempt < UPLOAD_MAX_RETRIES - 1:
            delay = UPLOAD_RETRY_BACKOFF[attempt]
            log(f"Retrying in {delay}s...", level="WARN")
            time.sleep(delay)
    return False, status


# ── Main ───────────────────────────────────────────────────────────
verbose_global = False

def main():
    global verbose_global

    parser = argparse.ArgumentParser(description="Backup OpenClaw PVC config to S3")
    parser.add_argument("--dry-run", action="store_true",
                        help="Create archive locally, skip upload")
    parser.add_argument("--verbose", action="store_true",
                        help="Print excluded dirs/files and extra detail")
    args = parser.parse_args()
    verbose_global = args.verbose

    # ── Load config ──────────────────────────────────────────────
    access_key    = os.environ.get("AWS_ACCESS_KEY_ID")
    secret_key    = os.environ.get("AWS_SECRET_ACCESS_KEY")
    region        = os.environ.get("AWS_REGION", "ap-southeast-2")
    bucket        = os.environ.get("S3_BUCKET")
    backup_prefix = os.environ.get("BACKUP_PREFIX", DEFAULT_BACKUP_PREFIX)

    # Fall back to credentials file on PVC
    cred_file = os.path.expanduser("~/.openclaw/credentials/aws-backup.json")
    if not all([access_key, secret_key, bucket]) and os.path.exists(cred_file):
        import json as _json
        with open(cred_file) as f:
            creds = _json.load(f)
        access_key    = access_key    or creds.get("aws_access_key_id")
        secret_key    = secret_key    or creds.get("aws_secret_access_key")
        region        = region        or creds.get("region", "ap-southeast-2")
        bucket        = bucket        or creds.get("bucket")
        backup_prefix = backup_prefix or creds.get("backup_prefix", DEFAULT_BACKUP_PREFIX)

    if not args.dry_run and not all([access_key, secret_key, bucket]):
        log("Missing AWS credentials. Set AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, S3_BUCKET.", level="ERROR")
        sys.exit(1)

    if not os.path.isdir(OPENCLAW_DIR):
        log(f"Source directory not found: {OPENCLAW_DIR}", level="ERROR")
        sys.exit(1)

    timestamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H%M%SZ")
    s3_key    = f"{backup_prefix}/{timestamp}.tar.gz"

    log(f"Source:    {OPENCLAW_DIR}")
    log(f"Excluding: {', '.join(sorted(EXCLUDE_DIRS))}")
    if args.dry_run:
        log("DRY RUN — archive will not be uploaded")

    # ── Create archive ───────────────────────────────────────────
    with tempfile.NamedTemporaryFile(suffix=".tar.gz", delete=False) as tmp:
        tmp_path = tmp.name

    try:
        log("Creating archive...")
        try:
            stats = create_backup_archive(OPENCLAW_DIR, tmp_path, verbose=args.verbose)
        except Exception as e:
            log(f"Archive creation failed: {e}", level="ERROR")
            log_json("backup_failed", stage="archive", error=str(e))
            sys.exit(2)

        size_bytes = os.path.getsize(tmp_path)
        size_mb    = size_bytes / (1024 * 1024)
        log(f"Archive:   {size_mb:.1f} MB ({stats['total_files']} files)")

        # ── Integrity check ──────────────────────────────────────
        log("Verifying archive integrity...")
        ok, member_count, err = verify_archive(tmp_path)
        if not ok:
            log(f"Archive integrity check FAILED: {err}", level="ERROR")
            log_json("backup_failed", stage="verify", error=err)
            sys.exit(3)
        log(f"Integrity OK ({member_count} members)")

        if args.dry_run:
            log(f"DRY RUN complete. Would upload to: s3://{bucket}/{s3_key}")
            log_json("backup_dry_run", size_mb=round(size_mb, 1),
                     total_files=stats["total_files"], member_count=member_count,
                     s3_path=f"s3://{bucket}/{s3_key}")
            return

        # ── Upload ───────────────────────────────────────────────
        log(f"Uploading to s3://{bucket}/{s3_key} ...")
        ok, status = upload_with_retry(bucket, s3_key, tmp_path, region, access_key, secret_key)

        if ok:
            log(f"✓ Backup complete")
            log_json("backup_success", size_mb=round(size_mb, 1),
                     total_files=stats["total_files"], member_count=member_count,
                     s3_bucket=bucket, s3_key=s3_key)
        else:
            log(f"✗ Upload failed after {UPLOAD_MAX_RETRIES} attempts (last HTTP {status})", level="ERROR")
            log_json("backup_failed", stage="upload", http_status=status,
                     s3_bucket=bucket, s3_key=s3_key)
            sys.exit(4)

    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass


if __name__ == "__main__":
    main()
