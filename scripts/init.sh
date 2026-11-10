#!/usr/bin/env bash
# Turns a fresh copy of the template into a working project:
#   - .NET solution: Domain, Application, Infrastructure, Api + test projects
#   - Next.js app in web/ with strict TypeScript, Vitest and a standalone build
#   - Dockerfiles, and the placeholder names in the workflows and compose file
# Then it builds and tests everything and removes itself.
#
# Usage: scripts/init.sh [--skip-dotnet] [--skip-web] <Name>
#   <Name>  PascalCase, dot-separated: Contoso.Orders -> image names contoso-orders-api/-web
#   --skip-dotnet / --skip-web  partial run for debugging; the result will not pass CI.
#
# Needs: bash 3.2+, git, perl, .NET SDK matching global.json, Node.js 20+ with npm.

set -euo pipefail

die()  { printf '\nerror: %s\n' "$*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }

usage() {
  sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

skip_dotnet=false
skip_web=false
name=""
while [ $# -gt 0 ]; do
  case $1 in
    --skip-dotnet) skip_dotnet=true ;;
    --skip-web) skip_web=true ;;
    -h|--help) usage ;;
    -*) die "unknown option: $1" ;;
    *) [ -z "$name" ] || die "only one name allowed"; name=$1 ;;
  esac
  shift
done
[ -n "$name" ] || usage

[[ $name =~ ^[A-Z][A-Za-z0-9]*(\.[A-Z][A-Za-z0-9]*)*$ ]] \
  || die "name must be PascalCase segments separated by dots, for example Contoso.Orders"

# Contoso.Orders -> contoso-orders, OrderService -> order-service
kebab=$(printf '%s' "$name" | sed -e 's/\./-/g' -e 's/\([a-z0-9]\)\([A-Z]\)/\1-\2/g' | tr '[:upper:]' '[:lower:]')

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
templates=scripts/templates

# ---------------------------------------------------------------- preflight
step "Checking prerequisites"
[ -d "$templates" ] || die "already initialized: $templates is gone"
[ ! -e web ] || die "web/ already exists; run this on a fresh copy of the template"
if compgen -G "src/*/*.csproj" >/dev/null; then die "src/ already has projects"; fi

for tool in git perl; do
  command -v "$tool" >/dev/null || die "$tool is required"
done
if ! $skip_dotnet; then
  command -v dotnet >/dev/null || die "the .NET SDK is required (version in global.json)"
  dotnet --version >/dev/null 2>&1 \
    || die "no installed .NET SDK satisfies global.json ($(grep '"version"' global.json | tr -d ' ,'))"
fi
if ! $skip_web; then
  for tool in node npm npx; do
    command -v "$tool" >/dev/null || die "Node.js 20+ with npm is required ($tool not found)"
  done
  node_major=$(node -p 'process.versions.node.split(".")[0]')
  [ "$node_major" -ge 20 ] || die "Node.js 20+ is required, found $(node --version)"
fi
echo "Project: $name   images: $kebab-api, $kebab-web"

# ---------------------------------------------------------------- .NET
if ! $skip_dotnet; then
  step "Creating the .NET solution"
  export DOTNET_NOLOGO=1 DOTNET_CLI_TELEMETRY_OPTOUT=1

  dotnet new sln --name "$name" --format slnx

  for layer in Domain Application Infrastructure; do
    dotnet new classlib --name "$name.$layer" --output "src/$name.$layer"
    rm -f "src/$name.$layer/Class1.cs"
  done
  dotnet new webapi --name "$name.Api" --output "src/$name.Api"
  rm -f "src/$name.Api/$name.Api.http"

  dotnet new xunit --name "$name.Domain.Tests" --output "tests/$name.Domain.Tests"
  dotnet new xunit --name "$name.Application.Tests" --output "tests/$name.Application.Tests"
  dotnet new xunit --name "$name.Api.IntegrationTests" --output "tests/$name.Api.IntegrationTests"

  step "Wiring project references"
  dotnet add "src/$name.Application" reference "src/$name.Domain"
  dotnet add "src/$name.Infrastructure" reference "src/$name.Application"
  dotnet add "src/$name.Api" reference "src/$name.Application" "src/$name.Infrastructure"
  dotnet add "tests/$name.Domain.Tests" reference "src/$name.Domain"
  dotnet add "tests/$name.Application.Tests" reference "src/$name.Application"
  dotnet add "tests/$name.Api.IntegrationTests" reference "src/$name.Api"

  step "Adding packages (latest stable versions)"
  dotnet add "src/$name.Infrastructure" package Dapr.Client
  dotnet add "src/$name.Api" package Dapr.AspNetCore
  dotnet add "src/$name.Api" package Microsoft.Extensions.ApiDescription.Server
  dotnet add "tests/$name.Api.IntegrationTests" package Microsoft.AspNetCore.Mvc.Testing

  # Replace the weather-forecast sample with a clean starting point:
  # Problem Details, OpenAPI, health checks and the Dapr client.
  cat > "src/$name.Api/Program.cs" <<'CSHARP'
