#!/usr/bin/env pwsh -NoProfile
#Set-PSDebug -Trace 1
$ErrorActionPreference = 'Stop'
$credentials=$(op item get "Adobe-Okta" --no-color --format json | ConvertFrom-Json)
$wiki_token=$credentials.fields | Where-Object { $_.label -eq "confluence" } | Select-Object -ExpandProperty value
$git_corp_token=$credentials.fields | Where-Object { $_.label -eq "git.corp.adobe.com" } | Select-Object -ExpandProperty value
$splunk_mcp_token=$credentials.fields | Where-Object { $_.label -eq "splunk" } | Select-Object -ExpandProperty value
$git_cloud_token=$credentials.fields | Where-Object { $_.label -eq "github.com" } | Select-Object -ExpandProperty value
$jira_corp_token=$credentials.fields | Where-Object { $_.label -eq "jira" } | Select-Object -ExpandProperty value

$credentials=$(op item get "vhaesc3hwo2meqqdk64dk7lsbe" --no-color --format json | ConvertFrom-Json)
$azure_openai_token=$credentials.fields | Where-Object { $_.label -eq "openai-api-token" } | Select-Object -ExpandProperty value
$azure_openai_endpoint=$credentials.fields | Where-Object { $_.label -eq "openai-endpoint" } | Select-Object -ExpandProperty value
$azure_litellm_key=$credentials.fields | Where-Object { $_.label -eq "litellm-master-key" } | Select-Object -ExpandProperty value

# Set environment variables for MCP
$env:ADA_MCP_UPSTREAM_URL="https://mcp.adobe.io/mcp/"
$env:SPLUNK_MCP_UPSTREAM_URL="https://splunk-mcp-us.adobelaas.com/services/mcp/"
$env:WIKI_MCP_TOKEN=$wiki_token
$env:GITHUB_CORP_TOKEN=$git_corp_token
$env:GITHUB_CLOUD_TOKEN=$git_cloud_token
$env:JIRA_PAT_TOKEN=$jira_corp_token
$env:SPLUNK_MCP_TOKEN=$splunk_mcp_token
$env:AZURE_FOUNDRY_API_BASE=$azure_openai_endpoint
$env:AZURE_FOUNDRY_API_KEY=$azure_openai_token
$env:LITELLM_MASTER_KEY=$azure_litellm_key

docker compose pull
docker compose up -d
