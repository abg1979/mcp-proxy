#!/usr/bin/env pwsh -NoProfile
[CmdletBinding()]
param(
	[ValidateSet('start', 'stop', 'destroy')]
	[string]$Action = 'start',

	[ValidateSet('litellm', 'adobe', 'all')]
	[string]$Stack = 'litellm',

	[Alias('h')]
	[switch]$Help,

	[switch]$RemoveVolumes
)

$ErrorActionPreference = 'Stop'

if ($Help) {
	@'
Usage: ./mcp.ps1 [-Action start|stop|destroy] [-Stack litellm|adobe|all] [-RemoveVolumes] [-Help]

Actions:
  start    Pull images and start the selected stack (default).
  stop     Stop containers without removing them.
  destroy  Remove containers and networks; volumes are preserved by default.

Stacks:
  litellm  Top-level LiteLLM stack (default).
  adobe    Adobe and Splunk MCP gateways.
  all      Apply the action to both stacks.

Options:
  -RemoveVolumes  With -Action destroy, also remove named volumes.
  -Help, -h       Show this help text.
'@
	return
}

if ($RemoveVolumes -and $Action -ne 'destroy') {
	throw '-RemoveVolumes is only valid with -Action destroy.'
}

function Get-StackCredentials {
	param([string]$Item)

	$json = op item get $Item --no-color --format json
	if ($LASTEXITCODE -ne 0) {
		throw "1Password credential lookup failed for '$Item' (exit code $LASTEXITCODE)."
	}
	return $json | ConvertFrom-Json
}

function Invoke-Compose {
	param([string[]]$CommandArguments)

	docker @composeArguments @CommandArguments
	if ($LASTEXITCODE -ne 0) {
		throw "Docker Compose '$($CommandArguments -join ' ')' failed for '$selectedStack' (exit code $LASTEXITCODE)."
	}
}

$stacks = if ($Stack -eq 'all') { @('litellm', 'adobe') } else { @($Stack) }

foreach ($selectedStack in $stacks) {
	$composeFile = if ($selectedStack -eq 'adobe') {
		Join-Path $PSScriptRoot 'adobe/docker-compose.yml'
	} else {
		Join-Path $PSScriptRoot 'docker-compose.yml'
	}
	$composeArguments = @('compose', '-f', $composeFile)
	$previousMasterKey = $env:LITELLM_MASTER_KEY

	try {
		if ($Action -eq 'start') {
			if ($selectedStack -eq 'adobe') {
				$credentials = Get-StackCredentials 'Adobe-Okta'
				$env:ADA_MCP_UPSTREAM_URL = 'https://mcp.adobe.io/mcp/'
				$env:SPLUNK_MCP_UPSTREAM_URL = 'https://splunk-mcp-us.adobelaas.com/services/mcp/'
				$env:WIKI_MCP_TOKEN = $credentials.fields | Where-Object { $_.label -eq 'confluence' } | Select-Object -ExpandProperty value
				$env:GITHUB_CORP_TOKEN = $credentials.fields | Where-Object { $_.label -eq 'git.corp.adobe.com' } | Select-Object -ExpandProperty value
				$env:GITHUB_CLOUD_TOKEN = $credentials.fields | Where-Object { $_.label -eq 'github.com' } | Select-Object -ExpandProperty value
				$env:JIRA_PAT_TOKEN = $credentials.fields | Where-Object { $_.label -eq 'jira' } | Select-Object -ExpandProperty value
				$env:SPLUNK_MCP_TOKEN = $credentials.fields | Where-Object { $_.label -eq 'splunk' } | Select-Object -ExpandProperty value
			} else {
				$credentials = Get-StackCredentials 'vhaesc3hwo2meqqdk64dk7lsbe'
				$env:AZURE_FOUNDRY_API_BASE = $credentials.fields | Where-Object { $_.label -eq 'openai-endpoint' } | Select-Object -ExpandProperty value
				$env:AZURE_FOUNDRY_API_KEY = $credentials.fields | Where-Object { $_.label -eq 'openai-api-token' } | Select-Object -ExpandProperty value
				$env:LITELLM_MASTER_KEY = $credentials.fields | Where-Object { $_.label -eq 'litellm-master-key' } | Select-Object -ExpandProperty value
			}
		} elseif ($selectedStack -eq 'litellm' -and -not $env:LITELLM_MASTER_KEY) {
			$env:LITELLM_MASTER_KEY = 'unused-for-teardown'
		}

		switch ($Action) {
			'start' {
				Invoke-Compose @('pull')
				Invoke-Compose @('up', '-d')
			}
			'stop' { Invoke-Compose @('stop') }
			'destroy' {
				$downArguments = @('down')
				if ($RemoveVolumes) { $downArguments += '--volumes' }
				Invoke-Compose $downArguments
			}
		}
	} finally {
		if ($Action -ne 'start') {
			$env:LITELLM_MASTER_KEY = $previousMasterKey
		}
	}
}
