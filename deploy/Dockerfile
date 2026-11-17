# ═══════════════════════════════════════════════════════════════
# HRMS — VPS image (Hostinger KVM). Independent of the Railway Dockerfile.
# Build context: repository root  (docker compose handles this)
# ═══════════════════════════════════════════════════════════════

# ── Stage 1: Angular ─────────────────────────────────────────
FROM node:20-alpine AS angular-build
WORKDIR /app/frontend
COPY hrms-ui/package*.json ./
RUN npm ci --legacy-peer-deps
COPY hrms-ui/ ./
RUN npm run build:prod

# ── Stage 2: .NET API ────────────────────────────────────────
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS dotnet-build
WORKDIR /src
COPY HrmsApi/*.csproj ./HrmsApi/
RUN dotnet restore HrmsApi/HrmsApi.csproj
COPY HrmsApi/ ./HrmsApi/
RUN dotnet publish HrmsApi/HrmsApi.csproj -c Release -o /app/publish

# ── Stage 3: Runtime (nginx + API) ───────────────────────────
FROM mcr.microsoft.com/dotnet/aspnet:8.0
WORKDIR /app

RUN apt-get update \
 && apt-get install -y --no-install-recommends nginx curl \
 && rm -rf /var/lib/apt/lists/* \
 && rm -f /etc/nginx/sites-enabled/default

COPY --from=dotnet-build /app/publish ./api/
COPY --from=angular-build /app/frontend/dist/hrms-ui/browser ./wwwroot
COPY deploy/nginx.conf /etc/nginx/conf.d/hrms.conf
COPY deploy/start.sh /app/start.sh

# Strip CRLF in case the script was saved on Windows; create uploads dir (volume mount point)
RUN sed -i 's/\r$//' /app/start.sh && chmod +x /app/start.sh \
 && mkdir -p /app/api/wwwroot/uploads/profiles

ENV ASPNETCORE_URLS=http://127.0.0.1:5000 \
    ASPNETCORE_ENVIRONMENT=Production \
    DOTNET_RUNNING_IN_CONTAINER=true \
    TZ=Asia/Kuala_Lumpur

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD curl -fs http://127.0.0.1:8080/ >/dev/null || exit 1

CMD ["/bin/bash", "/app/start.sh"]
