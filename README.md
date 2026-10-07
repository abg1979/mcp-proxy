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

## MCP notification compatibility

The gateway always normalizes empty `200 OK` responses to JSON-RPC notifications
to `202 Accepted`, which prevents clients such as Codex from trying to parse an
empty JSON response during initialization. A notification must have
`jsonrpc: "2.0"`, a nonempty string `method`, and no `id`. Only responses with an
explicit `Content-Length: 0` are changed. Normal requests, nonempty replies,
errors, and unknown-length responses pass through unchanged.

The filter reads POST request bodies before proxying; responses still stream
without buffering. It uses the njs module bundled with the supported nginx
image, including `js_access` and `r.readRequestText()`.

Build and run the container integration tests (Python standard library and
Docker required):

```bash
docker build -t mcp-nginx-proxy ./nginx-proxy
python3 tests/test_notification_normalization.py --image mcp-nginx-proxy
```

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
GitHub Copilot and Azure Foundry. The service is available at
`http://localhost:1982` and exposes OpenAI-compatible and Anthropic Messages APIs.

For **GitHub Copilot models only**, follow the
[GitHub Copilot model setup guide](litellm/README.md). It covers gateway
startup, GitHub device login, client configuration, and verification requests.
The Codex instructions use a dedicated `CODEX_HOME` for gateway configuration
and local state.

The configuration is stored in [`litellm/config.yaml`](litellm/config.yaml) and
defines GitHub Copilot routes for GPT, Claude, Gemini, MAI, Kimi, and Grok models.
GPT routes use the Responses API except `gpt-5-mini`. See the configuration for
the complete model alias list.

Azure Foundry routes are available as `model-router`, `Kimi-K2.6`,
`azure-gpt-5.6-luna`, `azure-gpt-5.6-sol`, `azure-gpt-5.6-terra`,
`azure-gpt-6-astra`, `azure-claude-sonnet-5`, and `azure-claude-opus-5`.

Set these environment variables before starting the service:

- `LITELLM_MASTER_KEY` (required): key clients use to authenticate with LiteLLM.
- `AZURE_FOUNDRY_API_BASE` (required for Azure routes): Azure Foundry endpoint
  shared by those routes.
- `AZURE_FOUNDRY_API_KEY` (required for Azure routes): credential for the Azure
  Foundry endpoint. GitHub Copilot routes do not use Azure credentials.

The GitHub Copilot routes use LiteLLM's native GitHub Copilot provider and
authenticate with GitHub's device flow. Complete the synchronous login helper
in the [client setup guide](litellm/README.md) before starting the proxy;
current LiteLLM proxy workers cannot perform the initial device login.
The Compose stack persists the resulting token in the `litellm-copilot-token`
volume. LiteLLM's trusted-proxy range list is explicitly empty.

Start LiteLLM with Docker Compose:

```bash
export LITELLM_MASTER_KEY="<master-key>"
export AZURE_FOUNDRY_API_BASE="https://<resource>.openai.azure.com"
export AZURE_FOUNDRY_API_KEY="<api-key>"
docker compose up -d litellm
```

The Compose service passes the master key and any Azure Foundry credentials to
the gateway. Keep these values out of source control.

### Compose Stack Script

Use `mcp.ps1` with PowerShell (`pwsh`) and Docker Compose installed. Starting
a stack also requires an authenticated 1Password CLI (`op`). The script can
be invoked from any working directory.

```powershell
./mcp.ps1 -Help                              # Show arguments and defaults
./mcp.ps1                                    # Start LiteLLM (default)
./mcp.ps1 -Action start -Stack adobe          # Start Adobe gateways
./mcp.ps1 -Action start -Stack all            # Start both stacks
./mcp.ps1 -Action stop -Stack all             # Stop containers, keep them
./mcp.ps1 -Action destroy -Stack adobe        # Remove containers and networks
./mcp.ps1 -Action destroy -Stack litellm -RemoveVolumes
```

`-Stack` accepts `litellm` (the top-level Compose file), `adobe` (the Compose
file in `adobe/`), or `all`. It defaults to `litellm`. `-Action` accepts
`start`, `stop`, or `destroy`, and defaults to `start`. Use `-Help` (or `-h`)
to print the available actions, stacks, and options.

Starting pulls images before running `up -d` and loads only the selected
stack's credentials from 1Password. Stopping uses `docker compose stop`;
destroying uses `docker compose down`. Neither requires 1Password access.
Commands run sequentially and abort on the first failure.

Destroy preserves volumes unless `-RemoveVolumes` is supplied. That switch
is valid only with `-Action destroy` and deletes the selected stacks' volumes,
including LiteLLM's saved GitHub Copilot token. You will need to authenticate
GitHub Copilot again after deleting that volume.

Run the script's isolated routing tests without Docker or 1Password access:

```bash
pwsh -NoProfile -File tests/test_compose_lifecycle.ps1
```
