#!/usr/bin/env bash
set -euo pipefail

: "${MCP_UPSTREAM_URL:?MCP_UPSTREAM_URL is required, e.g. http://upstream-mcp:9000}"
: "${NGINX_ERROR_LOG_LEVEL:=warn}"
# OAuth discovery routing: auto (probe upstream) | root | subpath | off
: "${MCP_OAUTH_DISCOVERY:=auto}"
# Rewrite the `resource` in protected-resource metadata to this proxy's own URL
# so clients that validate resource==server-URL (RFC 9728) accept it: on | off
: "${MCP_OAUTH_REWRITE_RESOURCE:=on}"

EXTRA_HEADERS_FILE="/etc/nginx/conf.d/mcp-extra-headers.conf"
DISCOVERY_FILE="/etc/nginx/conf.d/mcp-oauth-discovery.conf"
TEMPLATE_FILE="/etc/nginx/templates/nginx.conf.template"
TARGET_FILE="/etc/nginx/nginx.conf"

to_header_case() {
  local value="$1"
  local out=""
  local token
  local lowered
  local titled

  IFS='-' read -r -a tokens <<< "$value"
  for token in "${tokens[@]}"; do
    [[ -n "$token" ]] || continue
    lowered="${token,,}"
    titled="${lowered^}"
    if [[ -z "$out" ]]; then
      out="$titled"
    else
      out="${out}-${titled}"
    fi
  done

  printf '%s' "$out"
}

echo "[entrypoint] Starting MCP nginx proxy"
echo "[entrypoint] Upstream URL: ${MCP_UPSTREAM_URL}"
echo "[entrypoint] Error log level: ${NGINX_ERROR_LOG_LEVEL}"

header_count=0
header_keys=()
: > "${EXTRA_HEADERS_FILE}"

while IFS='=' read -r name value; do
  [[ "${name}" == MCP_HEADER_* ]] || continue
  [[ -n "${value}" ]] || continue

  raw_header="${name#MCP_HEADER_}"
  dashed_header="${raw_header//_/-}"
  header_name="$(to_header_case "${dashed_header}")"
  [[ -n "${header_name}" ]] || continue

  escaped_value="${value//\\/\\\\}"
  escaped_value="${escaped_value//\"/\\\"}"

  printf 'proxy_set_header %s "%s";\n' "${header_name}" "${escaped_value}" >> "${EXTRA_HEADERS_FILE}"
  header_count=$((header_count + 1))
  header_keys+=("${header_name}")
done < <(env)

if [[ "${header_count}" -eq 0 ]]; then
  echo "[entrypoint] Loaded header overrides: none"
else
  IFS=', '
  echo "[entrypoint] Loaded header overrides (${header_count}): ${header_keys[*]}"
  unset IFS
fi

MCP_UPSTREAM_HOST="$(printf '%s' "${MCP_UPSTREAM_URL}" | sed -E 's#^[a-z]+://([^/:]+).*#\1#')"
export MCP_UPSTREAM_HOST
echo "[entrypoint] Upstream host (Host header / SNI): ${MCP_UPSTREAM_HOST}"

# Origin (scheme://host[:port], no path) and subpath, used to reach OAuth
# discovery, which SaaS MCP servers serve either at the host root or under the
# MCP subpath rather than the subpath the proxy re-homes the server to (`/`).
MCP_UPSTREAM_ORIGIN="$(printf '%s' "${MCP_UPSTREAM_URL}" | sed -E 's#^([a-z]+://[^/]+).*#\1#')"
MCP_UPSTREAM_SUBPATH="$(printf '%s' "${MCP_UPSTREAM_URL}" | sed -E 's#^[a-z]+://[^/]+##; s#/+$##')"
echo "[entrypoint] Upstream origin: ${MCP_UPSTREAM_ORIGIN}  subpath: ${MCP_UPSTREAM_SUBPATH:-/}"

# Shared proxy directives for the discovery location block.
discovery_proxy_directives() {
  cat <<EOF
      proxy_http_version 1.1;
      proxy_ssl_server_name on;
      proxy_set_header Connection "";
      proxy_set_header Host ${MCP_UPSTREAM_HOST};
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto \$scheme;
      proxy_set_header X-Forwarded-Host \$host;

      proxy_buffering off;
      proxy_request_buffering off;
      proxy_read_timeout 300s;
      proxy_send_timeout 300s;
EOF
}

# Route /.well-known/, /oauth/, /register to the upstream host root (regex
# location cannot carry a URI in proxy_pass, so the request URI is preserved).
write_root_discovery() {
  {
    printf '    location ~ ^/(\\.well-known/|oauth/|register) {\n'
    printf '      proxy_pass %s;\n\n' "${MCP_UPSTREAM_ORIGIN}"
    discovery_proxy_directives
    printf '    }\n'
  } > "${DISCOVERY_FILE}"
}

