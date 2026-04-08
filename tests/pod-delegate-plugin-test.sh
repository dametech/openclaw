#!/bin/bash

set -euo pipefail

PLUGIN_JSON="openclaw/plugins/pod-delegate/openclaw.plugin.json"
PLUGIN_JS="openclaw/plugins/pod-delegate/index.js"

if [ ! -f "$PLUGIN_JSON" ]; then
    echo "missing expected file: $PLUGIN_JSON" >&2
    exit 1
fi

if [ ! -f "$PLUGIN_JS" ]; then
    echo "missing expected file: $PLUGIN_JS" >&2
    exit 1
fi

node --input-type=module <<'NODE'
import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";

const repoRoot = process.cwd();
const pluginJsonPath = path.join(repoRoot, "openclaw/plugins/pod-delegate/openclaw.plugin.json");
const pluginJsPath = path.join(repoRoot, "openclaw/plugins/pod-delegate/index.js");
const bootstrapPath = path.join(repoRoot, "openclaw/workspace/BOOTSTRAP.md");

function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
}

async function waitFor(check, timeoutMs = 1000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const value = await check();
    if (value) {
      return value;
    }
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  throw new Error("timed out waiting for condition");
}

const pluginJson = JSON.parse(await readFile(pluginJsonPath, "utf8"));
assert.equal(pluginJson.id, "pod-delegate");
assert.equal(pluginJson.name, "Pod Delegate");
assert.equal(pluginJson.configSchema.type, "object");
assert.equal(pluginJson.configSchema.additionalProperties, false);
assert.equal(pluginJson.configSchema.properties.jobStorePath.default, "~/.openclaw/pod-delegate-jobs.json");
assert.equal(pluginJson.configSchema.properties.defaultPollIntervalSeconds.default, 5);
assert.equal(pluginJson.configSchema.properties.targets.additionalProperties.required.length, 1);
assert.deepEqual(pluginJson.configSchema.properties.targets.additionalProperties.required, ["token"]);

const bootstrapDoc = await readFile(bootstrapPath, "utf8");
const deployEnvExample = await readFile(path.join(repoRoot, "deploy.env.example"), "utf8");
assert.match(bootstrapDoc, /This pod may start with no configured delegate targets\./);
assert.match(bootstrapDoc, /delegate pod\/service name and delegate pod gateway token/);
assert.match(bootstrapDoc, /The plugin derives the in-cluster service URL from the target name\./);
assert.match(deployEnvExample, /POD_DELEGATE_TARGETS_JSON='\{"openclaw-b":\{"token":"replace-with-gateway-token"\}\}'/);

const pluginModule = await import(pathToFileURL(pluginJsPath).href);
const plugin = pluginModule.default;
assert.equal(plugin.id, "pod-delegate");
assert.equal(plugin.name, "Pod Delegate");
assert.equal(typeof plugin.register, "function");

let initialFactory = null;
plugin.register({
  registerTool(factory) {
    initialFactory = factory;
  },
  runtime: {
    config: {
      async loadConfig() {
        return {};
      },
    },
  },
});

assert.equal(typeof initialFactory, "function");
const descriptor = initialFactory();
assert.equal(descriptor.name, "pod_delegate");
assert.deepEqual(
  descriptor.parameters.properties.action.enum,
  ["delegate_targets", "delegate_start", "delegate_status", "delegate_result", "delegate_clear"],
);
assert.equal(descriptor.parameters.properties.message.type, "string");
assert.equal(descriptor.parameters.properties.completedBeforeSeconds.type, "integer");
assert.equal(descriptor.parameters.properties.failedBeforeSeconds.type, "integer");

const tempRoot = await mkdtemp(path.join(os.tmpdir(), "pod-delegate-plugin-test-"));
const jobStorePath = path.join(tempRoot, "jobs.json");

function createTool(targets) {
  let factory = null;
  plugin.register({
    runtime: {
      config: {
        async loadConfig() {
          return {
            plugins: {
              entries: {
                "pod-delegate": {
                  config: {
                    jobStorePath,
                    defaultPollIntervalSeconds: 5,
                    targets,
                  },
                },
              },
            },
          };
        },
      },
    },
    registerTool(toolFactory) {
      factory = toolFactory;
    },
  });
  return factory();
}

async function readStore() {
  return JSON.parse(await readFile(jobStorePath, "utf8"));
}

const baseTargets = {
  alpha: {
    token: "secret-token",
  },
};

