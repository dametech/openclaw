# OpenClaw Pod Tools

## Channels On This Pod

Channel integrations are not structured tools, but they are part of how this pod is accessed and used.

- `slack`
  Configured through `setup-slack-integration.sh`. The base config includes a disabled Slack channel block by default, and deploy preserves an existing configured Slack channel from live or restored state.
- `msteams`
  Configured through `setup-msteams-integration.sh`. This repo includes the Teams plugin and deploy preserves an existing configured Teams channel block from live or restored state.

## Custom Gateway Tools On This Pod

These custom gateway tools are deployed by default on this pod and should appear as structured tools when the gateway tool registry is working correctly:

- `ms_graph_query`
  Microsoft Graph delegated login, Outlook, OneDrive, and SharePoint operations.
- `jira_query`
  Jira login setup, ticket lookup, and Jira write actions for the configured account.
- `pod_delegate`
  Asynchronous delegation to other configured OpenClaw pods through the OpenResponses API.

## Optional Repo Plugin

The repo also contains an `msteams` plugin under `openclaw/plugins/msteams`, but it is not loaded on this pod by default.
It is enabled separately through `setup-msteams-integration.sh`.

## Local Shell Tooling In The Pod

This pod installs a PVC-backed local toolchain into `~/.openclaw/bin`, and the main container prepends that directory to `PATH`.

Common command-line tools available inside the pod include:

- `jq`
- `kubectl`
- `helm`
- `gh`
- `go`
- `terraform`
- `op`
- `aws`
- `curl`
- `tar`
- `gzip`
- `unzip`

Important: these binaries being present on `PATH` does not by itself make them agent-callable structured tools.
They are available for local shell execution only when the OpenClaw runtime exposes a shell or exec tool in the current agent context.
