# AGENTS.md

Guidance for AI coding agents working in this repository. Follow these rules unless a task explicitly says otherwise. When existing code conflicts with a rule in this file, follow the existing code so the codebase stays consistent, and report the mismatch: name the rule, the file and what the code does instead, in your reply and in the PR description. Do not refactor the code to match the rule unless asked. Exception: security rules and the Repository setup settings always win; never copy an insecure pattern for consistency, flag it instead.

This file only describes what the project actually uses. A rule that starts with "When the project adds…" applies once the project has that capability; do not add the capability just to satisfy the rule.

## Repository setup

This repo starts from the team template. If any of these files are missing, stop and restore them from the template before writing feature code. Never weaken their settings to make a build pass.

- `.editorconfig`: formatting and C# style rules.
- `Directory.Build.props`: nullable reference types, warnings as errors, analyzers, build-time OpenAPI generation.
- `global.json`: pinned .NET SDK version.
- `web/tsconfig.json`: TypeScript strict mode.
- `.github/dependabot.yml`: dependency updates for NuGet, npm, Docker, Docker Compose and Actions.
- `.github/workflows/`: CI, CodeQL, the Docker build, scan and push pipeline, and the deploy job.
- `deploy/`: the production stack.
<!-- >>> dapr -->
- `components/`: Dapr components for local development and production.
<!-- <<< dapr -->
- `.dockerignore`, `web/.dockerignore` and `.gitignore`.

## Working principles

