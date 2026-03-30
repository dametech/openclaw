import { mkdir, readFile, writeFile, stat } from "node:fs/promises";
import { createReadStream } from "node:fs";
import path from "node:path";
import os from "node:os";

function expandHome(p) {
  if (!p) return p;
  if (p === "~") return os.homedir();
  if (p.startsWith("~/")) return path.join(os.homedir(), p.slice(2));
  return p;
}

async function loadStore(filePath) {
  try {
    const raw = await readFile(filePath, "utf8");
    return JSON.parse(raw);
  } catch {
    return {};
  }
}

async function saveStore(filePath, store) {
  await mkdir(path.dirname(filePath), { recursive: true, mode: 0o700 });
  await writeFile(filePath, JSON.stringify(store, null, 2) + "\n", { encoding: "utf8", mode: 0o600 });
}

async function refreshDelegatedToken(tenantId, clientId, refreshToken) {
  const res = await fetch(
    `https://login.microsoftonline.com/${encodeURIComponent(tenantId)}/oauth2/v2.0/token`,
    {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: clientId,
        grant_type: "refresh_token",
        refresh_token: refreshToken,
      }),
    },
  );
  const body = await res.json();
  if (!res.ok) {
    throw new Error(`Token refresh failed (${res.status}): ${JSON.stringify(body)}`);
  }
  return body;
}

async function uploadLargeFile(uploadUrl, filePath, fileSize, chunkSize = 320 * 1024 * 10) {
  let uploadedBytes = 0;
  const stream = createReadStream(filePath, { highWaterMark: chunkSize });

  for await (const chunk of stream) {
    const buffer = Buffer.from(chunk);
    const chunkStart = uploadedBytes;
    const chunkEnd = uploadedBytes + buffer.length - 1;

    const res = await fetch(uploadUrl, {
      method: "PUT",
      headers: {
        "Content-Length": String(buffer.length),
        "Content-Range": `bytes ${chunkStart}-${chunkEnd}/${fileSize}`,
      },
      body: buffer,
    });

    if (!res.ok && res.status !== 202) {
      const errorBody = await res.text();
      throw new Error(`Chunk upload failed (${res.status}): ${errorBody}`);
    }

    uploadedBytes += buffer.length;

    if (res.status === 201) {
      return await res.json();
    }
  }

  throw new Error("Upload completed but no 201 response received");
}