const delegateTargetsTool = createTool(baseTargets);
const targetsResponse = await delegateTargetsTool.execute("tool-call-1", { action: "delegate_targets" });
assert.equal(targetsResponse.details.ok, true);
assert.equal(targetsResponse.details.count, 1);
assert.equal(targetsResponse.details.targets[0].name, "alpha");
assert.equal(targetsResponse.details.targets[0].serviceUrl, "http://alpha.openclaw.svc.cluster.local:18789");

const unknownTargetTool = createTool(baseTargets);
const unknownTarget = await unknownTargetTool.execute("tool-call-2", {
  action: "delegate_start",
  target: "missing",
  message: "hello",
});
assert.equal(unknownTarget.details.ok, false);
assert.equal(unknownTarget.details.error, "Unknown target");

const invalidTargetTool = createTool({
  broken: {
    token: "",
  },
});
const invalidTarget = await invalidTargetTool.execute("tool-call-3", {
  action: "delegate_start",
  target: "broken",
  message: "hello",
});
assert.equal(invalidTarget.details.ok, false);
assert.equal(invalidTarget.details.error, "Target config missing token");

const finishNow = deferred();
const runOne = deferred();
const runTwo = deferred();
const plannedResponses = new Map([
  ["finish-now", finishNow],
  ["one", runOne],
  ["two", runTwo],
]);

globalThis.fetch = async (url, options) => {
  assert.equal(String(url), "http://alpha.openclaw.svc.cluster.local:18789/v1/responses");
  assert.equal(options.method, "POST");
  assert.equal(options.headers.authorization, "Bearer secret-token");
  assert.equal(options.headers["content-type"], "application/json");
  assert.equal(options.headers["x-openclaw-scopes"], "operator.write");

  const body = JSON.parse(options.body);
  assert.equal(body.model, "openclaw");
  assert.equal(typeof body.input, "string");
  assert.match(String(body.user || ""), /^pod-delegate:/);

  if (body.input === "finish-now") {
    assert.equal(options.headers["x-openclaw-agent-id"], "main");
    return finishNow.promise;
  }

  if (body.input === "one" || body.input === "two") {
    assert.equal(options.headers["x-openclaw-agent-id"], "main");
    return plannedResponses.get(body.input).promise;
  }

  throw new Error(`unexpected remote request for input: ${body.input}`);
};

const startTool = createTool(baseTargets);
const started = await startTool.execute("tool-call-4", {
  action: "delegate_start",
  target: "alpha",
  message: "finish-now",
});
assert.equal(started.details.ok, true);
assert.equal(started.details.status, "pending");
assert.equal(started.details.inflight, true);

let store = await readStore();
let localJob = store.jobs[started.details.jobId];
assert.equal(localJob.status, "pending");
assert.equal(localJob.transport.endpoint, "/v1/responses");
assert.equal(localJob.transport.agentId, "main");
assert.equal(localJob.target.serviceUrl, "http://alpha.openclaw.svc.cluster.local:18789");

const runningStatus = await startTool.execute("tool-call-5", {
  action: "delegate_status",
  jobId: started.details.jobId,
});
assert.equal(runningStatus.details.ok, true);
assert.ok(["pending", "running"].includes(runningStatus.details.status));
assert.equal(runningStatus.details.inflight, true);

finishNow.resolve({
  ok: true,
  status: 200,
  headers: { get: () => "application/json" },
  async json() {
    return {
      id: "resp-finish-now",
      output: [
        {
          type: "message",
          role: "assistant",
          content: [
            {
              type: "output_text",
              text: "done",
            },
          ],
        },
      ],
    };
  },
});

await waitFor(async () => {
  const nextStore = await readStore();
  return nextStore.jobs[started.details.jobId]?.status === "completed";
});

store = await readStore();
localJob = store.jobs[started.details.jobId];
assert.equal(localJob.status, "completed");
assert.equal(localJob.remoteResponseId, "resp-finish-now");
assert.equal(localJob.result.outputText, "done");

const finishedResult = await startTool.execute("tool-call-6", {
  action: "delegate_result",
  jobId: started.details.jobId,
});
assert.equal(finishedResult.details.ok, true);
assert.equal(finishedResult.details.status, "completed");
assert.equal(finishedResult.details.result.outputText, "done");

