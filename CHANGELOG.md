# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Enabled SNI to HTTPS upstreams (`proxy_ssl_server_name on`), fixing TLS handshake failures (502) when proxying to SNI/vhost-routed endpoints.
- Send the upstream hostname as the `Host` header (derived from `MCP_UPSTREAM_URL`) instead of the client's host, fixing incorrect upstream routing (404).
- Removed literal quotes around the `Authorization` header value in `docker-compose.yml` so the header is sent as `Bearer <token>` rather than `"Bearer <token>"`.

### Changed

- Updated GitHub Actions to latest versions: `actions/checkout@v7.0.1`, `docker/setup-buildx-action@v4.2.0`, `docker/login-action@v4.6.0`, `docker/metadata-action@v6.2.0`, `docker/build-push-action@v7.3.0`.
- `mcp.ps1` now runs `docker compose pull` before `up -d` so the launch picks up the latest published image.

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
