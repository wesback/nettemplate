# Build context: repository root (see docker-compose.yml and .github/workflows/docker.yml)
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /repo

# Restore first so the layer is cached until a project file changes
COPY global.json Directory.Build.props .editorconfig ./
COPY src/MyService.Domain/*.csproj src/MyService.Domain/
COPY src/MyService.Application/*.csproj src/MyService.Application/
COPY src/MyService.Infrastructure/*.csproj src/MyService.Infrastructure/
COPY src/MyService.Api/*.csproj src/MyService.Api/
RUN dotnet restore src/MyService.Api/MyService.Api.csproj

COPY src/ src/
RUN dotnet publish src/MyService.Api/MyService.Api.csproj \
    --configuration Release --no-restore --output /app \
    -p:OpenApiGenerateDocuments=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
COPY --from=build /app .
# Non-root user built into the official .NET images
USER $APP_UID
ENV ASPNETCORE_HTTP_PORTS=8080
EXPOSE 8080
ENTRYPOINT ["dotnet", "MyService.Api.dll"]
