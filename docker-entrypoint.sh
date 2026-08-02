#!/usr/bin/env bash
set -euo pipefail

: "${MCP_UPSTREAM_URL:?MCP_UPSTREAM_URL is required, e.g. http://upstream-mcp:9000}"
: "${NGINX_ERROR_LOG_LEVEL:=warn}"

EXTRA_HEADERS_FILE="/etc/nginx/conf.d/mcp-extra-headers.conf"
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

envsubst '${MCP_UPSTREAM_URL} ${NGINX_ERROR_LOG_LEVEL}' < "${TEMPLATE_FILE}" > "${TARGET_FILE}"

nginx -t
exec nginx -g 'daemon off;'
