#!/usr/bin/env pwsh -NoProfile
#Set-PSDebug -Trace 1
$ErrorActionPreference = 'Stop'
$credentials=$(op item get "Adobe-Okta" --no-color --format json | ConvertFrom-Json)
$wiki_token=$credentials.fields | Where-Object { $_.label -eq "confluence" } | Select-Object -ExpandProperty value
$git_corp_token=$credentials.fields | Where-Object { $_.label -eq "git.corp.adobe.com" } | Select-Object -ExpandProperty value
$splunk_mcp_token=$credentials.fields | Where-Object { $_.label -eq "splunk" } | Select-Object -ExpandProperty value
$git_cloud_token=$credentials.fields | Where-Object { $_.label -eq "github.com" } | Select-Object -ExpandProperty value
$jira_corp_token=$credentials.fields | Where-Object { $_.label -eq "jira" } | Select-Object -ExpandProperty value

# Set environment variables for MCP
$env:ADA_MCP_UPSTREAM_URL="https://mcp.adobe.io/mcp/"
$env:SPLUNK_MCP_UPSTREAM_URL="https://splunk-mcp-us.adobelaas.com/services/mcp/"
$env:WIKI_MCP_TOKEN=$wiki_token
$env:GITHUB_CORP_TOKEN=$git_corp_token
$env:GITHUB_CLOUD_TOKEN=$git_cloud_token
$env:JIRA_PAT_TOKEN=$jira_corp_token
$env:SPLUNK_MCP_TOKEN=$splunk_mcp_token

docker compose pull
docker compose up -d
