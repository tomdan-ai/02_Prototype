# SwiftDrop Logistics: WhatsApp Automation Prototype

AIL Lead Systems & Automation Engineer Assessment. **Synthetic data only — no real customer, delivery, or personal information.**

SwiftDrop Logistics is a fictional Nigerian SME courier service. This prototype is a first-stage WhatsApp automation layer built in n8n that handles common customer requests (delivery booking, quotes, tracking, rescheduling, problem reports), collects and validates the information needed to act on them, and escalates to a human operations team whenever automation is uncertain, unavailable, or inappropriate.

## Status

- [x] Infrastructure (Docker Compose, PostgreSQL, n8n)
- [x] Database schema + synthetic seed data
- [x] Workflow 1 — Incoming Message Router (webhook, validation, dedup, intent routing)
- [x] Workflow 2 — Delivery Request (full multi-turn booking flow, quote, tracking number generation)
- [x] Workflow 3 — Quote Request
- [x] Workflow 4 — Track Delivery (+ simulated integration-failure handling with retry/escalation)
- [x] Workflow 5 — Reschedule Delivery (eligibility check, escalation for ineligible deliveries)
- [x] Workflow 6 — Escalation Handler (delivery problems, HIGH priority, simulated ops notification)
- [x] WhatsApp simulator (browser chat UI)
- [x] Operational metrics (SQL queries)
- [ ] Final written submission sections (cost analysis, security/risk, NDPA 2023, 90-day plan)
- [ ] Demo video

## Architecture

```
WhatsApp Simulator (browser)
        │ POST /webhook/whatsapp
        ▼
n8n: 01 - Incoming Message Router
  validate → find/create customer → dedupe by message_id
  → save inbound message → load active conversation → classify intent
        │
        ├─ DELIVERY_REQUEST     → 02 - Delivery Request    (sub-workflow)
        ├─ DELIVERY_QUOTE       → 03 - Quote Request        (sub-workflow)
        ├─ TRACK_DELIVERY       → 04 - Track Delivery       (sub-workflow)
        ├─ RESCHEDULE_DELIVERY  → 05 - Reschedule Delivery  (sub-workflow)
        └─ DELIVERY_PROBLEM     → 06 - Escalation Handler   (sub-workflow)
        ▼
PostgreSQL (customers, conversations, messages, deliveries, escalations, audit_logs)
        ▼
Reply text returned synchronously in the webhook response
```

Each intent is a separate n8n workflow, invoked from the router via an **Execute Workflow** node and returning `{ reply, next_state, ... }`. This keeps each flow small enough to understand and modify independently, and matches n8n's own sub-workflow pattern rather than one monolithic canvas.

Conversation state is stored in the `conversations` table (`current_intent`, `current_state`, `context` as JSONB) so a multi-turn flow survives across separate webhook calls — each inbound message is a fresh HTTP request with no in-memory session.

## Setup

Requires Docker and Docker Compose (no Docker Desktop needed — plain `docker.io` + `docker-compose-v2` packages work fine on Ubuntu).

```bash
cd 02_Prototype
cp .env.example .env     # edit POSTGRES_PASSWORD / N8N_BASIC_AUTH_PASSWORD before any real use
docker compose up -d
docker compose ps        # both swiftdrop-postgres and swiftdrop-n8n should be healthy/running
```

- n8n editor: http://localhost:5678
- PostgreSQL: `localhost:5433` (not 5432 — remapped to avoid clashing with a locally installed Postgres; internal container-to-container traffic between n8n and Postgres still uses 5432)

The schema, seed data, and a sequence for tracking-number generation in `database/` run automatically against the `swiftdrop` database on first container start, via Postgres's `docker-entrypoint-initdb.d` mechanism. n8n keeps its own internal state in a separate `n8n` database on the same Postgres instance (created by `database/00-create-n8n-db.sql`), so application data and n8n's workflow/execution metadata never mix.

To reset the database from scratch: `docker compose down -v && docker compose up -d`.

### Importing the workflows

n8n workflows are version-controlled as JSON in `n8n/`. On a fresh n8n instance:

