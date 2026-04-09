---
name: dame-apps
description: Deploy static dashboards and web apps to the DAME internal app platform (apps.dametech.net), protected by Entra ID SSO. Use when any agent is asked to create, build, update, or deploy a dashboard, web app, chart, report, or any static HTML/JS/CSS content for internal DAME use. Triggers on phrases like "create a dashboard", "deploy an app", "build a chart", "publish a report", "create a web app", "deploy to dame apps", "make a dashboard for", etc. Each agent deploys under their own subfolder (e.g. apps.dametech.net/marc/my-app/).
---

# DAME Apps Skill

Deploy static web apps and dashboards to `apps.dametech.net` — DAME's internal app platform backed by S3 + CloudFront + Entra ID SSO.

## Platform

- **URL:** `https://apps.dametech.net/{agent}/{app-name}/`
- **Auth:** Entra ID SSO (DAME Microsoft login) — enforced automatically by CloudFront Lambda@Edge
- **Hosting:** Private S3 bucket `dame-openclaw-apps-assets`, served via CloudFront
- **Stack:** Static only — HTML, CSS, JavaScript, JSON. No server-side runtime.

## Folder Convention

Each agent owns a top-level folder. Apps live inside it:

```
dame-openclaw-apps-assets/
├── marc/
│   ├── energy-dashboard/
│   │   └── index.html
│   └── cost-report/
│       └── index.html
├── nick/
│   └── crm-summary/
│       └── index.html
└── scrumm4st3r/
    └── sprint-board/
        └── index.html
```

**Rule:** Always deploy to `s3://dame-openclaw-apps-assets/{agent_name}/{app_name}/`.
Use your agent name (e.g. `marc`, `nick`, `jack`, `luc`, `brad`) as the top-level folder.

## Deployment Steps

### 1. Build the app

Create `index.html` (and any supporting files). See `references/app-patterns.md` for common app types (charts, tables, dashboards). Use `assets/template/` as a starting point.

Keep it self-contained where possible — inline CSS/JS or use CDN-hosted libraries (Chart.js, Tailwind, etc.). Avoid build tools unless necessary.

### 2. Deploy to S3

Use the deploy script:

```bash
python3 scripts/deploy.py \
  --agent {agent_name} \
  --app {app_name} \
  --dir {local_build_dir}
```

The script will:
- Create the agent folder if it doesn't exist
- Upload all files with correct Content-Type headers
- Invalidate the CloudFront cache for that path
- Print the live URL when done

### 3. Verify

After deployment, curl the URL to confirm it redirects to Cognito login (unauthenticated):

```bash
curl -s -o /dev/null -w "%{http_code}" https://apps.dametech.net/{agent}/{app}/
# Expected: 302 (auth redirect) — means it's live
```

## App Guidelines

- Every app **must** have an `index.html` at the root of its folder
- Use relative paths for assets — don't hardcode full URLs
- For SPA routing: all paths must resolve to `index.html` (Lambda@Edge handles the `/` → `index.html` rewrite automatically)
- DAME brand colours: `#1B4B8A` (blue), `#F5A623` (orange) — see `references/app-patterns.md`
- Keep apps focused — one purpose per app

## Updating an App

Re-run `scripts/deploy.py` with the same `--agent` and `--app`. It syncs and invalidates the cache. Changes are live in ~30 seconds.

## References

- `references/app-patterns.md` — Common app types, boilerplate snippets, CDN library list
- `assets/template/` — Base HTML template to start from