- Make the smallest change that solves the task. No drive-by refactors.
- State assumptions in the PR description or commit message.
- Never invent APIs, packages or config keys. If unsure, check the docs or ask.
- Keep functions small, names explicit, and side effects at the edges.
- Prefer composition over inheritance and explicit dependencies over globals.
- No secrets in code, tests or logs. Secrets reach the app as environment variables (the host's `.env` in production), never from files in the repo.

## Code quality

- Run the formatter, linter, type check and full test suite before proposing a change, using the Commands table. Run a single failing test first when iterating.
- Public interfaces get short doc comments explaining intent, not mechanics.
- Log with structure and include correlation IDs.
- Handle errors explicitly. No swallowed exceptions.
- Domain rule violations return results or raise domain exceptions mapped to Problem Details; never leak infrastructure exceptions to callers.
- Never hand-edit generated files (OpenAPI clients, lock files, migration snapshots); regenerate them.
- Do not reformat files you did not change.

## Test-driven development

- Work in red, green, refactor cycles: write a failing test first, make it pass with the simplest code, then clean up.
- Every bug fix starts with a test that reproduces the bug.
- Unit tests cover domain logic with no I/O. Integration tests cover infrastructure adapters against real dependencies, not mocks.
- Tests must be deterministic: no real clocks, random values or network calls without injection or fakes.
- Name tests by behaviour: `Given_<state>_When_<action>_Then_<outcome>`.
- Do not delete or weaken an existing test to make a change pass. Flag it instead.

<!-- >>> cqrs -->
## Architecture: CQRS

- Commands change state and return no domain data (at most an ID or acknowledgement).
- Queries read state and never change it.
- One handler per command and per query in the Application layer. Handlers are thin and delegate to the domain; API endpoints map each request to exactly one handler.
- Validate commands at the boundary before they reach the domain.
- Read models are separate from write models and may be denormalised for the query they serve.
- HTTP: commands map to `POST`/`PUT`/`PATCH`/`DELETE`, queries to `GET`. Commands return `202` or `201` with an ID, not the read model.
- Next.js mirrors the split: reads call query endpoints, writes go through server actions calling command endpoints.
- The UI expects eventual consistency: show pending states after a command instead of assuming the read model updated instantly.
- Authorisation is checked per command and per query.

<!-- <<< cqrs -->
<!-- >>> event-sourcing -->
## Event sourcing

- Aggregates are the consistency boundary. State changes only by applying events.
- Events are immutable, named in the past tense (`OrderPlaced`, not `PlaceOrder`), and carry everything needed to rebuild state.
- Never change the meaning of a published event. Add a new version and an upcaster instead.
- Use optimistic concurrency on the event stream (expected version).
- Projections build read models from events and must be idempotent and replayable.
- Snapshots are an optimisation only, never the source of truth.
- Test aggregates as: given past events, when command, then expected new events (or expected error).
- Aggregates and events live in `Domain`; the event store adapter lives in `Infrastructure` and stores events in the app's Postgres.
<!-- >>> dapr -->
- The Dapr state store may hold read models but never events.
<!-- <<< dapr -->
- Events carry a causation ID as well as the correlation ID.
- A reset script rebuilds every read model by replaying the event store from scratch.
- Stop and ask before changing a published event or deleting or rewriting stored events.
- Done means: new events are versioned and all projections replay cleanly.

<!-- <<< event-sourcing -->
## Data

- Each app owns one Postgres database. The API reads its connection string from `ConnectionStrings:Database`.
- When the project adds relational data, use EF Core with the Npgsql provider in `Infrastructure`; the DbContext and migrations live there. These packages need no stop-and-ask.
- Migrations must work with the previous release still running (expand first, contract in a later release), so a rollback stays possible.
- Before the first migration ships, stop and ask how production should apply migrations.

<!-- >>> dapr -->
## Decoupling with Dapr

- Key-value state, service-to-service calls<!-- >>> messaging --> and messaging<!-- <<< messaging --> go through Dapr building blocks behind interfaces owned by the Application layer. Domain and Application code never reference a broker, cache or cloud SDK.
- The relational database is the exception: it is accessed with EF Core in `Infrastructure` (see Data).
- Use the Dapr state store (`statestore`, backed by Postgres) for simple key-value state only.
<!-- >>> messaging -->
- Publish integration events through Dapr pub/sub (`pubsub`, backed by RabbitMQ). Keep integration events separate from internal domain events.
- Subscribers must be idempotent and tolerate at-least-once delivery.
<!-- <<< messaging -->
- Use Dapr service invocation for synchronous service-to-service calls, with resiliency policies (timeouts, retries, circuit breakers) defined in Dapr config, not hand-coded.
- Components live in `components/local/` (dev credentials) and `components/prod/` (credentials from the `envsecrets` store), with the same names. Local and production components may differ; code must not.
- Use the Dapr .NET SDK (`Dapr.Client`, `Dapr.AspNetCore`) only in `Infrastructure` and `Api`.

<!-- <<< dapr -->
## Back end: .NET

- Solution layout: `Domain` (entities and business rules, no dependencies), `Application` (use-case handlers, ports), `Infrastructure` (persistence and other adapters), `Api` (endpoints only), plus matching test projects under `tests/`.
- Use ASP.NET Core Minimal APIs or controllers consistently; endpoints map requests to application handlers and do nothing else.
- Use the built-in dependency injection, options pattern and `ILogger<T>`. No service locator.
- Async all the way with `CancellationToken` passed through. No `.Result` or `.Wait()`.
- Tests: xUnit. API integration tests use `WebApplicationFactory` from `Microsoft.AspNetCore.Mvc.Testing`. When a test needs Postgres, use Testcontainers rather than a shared database.

## API contracts: OpenAPI

- Every HTTP API has an OpenAPI document checked into the repo and treated as the contract. It is generated on build next to the Api project (`src/<Name>.Api/<Name>.Api.json`); commit it with the change that caused it.
- Generate it from ASP.NET Core (`Microsoft.AspNetCore.OpenApi`); CI fails if the committed spec drifts from the generated one.
- Use HTTP methods by intent: `GET` reads and never changes state; `POST`/`PUT`/`PATCH`/`DELETE` change state.
- Errors use RFC 9457 Problem Details.
- Version APIs explicitly. Breaking changes need a new version and a stop-and-ask.
- When the front end calls the API, generate its client and types from the spec; never handwrite them.

## Front end: Next.js

- Next.js with the App Router and TypeScript, in `web/`.
- Default to Server Components; add `"use client"` only for interactivity, state or browser APIs.
- Reads go through server components or route handlers; writes go through server actions calling the API.
- Validate all input at the boundary, before it reaches a server action or the API.
- No secrets in client code. Only `NEXT_PUBLIC_` variables reach the browser.
- Tests: unit and component tests with Vitest and Testing Library, next to the code (`*.test.tsx`). When the project adds end-to-end tests, use Playwright for the critical flows.
- Accessibility is a requirement: semantic HTML, labels on inputs, keyboard navigation.

## Containers and CI/CD

- Every deployable service (API, workers, Next.js app) has its own multi-stage `Dockerfile`: SDK image to build, slim runtime image to run. Tests run in CI, not in the image build.
- Run as a non-root user, pin base image versions, and keep a `.dockerignore`.
- Next.js uses `output: "standalone"` for a small runtime image.
<!-- >>> dapr -->
- Dapr runs as a sidecar; images never bundle the Dapr runtime.
<!-- <<< dapr -->
- Deployments pin the commit SHA or semver image tag, never latest.

The pipeline lives in `.github/workflows/`. Read it before changing anything about builds, tags or deployment. A new deployable image is one new entry in the `image` matrix of `docker.yml` and one new service in `deploy/compose.yml`.

### Deployment

- The app is self-contained: `deploy/compose.yml` brings its own database<!-- >>> messaging --> and broker<!-- <<< messaging -->. Never depend on infrastructure shared with other apps on the host.
- The app does not know the host's reverse proxy. Proxy labels, hostnames and external networks belong in `compose.host.yml` on the host, never in this repo.
- `deploy.yml` deploys after a green `docker` run on `main`, using the `sha-<full commit sha>` image tag. Roll back by running it manually with an older tag.
- Secrets live only in the host's `.env`; `deploy/.env.example` lists the names. Adding a secret means updating `.env.example` and telling the user to add it on the host before merging.

## Security

- Do not add a new package without stating why, its licence, and that it is actively maintained (stop-and-ask).
- Pin GitHub Actions to a major version at minimum; prefer a commit SHA for third-party actions.
- Validate all external input, authorise every operation, and never log tokens or personal data.
- When the project adds authentication, use OpenID Connect with the configured identity provider: APIs validate JWT bearer tokens, the Next.js server holds tokens, and the browser never sees them.
- Authorisation is enforced in the Application layer per use case, not only at the endpoint.

## Observability

- Structured logs to stdout. Every request<!-- >>> messaging --> and message<!-- <<< messaging --> carries a correlation ID.
- Health checks: `/healthz` (liveness) and `/readyz` (readiness) on every service. Register a readiness check for each dependency the service cannot work without.
- When the host has an OpenTelemetry collector, export traces, metrics and logs over OTLP from .NET and Next.js.
<!-- >>> dapr -->
- Enable Dapr tracing at the same time, so spans flow through Dapr calls.
<!-- <<< dapr -->
- New features ship with the logs needed to tell whether they work in production.

## Local development

- One command starts the full stack: `docker compose up --build`. It runs the same images and infrastructure as production, with dev credentials.
<!-- >>> messaging -->
- The RabbitMQ management UI is on http://localhost:15672 (user `app`, password `app`).
<!-- <<< messaging -->
- When the project has data, add seed data and a reset script so local data can be rebuilt from scratch.
- The agent runs the stack and exercises its change before calling it done.

## Commands

Keep this table accurate for this repo; agents run these instead of guessing. Front-end commands run in `web/`.

| Task | Command |
| --- | --- |
| Build back end | `dotnet build` |
| Test back end | `dotnet test` |
| Run one back-end test | `dotnet test --filter "FullyQualifiedName~<TestName>"` |
| Format back end | `dotnet format` |
| Install front end | `npm ci` |
| Lint and type check front end | `npm run lint && npx tsc --noEmit` |
| Test front end | `npm test` |
| Run one front-end test | `npx vitest run <path>` |
| Run full stack | `docker compose up --build` |

## Commits and pull requests

- Small, focused commits with Conventional Commit messages (`feat: add order export endpoint`, `fix:`, `chore:`), so changelogs and semver tags can be derived.
- Each PR explains what changed, why, how it was tested, and any assumptions.
- Update docs and this file when a convention changes.
- Work on a short-lived branch; `main` is protected and only receives merged, green PRs.

## When to stop and ask

- The task needs a new external dependency.
- A change would alter an API contract, message contract or database schema.
- Tests cannot be written for the requested behaviour.
- The change touches authentication, authorisation, secrets handling or the CI workflow.
- A migration, replay or script would delete or rewrite stored data.
- A test is flaky: report it, do not retry until green or mark it skipped without a linked issue.
- Requirements are ambiguous and a wrong guess would cost more than a question.

## Definition of done

- [ ] Tests written first and passing, including a regression test for bug fixes.
- [ ] CI is green, including security scans.
- [ ] OpenAPI spec updated and generated clients regenerated.
- [ ] Logs cover the new behaviour (and metrics and traces, once telemetry is set up).
- [ ] Docs and this file updated if a convention changed.
- [ ] PR description states what, why, how it was tested, and assumptions.
- [ ] Any conflicts between existing code and this file are reported.
