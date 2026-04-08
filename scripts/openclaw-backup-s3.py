#!/usr/bin/env python3
"""
OpenClaw PVC config backup to S3.
Pure stdlib — no boto3 required.

Usage:
  export AWS_ACCESS_KEY_ID=AKIA...
  export AWS_SECRET_ACCESS_KEY=...
  export AWS_REGION=ap-southeast-2      # optional, defaults to ap-southeast-2
  export S3_BUCKET=your-bucket-name
  python3 openclaw-backup-s3.py

Creates a tar.gz of ~/.openclaw/ config files (excluding tools, bin, go,
node_modules, .tool-versions, and large reproducible dirs) and uploads
to s3://<bucket>/openclaw-backups/<cluster>/<instance>/<pvc>/<timestamp>.tar.gz
"""

import datetime
import hashlib
import hmac
import os
import sys
import tarfile
import tempfile
import urllib.request
import urllib.error

# ── Config ─────────────────────────────────────────────────────────
OPENCLAW_DIR = os.path.expanduser("~/.openclaw")
BACKUP_CLUSTER = os.environ.get("BACKUP_CLUSTER", "au01-0")
BACKUP_INSTANCE = os.environ.get("BACKUP_INSTANCE", "unknown-instance")
BACKUP_PVC = os.environ.get("BACKUP_PVC", "openclaw-data")
BACKUP_PREFIX = f"openclaw-backups/{BACKUP_CLUSTER}/{BACKUP_INSTANCE}/{BACKUP_PVC}"

# Top-level directories to EXCLUDE (reproducible or large)
EXCLUDE_DIRS = {
    "bin", "tools", "go", ".tool-versions",
    "node_modules", ".cache", "chromium",
    "sessions",       # session data can be large, not config
}

# Individual filenames to EXCLUDE
EXCLUDE_FILES = {
    ".git-credentials",
}

# ── AWS SigV4 Signing ─────────────────────────────────────────────
def sign(key, msg):
    return hmac.new(key, msg.encode("utf-8"), hashlib.sha256).digest()

def get_signature_key(secret, date_stamp, region, service):
    k_date = sign(("AWS4" + secret).encode("utf-8"), date_stamp)
    k_region = sign(k_date, region)
    k_service = sign(k_region, service)
    k_signing = sign(k_service, "aws4_request")
    return k_signing

