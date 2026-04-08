import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";

const CREDENTIALS_DIR = path.join(os.homedir(), ".openclaw");
const CREDENTIALS_FILE = path.join(CREDENTIALS_DIR, "jira-credentials.json");

function loadCredentials() {
  try {
    if (!fs.existsSync(CREDENTIALS_FILE)) return null;

    const raw = fs.readFileSync(CREDENTIALS_FILE, "utf8");
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function saveCredentials(creds) {
  if (!fs.existsSync(CREDENTIALS_DIR)) {
    fs.mkdirSync(CREDENTIALS_DIR, { recursive: true, mode: 0o700 });
  }

  fs.writeFileSync(CREDENTIALS_FILE, JSON.stringify(creds, null, 2), { encoding: "utf8", mode: 0o600 });
}

const plugin = {
  id: "jira-query",
  name: "Jira Query",
  description: "Read Jira issues with JQL and issue key lookups for a single-user pod.",
  configSchema: {
    type: "object",
    additionalProperties: false,
    properties: {
      baseUrl: { type: "string", minLength: 1 },
      email: { type: "string", minLength: 1 },
      apiToken: { type: "string", minLength: 1 },
      defaultProjectKeys: { type: "array", items: { type: "string" }, default: [] },
    },
  },
  register(api) {
    api.registerTool(
      () => ({
        name: "jira_query",
        label: "Jira Query",
        description:
          "Read and write Jira for a single-user pod. Actions: me, my_open_tickets, search_jql, issue_get, login_setup, issue_create, issue_update, comment_add, issue_transition.",
        parameters: {
          type: "object",
          additionalProperties: false,
          properties: {
            action: {
              type: "string",
              enum: ["me", "my_open_tickets", "search_jql", "issue_get", "login_setup", "issue_create", "issue_update", "comment_add", "issue_transition"],
              default: "my_open_tickets",
            },
            jql: { type: "string" },
            issueKey: { type: "string" },
            maxResults: { type: "integer", minimum: 1, maximum: 100, default: 20 },
            fields: {
              type: "array",
              items: { type: "string" },
              default: ["summary", "status", "assignee", "reporter", "priority", "updated", "created"],
            },
            raw: { type: "boolean", default: false },
            baseUrl: { type: "string" },
            email: { type: "string" },
            apiToken: { type: "string" },
            defaultProjectKeys: { type: "array", items: { type: "string" } },
            projectKey: { type: "string" },
            issueType: { type: "string" },
            summary: { type: "string" },
            description: { type: "string" },
            assignee: { type: "string" },
            priority: { type: "string" },
            labels: { type: "array", items: { type: "string" } },
            components: { type: "array", items: { type: "string" } },
            comment: { type: "string" },
            transitionId: { type: "string" },
            transitionName: { type: "string" },
            updateFields: { type: "object" },
          },
        },
        async execute(_toolCallId, params) {
          const action = String(params?.action || "my_open_tickets");

          if (action === "login_setup") {
            const cfg = await api.runtime.config.loadConfig();
            const entry = (cfg?.plugins?.entries?.["jira-query"]?.config || {});
            const configuredBaseUrl = String(entry.baseUrl || "").replace(/\/$/, "");

            if ((!params?.baseUrl && !configuredBaseUrl) || !params?.email || !params?.apiToken) {
              throw new Error("email and apiToken are required for action=login_setup, and baseUrl must be provided either in the call or plugin config");
            }

            const creds = {
              baseUrl: String(params.baseUrl || configuredBaseUrl).replace(/\/$/, ""),
              email: String(params.email).trim(),
              apiToken: String(params.apiToken).trim(),
              defaultProjectKeys: Array.isArray(params.defaultProjectKeys)
                ? params.defaultProjectKeys.map((x) => String(x).trim()).filter(Boolean)
                : [],
            };

            saveCredentials(creds);

            return {
              content: [{
                type: "text",
                text: JSON.stringify({
                  ok: true,
                  message: "Credentials saved for this pod",
                  email: creds.email,
                  baseUrl: creds.baseUrl,
                }, null, 2),
              }],
              details: { ok: true, email: creds.email },
            };
          }

          let baseUrl;
          let email;
          let apiToken;
          let defaultProjectKeys;

          const userCreds = loadCredentials();

          if (userCreds) {
            baseUrl = userCreds.baseUrl;
            email = userCreds.email;
            apiToken = userCreds.apiToken;
            defaultProjectKeys = userCreds.defaultProjectKeys || [];
          } else {
            const cfg = await api.runtime.config.loadConfig();
            const entry = (cfg?.plugins?.entries?.["jira-query"]?.config || {});

            baseUrl = String(entry.baseUrl || "").replace(/\/$/, "");
            email = String(entry.email || "").trim();
            apiToken = String(entry.apiToken || "").trim();
            defaultProjectKeys = Array.isArray(entry.defaultProjectKeys)
              ? entry.defaultProjectKeys.map((x) => String(x).trim()).filter(Boolean)
              : [];
          }

          if (!baseUrl || !email || !apiToken) {
            throw new Error("Missing Jira credentials. Use action=login_setup to configure this pod, or set plugins.entries.jira-query.config { baseUrl, email, apiToken }.");
          }

          const maxResults = Number(params?.maxResults || 20);
          const fieldsArr = Array.isArray(params?.fields)
            ? params.fields.map((x) => String(x)).filter(Boolean)
            : ["summary", "status", "assignee", "reporter", "priority", "updated", "created"];
          const fields = fieldsArr.join(",");
          const raw = Boolean(params?.raw);

          const auth = Buffer.from(`${email}:${apiToken}`, "utf8").toString("base64");
          const headers = {
            Authorization: `Basic ${auth}`,
            Accept: "application/json",
            "Content-Type": "application/json",
          };

          const call = async (urlPath, method = "GET", body) => {
            const res = await fetch(`${baseUrl}${urlPath}`, {
              method,
              headers,
              body: body === undefined ? undefined : JSON.stringify(body),
            });
            const ct = res.headers.get("content-type") || "";
            const data = ct.includes("application/json") ? await res.json() : await res.text();
            if (!res.ok) {
              throw new Error(`Jira API ${res.status}: ${typeof data === "string" ? data : JSON.stringify(data)}`);
            }
            return data;
          };

          let out;

          if (action === "me") {
            out = await call("/rest/api/3/myself");
          } else if (action === "issue_get") {
            const issueKey = String(params?.issueKey || "").trim();
            if (!issueKey) throw new Error("issueKey is required for action=issue_get");
            out = await call(`/rest/api/3/issue/${encodeURIComponent(issueKey)}?fields=${encodeURIComponent(fields)}`);
          } else if (action === "my_open_tickets" || action === "search_jql") {
            let jql = String(params?.jql || "").trim();
            if (action === "my_open_tickets" && !jql) {
              const projectClause = defaultProjectKeys.length
                ? ` AND project in (${defaultProjectKeys.map((p) => `"${p}"`).join(",")})`
                : "";
              jql = `assignee = currentUser() AND statusCategory != Done${projectClause} ORDER BY updated DESC`;
            }
            if (!jql) throw new Error("jql is required for action=search_jql");

            out = await call("/rest/api/3/search/jql", "POST", {
              jql,
              maxResults,
              fields: fieldsArr,
            });
          } else if (action === "issue_create") {
            const projectKey = String(params?.projectKey || "").trim();
            const issueType = String(params?.issueType || "Task").trim();
            const summary = String(params?.summary || "").trim();

            if (!projectKey) throw new Error("projectKey is required for action=issue_create");
            if (!summary) throw new Error("summary is required for action=issue_create");

            const issueFields = {
              project: { key: projectKey },
              issuetype: { name: issueType },
              summary,
            };

            if (params?.description) {
              issueFields.description = {
                type: "doc",
                version: 1,
                content: [
                  {
                    type: "paragraph",
                    content: [{ type: "text", text: String(params.description) }],
                  },
                ],
              };
            }

            if (params?.assignee) {
              issueFields.assignee = { accountId: String(params.assignee) };
            }

            if (params?.priority) {
              issueFields.priority = { name: String(params.priority) };
            }

            if (Array.isArray(params?.labels) && params.labels.length > 0) {
              issueFields.labels = params.labels.map((l) => String(l));
            }

            if (Array.isArray(params?.components) && params.components.length > 0) {
              issueFields.components = params.components.map((c) => ({ name: String(c) }));
            }

            out = await call("/rest/api/3/issue", "POST", { fields: issueFields });
          } else if (action === "issue_update") {
            const issueKey = String(params?.issueKey || "").trim();
            if (!issueKey) throw new Error("issueKey is required for action=issue_update");

            const issueFields = {};

            if (params?.summary) {
              issueFields.summary = String(params.summary);
            }

            if (params?.description) {
              issueFields.description = {
                type: "doc",
                version: 1,
                content: [
                  {
                    type: "paragraph",
                    content: [{ type: "text", text: String(params.description) }],
                  },
                ],
              };
            }

            if (params?.assignee) {
              issueFields.assignee = { accountId: String(params.assignee) };
            }

            if (params?.priority) {
              issueFields.priority = { name: String(params.priority) };
            }

            if (Array.isArray(params?.labels)) {
              issueFields.labels = params.labels.map((l) => String(l));
            }

            if (params?.updateFields && typeof params.updateFields === "object") {
              Object.assign(issueFields, params.updateFields);
            }

            await call(`/rest/api/3/issue/${encodeURIComponent(issueKey)}`, "PUT", { fields: issueFields });
            out = { ok: true, issueKey, message: "Issue updated successfully" };
          } else if (action === "comment_add") {
            const issueKey = String(params?.issueKey || "").trim();
            const comment = String(params?.comment || "").trim();

            if (!issueKey) throw new Error("issueKey is required for action=comment_add");
            if (!comment) throw new Error("comment is required for action=comment_add");

            const buildParagraphContent = (text) => {
              const URL_REGEX = /(https?:\/\/[^\s]+)/g;
              const trimUrlTrailing = (url) => url.replace(/[)*?\].,!;:'"]+$/, "");
              const nodes = [];
              let lastIndex = 0;
              let match;
              while ((match = URL_REGEX.exec(text)) !== null) {
                const rawUrl = match[1];
                const cleanUrl = trimUrlTrailing(rawUrl);
                const trailingChars = rawUrl.slice(cleanUrl.length);
                if (match.index > lastIndex) {
                  nodes.push({ type: "text", text: text.slice(lastIndex, match.index) });
                }
                nodes.push({
                  type: "text",
                  text: cleanUrl,
                  marks: [{ type: "link", attrs: { href: cleanUrl } }],
                });
                if (trailingChars) {
                  nodes.push({ type: "text", text: trailingChars });
                }
                lastIndex = match.index + rawUrl.length;
              }
              if (lastIndex < text.length) {
                nodes.push({ type: "text", text: text.slice(lastIndex) });
              }
              return nodes.length > 0 ? nodes : [{ type: "text", text }];
            };

            const paragraphs = comment.split(/\n+/).filter(Boolean).map((line) => ({
              type: "paragraph",
              content: buildParagraphContent(line),
            }));

            const body = {
              body: {
                type: "doc",
                version: 1,
                content: paragraphs.length > 0 ? paragraphs : [{ type: "paragraph", content: [{ type: "text", text: comment }] }],
              },
            };

            out = await call(`/rest/api/3/issue/${encodeURIComponent(issueKey)}/comment`, "POST", body);
          } else if (action === "issue_transition") {
            const issueKey = String(params?.issueKey || "").trim();
            if (!issueKey) throw new Error("issueKey is required for action=issue_transition");

            if (!params?.transitionId && !params?.transitionName) {
              out = await call(`/rest/api/3/issue/${encodeURIComponent(issueKey)}/transitions`);
            } else {
              let transitionId = params?.transitionId ? String(params.transitionId) : null;

              if (!transitionId && params?.transitionName) {
                const transitions = await call(`/rest/api/3/issue/${encodeURIComponent(issueKey)}/transitions`);
                const targetName = String(params.transitionName).toLowerCase();
                const match = transitions?.transitions?.find((t) => String(t.name).toLowerCase() === targetName);
                if (!match) {
                  throw new Error(`Transition "${params.transitionName}" not found. Available: ${transitions?.transitions?.map((t) => t.name).join(", ")}`);
                }
                transitionId = match.id;
              }

              if (!transitionId) {
                throw new Error("transitionId or transitionName is required for action=issue_transition");
              }

              await call(`/rest/api/3/issue/${encodeURIComponent(issueKey)}/transitions`, "POST", {
                transition: { id: transitionId },
              });
              out = { ok: true, issueKey, transitionId, message: "Transition completed successfully" };
            }
          }

          const payload = raw
            ? out
            : {
                action,
                ok: true,
                summary:
                  action === "me"
                    ? { accountId: out?.accountId, emailAddress: out?.emailAddress, displayName: out?.displayName }
                    : action === "issue_get"
                      ? {
                          key: out?.key,
                          summary: out?.fields?.summary,
                          status: out?.fields?.status?.name,
                          assignee: out?.fields?.assignee?.displayName,
                          updated: out?.fields?.updated,
                        }
                      : action === "issue_create"
                        ? {
                            key: out?.key,
                            id: out?.id,
                            self: out?.self,
                            message: "Issue created successfully",
                          }
                        : action === "issue_update" || action === "issue_transition"
                          ? out
                          : action === "comment_add"
                            ? {
                                id: out?.id,
                                created: out?.created,
                                author: out?.author?.displayName,
                                message: "Comment added successfully",
                              }
                            : {
                                total: out?.total,
                                issues: (out?.issues || []).map((i) => ({
                                  key: i?.key,
                                  summary: i?.fields?.summary,
                                  status: i?.fields?.status?.name,
                                  assignee: i?.fields?.assignee?.displayName,
                                  updated: i?.fields?.updated,
                                })),
                              },
                data: out,
              };

          return {
            content: [{ type: "text", text: JSON.stringify(payload, null, 2) }],
            details: payload,
          };
        },
      }),
      { optional: true },
    );
  },
};

export default plugin;
