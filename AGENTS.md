# AGENTS.md

Guidance for AI coding agents working in this repository. Follow these rules unless a task explicitly says otherwise. When existing code conflicts with a rule in this file, follow the existing code so the codebase stays consistent, and report the mismatch: name the rule, the file and what the code does instead, in your reply and in the PR description. Do not refactor the code to match the rule unless asked. Exception: security rules and the Repository setup settings always win; never copy an insecure pattern for consistency, flag it instead.

Sections marked **(optional module)** are self-contained. Delete a module you do not use and no other section depends on it.

## Repository setup

This repo starts from the team template. If any of these files are missing, stop and restore them from the template before writing feature code. Never weaken their settings to make a build pass.

- `.editorconfig`: formatting and C# style rules.
- `Directory.Build.props`: nullable reference types, warnings as errors, analyzers, build-time OpenAPI generation.
- `global.json`: pinned .NET SDK version.
- `web/tsconfig.json`: TypeScript strict mode.
- `.github/dependabot.yml`: dependency updates for NuGet, npm, Docker, Docker Compose and Actions.
- `.github/workflows/`: CI, CodeQL, the Docker build, scan and push pipeline, and the deploy job.
- `deploy/` and `components/prod/`: the production stack and its Dapr components.
- `.dockerignore`, `web/.dockerignore` and `.gitignore`.

## Working principles

- Make the smallest change that solves the task. No drive-by refactors.
- State assumptions in the PR description or commit message.
- Never invent APIs, packages or config keys. If unsure, check the docs or ask.
- Keep functions small, names explicit, and side effects at the edges.
- Prefer composition over inheritance and explicit dependencies over globals.
- No secrets in code, tests or logs. Use the configured secret store.

## Code quality

- Run the formatter, linter, type check and full test suite before proposing a change, using the Commands table. Run a single failing test first when iterating.
- Public interfaces get short doc comments explaining intent, not mechanics.
- Log with structure and correlation IDs; propagate trace context through Dapr.
- Handle errors explicitly. No swallowed exceptions.
- Domain rule violations return results or raise domain exceptions mapped to Problem Details; never leak infrastructure exceptions to callers.
- Never hand-edit generated files (OpenAPI clients, lock files, migrations snapshots); regenerate them.
- Do not reformat files you did not change.

## Test-driven development

- Work in red, green, refactor cycles: write a failing test first, make it pass with the simplest code, then clean up.
- Every bug fix starts with a test that reproduces the bug.
- Unit tests cover domain logic with no I/O. Integration tests cover infrastructure adapters and Dapr components.
- Tests must be deterministic: no real clocks, random values or network calls without injection or fakes.
- Name tests by behaviour: `Given_<state>_When_<action>_Then_<outcome>`.
- Do not delete or weaken an existing test to make a change pass. Flag it instead.

## Architecture: CQRS (optional module)

Remove this section if the project does not separate commands and queries.

- Commands change state and return no domain data (at most an ID or acknowledgement).
- Queries read state and never change it.
- One handler per command and per query. Handlers are thin and delegate to the domain.
- Validate commands at the boundary before they reach the domain.
- Read models are separate from write models and may be denormalised for the query they serve.
- The Application layer holds one handler per command and per query; API endpoints map each request to exactly one of them.
- HTTP: commands map to `POST`/`PUT`/`PATCH`/`DELETE`, queries to `GET`. Commands return `202` or `201` with an ID, not the read model.
- Next.js mirrors the split: reads call query endpoints, writes go through server actions calling command endpoints.
- The UI expects eventual consistency: show pending states after a command instead of assuming the read model updated instantly.
- Authorisation is checked per command and per query.

## Event sourcing (optional module)

Remove this section if state is stored directly. It assumes the CQRS module.

- Aggregates are the consistency boundary. State changes only by applying events.
- Events are immutable, named in the past tense (`OrderPlaced`, not `PlaceOrder`), and carry everything needed to rebuild state.
- Never change the meaning of a published event. Add a new version and an upcaster instead.
- Use optimistic concurrency on the event stream (expected version).
- Projections build read models from events and must be idempotent and replayable.
- Snapshots are an optimisation only, never the source of truth.
- Test aggregates as: given past events, when command, then expected new events (or expected error).
- Layout: aggregates and events live in `Domain`; the event store adapter lives in `Infrastructure`.
- The event store is explicit; Dapr state management may hold read models but never events.
- Events carry a causation ID as well as the correlation ID.
- A reset script rebuilds every read model by replaying the event store from scratch.
- Stop and ask before changing a published event or deleting or rewriting stored events.
- Done means: new events are versioned and all projections replay cleanly.

## Decoupling with Dapr

- Domain and application code never reference a concrete broker, database or cloud SDK. Talk to infrastructure through Dapr building blocks behind an interface owned by the application layer.
- Publish integration events through Dapr pub/sub. Keep integration events separate from internal domain events.
- Use Dapr state management for simple state where appropriate.
- Use Dapr service invocation for synchronous service-to-service calls, with resiliency policies (timeouts, retries, circuit breakers) defined in Dapr config, not hand-coded.
- Read secrets and configuration through the Dapr secrets and configuration APIs.
- Component definitions live in `components/local/` (dev credentials) and `components/prod/` (credentials via the `envsecrets` secret store). Both sets use the same component names: `pubsub` (RabbitMQ) and `statestore` (Postgres). Local and production components may differ; code must not.
- Subscribers must be idempotent and tolerate at-least-once delivery.

## Back end: .NET

