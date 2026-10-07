# Use GitHub Copilot models through the LiteLLM gateway

This guide connects OpenAI-compatible clients, the Claude Code CLI, and the
OpenAI Codex CLI to this repository's LiteLLM gateway. Every Copilot model used
below routes through LiteLLM's `github_copilot/` provider in
[config.yaml](config.yaml).

The request path is: coding CLI → LiteLLM on port `1982` → GitHub Copilot.

| Client | Client base URL | Request endpoint | Example gateway model alias |
| --- | --- | --- | --- |
| Claude Code | `http://localhost:1982` | `/v1/messages` | `claude-sonnet-4.6` |
| OpenAI Codex | `http://localhost:1982/v1` | `/v1/responses` | `gpt-5.3-codex` |

Use the exact `model_name` from `config.yaml` in client requests. For example,
send `claude-sonnet-4.6`, not Anthropic's `claude-sonnet-4-6` or LiteLLM's internal
`github_copilot/claude-sonnet-4.6`. The gateway adds the provider prefix.

## Prerequisites

- Docker with Docker Compose, plus `curl` for the connection checks.
- Claude Code and/or OpenAI Codex CLI installed.
- A GitHub account with Copilot access and permission to use the selected models.
- The gateway's `LITELLM_MASTER_KEY`, which authenticates clients to LiteLLM.

The gateway authenticates to GitHub separately using a device login. You do not
need an Anthropic API key, OpenAI API key, or Azure credentials for these routes.
Model availability and usage limits depend on your Copilot account and
organization policies; a configured alias alone does not establish access.

The shell examples below use Bash or Zsh. Run Compose commands from the
repository root. Run the coding clients from the project you want to work on.

## 1. Authenticate GitHub Copilot and start the gateway

Choose a gateway key and keep it out of source control. If the gateway is
already running, use the same key it was started with.

```bash
export LITELLM_MASTER_KEY="<your-gateway-key>"

# The shared Compose file declares these variables for its Azure routes.
# Empty values suppress interpolation warnings when using Copilot only.
export AZURE_FOUNDRY_API_BASE=""
export AZURE_FOUNDRY_API_KEY=""

docker compose run --rm --no-deps --entrypoint python litellm \
  -c 'from litellm.llms.github_copilot.authenticator import Authenticator; Authenticator().get_access_token()'

docker compose up -d litellm
```

