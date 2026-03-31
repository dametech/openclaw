import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import crypto from "node:crypto";
import os from "node:os";
import path from "node:path";

const storeQueues = new Map();
const inflightRuns = new Map();

function expandHome(value) {
  if (!value) return value;
  if (value === "~") return os.homedir();
  if (value.startsWith("~/")) return path.join(os.homedir(), value.slice(2));
  return value;
}

function normalize(payload) {
  return {
    content: [{ type: "text", text: JSON.stringify(payload, null, 2) }],
    details: payload,
  };
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

async function loadJobStore(filePath) {
  try {
    const raw = await readFile(filePath, "utf8");
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return { jobs: {} };
    }
    if (!parsed.jobs || typeof parsed.jobs !== "object" || Array.isArray(parsed.jobs)) {
      parsed.jobs = {};
    }
    return parsed;
  } catch (error) {
    if (error?.code === "ENOENT") {
      return { jobs: {} };
    }
    throw error;
  }
}

async function saveJobStore(filePath, store) {
  const dirPath = path.dirname(filePath);
  const tempPath = path.join(dirPath, `.${path.basename(filePath)}.tmp-${crypto.randomUUID()}`);
  await mkdir(dirPath, { recursive: true, mode: 0o700 });
  await writeFile(tempPath, JSON.stringify(store, null, 2) + "\n", { encoding: "utf8", mode: 0o600 });
  await rename(tempPath, filePath);
}

function getJobTimestamp(job) {
  return Date.parse(job.updatedAt || job.createdAt || 0);
}

function targetSummary(name) {
  return {
    name,
    serviceUrl: `http://${name}.openclaw.svc.cluster.local:18789`,
  };
}

function resolveTarget(targets, name) {
  const target = targets[name];
  if (!target) {
    return { error: "Unknown target" };
  }
  if (!target?.token) {
    return { error: "Target config missing token" };
  }
  return {
    target: {
      name,
      serviceUrl: `http://${name}.openclaw.svc.cluster.local:18789`,
      token: String(target.token),
      agent: "main",
    },
  };
}

async function withStore(jobStorePath, mutator) {
  const previous = storeQueues.get(jobStorePath) || Promise.resolve();
  let releaseQueue;
  const gate = new Promise((resolve) => {
    releaseQueue = resolve;
  });
  const queued = previous.catch(() => {}).then(() => gate);
  storeQueues.set(jobStorePath, queued);

  await previous.catch(() => {});

  try {
    const store = await loadJobStore(jobStorePath);
    const result = await mutator(store);
    await saveJobStore(jobStorePath, store);
    return result;
  } finally {
    releaseQueue();
    if (storeQueues.get(jobStorePath) === queued) {
      storeQueues.delete(jobStorePath);
    }
  }
}

async function createJob(jobStorePath, payload) {
  return withStore(jobStorePath, async (store) => {
    const jobId = crypto.randomUUID();
    const now = new Date().toISOString();
    const job = {
      jobId,
      status: "pending",
      createdAt: now,
      updatedAt: now,
      ...payload,
    };
    store.jobs[jobId] = job;
    return clone(job);
  });
}

async function updateJob(jobStorePath, jobId, mutator) {
  return withStore(jobStorePath, async (store) => {
    const job = store.jobs[jobId];
    if (!job) {
      return null;
    }
    await mutator(job);
    job.updatedAt = new Date().toISOString();
    store.jobs[jobId] = job;
    return clone(job);
  });
}

async function getJob(jobStorePath, jobId) {
  const store = await loadJobStore(jobStorePath);
  const job = store.jobs[jobId];
  return job ? clone(job) : null;
}

