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
├── docker-compose.yml           # api + Dapr sidecar, web, redis
├── components/local/            # Dapr pub/sub and state store for local dev
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
    └── workflows/               # ci, codeql, docker (build, Trivy scan, push to Docker Hub)
```

## Maintaining the template

- The workflows skip themselves in this repository (`github.repository != 'wesback/nettemplate'`) because it has no projects. Update that line if the template moves.
- `MyService` and `my-service` in `docker.yml`, `docker-compose.yml` and `scripts/templates/api.Dockerfile` are placeholders that `init.sh` replaces.
- Dependabot keeps action, image and package versions current in every project created from the template; bump `global.json` and the image tags here when a new LTS ships.
