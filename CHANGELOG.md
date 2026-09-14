# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Enabled SNI to HTTPS upstreams (`proxy_ssl_server_name on`), fixing TLS handshake failures (502) when proxying to SNI/vhost-routed endpoints.
- Send the upstream hostname as the `Host` header (derived from `MCP_UPSTREAM_URL`) instead of the client's host, fixing incorrect upstream routing (404).
- Removed literal quotes around the `Authorization` header value in `docker-compose.yml` so the header is sent as `Bearer <token>` rather than `"Bearer <token>"`.
- Route OAuth discovery paths (`/.well-known/`, `/oauth/`, `/register`) to the base the upstream actually serves them from, so OAuth-protected upstreams (e.g. `mcp.adobe.io`) can complete the client OAuth handshake. Previously all paths were rewritten under the MCP subpath, so discovery hit `<upstream>/mcp/.well-known/...` and returned 401 instead of the metadata served at the host root.

### Added

- Added Azure Foundry LiteLLM aliases for Kimi K2.6, model-router, GPT-5.6 Sol/Terra, GPT-6 Astra, Claude Sonnet 5, and Claude Opus 5.
- `MCP_OAUTH_DISCOVERY` (default `auto`) to control OAuth discovery routing. In `auto` mode the entrypoint probes the upstream at startup and selects the discovery base — host root or MCP subpath — from wherever `oauth-protected-resource` metadata is served, disables the routing for non-OAuth upstreams, and falls back to root if the upstream is unreachable at boot. `root`/`subpath` force a base; `off` disables it (e.g. static-bearer upstreams).
- `MCP_OAUTH_REWRITE_RESOURCE` (default `on`) to rewrite the `resource` field in the upstream's `oauth-protected-resource` metadata to this proxy's own origin, so clients that validate `resource` against the connected URL (RFC 9728) accept the proxied endpoint instead of rejecting it (`Protected resource <upstream> does not match expected <proxy>`). Set to `off` to pass it through unchanged.
- Local LiteLLM service configuration for routing GPT-5.6 Luna, Kimi K2.5, and Claude Sonnet requests through Azure Foundry.

### Changed

- Isolated the Nginx proxy Docker component under `nginx-proxy/` and updated local and CI build contexts.
- Updated GitHub Actions to latest versions: `actions/checkout@v7.0.1`, `docker/setup-buildx-action@v4.2.0`, `docker/login-action@v4.6.0`, `docker/metadata-action@v6.2.0`, `docker/build-push-action@v7.3.0`.
- `mcp.ps1` now runs `docker compose pull` before `up -d` so the launch picks up the latest published image.
- `mcp.ps1` now loads Azure Foundry and LiteLLM credentials from 1Password and exports them before starting Docker Compose.

## [0.1.0] - 2026-08-03

### Added

- Nginx-based HTTP reverse proxy container for upstream MCP HTTP servers.
- `MCP_UPSTREAM_URL` environment variable to configure the proxy target.
- `MCP_HEADER_*` environment variables for injecting arbitrary upstream headers (e.g. `Authorization`, `X-Tenant-Id`).
- `NGINX_ERROR_LOG_LEVEL` environment variable to control nginx error log verbosity (default: `warn`).
- Structured access log to `stdout` with upstream timing and status fields.
- Error log to `stderr`.
- Startup log emitting upstream URL, log level, and loaded header key names (values redacted).
- `docker-compose.yml` for local development.
- `mcp.ps1` helper script.
- GitHub Actions workflow to build and publish the Docker image.