async function clearJobs(jobStorePath, options = {}) {
  return withStore(jobStorePath, async (store) => {
    const clearedJobIds = [];
    const clearedJobs = [];
    const now = Date.now();
    const completedBeforeSeconds = Number(options.completedBeforeSeconds || 0);
    const failedBeforeSeconds = Number(options.failedBeforeSeconds || 0);
    const statusFilter = String(options.statusFilter || "").trim();

    if (options.jobId) {
      const job = store.jobs[options.jobId];
      if (!job) {
        return null;
      }
      delete store.jobs[options.jobId];
      clearedJobIds.push(options.jobId);
      clearedJobs.push(clone(job));
      return { clearedJobIds, clearedJobs };
    }

    for (const [jobId, job] of Object.entries(store.jobs)) {
      const jobStatus = String(job?.status || "");
      const ageSeconds = Math.max(0, Math.floor((now - getJobTimestamp(job)) / 1000));

      let matches = false;
      if (jobStatus === "completed" && completedBeforeSeconds > 0 && ageSeconds >= completedBeforeSeconds) {
        matches = true;
      }
      if (jobStatus === "failed" && failedBeforeSeconds > 0 && ageSeconds >= failedBeforeSeconds) {
        matches = true;
      }
      if (statusFilter && jobStatus !== statusFilter) {
        matches = false;
      }

      if (matches) {
        delete store.jobs[jobId];
        clearedJobIds.push(jobId);
        clearedJobs.push(clone(job));
      }
    }

    return { clearedJobIds, clearedJobs };
  });
}

function stringifyStructuredInput(input) {
  try {
    return JSON.stringify(input, null, 2);
  } catch {
    return String(input);
  }
}

function buildResponsesInput(message, input) {
  if (input === undefined || input === null) {
    return message;
  }

  return [
    {
      type: "message",
      role: "user",
      content: [{ type: "input_text", text: message }],
    },
    {
      type: "message",
      role: "user",
      content: [{ type: "input_text", text: `Additional structured input (JSON):\n${stringifyStructuredInput(input)}` }],
    },
  ];
}

function extractOutputText(remoteResponse) {
  if (typeof remoteResponse?.output_text === "string" && remoteResponse.output_text.trim()) {
    return remoteResponse.output_text;
  }

  const outputItems = Array.isArray(remoteResponse?.output) ? remoteResponse.output : [];
  const texts = [];

  for (const item of outputItems) {
    const contentParts = Array.isArray(item?.content) ? item.content : [];
    for (const part of contentParts) {
      if (typeof part?.text === "string" && part.text) {
        texts.push(part.text);
      }
    }
  }

  return texts.length ? texts.join("\n") : null;
}

function normalizeRemoteResponse(remoteResponse) {
  if (!remoteResponse || typeof remoteResponse !== "object" || Array.isArray(remoteResponse)) {
    throw new Error("Malformed remote response: expected object");
  }

  const responseId = String(remoteResponse?.id || remoteResponse?.response_id || "").trim() || null;
  return {
    responseId,
    result: {
      responseId,
      outputText: extractOutputText(remoteResponse),
      response: remoteResponse,
    },
    remoteResponse,
  };
}

async function parseGatewayBody(response) {
  const contentType = response.headers.get("content-type") || "";
  if (contentType.includes("application/json")) {
    return await response.json();
  }
  return { raw: await response.text() };
}

async function callResponsesApi(target, request) {
  const url = new URL("/v1/responses", target.serviceUrl);
  const response = await fetch(url, {
    method: "POST",
    headers: {
      accept: "application/json",
      authorization: `Bearer ${target.token}`,
      "content-type": "application/json",
      "x-openclaw-agent-id": target.agent,
      "x-openclaw-scopes": "operator.write",
    },
    body: JSON.stringify(request),
  });
  const payload = await parseGatewayBody(response);
  if (!response.ok) {
    const message = payload?.error?.message || payload?.message || payload?.raw || `Responses API request failed (${response.status})`;
    const error = new Error(message);
    error.status = response.status;
    error.payload = payload;
    throw error;
  }
  return payload;
}

function buildResponsesRequest(message, input, jobId) {
  return {
    model: "openclaw",
    input: buildResponsesInput(message, input),
    user: `pod-delegate:${jobId}`,
  };
}

function pluginConfig(cfg) {
  const entry = cfg?.plugins?.entries?.["pod-delegate"]?.config || {};
  return {
    jobStorePath: expandHome(String(entry.jobStorePath || "~/.openclaw/pod-delegate-jobs.json")),
    defaultPollIntervalSeconds: Number(entry.defaultPollIntervalSeconds || 5),
    targets: entry?.targets && typeof entry.targets === "object" ? entry.targets : {},
  };
}

