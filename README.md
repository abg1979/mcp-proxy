# MCP HTTP Proxy (Nginx)

This container runs an HTTP reverse proxy for an upstream MCP HTTP server and injects outbound headers from environment variables.

## Build

```bash
docker build -t mcp-nginx-proxy .
```

## Run

```bash
docker run --rm -p 8080:8080 \
  -e MCP_UPSTREAM_URL="http://upstream-mcp:9000" \
  -e MCP_HEADER_AUTHORIZATION="Bearer <token>" \
  -e MCP_HEADER_X_TENANT_ID="tenant-42" \
  -e NGINX_ERROR_LOG_LEVEL="info" \
  mcp-nginx-proxy
```

## Environment variables

- `MCP_UPSTREAM_URL` (required): upstream target URL for proxy pass.
- `MCP_HEADER_*` (optional): dynamic upstream headers.
  - `MCP_HEADER_AUTHORIZATION` -> `Authorization`
  - `MCP_HEADER_X_TENANT_ID` -> `X-Tenant-Id`
- `NGINX_ERROR_LOG_LEVEL` (optional, default `warn`): nginx error log level.
- `MCP_OAUTH_DISCOVERY` (optional, default `auto`): how to route OAuth
  discovery paths (`/.well-known/`, `/oauth/`, `/register`) for OAuth-protected
  upstreams. Clients derive discovery from this proxy's origin (`/`), but
  upstreams serve their metadata at the host root or under the MCP subpath, so
  the paths must be re-targeted or the OAuth handshake never starts.
  - `auto` — probe the upstream at startup and pick the base that serves
    `oauth-protected-resource` metadata (host root or MCP subpath); disable the
    routing for non-OAuth upstreams; fall back to root if the upstream is
    unreachable at boot.
  - `root` / `subpath` — force the discovery base without probing.
  - `off` — no discovery routing (e.g. static-bearer upstreams that never
    trigger the client OAuth flow).

## Logging

All logs are emitted to container logs:

- **Access log** -> `stdout`: request + upstream timing/status fields.
- **Error log** -> `stderr`: nginx runtime errors using `NGINX_ERROR_LOG_LEVEL`.
- **Startup log** -> `stdout`: upstream URL, log level, and loaded `MCP_HEADER_*` header keys (names only, no values).

View logs with:

```bash
docker logs <container-id>
```