1. Create a Postgres credential in n8n (Credentials → Add → Postgres): host `postgres`, database `swiftdrop`, user/password from `.env`, port `5432` (the internal container port).
2. For each file in `n8n/` (import in numeric order, 01 through 06): **+** → **Import from File**, then re-select the Postgres credential in every Postgres node (credential IDs aren't portable across n8n instances, so this step is manual every time).
3. In Workflow 1, each "Run ... Flow" node (Execute Workflow) needs its target sub-workflow re-selected from its dropdown after import, for the same reason.
4. Publish every workflow once set up.
5. Create the tracking-number sequence once (not part of the auto-run init scripts, since it was added after the first deployment in this session — folded into `schema.sql` for any future fresh install):
   ```sql
   CREATE SEQUENCE IF NOT EXISTS tracking_number_seq START WITH 1100;
   ```

### Running the simulator

```bash
cd simulator
python3 -m http.server 8080
```

Open http://localhost:8080. The simulator posts directly to `http://localhost:5678/webhook/whatsapp` from the browser — n8n's webhook reflects CORS headers automatically, no extra configuration needed. Use the "New customer" button to start a fresh conversation with a random phone number, or type/use the quick-reply buttons for the four main scenarios (send a package, get a quote, track a delivery, report a problem).

Each simulated customer's chat history persists in the browser's `localStorage`, keyed by phone number, so refreshing the page doesn't lose the conversation. It's local to that browser only — same as n8n/Postgres, nothing here is a shared or server-side session.

## Database schema

| Table | Purpose |
|---|---|
| `customers` | One row per WhatsApp phone number |
| `conversations` | Multi-turn state machine: `current_intent`, `current_state`, `context` (JSONB) |
| `messages` | Full inbound/outbound message log, `external_id` unique for idempotency |
| `deliveries` | Created by the delivery-request flow; tracking numbers are `SD-####` |
| `escalations` | Human hand-off queue: `reason`, `priority`, `status` |
| `audit_logs` | Append-only event log (`INTENT_CLASSIFIED`, `DELIVERY_CREATED`, `ESCALATION_CREATED`, `INTEGRATION_FAILURE`, etc.) |

See `database/schema.sql` for full column definitions and constraints.

## Reliability features demonstrated

- **Idempotency**: every inbound message carries a `message_id`; duplicates are detected via a unique constraint on `messages.external_id` and silently ignored (logged as `DUPLICATE_MESSAGE_IGNORED`), so retried/duplicate WhatsApp deliveries never create duplicate bookings or notifications.
- **Graceful handling of incomplete input**: missing webhook fields return `400` with the specific missing fields named, logged as `VALIDATION_FAILURE`. Missing conversation fields (e.g. no pickup location yet) simply prompt the customer for what's needed next — nothing is invented or guessed.
- **Simulated integration failure + retry**: Workflow 4 (Track Delivery) treats the tracking number `SD-0000` as a forced simulated timeout of the "tracking service." The lookup node retries 3 times automatically (n8n's built-in retry-on-fail), then falls through to a graceful customer-facing message and an automatic MEDIUM-priority escalation — instead of surfacing an internal error.
- **Unsupported routes / ineligible reschedules** escalate to operations automatically rather than silently failing or guessing an answer.
- **Audit trail**: every meaningful event (classification, creation, failure, escalation, notification) is written to `audit_logs`, independent of n8n's own execution history — so "what happened to this request?" can be answered with a SQL query alone.

## Operational metrics

No dashboard was built — per the assessment's own guidance, the data matters more than the UI for this requirement. `database/metrics.sql` has 7 ready-to-run queries covering total requests, intent breakdown, escalations by priority/status, unresolved count, integration failures, and automation success rate:

```bash
docker exec -i swiftdrop-postgres psql -U swiftdrop -d swiftdrop < database/metrics.sql
```

## What's simulated vs. what's working

**Simulated:**
- WhatsApp itself (browser chat UI instead of the real WhatsApp Business API)
- The tracking-number-unavailable scenario (forced via the `SD-0000` sentinel, to make the failure path demoable on demand)
- Operations notification channel (written to `audit_logs` as a `NOTIFICATION_SENT` event rather than a real email/Slack message)
- Delivery status updates over time (seed data has fixed statuses; nothing moves a delivery through its lifecycle automatically)

**Actually working, end to end, against real Postgres data:**
- Webhook ingestion, input validation, customer creation
- Conversation state machine across multiple HTTP calls
- Intent classification and routing to 5 distinct conversational flows
- Quote calculation, route-support checking, delivery creation with generated tracking numbers
- Tracking lookup, reschedule eligibility checking, escalation creation
- Retry-then-escalate failure handling
- Full audit logging and the metrics queries above

## Known limitations / deferred cleanup

- `messages.intent` is not currently populated on inbound rows (intent is classified after the message is saved; not fixed as it doesn't block any demo or test case).
- Tracking lookups aren't scoped to the requesting customer's own deliveries (any customer can query any tracking number) — acceptable for this simulated prototype, would need an ownership check before any real deployment.
- Early in development, n8n's internal tables briefly ended up back in the `swiftdrop` database instead of staying isolated in `n8n` (see `database/00-create-n8n-db.sql`); a clean `docker compose down -v && up -d` resolves it if it recurs.

## Security & data handling

- `.env` is gitignored; only `.env.example` with placeholder values is committed. No credentials, API keys, or tokens are present anywhere in this repository.
- All customer data (names, phone numbers, delivery details) is synthetic/fictional, generated for this assessment only.
- n8n Postgres credentials are stored through n8n's own credential store, not hardcoded in workflow JSON.
- Webhook input is validated before any processing; required fields are explicitly checked rather than assumed present.
- See the written submission for discussion of the Nigeria Data Protection Act 2023 as it would apply to a production deployment of this system.
