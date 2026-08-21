# Deployment Checklist — Getting the Pilot Into Engineers' Hands

Execution tracker for taking this repo from a laptop demo to a supported tool used by real engineers.
The README explains *why* each item matters; this file tracks *who does it and in what order*.

Assign an owner and a date to every line before starting. An unowned item is not a plan.

**Critical path:** Phase 0 is the long pole. Approval to send proprietary source code to third-party
inference providers routinely takes longer than all the engineering below combined, and if it comes
back "no" the technical work is wasted. Start it on day one and run Phases 1–3 in parallel.

**Suggested shape:** Week 1 — Phases 0–2. Week 2 — Phases 3–5. Week 3 — Phase 6 with 2 engineers.
Week 4+ — Phase 7 expansion and measurement. Phase 8 closes the pilot.

---

## Phase 0 — Approvals and decisions (start immediately, blocks Phase 6)

| | Item | Owner | Notes |
|---|---|---|---|
| [ ] | Security/legal sign-off on sending source code to third-party inference providers | | The gating item. Nothing ships to engineers without it. |
| [ ] | Configure OpenRouter account data policy to exclude providers that retain or train on prompts | | Verify the tiers still route acceptably afterwards; some providers drop out. |
| [ ] | Decide Langfuse Cloud vs self-hosted | | Traces contain full prompts and completions, i.e. source code in a SaaS. |
| [ ] | Set Langfuse trace retention window and restrict project access | | |
| [ ] | Agree the monthly budget envelope: $30 × headcount, plus who approves top-ups and how fast | | A blocked engineer at month-end is a productivity incident, not a cost saving. |
| [ ] | Decide whether tier-3 access is open to all or allowlisted per team | | Enforcement mechanism already proven by `test-key-controls.sh`. |
| [ ] | Name the pilot owner and the support channel | | One person accountable for spend and one Slack channel for issues. |

## Phase 1 — Accounts and credentials

| | Item | Owner | Notes |
|---|---|---|---|
| [ ] | OpenRouter account created, payment method attached, credit loaded | | |
| [ ] | OpenRouter account-level spend limit set as a backstop | | Per-key caps do not bound the total. |
| [ ] | Langfuse Cloud project created; note whether it is the EU or US host | | Keys are not portable between regions. |
| [ ] | Master key generated: `echo "sk-$(openssl rand -hex 24)"` | | Never distributed to engineers. |
| [ ] | Verify all three model slugs resolve against `curl https://openrouter.ai/api/v1/models` | | A retired slug surfaces as a confusing 400. |
| [ ] | Confirm pricing per tier and sanity-check the $30 cap against expected usage | | |

## Phase 2 — Infrastructure

| | Item | Owner | Notes |
|---|---|---|---|
| [ ] | Provision a host for the proxy (VM or container service) | | Localhost does not survive contact with a team. |
| [ ] | Managed Postgres provisioned, with backups enabled | | Spend history lives here; losing it resets every budget to zero. |
| [ ] | Replace the `litellm:litellm` credentials in `docker-compose.yml` | | |
| [ ] | Pin the LiteLLM image to a specific `-stable` tag | | `main-latest` moves and can invalidate pilot results mid-flight. |
| [ ] | DNS name assigned | | |
| [ ] | TLS terminated in front of the proxy | | Virtual keys are bearer tokens on every request. |
| [ ] | Secrets moved from `.env` into a secret manager | | Master key reads all traffic and mints unlimited keys. |
| [ ] | Egress to `openrouter.ai` and the Langfuse host allowed from the proxy | | |
| [ ] | Restrict who can reach `/ui` and the admin API | | Admin surface should not be open to the office network. |
| [ ] | Decide the restart/upgrade policy and who owns patching | | |

## Phase 3 — Proxy hardening

| | Item | Owner | Notes |
|---|---|---|---|
| [ ] | Add `rpm_limit`, `tpm_limit`, `max_parallel_requests` to the key payload in `seed-developer-keys.sh` | | Budgets are monthly; rate limits bound a runaway loop to an hour. |
| [ ] | Set `soft_budget` at ~80% of the cap | | Warn before cutting someone off. |
| [ ] | Enable Slack alerting (`alerting: ["slack"]` + `SLACK_WEBHOOK_URL`) | | Otherwise the first signal is a complaint. |
| [ ] | Confirm cost tracking resolves prices for all three tiers | | A model with unresolved pricing accrues no spend and never trips its cap. |
| [ ] | Decide Redis now or later | | Required before a second proxy replica; local cache and counters are per-process. |
| [ ] | Document the backup/restore procedure for Postgres | | Test the restore, not just the backup. |

