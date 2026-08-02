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

## Logging

All logs are emitted to container logs:

- **Access log** -> `stdout`: request + upstream timing/status fields.
- **Error log** -> `stderr`: nginx runtime errors using `NGINX_ERROR_LOG_LEVEL`.
- **Startup log** -> `stdout`: upstream URL, log level, and loaded `MCP_HEADER_*` header keys (names only, no values).

View logs with:

```bash
docker logs <container-id>
```