# Route /.well-known/ under the upstream MCP subpath (prefix location, so the
# matched /.well-known/ prefix is replaced with <subpath>/.well-known/).
write_subpath_discovery() {
  {
    printf '    location /.well-known/ {\n'
    printf '      proxy_pass %s%s/.well-known/;\n\n' "${MCP_UPSTREAM_ORIGIN}" "${MCP_UPSTREAM_SUBPATH}"
    discovery_proxy_directives
    printf '    }\n'
  } > "${DISCOVERY_FILE}"
}

# Exact-match location for oauth-protected-resource that rewrites the upstream's
# `resource` value to this proxy's own origin ($scheme://$http_host), so clients
# validating resource==server-URL (RFC 9728) accept the proxied endpoint. Takes
# priority over the general discovery location (exact match wins). $1 = upstream
# metadata URL to proxy to.
write_resource_rewrite() {
  local meta_url="$1"
  local upstream_resource="${MCP_UPSTREAM_ORIGIN}${MCP_UPSTREAM_SUBPATH}"
  cat >> "${DISCOVERY_FILE}" <<EOF
    location = /.well-known/oauth-protected-resource {
      proxy_pass ${meta_url};

$(discovery_proxy_directives)

      proxy_set_header Accept-Encoding "";
      sub_filter_once on;
      sub_filter_types application/json;
      sub_filter '"${upstream_resource}"' '"\$scheme://\$http_host"';
    }
EOF
}

# HTTP status of a GET, or 000 if the upstream is unreachable.
probe_status() {
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 --retry 1 "$1" 2>/dev/null)" || true
  printf '%s' "${code:-000}"
}

# discovery_mode is set to root/subpath/none/off by the routing decision below;
# resource rewriting is then layered on for root/subpath modes.
discovery_mode=""
: > "${DISCOVERY_FILE}"
case "${MCP_OAUTH_DISCOVERY}" in
  off)
    echo "[entrypoint] OAuth discovery routing: disabled (MCP_OAUTH_DISCOVERY=off)"
    discovery_mode="off"
    ;;
  root)
    write_root_discovery
    echo "[entrypoint] OAuth discovery routing: root (forced)"
    discovery_mode="root"
    ;;
  subpath)
    write_subpath_discovery
    echo "[entrypoint] OAuth discovery routing: subpath (forced)"
    discovery_mode="subpath"
    ;;
  auto)
    root_pr="${MCP_UPSTREAM_ORIGIN}/.well-known/oauth-protected-resource"
    sub_pr="${MCP_UPSTREAM_ORIGIN}${MCP_UPSTREAM_SUBPATH}/.well-known/oauth-protected-resource"
    root_code="$(probe_status "${root_pr}")"
    if [[ "${root_code}" == "200" ]]; then
      write_root_discovery
      echo "[entrypoint] OAuth discovery routing: root (detected, ${root_pr} -> 200)"
      discovery_mode="root"
    else
      sub_code="$(probe_status "${sub_pr}")"
      if [[ "${sub_code}" == "200" ]]; then
        write_subpath_discovery
        echo "[entrypoint] OAuth discovery routing: subpath (detected, ${sub_pr} -> 200)"
        discovery_mode="subpath"
      elif [[ "${root_code}" == "000" && "${sub_code}" == "000" ]]; then
        write_root_discovery
        echo "[entrypoint] OAuth discovery routing: root (fallback, upstream unreachable at startup)"
        discovery_mode="root"
      else
        echo "[entrypoint] OAuth discovery routing: disabled (no protected-resource metadata; root=${root_code} subpath=${sub_code})"
        discovery_mode="none"
      fi
    fi
    ;;
  *)
    echo "[entrypoint] Unknown MCP_OAUTH_DISCOVERY='${MCP_OAUTH_DISCOVERY}', treating as auto" >&2
    write_root_discovery
    discovery_mode="root"
    ;;
esac

if [[ "${MCP_OAUTH_REWRITE_RESOURCE}" == "on" ]]; then
  case "${discovery_mode}" in
    root)
      write_resource_rewrite "${MCP_UPSTREAM_ORIGIN}/.well-known/oauth-protected-resource"
      echo "[entrypoint] OAuth resource rewrite: on (resource -> \$scheme://\$http_host)"
      ;;
    subpath)
      write_resource_rewrite "${MCP_UPSTREAM_ORIGIN}${MCP_UPSTREAM_SUBPATH}/.well-known/oauth-protected-resource"
      echo "[entrypoint] OAuth resource rewrite: on (resource -> \$scheme://\$http_host)"
      ;;
  esac
fi

envsubst '${MCP_UPSTREAM_URL} ${MCP_UPSTREAM_HOST} ${NGINX_ERROR_LOG_LEVEL}' < "${TEMPLATE_FILE}" > "${TARGET_FILE}"

nginx -t
exec nginx -g 'daemon off;'
