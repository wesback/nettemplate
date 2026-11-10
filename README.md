# nettemplate

Template for .NET + Next.js services with Dapr, built for AI coding agents: the conventions live in [AGENTS.md](AGENTS.md), and the configs and workflows that enforce them are already in place.

## Start a new project

```bash
gh repo create contoso-orders --template wesback/nettemplate --private --clone
cd contoso-orders
bash scripts/init.sh Contoso.Orders
git add -A && git commit -m "chore: initialize Contoso.Orders from template" && git push
```

`init.sh` creates the solution and the Next.js app, wires everything up, builds and tests it, then deletes itself. Run it from bash (Linux, macOS, WSL or Git Bash on Windows) with the .NET SDK from `global.json` and Node.js 20+ installed.

Then, in the new repository on GitHub:

- Add the `DOCKERHUB_USERNAME` repository variable and the `DOCKERHUB_TOKEN` secret (a Docker Hub access token), or set both at organisation level once.
- Protect `main`: require pull requests and the `ci`, `codeql` and `docker` checks.

## What you get

```
.
├── AGENTS.md                    # rules for coding agents
├── .editorconfig                # style, enforced at build
├── Directory.Build.props        # nullable, warnings as errors, analyzers, OpenAPI on build
├── global.json                  # pinned .NET SDK
├── <Name>.slnx
├── docker-compose.yml           # local: api + Dapr sidecar, web, RabbitMQ, Postgres
├── components/
│   ├── local/                   # Dapr pub/sub (RabbitMQ) and state (Postgres), dev credentials
│   └── prod/                    # same names, credentials from the envsecrets store
├── deploy/
│   ├── compose.yml              # production stack, self-contained, no proxy config
│   ├── .env.example             # secrets the host's .env must define
│   └── compose.host.example.yml # example Traefik overlay; the real one lives on the host
├── src/
│   ├── <Name>.Domain/
│   ├── <Name>.Application/
│   ├── <Name>.Infrastructure/   # Dapr.Client
│   └── <Name>.Api/              # Dapr.AspNetCore, health checks, Problem Details, Dockerfile
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

Each app runs as its own Compose project with its own RabbitMQ and Postgres, so apps share nothing but the host and its reverse proxy. The app repo never mentions the proxy: routing lives in a small overlay file on the host.

### Once per host

1. Install Docker with the Compose plugin.
2. Install a [self-hosted GitHub Actions runner](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/adding-self-hosted-runners) as a service, for your account or organisation, with the label `docker-host`. Add its user to the `docker` group and give it write access to `/opt/apps`.
3. If your Docker Hub images are private, run `docker login` as the runner's user.

Keep app repositories private: on a public repository, pull requests from forks could run code on a self-hosted runner.

### Once per app

On the host, as the runner's user, with `<repo>` being the GitHub repository name:

```bash
mkdir -p /opt/apps/<repo> && cd /opt/apps/<repo>
# fill in from deploy/.env.example; use: openssl rand -hex 24
nano .env && chmod 600 .env
# optional: routing for your proxy, from deploy/compose.host.example.yml
nano compose.host.yml
```

In the GitHub repo, create a `production` environment (Settings, Environments). Add required reviewers there if deploys should wait for approval.

### Every deploy

Merging to `main` runs `docker`, and when that succeeds, `deploy` pulls the `sha-<commit>` images and restarts the stack with `docker compose up -d --wait`. To roll back, run `deploy` manually with an older `sha-<commit>` tag.

Database and broker data live in named Docker volumes (`<repo>_postgres-data`, `<repo>_rabbitmq-data`). Back those up from the host.

## Maintaining the template

- The workflows skip themselves in this repository (`github.repository != 'wesback/nettemplate'`) because it has no projects. Update that line if the template moves.
- `MyService` and `my-service` in `docker.yml`, `docker-compose.yml`, `deploy/compose.yml`, `deploy/compose.host.example.yml` and `scripts/templates/api.Dockerfile` are placeholders that `init.sh` replaces.
- Dependabot keeps action, image and package versions current in every project created from the template; bump `global.json` and the image tags here when a new LTS ships.