The one-off container runs LiteLLM's synchronous login helper with the same
token volume as the gateway. Open the printed GitHub verification URL, enter
the device code promptly, and authorize the GitHub account with Copilot access.
The token is saved in the volume before the proxy starts. Current LiteLLM
releases cannot complete device login from proxy workers; waiting for a prompt
in gateway logs can leave the routes unhealthy. See the
[provider's login instructions](https://docs.litellm.ai/docs/providers/github_copilot#sign-in-before-starting-the-proxy).

If the gateway was already running without a token, restart it after login:

```bash
docker compose restart litellm
```

The host port is `1982`; port `4000` is internal to the container. If you use
another terminal for the following checks, export the same
`LITELLM_MASTER_KEY` there first.

If you already use [mcp.ps1](../README.md#compose-stack-script), you can start the
gateway with that instead, after completing the login helper. The script loads
credentials from 1Password, including Azure credentials; the Copilot routes
still authenticate through GitHub. Clients need the LiteLLM key loaded by the
script.

## 2. Check the routes

List the gateway's configured model aliases:

```bash
curl --fail-with-body --silent --show-error \
  http://localhost:1982/v1/models \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY"
```

This lists configured routes, including routes outside Copilot, and does not
validate GitHub access. Select a Copilot alias from `config.yaml`; avoid
`azure-*`, `model-router`, and `Kimi-K2.6` for this guide.

For Claude Code, check the Anthropic Messages route:

```bash
curl --fail-with-body --silent --show-error \
  http://localhost:1982/v1/messages \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -H "anthropic-version: 2023-06-01" \
  -d '{
    "model": "claude-sonnet-4.6",
    "max_tokens": 64,
    "messages": [{"role": "user", "content": "Reply with exactly: gateway-ok"}]
  }'
```

For Codex, check the Responses route:

```bash
curl --fail-with-body --silent --show-error \
  http://localhost:1982/v1/responses \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-5.3-codex",
    "input": "Reply with exactly: gateway-ok"
  }'
```

Check both routes if you plan to use both clients. Successful responses contain
`gateway-ok` in their output. If a route is unhealthy, inspect
`docker compose logs litellm`; complete the login helper and restart the gateway
if its token is missing.

Credentials persist in the `litellm-copilot-token` Docker volume and survive
container restarts. Removing that volume, including with
`./mcp.ps1 -Action destroy -Stack litellm -RemoveVolumes`, requires another
GitHub login.

## 3. Configure Claude Code

In the terminal where you will run Claude Code:

```bash
export ANTHROPIC_BASE_URL="http://localhost:1982"
export ANTHROPIC_AUTH_TOKEN="$LITELLM_MASTER_KEY"
export ANTHROPIC_MODEL="claude-sonnet-4.6"

# Map Claude Code's family aliases and background model to gateway aliases.
export ANTHROPIC_DEFAULT_SONNET_MODEL="claude-sonnet-4.6"
export ANTHROPIC_DEFAULT_OPUS_MODEL="claude-opus-4.7"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="claude-haiku-4.5"
export ANTHROPIC_DEFAULT_FABLE_MODEL="claude-fable-5.1"

claude --model claude-sonnet-4.6
```

`ANTHROPIC_AUTH_TOKEN` sends the LiteLLM key as an `Authorization: Bearer`
header. Keep `ANTHROPIC_BASE_URL` at the gateway root: Claude Code appends
`/v1/messages` itself. The family mappings keep `sonnet`, `opus`, `haiku`, and
`fable` requests on configured Copilot routes, including background requests
that use Haiku. Change a mapping if your Copilot account does not offer its model.

Inside Claude Code, run `/status` and confirm the base URL and auth token source.
Send `Reply with exactly: gateway-ok`. You can switch with `/model sonnet`,
`/model opus`, or `/model haiku`, or use an explicit configured Claude alias such
as `/model claude-sonnet-5.5`. Newer models can require a newer Claude Code
version; Sonnet 5.5 requires v2.1.284 or later, and Opus 5.5 requires v2.1.280 or
later. Use Claude models for Claude Code.

For a noninteractive connection check:

```bash
claude --model claude-sonnet-4.6 -p "Reply with exactly: gateway-ok"
```

### Persist Claude Code settings

To persist routing and model mappings, merge this into your user-level
`~/.claude/settings.json`, preserving existing settings:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://localhost:1982",
    "ANTHROPIC_MODEL": "claude-sonnet-4.6",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "claude-sonnet-4.6",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "claude-opus-4.7",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "claude-haiku-4.5",
    "ANTHROPIC_DEFAULT_FABLE_MODEL": "claude-fable-5.1"
  }
}
```

Keep supplying `ANTHROPIC_AUTH_TOKEN` in the launching shell or through your
secret manager. JSON does not expand `$LITELLM_MASTER_KEY`: do not put that
literal string in the file as a credential. Settings-file `env` values take
precedence over shell exports, so update them too when changing routes or models.

## 4. Configure OpenAI Codex

Create a dedicated Codex home for this gateway setup. OpenAI documents
[`CODEX_HOME`](https://developers.openai.com/codex/environment-variables#core-locations)
as the directory for configuration and local state, including file-based auth,
logs, sessions, and skills. It defaults to `~/.codex`, and a custom directory
must exist before Codex starts.

```bash
mkdir -p "$HOME/.codex-copilot"
```

Create `~/.codex-copilot/config.toml` with the following contents. If you
already created a dedicated home, use that path throughout these instructions.
Keep top-level keys before the first table and avoid duplicate keys or tables.
The provider settings follow the
[OpenAI gateway guide](https://developers.openai.com/codex/enterprise/connect-to-a-gateway/)
and [LiteLLM's Codex setup](https://docs.litellm.ai/docs/proxy/client_setup/codex_cli).

```toml
model_provider = "litellm"
model = "gpt-6.1-sol"
model_reasoning_effort = "high"
service_tier = "default"
plan_mode_reasoning_effort = "high"