using Microsoft.AspNetCore.Diagnostics.HealthChecks;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddOpenApi();
builder.Services.AddProblemDetails();
builder.Services.AddHealthChecks();
builder.Services.AddDaprClient();

var app = builder.Build();

app.UseExceptionHandler();
app.UseStatusCodePages();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

// Liveness: the process is up. Readiness: every registered health check passes.
app.MapHealthChecks("/healthz", new HealthCheckOptions { Predicate = _ => false });
app.MapHealthChecks("/readyz");

app.Run();
CSHARP

  cp "$templates/api.Dockerfile" "src/$name.Api/Dockerfile"

  dotnet sln "$name.slnx" add src/*/*.csproj tests/*/*.csproj
fi

# ---------------------------------------------------------------- Next.js
if ! $skip_web; then
  step "Creating the Next.js app in web/"
  npx --yes create-next-app@latest web \
    --ts --eslint --app --src-dir --import-alias "@/*" --use-npm --disable-git --yes

  step "Applying template settings to web/"
  rm -f web/next.config.js web/next.config.mjs
  cp "$templates/web/next.config.ts" "$templates/web/vitest.config.mts" \
     "$templates/web/Dockerfile" "$templates/web/.dockerignore" web/
  cp "$templates/web/src/app/page.test.tsx" web/src/app/
  echo 24 > web/.nvmrc

  # Tighten the generated tsconfig instead of replacing it, so it keeps whatever
  # the current Next.js version expects.
  node -e '
    const fs = require("fs");
    const file = "web/tsconfig.json";
    const config = JSON.parse(fs.readFileSync(file, "utf8"));
    Object.assign(config.compilerOptions, {
      strict: true,
      noUncheckedIndexedAccess: true,
      noImplicitOverride: true,
    });
    fs.writeFileSync(file, JSON.stringify(config, null, 2) + "\n");
  '

  # @types/node follows the runtime in .nvmrc and the Dockerfile (create-next-app
  # pins an older major, which newer Vitest releases refuse as a peer).
  (
    cd web
    npm install --save-dev --no-fund --no-audit \
      "@types/node@^24" \
      vitest @vitejs/plugin-react vite-tsconfig-paths jsdom \
      @testing-library/react @testing-library/dom
    npm pkg set scripts.test="vitest run"
  )
fi

# ---------------------------------------------------------------- names
step "Replacing template names"
targets=".github/workflows/docker.yml docker-compose.yml deploy/compose.yml deploy/compose.host.example.yml"
[ -f "src/$name.Api/Dockerfile" ] && targets="$targets src/$name.Api/Dockerfile"
for file in $targets; do
  [ -f "$file" ] || die "template file missing: $file"
done
# shellcheck disable=SC2086
perl -pi -e "s/MyService/$name/g; s/my-service/$kebab/g" $targets

cat > README.md <<EOF
# $name

Created from [wesback/nettemplate](https://github.com/wesback/nettemplate).
Conventions, commands and the definition of done are in [AGENTS.md](AGENTS.md).

\`\`\`bash
docker compose up --build   # web on :3000, api on :8080
\`\`\`
EOF

# ---------------------------------------------------------------- verify
if ! $skip_dotnet; then
  step "Formatting, building and testing the back end"
  dotnet format
  dotnet build --configuration Release \
    || die "the generated .NET code does not build under the template settings; see the errors above"
  dotnet test --configuration Release --no-build
fi
if ! $skip_web; then
  step "Linting, type checking, testing and building the front end"
  (
    cd web
    npm run lint
    npx tsc --noEmit
    npm test
    npm run build
  ) || die "the front end failed a check; see the errors above"
fi

# ---------------------------------------------------------------- cleanup
step "Removing the template scaffolding"
rm -rf "$templates"
rm -f scripts/init.sh
rmdir scripts 2>/dev/null || true

cat <<EOF

Done. Next steps:
  1. Review and commit:   git add -A && git commit -m "chore: initialize $name from template"
  2. In the GitHub repo:  add the DOCKERHUB_USERNAME variable and DOCKERHUB_TOKEN secret
  3. Protect main:        require pull requests and the ci, codeql and docker checks
  4. Run it locally:      docker compose up --build
  5. Before deploying:    prepare the host, see "Deploying to a Docker host" in README.md
EOF
