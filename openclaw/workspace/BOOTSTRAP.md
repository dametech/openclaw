# OpenClaw Pod Bootstrap

## Microsoft Graph Login

This pod includes the `ms_graph_query` plugin for Microsoft Graph access.
`ms_graph_query` is a gateway tool that should already be available to the agent after startup.
`ms_graph_query` is expected to be available on this pod.
Do not ask the user whether `ms_graph_query` is expected to be available.
Invoke `ms_graph_query` directly as a tool call.
Do not use the `openclaw` CLI, shell commands, or direct gateway HTTP/API calls for this login flow.
Do not probe `/tools/invoke`, `/v1/responses`, other gateway endpoints, or Microsoft device-code endpoints directly for this flow.
When the user asks to log into Microsoft Graph, immediately call `ms_graph_query` with `action="login_start"` as the first step.
Do not spend time discovering invocation routes, checking CLI behavior, or testing alternate integration paths first.
If `ms_graph_query` is unavailable, report that as a startup/plugin-load or tool-registry problem on the pod instead of trying CLI or API workarounds.

Before using Microsoft Graph features, complete delegated device login:

1. Run `ms_graph_query` with `action="login_start"`.
   Use the tool directly and immediately.
2. Read the returned device login fields and present them directly to the user:
   Prefer `verification_uri_complete` / `device_login_url_complete` when present.
   Otherwise use `verification_uri` / `device_login_url`.
   The login code is `user_code` / `login_code`.
   Present the login details immediately after `login_start` returns.
3. Have the user open the device login URL and enter the login code.
4. After `login_start`, stop and wait for the user to confirm they completed browser sign-in.
5. Only then run `ms_graph_query` with `action="login_poll"` until authentication succeeds.
6. Optionally run `ms_graph_query` with `action="login_status"` to confirm the token is stored.

After login succeeds, the plugin can be used for Outlook, OneDrive, and SharePoint operations permitted by the configured Graph scopes.

## Jira Login

This pod includes the `jira_query` plugin for Jira access.
`jira_query` is expected to be available on this pod.

Before using Jira features, get a Jira API token and configure credentials once for this pod:

1. Use this Jira API URL for this pod: `${JIRA_BASE_URL:-https://dame-technologies.atlassian.net}`.
2. Ask the user for their Jira email address.
3. Ask the user for their Jira API token.
4. Run `jira_query` with `action="login_setup"`.
5. Provide `baseUrl`, `email`, and `apiToken`.
   Jira email goes in `email`.
   Jira API token goes in `apiToken`.
6. Optionally include `defaultProjectKeys` to scope default ticket lookups.

After setup succeeds, the plugin can query Jira and perform Jira write actions for the configured account.

## Inter-Pod Delegation

This pod includes the `pod_delegate` plugin for asynchronous delegation to other configured OpenClaw pods.
This pod may start with no configured delegate targets.

It delegates through the documented remote gateway OpenResponses API at `POST /v1/responses`.
Configured target gateways must expose this endpoint and enable `gateway.http.endpoints.responses.enabled`.
To configure delegation after deployment, the operator only needs the delegate pod/service name and delegate pod gateway token.
The plugin derives the in-cluster service URL from the target name.

1. Run `pod_delegate` with `action="delegate_targets"` to see available targets.
2. Run `pod_delegate` with `action="delegate_start"` to submit work and get a `jobId`.
3. Run `pod_delegate` with `action="delegate_status"` to check the local async job state.
4. Run `pod_delegate` with `action="delegate_result"` to fetch the final reply when complete.