[model_providers.litellm]
name = "LiteLLM OpenAI"
base_url = "http://localhost:1982/v1"
env_key = "LITELLM_MASTER_KEY"
wire_api = "responses"
requires_openai_auth = false
```

The base URL includes `/v1`; Codex appends `/responses`. The provider reads the
gateway key from `LITELLM_MASTER_KEY` and sends a bearer header, so no
`codex login` is needed for this provider. GitHub login happens in step 1.
`wire_api = "responses"` matches the configured GPT Responses routes. The
example selects GPT-6.1 Sol with high reasoning effort for normal and plan-mode
requests and the default service tier.

Export the same key used to start LiteLLM in the terminal that launches Codex:

```bash
export LITELLM_MASTER_KEY="<your-gateway-key>"
CODEX_HOME="$HOME/.codex-copilot" codex
```

Set `CODEX_HOME` for every gateway invocation. The inline assignment above
selects the dedicated home for that command. A plain `codex` command uses the
home selected by your existing environment, which may load a different
configuration.

Run `/status` and confirm the model is `gpt-6.1-sol` and the provider is
`litellm`. Send `Reply with exactly: gateway-ok`. For a noninteractive
check, run this from a Git repository:

```bash
CODEX_HOME="$HOME/.codex-copilot" \
  codex exec "Reply with exactly: gateway-ok"
```

To select another configured Copilot GPT Responses model:

```bash
CODEX_HOME="$HOME/.codex-copilot" codex --model gpt-5.3-codex
```

Choose a GPT alias with `model_info.mode: responses` in `config.yaml` and
Copilot access for your account. `gpt-5-mini` is the configured GPT exception
without that mode; use a Responses route for this setup. Model capabilities also
depend on the metadata available to your Codex version. An unknown alias can
run with fallback metadata; upgrading alone does not teach Codex all gateway
aliases.

### Discover gateway models in Codex

On Codex v0.159.0 or later and a LiteLLM release supporting Codex catalogs,
merge these settings into `~/.codex-copilot/config.toml`. Add
`model_catalog_url` to the existing provider table:

```toml
[model_providers.litellm]
model_catalog_url = "http://localhost:1982/v1/models"

[features]
api_key_model_discovery = true
```

Both settings are needed. Without discovery, `/model` can still show Codex's
built-in list. Discovery lists the gateway's routes, including Azure routes;
select only aliases backed by `github_copilot/` in `config.yaml` for this guide.

To check the gateway's catalog support:

```bash
curl --fail-with-body --silent --show-error \
  'http://localhost:1982/v1/models?client_version=0.159.3' \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY"
```

Expect a top-level `models` field. A `data` field indicates the ordinary OpenAI
model listing. For older versions or custom model metadata, use a matching
local catalog via `model_catalog_json`; see
[LiteLLM's Codex metadata instructions](https://docs.litellm.ai/docs/proxy/client_setup/codex_cli#model-metadata-for-custom-aliases).

Put provider settings in the selected home's `config.toml`, since current
Codex ignores them in project-local `.codex/config.toml`. A separate home
changes local configuration and state; managed policies and applicable project
configuration still apply. Desktop apps must receive both `CODEX_HOME` and the
gateway credential in their own process environment; a terminal assignment
alone does not configure an app launched from the desktop.

## Use as a standard OpenAI-compatible provider

Any application that supports a custom OpenAI-compatible provider can connect
directly to the gateway. Configure it with:

| Setting | Value |
| --- | --- |
| Provider type | OpenAI-compatible (or custom OpenAI endpoint) |
| Base URL | `http://localhost:1982/v1` |
| API key | The value of `LITELLM_MASTER_KEY` |
| Model | An exact Copilot alias from `config.yaml`, such as `claude-sonnet-4.6` |
| API format | Chat Completions |

For example, with an OpenAI-compatible client that uses Chat Completions:

```bash
curl --fail-with-body --silent --show-error \
  http://localhost:1982/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4.6",
    "messages": [{"role": "user", "content": "Reply with exactly: gateway-ok"}]
  }'
```

Use the alias exactly as it appears in `config.yaml`; do not add the
`github_copilot/` provider prefix. GPT aliases with
`model_info.mode: responses` require a client that supports the OpenAI
Responses API and the `/v1/responses` endpoint; they will not work with a
Chat Completions-only client. See the
[Responses example](#2-check-the-routes) for the request shape. The gateway
key authenticates the client to LiteLLM; GitHub Copilot authentication remains
on the gateway and uses the login from step 1.

## Limitations

The gateway proxies model API requests; it does not provide the web-search
tools built into Claude Code or Codex CLI. Those clients' native web search
does not work for sessions using models through this LiteLLM gateway.

For web search, configure a separate MCP server in the client. Exa is the
recommended option: see the [Exa MCP server documentation](https://docs.exa.ai/mcp)
for setup instructions, then add it to Claude Code or Codex as an MCP server.
The MCP server connects to the client independently of LiteLLM; its Exa
credentials are separate from `LITELLM_MASTER_KEY`.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| Connection refused | Check `docker compose ps` and `docker compose logs litellm`; use host port `1982`. |
| LiteLLM returns `401` | The client key must match the running gateway's `LITELLM_MASTER_KEY`. Export it in the terminal that launches the client. |
| GitHub token is missing, or there are no healthy deployments | Run the synchronous login helper in step 1, then restart LiteLLM. The proxy workers cannot perform the initial device login. |
| Unknown model or model access denied | Check the exact alias in `config.yaml` and your GitHub account's Copilot model access. `/v1/models` alone does not check access. |
| Claude Code requests a dashed Anthropic model ID | Set the `ANTHROPIC_DEFAULT_*_MODEL` mappings above to the gateway's exact aliases. |
| Claude Code shows the wrong provider or credential | Check `/status`, conflicting settings-file `env` values, `ANTHROPIC_API_KEY`, `CLAUDE_CODE_OAUTH_TOKEN`, and any enabled `CLAUDE_CODE_USE_BEDROCK`, `CLAUDE_CODE_USE_VERTEX`, or `CLAUDE_CODE_USE_FOUNDRY` variables. |
| Codex uses another provider or loads your usual configuration | Set `CODEX_HOME` on the invocation and check `<CODEX_HOME>/config.toml`, `/status`, and overrides. Keep `model_provider` at the top level. |
| Codex cannot find its home or configuration | Create the directory first, put `config.toml` directly inside it, and use the same `CODEX_HOME` on every invocation. |
| Codex's `/model` picker shows only built-in models | Configure both `model_catalog_url` and `features.api_key_model_discovery` on supported releases. |
| `gpt-5.3-codex` fails on Chat Completions | Use `/v1/responses` and `wire_api = "responses"`; this model only supports the Responses API. |
| A basic request works but streaming or tools fail | Pull the current LiteLLM image with `docker compose pull litellm`, recreate with `docker compose up -d litellm`, and inspect logs while repeating the client request. |

The direct requests above check authentication and basic routing. A coding
session should also successfully read a project file and answer a follow-up
request to verify tool calls and multi-turn behavior. Review the gateway logs
alongside `/status` to confirm the requested alias; asking the model its name
does not verify which route served the request.

## References

- [LiteLLM GitHub Copilot provider](https://docs.litellm.ai/docs/providers/github_copilot)
- [LiteLLM Codex CLI setup](https://docs.litellm.ai/docs/proxy/client_setup/codex_cli)
- [Claude Code gateway connection](https://code.claude.com/docs/en/llm-gateway-connect)
- [Claude Code model configuration](https://code.claude.com/docs/en/model-config)
- [Codex gateway connection](https://developers.openai.com/codex/enterprise/connect-to-a-gateway/)
- [Codex environment variables and CODEX_HOME](https://developers.openai.com/codex/environment-variables)
- [Codex configuration reference](https://developers.openai.com/codex/config-reference/)
