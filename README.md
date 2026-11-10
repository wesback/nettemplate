# nettemplate

Template for .NET + Next.js apps, built for AI coding agents: the conventions live in [AGENTS.md](AGENTS.md), and the configs and workflows that enforce them are already in place. Every app is self-contained and deploys to a Docker host.

## Start a new project

```bash
gh repo create contoso-orders --template wesback/nettemplate --private --clone
cd contoso-orders
bash scripts/init.sh Contoso.Orders            # API, web app and Postgres
git add -A && git commit -m "chore: initialize Contoso.Orders from template" && git push
```

`init.sh` creates the solution and the Next.js app, wires everything up, trims the compose files and AGENTS.md to the modules you picked, builds and tests it, then deletes itself. Run it from bash (Linux, macOS, WSL or Git Bash on Windows) with the .NET SDK from `global.json` and Node.js 20+ installed.

### Modules

The default is the smallest useful app: API, web app and Postgres. Add only what the app needs:

| Flag | Adds |
| --- | --- |
| `--dapr` | Dapr sidecar for the API: key-value state store (Postgres) and service invocation |
| `--messaging` | RabbitMQ pub/sub through Dapr, with its own broker per app (implies `--dapr`) |
| `--cqrs` | CQRS rules in AGENTS.md |
| `--event-sourcing` | Event-sourcing rules in AGENTS.md (implies `--cqrs`) |
| `--all` | Everything above |

Adding a module later by hand means copying its marked parts (`>>> name` to `<<< name`) from this template.

### Then, in the new repository on GitHub

- Add the `DOCKERHUB_USERNAME` repository variable and the `DOCKERHUB_TOKEN` secret (a Docker Hub access token), or set both at organisation level once.
- Protect `main`: require pull requests and the `ci` and `docker` checks.
- Code scanning (`codeql`) runs on public repositories. On a private repository it needs a [GitHub Code Security license](https://docs.github.com/en/code-security/concepts/code-scanning/about-code-scanning); if you have one, set the repository variable `CODEQL` to `true`.
- Docker Hub repositories are public unless you make them private. If the app's code is private, make its image repositories private too and check how many private repositories your Docker Hub plan allows.

## What you get

```
.
├── AGENTS.md                    # rules for coding agents, trimmed to your modules
├── .editorconfig                # style, enforced at build
├── Directory.Build.props        # nullable, warnings as errors, analyzers, OpenAPI on build
├── global.json                  # pinned .NET SDK
├── <Name>.slnx
├── docker-compose.yml           # local stack: api, web, Postgres (+ Dapr, RabbitMQ)
├── components/                  # Dapr components, local and prod (with --dapr)
├── deploy/
│   ├── compose.yml              # production stack, self-contained, no proxy config
│   ├── .env.example             # secrets the host's .env must define
│   └── compose.host.example.yml # example Traefik overlay; the real one lives on the host
├── src/
│   ├── <Name>.Domain/
│   ├── <Name>.Application/
│   ├── <Name>.Infrastructure/
│   └── <Name>.Api/              # health checks, Problem Details, OpenAPI, Dockerfile
├── tests/
│   ├── <Name>.Domain.Tests/
│   ├── <Name>.Application.Tests/
│   └── <Name>.Api.IntegrationTests/
├── web/                         # Next.js App Router, strict TS, Vitest, standalone Dockerfile
└── .github/
    ├── dependabot.yml
    └── workflows/               # ci, codeql, docker (build, Trivy scan, push), deploy
```

## Deploying to a Docker host

Each app runs as its own Compose project with its own database (and broker, with `--messaging`), so apps share nothing but the host and its reverse proxy. The app repo never mentions the proxy: routing lives in a small overlay file on the host.

### Once per host

1. Install Docker with the Compose plugin.
2. Install a [self-hosted GitHub Actions runner](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/adding-self-hosted-runners) as a service, for your account or organisation, with the label `docker-host`. Add its user to the `docker` group and give it write access to `/opt/apps`.
3. If your Docker Hub images are private, run `docker login` as the runner's user.

Keep app repositories private: on a public repository, pull requests from forks could run code on a self-hosted runner. The deploy workflow also only deploys pushes to the repository itself, never runs started from a fork.

### Once per app

On the host, as the runner's user, with `<repo>` being the GitHub repository name:

```bash
mkdir -p /opt/apps/<repo> && cd /opt/apps/<repo>
# fill in from deploy/.env.example; use: openssl rand -hex 24
nano .env && chmod 600 .env
# optional: routing for your proxy, from deploy/compose.host.example.yml
nano compose.host.yml
```

The deploy job runs in a `production` [environment](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments). Check what your plan allows before relying on it: on a private repository, environments need GitHub Pro or a team plan, and protection rules such as required reviewers are limited to public repositories below GitHub Enterprise. Without required reviewers, every green merge to `main` deploys.

### Every deploy

Merging to `main` runs `docker`, and when that succeeds, `deploy` pulls the `sha-<commit>` images and restarts the stack with `docker compose up -d --wait`, which waits for the API's health check. To roll back, run `deploy` manually with an older `sha-<commit>` tag.

### Backups

Data lives in named Docker volumes (`<repo>_postgres-data`, and `<repo>_rabbitmq-data` with messaging). The database needs a real backup; for example a nightly dump, kept for 14 days, in `/etc/cron.d/<repo>-backup`:

```
0 3 * * * root docker exec <repo>-postgres-1 sh -c 'pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB"' | gzip > /var/backups/<repo>/$(date +\%F).sql.gz && find /var/backups/<repo> -name '*.sql.gz' -mtime +14 -delete
```

Create `/var/backups/<repo>` first, and copy it off the host (NFS, object storage) as part of your normal backup routine.

## Maintaining the template

- `template-ci` runs `init.sh` with no modules and with `--all` on every pull request and weekly, then builds, tests and starts the result. The weekly run catches breaking changes in `create-next-app`, the `dotnet new` templates and base images.
- The other workflows skip themselves in this repository (`github.repository != 'wesback/nettemplate'`) because it has no projects. Update that line if the template moves.
- `MyService` and `my-service` in `docker.yml`, both compose files, `deploy/compose.host.example.yml` and `scripts/templates/api.Dockerfile` are placeholders that `init.sh` replaces.
- Module parts are marked with `>>> name` and `<<< name` comments; `template-ci` fails if any marker survives `init.sh`.
- Dependabot keeps action, image and package versions current in every project created from the template; bump `global.json` and the image tags here when a new LTS ships.