const plugin = {
  id: "ms-graph-query",
  name: "MS Graph Query",
  description: "Read data from Microsoft Graph (SharePoint, OneDrive, Outlook).",
  configSchema: {
    type: "object",
    additionalProperties: false,
    properties: {
      tenantId: { type: "string", minLength: 1 },
      clientId: { type: "string", minLength: 1 },
      delegatedScope: {
        type: "string",
        default: "offline_access openid profile User.Read Mail.Read Calendars.Read Files.Read Sites.Read.All",
      },
      graphBaseUrl: { type: "string", default: "https://graph.microsoft.com" },
      tokenStorePath: { type: "string", default: "~/.openclaw/ms-graph-query-tokens.json" },
      allowedPathPrefixes: {
        type: "array",
        items: { type: "string" },
        default: [
          "/v1.0/sites",
          "/v1.0/drives",
          "/v1.0/me",
          "/v1.0/users",
          "/v1.0/search/query",
        ],
      },
      allowedUserEmails: {
        type: "array",
        items: { type: "string" },
        default: [],
      },
      largeFileThreshold: {
        type: "number",
        default: 4 * 1024 * 1024,
        description: "File size threshold (bytes) for using resumable upload sessions",
      },
    },
  },
  register(api) {
    api.registerTool(
      () => ({
        name: "ms_graph_query",
        label: "MS Graph Query",
        description:
          "Query Microsoft Graph for SharePoint/OneDrive/Outlook using delegated device-code login.",
        parameters: {
          type: "object",
          additionalProperties: false,
          properties: {
            action: {
              type: "string",
              enum: ["query", "login_start", "login_poll", "login_status", "login_clear"],
              default: "query",
            },
            method: { type: "string", enum: ["GET", "POST", "PATCH", "PUT", "DELETE"], default: "GET" },
            path: { type: "string", description: "Graph path, e.g. /v1.0/sites?search=*" },
            body: {
              description: "Optional JSON body for POST/PUT/PATCH. Use object/array/string/number/bool/null.",
              oneOf: [
                { type: "object", additionalProperties: true },
                { type: "array", items: {} },
                { type: "string" },
                { type: "number" },
                { type: "boolean" },
                { type: "null" },
              ],
            },
            fileContent: {
              type: "string",
              description: "DEPRECATED: Use filePath instead. Raw file content to upload (causes memory issues for large files).",
            },
            filePath: {
              type: "string",
              description: "Path to file to upload (preferred over fileContent; automatically uses streaming for large files).",
            },
            contentType: {
              type: "string",
              description: "Content-Type header (e.g., 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'). Auto-detected from file extension if not provided.",
            },
            downloadToPath: {
              type: "string",
              description: "When downloading binary content, save to this file path instead of returning base64. Returns metadata { savedTo, size, contentType }.",
            },
            downloadToDir: {
              type: "string",
              description: "When downloading binary content, save to this directory with auto-generated filename. Returns metadata { savedTo, size, contentType }.",
            },
            raw: { type: "boolean", default: false },
          },
        },
        async execute(_toolCallId, params) {
          const cfg = await api.runtime.config.loadConfig();
          const entry = (cfg?.plugins?.entries?.["ms-graph-query"]?.config || {});
          const msteams = (cfg?.channels?.msteams || {});

          const tenantId = String(entry.tenantId || msteams.tenantId || "").trim();
          const clientId = String(entry.clientId || msteams.appId || "").trim();
          const delegatedScope = String(
            entry.delegatedScope ||
              "offline_access openid profile User.Read Mail.Read Calendars.Read Files.Read Sites.Read.All",
          ).trim();
          const graphBaseUrl = String(entry.graphBaseUrl || "https://graph.microsoft.com").replace(/\/$/, "");
          const tokenStorePath = expandHome(String(entry.tokenStorePath || "~/.openclaw/ms-graph-query-tokens.json"));
          const largeFileThreshold = Number(entry.largeFileThreshold || 4 * 1024 * 1024);

          const allowedPathPrefixes = Array.isArray(entry.allowedPathPrefixes)
            ? entry.allowedPathPrefixes.map((x) => String(x))
            : ["/v1.0/sites", "/v1.0/drives", "/v1.0/me", "/v1.0/users", "/v1.0/search/query"];
          const allowedUserEmails = (Array.isArray(entry.allowedUserEmails) ? entry.allowedUserEmails : [])
            .map((x) => String(x || "").trim().toLowerCase())
            .filter(Boolean);

          if (!tenantId || !clientId) {
            throw new Error("Missing tenantId/clientId in plugin config (or msteams channel config).");
          }

          const action = String(params?.action || "query");

          const json = (payload) => ({
            content: [{ type: "text", text: JSON.stringify(payload, null, 2) }],
            details: payload,
          });

          if (action === "login_start") {
            const res = await fetch(
              `https://login.microsoftonline.com/${encodeURIComponent(tenantId)}/oauth2/v2.0/devicecode`,
              {
                method: "POST",
                headers: { "content-type": "application/x-www-form-urlencoded" },
                body: new URLSearchParams({
                  client_id: clientId,
                  scope: delegatedScope,
                }),
              },
            );
            const body = await res.json();
            if (!res.ok) {
              throw new Error(`Device code start failed (${res.status}): ${JSON.stringify(body)}`);
            }

            const store = await loadStore(tokenStorePath);
            store.pending = {
              device_code: body.device_code,
              user_code: body.user_code,
              verification_uri: body.verification_uri,
              verification_uri_complete: body.verification_uri_complete,
              interval: body.interval,
              expires_in: body.expires_in,
              created_at: Date.now(),
            };
            await saveStore(tokenStorePath, store);

            return json({
              ok: true,
              message: body.message,
              user_code: body.user_code,
              verification_uri: body.verification_uri,
              verification_uri_complete: body.verification_uri_complete,
              interval: body.interval,
              expires_in: body.expires_in,
            });
          }

          if (action === "login_poll") {
            const store = await loadStore(tokenStorePath);
            const pending = store.pending;
            if (!pending?.device_code) {
              throw new Error("No pending device login. Start with action=login_start.");
            }

            const res = await fetch(
              `https://login.microsoftonline.com/${encodeURIComponent(tenantId)}/oauth2/v2.0/token`,
              {
                method: "POST",
                headers: { "content-type": "application/x-www-form-urlencoded" },
                body: new URLSearchParams({
                  client_id: clientId,
                  grant_type: "urn:ietf:params:oauth:grant-type:device_code",
                  device_code: pending.device_code,
                }),
              },
            );
            const body = await res.json();

            if (!res.ok) {
              const transient = ["authorization_pending", "slow_down"];
              if (transient.includes(String(body?.error || ""))) {
                return json({ ok: false, pending: true, error: body.error, description: body.error_description });
              }
              throw new Error(`Device token poll failed (${res.status}): ${JSON.stringify(body)}`);
            }

            store.delegated = {
              access_token: body.access_token,
              refresh_token: body.refresh_token,
              token_type: body.token_type,
              scope: body.scope,
              expires_at: Date.now() + Number(body.expires_in || 3600) * 1000,
            };
            delete store.pending;
            await saveStore(tokenStorePath, store);

            return json({ ok: true, authenticated: true, scope: body.scope, expires_in: body.expires_in });
          }

          if (action === "login_status") {
            const store = await loadStore(tokenStorePath);
            const t = store.delegated;
            return json({
              ok: true,
              authenticated: Boolean(t?.access_token),
              expires_at: t?.expires_at,
              expires_in_seconds: t?.expires_at ? Math.max(0, Math.floor((t.expires_at - Date.now()) / 1000)) : null,
              scope: t?.scope,
              pending: Boolean(store.pending),
            });
          }

          if (action === "login_clear") {
            const store = await loadStore(tokenStorePath);
            delete store.delegated;
            delete store.pending;
            await saveStore(tokenStorePath, store);
            return json({ ok: true, cleared: true });
          }

          const method = String(params?.method || "GET").toUpperCase();
          const pathValue = String(params?.path || "").trim();
          const raw = Boolean(params?.raw);

          if (!pathValue.startsWith("/")) throw new Error("path must start with '/'");
          if (!["GET", "POST", "PATCH", "PUT", "DELETE"].includes(method)) throw new Error(`Unsupported method: ${method}`);
          const pathAllowed = allowedPathPrefixes.some((prefix) => pathValue.startsWith(prefix));
          if (!pathAllowed) {
            throw new Error(`Path not allowlisted. Allowed prefixes: ${allowedPathPrefixes.join(", ")}`);
          }

          const usersMatch = pathValue.match(/^\/v1\.0\/users\/([^/\?]+)(?:[\/\?]|$)/i);
          if (usersMatch) {
            const rawUser = decodeURIComponent(usersMatch[1] || "").trim().toLowerCase();
            if (allowedUserEmails.length > 0 && !allowedUserEmails.includes(rawUser)) {
              throw new Error(`Access to user '${rawUser}' is denied by ms-graph-query allowedUserEmails policy.`);
            }
          }

          const delegatedAllowed =
            pathValue.startsWith("/v1.0/me") ||
            pathValue.startsWith("/v1.0/shares/") ||
            pathValue.startsWith("/v1.0/sites") ||
            pathValue.startsWith("/v1.0/drives") ||
            pathValue.startsWith("/v1.0/search/query");
          if (!delegatedAllowed) {
            throw new Error("Delegated mode only allows /v1.0/me, /v1.0/shares, /v1.0/sites, /v1.0/drives, and /v1.0/search paths.");
          }

          const store = await loadStore(tokenStorePath);
          let t = store.delegated;
          if (!t?.access_token) {
            throw new Error("No delegated token found. Use action=login_start then action=login_poll first.");
          }

          const now = Date.now();
          const expiryBuffer = 5 * 60 * 1000;
          const isExpired = t.expires_at && (t.expires_at - expiryBuffer) < now;

          if (isExpired && t.refresh_token) {
            try {
              const refreshed = await refreshDelegatedToken(tenantId, clientId, t.refresh_token);
              store.delegated = {
                access_token: refreshed.access_token,
                refresh_token: refreshed.refresh_token || t.refresh_token,
                token_type: "Bearer",
                scope: refreshed.scope || t.scope,
                expires_at: now + Number(refreshed.expires_in || 3600) * 1000,
              };
              await saveStore(tokenStorePath, store);
              t = store.delegated;
            } catch (err) {
              throw new Error(
                "Token expired and refresh failed. " +
                `Please re-authenticate with action=login_start. Error: ${err instanceof Error ? err.message : String(err)}`
              );
            }
          }

          const accessToken = t.access_token;
          const reqHeaders = {
            authorization: `Bearer ${accessToken}`,
            accept: "*/*",
          };
          let body;
          let useStreamingUpload = false;
          let filePathToUpload;
          let fileSize = 0;

          if (params?.filePath !== undefined) {
            filePathToUpload = String(params.filePath);
            try {
              const stats = await stat(filePathToUpload);
              fileSize = stats.size;
              if (fileSize >= largeFileThreshold) {
                useStreamingUpload = true;
              } else {
                body = await readFile(filePathToUpload);
              }
            } catch (err) {
              throw new Error(`Failed to read file at '${filePathToUpload}': ${err instanceof Error ? err.message : String(err)}`);
            }

            if (!params?.contentType) {
              const ext = path.extname(filePathToUpload).toLowerCase();
              const mimeTypes = {
                ".docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                ".xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                ".pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
                ".pdf": "application/pdf",
                ".txt": "text/plain",
                ".json": "application/json",
                ".xml": "text/xml",
                ".csv": "text/csv",
                ".zip": "application/zip",
                ".png": "image/png",
                ".jpg": "image/jpeg",
                ".jpeg": "image/jpeg",
                ".gif": "image/gif",
              };
              reqHeaders["content-type"] = mimeTypes[ext] || "application/octet-stream";
            } else {
              reqHeaders["content-type"] = String(params.contentType);
            }
          } else if (params?.fileContent !== undefined) {
            if (params?.body !== undefined) {
              throw new Error("Cannot specify both 'fileContent' and 'body'. Use one or the other.");
            }
            if (!params?.contentType) {
              throw new Error("contentType is required when using fileContent (e.g., 'text/plain', 'application/octet-stream').");
            }
            reqHeaders["content-type"] = String(params.contentType);
            body = String(params.fileContent);
          } else if (params?.body !== undefined) {
            reqHeaders["content-type"] = "application/json";
            if (typeof params.body === "string") {
              try {
                JSON.parse(params.body);
                body = params.body;
              } catch {
                body = JSON.stringify(params.body);
              }
            } else {
              body = JSON.stringify(params.body);
            }
          }

          if (useStreamingUpload && filePathToUpload) {
            if (!pathValue.includes(":/createUploadSession")) {
              throw new Error(
                "Large file upload requires path ending with ':/{filename}:/createUploadSession'. " +
                `File size: ${fileSize} bytes (threshold: ${largeFileThreshold} bytes)`
              );
            }

            const sessionRes = await fetch(`${graphBaseUrl}${pathValue}`, {
              method: "POST",
              headers: {
                authorization: `Bearer ${accessToken}`,
                "content-type": "application/json",
              },
              body: JSON.stringify({
                item: {
                  "@microsoft.graph.conflictBehavior": "rename",
                },
              }),
            });

            if (!sessionRes.ok) {
              const errorBody = await sessionRes.text();
              throw new Error(`Failed to create upload session (${sessionRes.status}): ${errorBody}`);
            }

            const sessionData = await sessionRes.json();
            const uploadUrl = sessionData.uploadUrl;
            if (!uploadUrl) {
              throw new Error("Upload session created but no uploadUrl returned");
            }

            const result = await uploadLargeFile(uploadUrl, filePathToUpload, fileSize);
            return {
              content: [{
                type: "text",
                text: JSON.stringify({
                  ok: true,
                  status: 201,
                  method: "PUT (streaming)",
                  path: pathValue,
                  authMode: "delegated",
                  fileSize,
                  uploaded: true,
                  data: result,
                }, null, 2),
              }],
              details: { ok: true, uploaded: true, fileSize, data: result },
            };
          }

          const res = await fetch(`${graphBaseUrl}${pathValue}`, { method, headers: reqHeaders, body });
          const contentType = (res.headers.get("content-type") || "").toLowerCase();
          const isJson = contentType.includes("application/json");
          const isText = contentType.startsWith("text/") ||
            contentType.includes("application/xml") ||
            contentType.includes("application/xhtml+xml") ||
            contentType.includes("application/csv");

          let payload;
          let encoding = "text";

          if (isJson) {
            payload = await res.json();
            encoding = "json";
          } else if (isText) {
            payload = await res.text();
            encoding = "text";
          } else {
            const buf = Buffer.from(await res.arrayBuffer());
            const downloadToPath = typeof params?.downloadToPath === "string" ? String(params.downloadToPath) : "";
            const downloadToDir = typeof params?.downloadToDir === "string" ? String(params.downloadToDir) : "";

            if (downloadToPath || downloadToDir) {
              let finalPath;
              if (downloadToPath) {
                finalPath = downloadToPath;
              } else {
                const contentDisposition = res.headers.get("content-disposition") || "";
                const filenameMatch = contentDisposition.match(/filename[^;=\n]*=((['"]).*?\2|[^;\n]*)/i);
                let filename = filenameMatch ? filenameMatch[1].replace(/['"]/g, "").trim() : "";

                if (filename) {
                  if (filename.toLowerCase().startsWith("utf-8")) {
                    const parts = filename.split("'");
                    filename = parts.length >= 3 ? parts[2] : filename.replace(/^utf-8/i, "");
                  }
                  try {
                    filename = decodeURIComponent(filename);
                  } catch {}
                }

                if (!filename) {
                  const urlPath = pathValue.split("?")[0];
                  const lastSegment = urlPath.split("/").filter(Boolean).pop() || "download";
                  try {
                    filename = decodeURIComponent(lastSegment);
                  } catch {
                    filename = lastSegment;
                  }
                  if (!path.extname(filename)) {
                    const ext = contentType.includes("pdf") ? ".pdf"
                      : contentType.includes("word") ? ".docx"
                      : contentType.includes("excel") || contentType.includes("spreadsheet") ? ".xlsx"
                      : contentType.includes("powerpoint") || contentType.includes("presentation") ? ".pptx"
                      : contentType.includes("image/png") ? ".png"
                      : contentType.includes("image/jpeg") ? ".jpg"
                      : contentType.includes("text/plain") ? ".txt"
                      : contentType.includes("json") ? ".json"
                      : "";
                    if (ext) filename += ext;
                  }
                }

                const safeFilename = path.basename(filename);
                if (!safeFilename || safeFilename === "." || safeFilename === "..") {
                  throw new Error(`Unsafe download filename derived from response: '${filename}'`);
                }
                finalPath = path.join(downloadToDir, safeFilename);
              }

              await mkdir(path.dirname(finalPath), { recursive: true });
              await writeFile(finalPath, buf);
              payload = { savedTo: finalPath, size: buf.length, contentType };
              encoding = "file";
            } else {
              payload = buf.toString("base64");
              encoding = "base64";
            }
          }

          const out = {
            ok: res.ok,
            status: res.status,
            method,
            path: pathValue,
            authMode: "delegated",
            contentType,
            encoding,
            data: payload,
          };

          return {
            content: [{ type: "text", text: raw ? JSON.stringify(payload, null, 2) : JSON.stringify(out, null, 2) }],
            details: out,
          };
        },
      }),
      { optional: true },
    );
  },
};

export default plugin;
