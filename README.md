# MCP HTTP Proxy (Nginx)

This container runs an HTTP reverse proxy for an upstream MCP HTTP server and injects outbound headers from environment variables.

## Project structure

The Nginx proxy is a self-contained Docker component under `nginx-proxy/`:

```text
nginx-proxy/
|- Dockerfile
|- docker-entrypoint.sh
`- nginx.conf.template
```

Build commands use `nginx-proxy/` as the Docker build context so the component
can be built independently from the other services in this repository.

## Build

```bash
docker build -t mcp-nginx-proxy ./nginx-proxy
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
- `MCP_OAUTH_REWRITE_RESOURCE` (optional, default `on`): when discovery routing
  is active (`root`/`subpath`), rewrite the `resource` field in the upstream's
  `oauth-protected-resource` metadata to this proxy's own origin
  (`$scheme://$http_host`). Clients validate that `resource` matches the URL
  they connected to (RFC 9728); without this they reject the proxied endpoint
  (`Protected resource <upstream> does not match expected <proxy>`). Set to
  `off` to pass the upstream `resource` through unchanged. Note: this fixes the
  client-side check only — if the authorization server honors RFC 8707 resource
  indicators and the upstream strictly validates token audience, the issued
  token may still be scoped to the proxy origin rather than the upstream.

## Logging

All logs are emitted to container logs:

- **Access log** -> `stdout`: request + upstream timing/status fields.
- **Error log** -> `stderr`: nginx runtime errors using `NGINX_ERROR_LOG_LEVEL`.
- **Startup log** -> `stdout`: upstream URL, log level, and loaded `MCP_HEADER_*` header keys (names only, no values).

View logs with:

```bash
docker logs <container-id>
```

## LiteLLM gateway

The Compose stack also runs a LiteLLM gateway for routing model requests through
Azure Foundry. The service is available at `http://localhost:1982` and exposes
the configured OpenAI-compatible API.

The configuration is stored in [`litellm/config.yaml`](litellm/config.yaml) and
defines these model aliases:

- `gpt-5.6-luna`
- `kimi-k2.5`
- `claude-sonnet`

Set these environment variables before starting the service:

- `LITELLM_MASTER_KEY` (required): key clients use to authenticate with LiteLLM.
- `AZURE_FOUNDRY_API_BASE` (required): Azure Foundry endpoint shared by the
  configured routes.
- `AZURE_FOUNDRY_API_KEY` (required): credential for the Azure Foundry endpoint.

Start LiteLLM with Docker Compose:

```bash
export LITELLM_MASTER_KEY="<master-key>"
export AZURE_FOUNDRY_API_BASE="https://<resource>.openai.azure.com"
export AZURE_FOUNDRY_API_KEY="<api-key>"
docker compose up -d litellm
```

The gateway is configured with the master key and Azure Foundry credentials by
the Compose service. Keep these values out of source control.