def s3_put(bucket, key, data, region, access_key, secret_key):
    """Upload bytes to S3 using PUT with SigV4 auth."""
    service = "s3"
    host = f"{bucket}.s3.{region}.amazonaws.com"
    endpoint = f"https://{host}/{key}"

    now = datetime.datetime.now(datetime.timezone.utc)
    amz_date = now.strftime("%Y%m%dT%H%M%SZ")
    date_stamp = now.strftime("%Y%m%d")

    content_hash = hashlib.sha256(data).hexdigest()

    # Canonical request
    canonical_uri = "/" + key
    canonical_querystring = ""
    canonical_headers = (
        f"host:{host}\n"
        f"x-amz-content-sha256:{content_hash}\n"
        f"x-amz-date:{amz_date}\n"
    )
    signed_headers = "host;x-amz-content-sha256;x-amz-date"
    canonical_request = (
        f"PUT\n{canonical_uri}\n{canonical_querystring}\n"
        f"{canonical_headers}\n{signed_headers}\n{content_hash}"
    )

    # String to sign
    credential_scope = f"{date_stamp}/{region}/{service}/aws4_request"
    string_to_sign = (
        f"AWS4-HMAC-SHA256\n{amz_date}\n{credential_scope}\n"
        + hashlib.sha256(canonical_request.encode("utf-8")).hexdigest()
    )

    # Signing key + signature
    signing_key = get_signature_key(secret_key, date_stamp, region, service)
    signature = hmac.new(
        signing_key, string_to_sign.encode("utf-8"), hashlib.sha256
    ).hexdigest()

    # Authorization header
    authorization = (
        f"AWS4-HMAC-SHA256 Credential={access_key}/{credential_scope}, "
        f"SignedHeaders={signed_headers}, Signature={signature}"
    )

    headers = {
        "Host": host,
        "x-amz-date": amz_date,
        "x-amz-content-sha256": content_hash,
        "Authorization": authorization,
        "Content-Type": "application/gzip",
        "Content-Length": str(len(data)),
    }

    req = urllib.request.Request(endpoint, data=data, headers=headers, method="PUT")
    try:
        resp = urllib.request.urlopen(req)
        return resp.status, resp.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def create_backup_archive(source_dir):
    """Create a tar.gz on disk, excluding large/reproducible dirs.

    Uses a temp file instead of in-memory buffer to avoid OOM under
    constrained K8s memory limits.
    """
    tmp = tempfile.NamedTemporaryFile(suffix=".tar.gz", delete=False)

    def exclude_filter(tarinfo):
        # Archive paths are like "openclaw/foo/bar" — split and take
        # components after the top-level archive name.
        parts = tarinfo.name.split(os.sep)
        if len(parts) <= 1:
            return tarinfo

        rel_parts = parts[1:]  # relative to the archive root

        # Skip excluded top-level directories
        if rel_parts[0] in EXCLUDE_DIRS:
            return None

        # Skip excluded individual files
        if tarinfo.isreg() and rel_parts[-1] in EXCLUDE_FILES:
            return None

        # Skip .git directories inside workspaces (can be large)
        if ".git" in rel_parts:
            idx = rel_parts.index(".git")
            if idx > 0 and rel_parts[idx - 1].startswith("workspace-"):
                return None

        return tarinfo

    try:
        with tarfile.open(fileobj=tmp, mode="w:gz") as tar:
            tar.add(source_dir, arcname="openclaw", filter=exclude_filter)
        tmp.close()

        with open(tmp.name, "rb") as f:
            data = f.read()
        return data
    finally:
        try:
            os.unlink(tmp.name)
        except OSError:
            pass


def main():
    access_key = os.environ.get("AWS_ACCESS_KEY_ID")
    secret_key = os.environ.get("AWS_SECRET_ACCESS_KEY")
    region = os.environ.get("AWS_REGION", "ap-southeast-2")
    bucket = os.environ.get("S3_BUCKET")

    # Fall back to credentials file on PVC
    cred_file = os.path.expanduser("~/.openclaw/credentials/aws-backup.json")
    if not all([access_key, secret_key, bucket]) and os.path.exists(cred_file):
        import json as _json
        with open(cred_file) as f:
            creds = _json.load(f)
        access_key = access_key or creds.get("aws_access_key_id")
        secret_key = secret_key or creds.get("aws_secret_access_key")
        region = region or creds.get("region", "ap-southeast-2")
        bucket = bucket or creds.get("bucket")

    if not all([access_key, secret_key, bucket]):
        print("Error: Set AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and S3_BUCKET")
        sys.exit(1)

    if not os.path.isdir(OPENCLAW_DIR):
        print(f"Error: {OPENCLAW_DIR} not found")
        sys.exit(1)

    # Create archive
    print(f"Creating backup archive of {OPENCLAW_DIR}...")
    print(f"Excluding: {', '.join(sorted(EXCLUDE_DIRS))}")
    archive_data = create_backup_archive(OPENCLAW_DIR)
    size_mb = len(archive_data) / (1024 * 1024)
    print(f"Archive size: {size_mb:.1f} MB")

    # Upload
    timestamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H%M%SZ")
    s3_key = f"{BACKUP_PREFIX}/{timestamp}.tar.gz"
    print(f"Uploading to s3://{bucket}/{s3_key}...")

    status, body = s3_put(bucket, s3_key, archive_data, region, access_key, secret_key)

    if status in (200, 201):
        print(f"✓ Backup uploaded successfully")
        print(f"  s3://{bucket}/{s3_key}")
        print(f"  Size: {size_mb:.1f} MB")
    else:
        print(f"✗ Upload failed (HTTP {status})")
        print(body)
        sys.exit(1)


if __name__ == "__main__":
    main()