## Phase 4 — Validation on the real deployment

Run against the hosted proxy over HTTPS, not localhost.

| | Item | Owner | Notes |
|---|---|---|---|
| [ ] | `/health/liveliness` returns 200 through the load balancer | | |
| [ ] | First-boot logs clean, no Prisma or database errors | | The proxy serves chat fine with a broken DB and fails only at key generation. |
| [ ] | `./scripts/test-proxy-routing.sh https://<host> <DEV_KEY>` passes | | Tiers, cache hit, streaming. |
| [ ] | `./scripts/test-key-controls.sh https://<host> "$MASTER_KEY"` passes | | Budget block and allowlist denial. |
| [ ] | `./scripts/test-fallbacks.sh` passes | | Tier-3 outage rescued by tier-2. |
| [ ] | Langfuse shows traces with tier alias, resolved model, tokens, latency, cost | | |
| [ ] | Confirm whether cached responses also create Langfuse traces | | If they do, reported cost overstates real spend. |
| [ ] | Measure p50/p95 latency for tier-1 through the real network path | | Autocomplete above ~500ms will be rejected by developers. |

## Phase 5 — Client packaging

| | Item | Owner | Notes |
|---|---|---|---|
| [ ] | Pin the Continue extension version for the pilot | | |
| [ ] | Verify the shipped `config.json` loads on that version and `/test` appears | | `config.json` is deprecated in favour of `config.yaml`. |
| [ ] | Add a pre-install check for an existing `~/.continue/config.yaml` | | If present, Continue loads it instead and ignores your file silently. |
| [ ] | Decide the distribution mechanism: dotfiles repo, MDM, or onboarding script | | `cp` does not scale and gives you no way to push a change. |
| [ ] | Write the one-page engineer setup guide | | Install extension, drop config, confirm autocomplete, where to ask for help. |
| [ ] | Tune tier-1 autocomplete settings against real latency | | `tabAutocompleteOptions` in the template are starting values. |
| [ ] | Dry run the whole install on a clean machine | | |

## Phase 6 — First cohort (2 engineers)

| | Item | Owner | Notes |
|---|---|---|---|
| [ ] | Phase 0 approvals confirmed complete | | Hard gate. |
| [ ] | Generate keys for the first two engineers | | `./scripts/seed-developer-keys.sh https://<host> "$MASTER_KEY" <alias>` |
| [ ] | Deliver keys over a secure channel, not Slack DM or email | | |
| [ ] | Baseline satisfaction survey before they start | | You cannot show improvement without a before. |
| [ ] | Both confirm autocomplete and chat work end to end | | |
| [ ] | Watch spend daily for the first week | | Validates the cap is set at a sane level before wider rollout. |
| [ ] | Support runbook written: cap hit, proxy down, model errors, key rotation | | |

## Phase 7 — Expand to the pilot group

| | Item | Owner | Notes |
|---|---|---|---|
| [ ] | Roll out to the remaining engineers in batches | | |
| [ ] | Enable Continue development data collection for acceptance rate | | `~/.continue/dev_data`; the only quantitative read on tier-1 quality. |
| [ ] | Dashboard: cost per developer per month | | |
| [ ] | Dashboard: tier mix by calls and by spend | | Tier 3 at 5% of calls and 60% of spend means routing needs tightening. |
| [ ] | Weekly spend and latency review | | |
| [ ] | Collect qualitative feedback continuously in the support channel | | |

## Phase 8 — Pilot exit

| | Item | Owner | Notes |
|---|---|---|---|
| [ ] | Closing satisfaction survey, compared against baseline | | |
| [ ] | Final cost per developer vs the $30 assumption | | Decides the cap at 50 engineers. |
| [ ] | Recommendation on tier composition and model choices | | |
| [ ] | Scaling plan to 50: Redis, multiple replicas, LiteLLM teams for per-squad budgets | | |
| [ ] | Go / no-go written up with the numbers behind it | | |

---

## Definition of done for "in engineers' hands"

Phases 0 through 6 complete, and specifically:

- An engineer can go from nothing to a working autocomplete in under 10 minutes using a written guide.
- No engineer ever handles an OpenRouter key.
- Spend per engineer is visible to the pilot owner without running a script.
- Someone is alerted before a developer is blocked by their cap, and there is a named person who can
  raise it the same day.
- Every request appears in Langfuse with model and cost attached.