- Solution layout: `Domain` (entities and business rules, no dependencies), `Application` (use-case handlers, ports), `Infrastructure` (persistence, Dapr adapters), `Api` (endpoints only), plus matching test projects under `tests/`.
- Use ASP.NET Core Minimal APIs or controllers consistently; endpoints map requests to application handlers and do nothing else.
- Use the built-in dependency injection, options pattern and `ILogger<T>`. No service locator.
- Use the Dapr .NET SDK (`Dapr.Client`, `Dapr.AspNetCore`) only in `Infrastructure` and `Api`.
- Async all the way with `CancellationToken` passed through. No `.Result` or `.Wait()`.
- Tests: xUnit, a fluent assertion library, and Testcontainers or the Dapr sidecar for integration tests.

## API contracts: OpenAPI

- Every HTTP API has an OpenAPI document checked into the repo and treated as the contract. It is generated on build next to the Api project (`src/<Name>.Api/<Name>.Api.json`); commit it with the change that caused it.
- Generate it from ASP.NET Core (`Microsoft.AspNetCore.OpenApi`); CI fails if the committed spec drifts from the generated one.
- Use HTTP methods by intent: `GET` reads and never changes state; `POST`/`PUT`/`PATCH`/`DELETE` change state.
- Errors use RFC 9457 Problem Details.
- Version APIs explicitly. Breaking changes need a new version and a stop-and-ask.
- Front-end API clients and types are generated from the spec, never handwritten.

## Front end: Next.js

- Next.js with the App Router and TypeScript, in `web/`.
- Default to Server Components; add `"use client"` only for interactivity, state or browser APIs.
- Reads go through server components or route handlers; writes go through server actions calling the API.
- Validate input at the boundary with a schema library shared with the generated OpenAPI types.
- No secrets in client code. Only `NEXT_PUBLIC_` variables reach the browser.
- Tests: unit and component tests with Vitest plus Testing Library; end-to-end tests with Playwright for critical flows.
- Accessibility is a requirement: semantic HTML, labels on inputs, keyboard navigation.

## Containers and CI/CD

- Every deployable service (API, workers, Next.js app) has its own multi-stage `Dockerfile`: SDK image to build, slim runtime image to run. Tests run in CI, not in the image build.
- Run as a non-root user, pin base image versions, and keep a `.dockerignore`.
- Next.js uses `output: "standalone"` for a small runtime image.
- Dapr runs as a sidecar; images never bundle the Dapr runtime.
- Deployments pin the commit SHA or semver image tag, never latest.

The pipeline lives in `.github/workflows/`. Read it before changing anything about builds, tags or deployment. A new deployable image is one new entry in the `image` matrix of `docker.yml` and one new service in `deploy/compose.yml`.

### Deployment

- The app is self-contained: `deploy/compose.yml` brings its own RabbitMQ and Postgres. Never depend on infrastructure shared with other apps on the host.
- The app does not know the host's reverse proxy. Proxy labels, hostnames and external networks belong in `compose.host.yml` on the host, never in this repo.
- `deploy.yml` deploys after a green `docker` run on `main`, using the `sha-<full commit sha>` image tag. Roll back by running it manually with an older tag.
- Secrets live only in the host's `.env`; `deploy/.env.example` lists the names. Adding a secret means updating `.env.example` and telling the user to add it on the host before merging.
- Schema and data changes must work with the previous image still running until the new one is healthy, so a rollback stays possible.

## Security

- Do not add a new package without stating why, its licence, and that it is actively maintained (stop-and-ask).
- Pin GitHub Actions to a major version at minimum; prefer a commit SHA for third-party actions.
- Validate all external input, authorise every operation, and never log tokens or personal data.
- Authentication uses OpenID Connect via the configured identity provider; APIs validate JWT bearer tokens, the Next.js server holds tokens, and the browser never sees them.
- Authorisation is enforced in the Application layer per use case, not only at the endpoint.

## Observability

- Use OpenTelemetry for traces, metrics and logs in .NET and Next.js, exported over OTLP.
- Enable Dapr tracing so spans flow through pub/sub and service invocation.
- Every request and message carries a correlation ID.
- Expose health checks (`/healthz` liveness, `/readyz` readiness) on every service.
- New features ship with the logs and metrics needed to tell whether they work in production.

## Local development

- One command starts the full stack: `docker compose up --build`, with a Dapr sidecar per service, RabbitMQ (management UI on port 15672) and Postgres.
- Local runs on the same infrastructure as production, so behaviour around redelivery, ordering and transactions matches.
- Seed data and a reset script exist so local data can be rebuilt from scratch.
- The agent runs the stack and exercises its change before calling it done.

## Commands

Keep this table accurate for this repo; agents run these instead of guessing. Front-end commands run in `web/`.

| Task | Command |
| --- | --- |
| Build back end | `dotnet build` |
| Test back end | `dotnet test` |
| Format back end | `dotnet format` |
| Install front end | `npm ci` |
| Lint and type check front end | `npm run lint && npx tsc --noEmit` |
| Test front end | `npm test` |
| End-to-end tests | `npx playwright test` |
| Run full stack | `docker compose up --build` |

## Commits and pull requests

- Small, focused commits with imperative messages (`feat: add order export endpoint`).
- Each PR explains what changed, why, how it was tested, and any assumptions.
- Update docs and this file when a convention changes.
- Use Conventional Commits (`feat:`, `fix:`, `chore:`) so changelogs and semver tags can be derived.
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
- [ ] Logs, metrics and traces cover the new behaviour.
- [ ] Docs and this file updated if a convention changed.
- [ ] PR description states what, why, how it was tested, and assumptions.
- [ ] Any conflicts between existing code and this file are reported.
