# Pilot Evaluation Environment — Enterprise AI Coding Stack

A self-contained pilot that puts **Continue.dev** (IDE), **LiteLLM Proxy** (routing, budgets, caching),
**OpenRouter** (model provider), and **Langfuse Cloud** (tracing) behind one endpoint, so engineers get
AI coding assistance without ever handling a provider API key.

## What this pilot proves

| Objective | How it is enforced |
| --- | --- |
| Model–task alignment | Continue maps autocomplete → `tier-1-fast`, chat → `tier-2-balanced`, deep reasoning → `tier-3-flagship` |
| Cost cap | Per-developer LiteLLM virtual keys with a hard `$30 / 30d` budget; requests are rejected at the cap |
| Zero-dev friction | `seed-developer-keys.sh` emits a ready-to-paste `config.json` with the key and proxy URL baked in |
| Observability | Every generation, model name, and token count streams to Langfuse Cloud |

## Model tiers

| Alias | OpenRouter model | Used for | Falls back to |
| --- | --- | --- | --- |
| `tier-1-fast` | `qwen/qwen-2.5-coder-32b-instruct` | Tab autocomplete, quick inline edits | — |
| `tier-2-balanced` | `deepseek/deepseek-chat` | Default chat, standard refactoring | `tier-1-fast` |
| `tier-3-flagship` | `anthropic/claude-3.7-sonnet` | Architecture, multi-file reasoning | `tier-2-balanced` |

## Layout

```text
.
├── docker/
│   ├── docker-compose.yml               # LiteLLM proxy + Postgres (required for virtual keys)
│   ├── litellm-config.yaml              # Model aliases, fallbacks, caching, Langfuse callbacks
│   └── litellm-config.fallback-test.yaml # Test fixture: tier-3 deliberately broken
├── client/
│   └── .continue/
│       └── config.json            # IDE configuration template
├── scripts/
│   ├── seed-developer-keys.sh     # Budgeted virtual key generator + config renderer
│   ├── test-proxy-routing.sh      # Tiers, prompt cache, SSE streaming
│   ├── test-key-controls.sh       # Budget enforcement + model allowlist
│   └── test-fallbacks.sh          # Tier-3 -> tier-2 failover
├── DEPLOYMENT-CHECKLIST.md        # Phased rollout tracker with owners
└── .env.example
```

## Prerequisites

Docker with Compose v2, `curl`, and `jq`. Accounts on OpenRouter (with credit) and Langfuse Cloud.