function buildFailure(message, extra = {}) {
  return normalize({ ok: false, error: message, ...extra });
}

async function recordTerminalFailure(jobStorePath, jobId, error, fallbackMessage) {
  return updateJob(jobStorePath, jobId, async (job) => {
    job.status = "failed";
    job.error = {
      message: String(error?.message || fallbackMessage),
      status: error?.status || null,
      payload: error?.payload || null,
    };
    job.completedAt = new Date().toISOString();
  });
}

function launchBackgroundRun(jobStorePath, jobId, target, request) {
  const promise = (async () => {
    await updateJob(jobStorePath, jobId, async (job) => {
      if (job.status === "pending") {
        job.status = "running";
      }
      job.transport = {
        type: "responses",
        endpoint: "/v1/responses",
        agentId: target.agent,
      };
    });

    try {
      const remoteResponse = await callResponsesApi(target, request);
      const normalized = normalizeRemoteResponse(remoteResponse);
      await updateJob(jobStorePath, jobId, async (job) => {
        job.status = "completed";
        job.remoteResponseId = normalized.responseId;
        job.remoteResponse = normalized.remoteResponse;
        job.result = normalized.result;
        delete job.error;
        job.completedAt = new Date().toISOString();
      });
      return normalized;
    } catch (error) {
      await recordTerminalFailure(jobStorePath, jobId, error, "Failed to invoke remote OpenResponses run");
      throw error;
    } finally {
      inflightRuns.delete(jobId);
    }
  })();

  inflightRuns.set(jobId, {
    jobId,
    startedAt: new Date().toISOString(),
    promise,
  });

  promise.catch(() => {});
}

function buildInflightMissingMessage() {
  return "Remote run is not inflight in this process. The process may have restarted; this job cannot be resumed automatically.";
}