const concurrentTool = createTool(baseTargets);
const concurrentStarts = await Promise.all([
  concurrentTool.execute("tool-call-7", {
    action: "delegate_start",
    target: "alpha",
    message: "one",
  }),
  concurrentTool.execute("tool-call-8", {
    action: "delegate_start",
    target: "alpha",
    message: "two",
  }),
]);

assert.equal(concurrentStarts[0].details.ok, true);
assert.equal(concurrentStarts[1].details.ok, true);
assert.equal(concurrentStarts[0].details.inflight, true);
assert.equal(concurrentStarts[1].details.inflight, true);

runOne.resolve({
  ok: true,
  status: 200,
  headers: { get: () => "application/json" },
  async json() {
    return {
      id: "resp-one",
      output: [
        {
          type: "message",
          role: "assistant",
          content: [{ type: "output_text", text: "result-one" }],
        },
      ],
    };
  },
});

runTwo.resolve({
  ok: true,
  status: 200,
  headers: { get: () => "application/json" },
  async json() {
    return {
      id: "resp-two",
      output: [
        {
          type: "message",
          role: "assistant",
          content: [{ type: "output_text", text: "result-two" }],
        },
      ],
    };
  },
});

await waitFor(async () => {
  const nextStore = await readStore();
  return (
    nextStore.jobs[concurrentStarts[0].details.jobId]?.status === "completed" &&
    nextStore.jobs[concurrentStarts[1].details.jobId]?.status === "completed"
  );
});

store = await readStore();
assert.equal(Object.keys(store.jobs).length, 3);
assert.equal(store.jobs[concurrentStarts[0].details.jobId].result.outputText, "result-one");
assert.equal(store.jobs[concurrentStarts[1].details.jobId].result.outputText, "result-two");

await writeFile(jobStorePath, JSON.stringify({
  jobs: {
    stalled: {
      jobId: "stalled",
      status: "running",
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      target: {
        name: "alpha",
        serviceUrl: "http://alpha.openclaw.svc.cluster.local:18789",
      },
      request: {
        message: "stalled work",
      },
      transport: {
        type: "responses",
        endpoint: "/v1/responses",
        agentId: "main",
      },
    },
  },
}, null, 2));

const recoveryTool = createTool(baseTargets);
const stalledStatus = await recoveryTool.execute("tool-call-9", {
  action: "delegate_status",
  jobId: "stalled",
});
assert.equal(stalledStatus.details.ok, false);
assert.equal(stalledStatus.details.status, "running");
assert.equal(stalledStatus.details.inflight, false);
assert.match(stalledStatus.details.error, /not inflight in this process/);

const stalledResult = await recoveryTool.execute("tool-call-10", {
  action: "delegate_result",
  jobId: "stalled",
});
assert.equal(stalledResult.details.ok, false);
assert.equal(stalledResult.details.status, "running");
assert.equal(stalledResult.details.inflight, false);
assert.match(stalledResult.details.error, /not inflight in this process/);

const now = new Date();
const oldCompletedAt = new Date(now.getTime() - 120000).toISOString();
const oldFailedAt = new Date(now.getTime() - 180000).toISOString();
await writeFile(jobStorePath, JSON.stringify({
  jobs: {
    keep: {
      jobId: "keep",
      status: "running",
      createdAt: now.toISOString(),
      updatedAt: now.toISOString(),
    },
    done: {
      jobId: "done",
      status: "completed",
      createdAt: oldCompletedAt,
      updatedAt: oldCompletedAt,
    },
    bad: {
      jobId: "bad",
      status: "failed",
      createdAt: oldFailedAt,
      updatedAt: oldFailedAt,
    },
  },
}, null, 2));

const clearTool = createTool(baseTargets);
const clearCompleted = await clearTool.execute("tool-call-11", {
  action: "delegate_clear",
  completedBeforeSeconds: 60,
  statusFilter: "completed",
});
assert.equal(clearCompleted.details.ok, true);
assert.deepEqual(clearCompleted.details.clearedJobIds, ["done"]);

store = await readStore();
assert.equal(Boolean(store.jobs.done), false);
assert.equal(Boolean(store.jobs.bad), true);

const clearById = await clearTool.execute("tool-call-12", {
  action: "delegate_clear",
  jobId: "bad",
});
assert.equal(clearById.details.ok, true);
assert.deepEqual(clearById.details.clearedJobIds, ["bad"]);

store = await readStore();
assert.deepEqual(Object.keys(store.jobs), ["keep"]);

await rm(tempRoot, { recursive: true, force: true });
NODE

echo "pod-delegate plugin checks passed"