This repo is a pilot harness, not a production deployment. See
[Before this is a working prototype](#before-this-is-a-working-prototype) for what still needs to be
configured or decided — hosting and TLS, secret storage, rate limits, data governance, and the
success metrics the pilot is supposed to produce.

To actually run the rollout, work through [DEPLOYMENT-CHECKLIST.md](DEPLOYMENT-CHECKLIST.md), which
sequences the same material into owned, phased tasks.

## Deployment

### 1. Environment

```bash
cp .env.example .env
# fill in OPENROUTER_API_KEY, LITELLM_MASTER_KEY, LANGFUSE_PUBLIC_KEY, LANGFUSE_SECRET_KEY
chmod +x scripts/*.sh
```

`LITELLM_MASTER_KEY` is the admin credential; generate one with `echo "sk-$(openssl rand -hex 24)"`.
It must never be distributed to developers — they only ever receive virtual keys.

### 2. Launch the proxy

```bash
docker compose -f docker/docker-compose.yml up -d
curl http://localhost:4000/health/liveliness   # expect "I'm alive!"
```

The admin UI is at `http://localhost:4000/ui` (log in with the master key) for live spend per key.

### 3. Generate developer keys

```bash
./scripts/seed-developer-keys.sh http://localhost:4000 "$LITELLM_MASTER_KEY" pilot-dev-1
./scripts/seed-developer-keys.sh http://localhost:4000 "$LITELLM_MASTER_KEY" pilot-dev-2
```

Each run prints the virtual key and writes `client/.continue/generated/<alias>/config.json` with the
proxy URL and key already substituted. Override the cap per run with `MAX_BUDGET=50 BUDGET_DURATION=30d`.

### 4. Validate the stack

Run the three suites in order. Each exits non-zero on the first real failure, so they chain safely.

```bash
./scripts/test-proxy-routing.sh http://localhost:4000 <GENERATED_DEV_KEY>
./scripts/test-key-controls.sh  http://localhost:4000 "$LITELLM_MASTER_KEY"
./scripts/test-fallbacks.sh
```

| Script | Credential | What it proves |
| --- | --- | --- |
| `test-proxy-routing.sh` | developer key | Proxy is live; all three tiers answer; an identical prompt is served from cache; SSE streaming emits multiple chunks and terminates with `[DONE]` |
| `test-key-controls.sh` | master key | A generated key stores the $30 cap; an exhausted key is refused with `budget_exceeded`; a key scoped to one tier cannot reach another |
| `test-fallbacks.sh` | master key (read from `.env`) | A request to a failing tier-3 is rescued by tier-2 instead of erroring |

`test-key-controls.sh` mints throwaway keys with a fractional cap, spends past it, and deletes them on
exit — including on failure. It drives spend through `tier-3-flagship` on purpose, because LiteLLM
resolves Anthropic pricing reliably; a model whose price it cannot resolve accrues no spend and would
never trip a cap, which is the silent failure this test exists to catch. Each probe uses a unique
prompt so a cache hit can't mask the spend.

`test-fallbacks.sh` starts a disposable proxy on port 4111 from
`docker/litellm-config.fallback-test.yaml`, in which tier-3 points at an unresolvable model; the pilot
stack on :4000 is untouched. LiteLLM strips `mock_testing_fallbacks` from proxy requests as of v1.85.0
unless `dangerously_allow_mock_testing_request_params` is enabled, so genuinely breaking a deployment
in a throwaway container is both the supported and the safer way to exercise failover.

### 5. Verify observability

Send any chat request, then open Langfuse Cloud → Tracing. Each generation should show the tier alias,
the resolved OpenRouter model, token counts, latency, and cost.

### 6. Roll out to a developer

```bash
cp client/.continue/generated/pilot-dev-1/config.json ~/.continue/config.json
```

Install the Continue extension in VS Code or JetBrains, reload, then confirm: tab autocomplete fires
(tier 1) and the sidebar chat answers with "Tier 2 - Balanced" selected. Switch to "Tier 3 - Flagship"
from the model dropdown for architecture questions.

For remote proxies, replace `localhost` with the proxy host and terminate TLS in front of it — virtual
keys are bearer tokens and must not cross the network in plaintext.

If the developer already has a `~/.continue/config.yaml`, Continue loads that instead and your file is
ignored silently. Check for one before assuming the rollout worked.

## Verification checklist

- [ ] `.env` populated with all four secrets
- [ ] `docker compose ... up -d` healthy; `/health/liveliness` returns 200
- [ ] At least two developer virtual keys generated with a $30 cap
- [ ] `test-proxy-routing.sh` passes: three tiers, cache hit, streaming
- [ ] `test-key-controls.sh` passes: budget block and allowlist denial
- [ ] `test-fallbacks.sh` passes: tier-3 outage served by tier-2
- [ ] Traces with model name and token usage visible in Langfuse Cloud
- [ ] Continue.dev autocomplete and sidebar chat working from the generated config

## Before this is a working prototype

Everything above is the mechanism. This section is what still has to be decided or configured — grouped
by when it blocks you, because most of it is not code.

### A. Blocks the very first request

Nothing in this repo works until these are true.

- **Docker with Compose v2 installed.** Plus `curl` and `jq` on the admin machine.
- **An OpenRouter account with credit on it.** A key with a zero balance returns 402 from every tier
  and the fallback chain will mask it as a tier-1 answer. Set an account-level spend limit in
  OpenRouter as a backstop — the $30 caps here are per virtual key, and nothing stops the *sum* of
  them from exceeding what you intended to spend.
- **A Langfuse Cloud project**, with the correct regional host in `LANGFUSE_HOST` (the EU and US
  clouds are different hostnames; keys are not portable between them).
- **Verified model slugs.** Check all three against `curl https://openrouter.ai/api/v1/models` before
  first run. A renamed or retired slug surfaces as a confusing 400 rather than a clear config error,
  and `anthropic/claude-3.7-sonnet` is the most likely to have drifted.
- **Egress to `openrouter.ai` and `cloud.langfuse.com`** allowed from wherever the proxy runs.

### B. Blocks giving it to real developers

- **Host the proxy somewhere reachable, behind TLS.** Right now everything assumes `localhost`.
  Virtual keys are bearer tokens sent on every request, so plain HTTP over a corporate network leaks
  a spendable credential. Put the proxy on a VM or container service, give it a DNS name, terminate
  TLS in front of it, and regenerate client configs against `https://…` — `seed-developer-keys.sh`
  bakes in whatever URL you pass it as argument 1.
- **Pin the image.** `ghcr.io/berriai/litellm:main-latest` is a moving tag that can change under you
  mid-pilot and invalidate your results. Pin a specific `-stable` release in `docker-compose.yml` and
  upgrade deliberately.
- **Give Postgres a real password and a backup.** The compose file uses `litellm:litellm` on a local
  volume, which is fine on a laptop and unacceptable anywhere else. Spend history lives there — losing
  the volume silently resets every developer's budget to zero. Use a managed instance with backups.
- **Move secrets out of `.env`.** The master key is the credential that can mint unlimited keys and
  read every developer's traffic. For a hosted deployment it belongs in a secret manager, with a
  documented rotation path.
- **Add per-key rate limits.** A budget alone does not stop a runaway agent loop from burning the
  whole $30 in an afternoon. Rate limits bound the blast radius per hour rather than per month; add
  them to the payload in `seed-developer-keys.sh`:

```json
{ "rpm_limit": 60, "tpm_limit": 200000, "max_parallel_requests": 4 }
```

- **Wire up budget alerting.** Set `soft_budget` to ~80% of the cap so someone is warned before a
  developer is cut off mid-task, and enable LiteLLM's Slack alerting in `general_settings`
  (`alerting: ["slack"]` with `SLACK_WEBHOOK_URL`). Without this, the first signal that a cap was hit
  is the developer complaining.
- **Decide the config distribution mechanism.** `cp` to `~/.continue/config.json` does not scale past
  a handful of people and gives you no way to push a change. Options are a dotfiles repo, MDM, or an
  onboarding script that calls the seeder and installs the result.
- **Confirm the Continue config format against the version you deploy.** This is the largest
  compatibility risk in the client layer. Continue has deprecated `config.json` in favour of
  `config.yaml`, and loads `config.yaml` *in preference* if both exist — so a developer with an
  existing YAML config will silently ignore the file you ship. `customCommands` (the `/test` command
  here) has no `config.yaml` equivalent and is replaced by prompt files. The template follows the
  PRD's JSON format; pin a Continue extension version for the pilot, verify the `/test` command
  actually appears, and plan a YAML port.

### C. Policy decisions, not configuration

These need an owner and an answer before engineers point the tool at real source code.

- **Data governance at the provider.** Requests carry proprietary source code to third-party
  inference providers. Configure OpenRouter's account-level data policy to exclude providers that
  retain or train on prompts, and confirm the routing you get is acceptable to whoever owns that
  decision. This is usually the item that actually blocks an enterprise rollout.
- **Trace retention and access.** Langfuse traces contain full prompts and completions — that is
  source code sitting in a third-party SaaS. Set a retention window, restrict project access, and
  decide whether the pilot needs self-hosted Langfuse instead of Cloud.
- **What happens at the cap.** At $30 the key stops working and the developer is blocked. Decide in
  advance who approves a top-up and how fast, or the cost control becomes a productivity incident.
  Note also that `budget_duration: "30d"` is a rolling window from key creation, not a calendar
  month — finance may expect the latter.
- **Whether tiering should be enforced rather than suggested.** Today a developer can select Tier 3
  for everything, which defeats the cost model. The allowlist mechanism proven by
  `test-key-controls.sh` can restrict flagship access to specific keys or teams if the pilot shows
  people over-reach for it.

### D. Needed to answer the pilot's actual question

The stack can be fully deployed and still not tell you whether to buy it. Before onboarding anyone,
define and instrument:

- **Cost per developer per month**, from `/key/info` spend or Langfuse — the number that decides
  whether $30 is the right cap at 50 engineers.
- **Tier mix**, the share of spend and calls per tier. If tier 3 is 5% of calls and 60% of spend, the
  routing needs tightening; if nobody uses tier 1, autocomplete is not landing.
- **Latency per tier**, p50 and p95 from Langfuse. Autocomplete is unusable above roughly 500ms, and
  this is the most common reason a tier-1 model gets rejected by developers.
- **Autocomplete acceptance rate.** Continue writes local development data (`~/.continue/dev_data`)
  covering accepted and rejected completions; collecting it is the only quantitative read on whether
  tier 1 is good enough.
- **A satisfaction survey** at start and end. "Developer satisfaction" is in the objectives and is the
  one metric no amount of telemetry will produce for you.

## Implementation notes

Three deliberate deviations from the original spec, each required for the setup to actually run:

1. **Postgres is included in the compose stack.** LiteLLM's `/key/generate` endpoint — the mechanism
   behind per-developer budgets — is only available when the proxy has a `DATABASE_URL`. Without it,
   step 3 fails and there is no cost cap.
2. **`cache_params.type` is `local`, not `memory`.** `local` is LiteLLM's in-process cache type; the
   cache is silently disabled otherwise. Move to `redis` when running more than one proxy replica, so
   the cache and budget counters are shared.
3. **`stream: true` is not pinned in `litellm_params`.** Streaming is negotiated per request by
   Continue; forcing it server-side breaks non-streaming callers such as the test script.

Also added: `drop_params: true` (Continue sends params some backends reject), `num_retries: 2`, and
`failure_callback` so errors — not just successes — reach Langfuse.

Two notes on budget behaviour that affect how you read test output. Spend is flushed to Postgres
asynchronously, so `/key/info` lags the last request by a few seconds — `test-key-controls.sh` waits
between probes for this reason. And a refused over-budget request returns **HTTP 429** with error type
`budget_exceeded` on current builds; older builds returned 400, so the test accepts either and asserts
on the error type rather than the status code alone.

## Operating the pilot

- **Raise a cap:** `curl -X POST $PROXY/key/update -H "Authorization: Bearer $LITELLM_MASTER_KEY" -H 'Content-Type: application/json' -d '{"key":"<key>","max_budget":50}'`
- **Revoke a key:** same pattern against `/key/delete` with `{"keys":["<key>"]}`
- **Inspect spend:** `curl $PROXY/key/info?key=<key> -H "Authorization: Bearer $LITELLM_MASTER_KEY"`

At 50 engineers, move the cache to Redis, run two or more proxy replicas behind a load balancer, and
use LiteLLM teams so budgets roll up per squad rather than per individual.