const plugin = {
  id: "pod-delegate",
  name: "Pod Delegate",
  description: "Delegate work asynchronously to configured OpenClaw pods in the same cluster.",
  configSchema: {
    type: "object",
    additionalProperties: false,
    properties: {
      jobStorePath: {
        type: "string",
        default: "~/.openclaw/pod-delegate-jobs.json",
      },
      defaultPollIntervalSeconds: {
        type: "integer",
        minimum: 1,
        default: 5,
      },
      targets: {
        type: "object",
        additionalProperties: {
          type: "object",
          additionalProperties: false,
          properties: {
            token: { type: "string", minLength: 1 },
          },
          required: ["token"],
        },
        default: {},
      },
    },
  },
  register(api) {
    api.registerTool(() => ({
      name: "pod_delegate",
      label: "Pod Delegate",
      description: "Delegate work asynchronously to configured OpenClaw targets.",
      parameters: {
        type: "object",
        additionalProperties: false,
        properties: {
          action: {
            type: "string",
            enum: ["delegate_targets", "delegate_start", "delegate_status", "delegate_result", "delegate_clear"],
            default: "delegate_targets",
          },
          target: { type: "string", description: "Configured target name." },
          message: { type: "string", description: "Delegated message text." },
          jobId: { type: "string", description: "Local delegation job ID." },
          input: {
            description: "Optional additive structured payload for the remote agent.",
            oneOf: [
              { type: "object", additionalProperties: true },
              { type: "array", items: {} },
              { type: "string" },
              { type: "number" },
              { type: "boolean" },
              { type: "null" },
            ],
          },
          statusFilter: { type: "string", enum: ["completed", "failed"] },
          completedBeforeSeconds: { type: "integer", minimum: 1 },
          failedBeforeSeconds: { type: "integer", minimum: 1 },
        },
      },
      async execute(_toolCallId, params) {
        const cfg = await api.runtime.config.loadConfig();
        const { jobStorePath, defaultPollIntervalSeconds, targets } = pluginConfig(cfg);
        const action = String(params?.action || "delegate_targets");

        try {
          if (action === "delegate_targets") {
            const availableTargets = Object.entries(targets).map(([name]) => targetSummary(name));
            return normalize({
              ok: true,
              action,
              targets: availableTargets,
              count: availableTargets.length,
              defaultPollIntervalSeconds,
            });
          }

          if (action === "delegate_start") {
            const targetName = String(params?.target || "").trim();
            const message = String(params?.message || "").trim();

            if (!targetName) {
              return buildFailure("target is required for delegate_start", { action });
            }
            if (!message) {
              return buildFailure("message is required for delegate_start", { action, target: targetName });
            }

            const resolvedTarget = resolveTarget(targets, targetName);
            if (resolvedTarget.error) {
              return buildFailure(resolvedTarget.error, { action, target: targetName });
            }
            const target = resolvedTarget.target;

            const localJob = await createJob(jobStorePath, {
              target: targetSummary(targetName),
              request: {
                message,
                input: params?.input ?? null,
              },
              transport: {
                type: "responses",
                endpoint: "/v1/responses",
                agentId: target.agent,
              },
              pollIntervalSeconds: defaultPollIntervalSeconds,
            });

            const remoteRequest = buildResponsesRequest(message, params?.input ?? null, localJob.jobId);
            launchBackgroundRun(jobStorePath, localJob.jobId, target, remoteRequest);

            return normalize({
              ok: true,
              action,
              jobId: localJob.jobId,
              status: localJob.status,
              inflight: true,
            });
          }

          if (action === "delegate_status" || action === "delegate_result") {
            const jobId = String(params?.jobId || "").trim();
            if (!jobId) {
              return buildFailure(`jobId is required for ${action}`, { action });
            }

            const localJob = await getJob(jobStorePath, jobId);
            if (!localJob) {
              return buildFailure("No job found", { action, jobId });
            }

            const inflight = inflightRuns.has(jobId);

            if (localJob.status === "completed") {
              return normalize({
                ok: true,
                action,
                jobId,
                status: localJob.status,
                inflight,
                result: localJob.result ?? null,
                error: null,
              });
            }

            if (localJob.status === "failed") {
              return normalize({
                ok: action === "delegate_status",
                action,
                jobId,
                status: localJob.status,
                inflight,
                result: null,
                error: localJob.error || { message: "Remote run failed" },
              });
            }

            if (inflight) {
              return normalize({
                ok: action === "delegate_status",
                action,
                jobId,
                status: localJob.status,
                inflight: true,
                result: null,
                error: null,
              });
            }

            return normalize({
              ok: false,
              action,
              jobId,
              status: localJob.status,
              inflight: false,
              result: null,
              error: buildInflightMissingMessage(),
            });
          }

          if (action === "delegate_clear") {
            const jobId = String(params?.jobId || "").trim();
            const completedBeforeSeconds = Number(params?.completedBeforeSeconds || 0);
            const failedBeforeSeconds = Number(params?.failedBeforeSeconds || 0);
            const statusFilter = String(params?.statusFilter || "").trim();

            if (!jobId && completedBeforeSeconds <= 0 && failedBeforeSeconds <= 0) {
              return buildFailure("jobId or a completed/failed age filter is required for delegate_clear", { action });
            }

            const cleared = await clearJobs(jobStorePath, {
              jobId,
              completedBeforeSeconds,
              failedBeforeSeconds,
              statusFilter,
            });

            if (!cleared || (jobId && cleared.clearedJobIds.length === 0)) {
              return buildFailure("No job found", { action, jobId });
            }

            for (const clearedJobId of cleared.clearedJobIds) {
              inflightRuns.delete(clearedJobId);
            }

            return normalize({
              ok: true,
              action,
              jobId: jobId || null,
              cleared: cleared.clearedJobIds.length > 0,
              clearedCount: cleared.clearedJobIds.length,
              clearedJobIds: cleared.clearedJobIds,
            });
          }

          return buildFailure("Unsupported action", { action });
        } catch (error) {
          return buildFailure(String(error?.message || "Unexpected plugin error"), { action });
        }
      },
    }));
  },
};

export default plugin;
