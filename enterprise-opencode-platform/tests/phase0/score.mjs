// Extracts cost, token counts, tool-call count and API errors from the NDJSON
// event stream produced by `opencode run --format json`.
//
// The event schema is not part of OpenCode's public contract, so this walks the
// tree looking for well-known field names rather than assuming fixed paths.
// Anything it cannot find comes back as null and prints as "-".
//
// Usage:
//   node score.mjs <events-file>          full JSON
//   node score.mjs <events-file> --line   one space-separated line for shell `read`

import { readFileSync } from "node:fs";

const events = readFileSync(process.argv[2], "utf8")
  .split("\n")
  .filter((line) => line.trim().startsWith("{"))
  .map((line) => {
    try {
      return JSON.parse(line);
    } catch {
      return null;
    }
  })
  .filter(Boolean);

let cost = 0;
let costSeen = false;
let input = 0;
let output = 0;
let tokensSeen = false;
const toolNames = [];
const errors = [];
const seen = new Set();

function walk(node) {
  if (node === null || typeof node !== "object") return;
  if (seen.has(node)) return;
  seen.add(node);

  if (Array.isArray(node)) {
    node.forEach(walk);
    return;
  }

  if (typeof node.cost === "number" && Number.isFinite(node.cost)) {
    cost += node.cost;
    costSeen = true;
  }

  // Usage blocks look like { tokens: { input, output, ... } } or a flat
  // { input_tokens, output_tokens }.
  const t = node.tokens;
  if (t && typeof t === "object" && (typeof t.input === "number" || typeof t.output === "number")) {
    input += t.input || 0;
    output += t.output || 0;
    tokensSeen = true;
  }
  if (typeof node.input_tokens === "number" || typeof node.output_tokens === "number") {
    input += node.input_tokens || 0;
    output += node.output_tokens || 0;
    tokensSeen = true;
  }

  if (node.type === "tool" && typeof node.tool === "string") {
    toolNames.push(node.tool);
  } else if (typeof node.toolCallId === "string" && typeof node.toolName === "string") {
    toolNames.push(node.toolName);
  }

  if (node.type === "error") {
    const msg =
      node.error?.data?.message ??
      node.error?.message ??
      node.error?.name ??
      "unknown error";
    errors.push(String(msg).slice(0, 160));
  }

  for (const value of Object.values(node)) walk(value);
}

events.forEach(walk);

const counts = {};
for (const name of toolNames) counts[name] = (counts[name] || 0) + 1;

const result = {
  cost: costSeen ? Number(cost.toFixed(6)) : null,
  inputTokens: tokensSeen ? input : null,
  outputTokens: tokensSeen ? output : null,
  toolCalls: toolNames.length,
  toolBreakdown: counts,
  errors: [...new Set(errors)],
  eventCount: events.length,
};

if (process.argv.includes("--line")) {
  // Commas and whitespace would break both `read` and the CSV downstream.
  const err = result.errors[0]
    ? result.errors[0].replace(/[\s,"]+/g, "_").slice(0, 80)
    : "-";
  process.stdout.write(
    [
      result.cost ?? "-",
      result.inputTokens ?? "-",
      result.outputTokens ?? "-",
      result.toolCalls,
      err,
    ].join(" ") + "\n"
  );
} else {
  process.stdout.write(JSON.stringify(result, null, 2) + "\n");
}
