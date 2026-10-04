#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'mcp.ps1'
$rootCompose = Join-Path (Split-Path $PSScriptRoot -Parent) 'docker-compose.yml'
$adobeCompose = Join-Path (Split-Path $PSScriptRoot -Parent) 'adobe/docker-compose.yml'
$global:composeLifecycleTestState = @{
    DockerExitCode = 0
    OpExitCode = 0
}
$originalEnvironment = @{}
foreach ($name in @('LITELLM_MASTER_KEY', 'AZURE_FOUNDRY_API_BASE', 'AZURE_FOUNDRY_API_KEY',
    'ADA_MCP_UPSTREAM_URL', 'SPLUNK_MCP_UPSTREAM_URL', 'WIKI_MCP_TOKEN',
    'GITHUB_CORP_TOKEN', 'GITHUB_CLOUD_TOKEN', 'JIRA_PAT_TOKEN', 'SPLUNK_MCP_TOKEN')) {
    $originalEnvironment[$name] = [Environment]::GetEnvironmentVariable($name)
}

function docker {
    $global:composeLifecycleTestState.DockerCalls.Add([pscustomobject]@{
        Arguments = @($args)
        MasterKey = $env:LITELLM_MASTER_KEY
    })
    $global:LASTEXITCODE = $global:composeLifecycleTestState.DockerExitCode
}

function op {
    $global:composeLifecycleTestState.OpCalls.Add(($args -join ' '))
    $global:LASTEXITCODE = $global:composeLifecycleTestState.OpExitCode
    @{
        fields = @(
            foreach ($label in @('confluence', 'git.corp.adobe.com', 'github.com', 'jira',
                'splunk', 'openai-endpoint', 'openai-api-token', 'litellm-master-key')) {
                @{ label = $label; value = "mock-$label" }
            }
        )
    } | ConvertTo-Json -Depth 4
}

function Assert-Equal {
    param($Actual, $Expected)
    if ($Actual -cne $Expected) {
        throw "Expected '$Expected', got '$Actual'."
    }
}

function Invoke-Case {
    param([hashtable]$Parameters = @{}, [string]$ExpectedError = '')
    $script:dockerCalls = [System.Collections.Generic.List[object]]::new()
    $script:opCalls = [System.Collections.Generic.List[string]]::new()
    $global:composeLifecycleTestState.DockerCalls = $script:dockerCalls
    $global:composeLifecycleTestState.OpCalls = $script:opCalls
    $caughtError = $null
    try { $script:lastOutput = & $scriptPath @Parameters } catch { $caughtError = $_ }
    if ($ExpectedError) {
        if (-not $caughtError -or $caughtError.ToString() -notlike "*$ExpectedError*") {
            throw "Expected error '$ExpectedError', got '$caughtError'."
        }
    } elseif ($caughtError) {
        throw $caughtError
    }
}

function Assert-Command {
    param([int]$Index, [string]$ComposeFile, [string]$Command)
    Assert-Equal ($script:dockerCalls[$Index].Arguments -join '|') "compose|-f|$ComposeFile|$Command"
}

try {
    Push-Location ([System.IO.Path]::GetTempPath())
    try {
        Invoke-Case @{ Help = $true }
        if ($lastOutput -notmatch 'Usage: ./mcp\.ps1' -or $lastOutput -notmatch '-Action start\|stop\|destroy') {
            throw 'Help output is missing usage or action details.'
        }
        Assert-Equal $opCalls.Count 0
        Assert-Equal $dockerCalls.Count 0

        Invoke-Case @{ h = $true }
        if ($lastOutput -notmatch 'Usage: ./mcp\.ps1') {
            throw 'The -h alias did not display help.'
        }
        Assert-Equal $opCalls.Count 0
        Assert-Equal $dockerCalls.Count 0

        Invoke-Case
        Assert-Equal $opCalls.Count 1
        Assert-Equal $opCalls[0] 'item get vhaesc3hwo2meqqdk64dk7lsbe --no-color --format json'
        Assert-Equal $dockerCalls.Count 2
        Assert-Command 0 $rootCompose 'pull'
        Assert-Command 1 $rootCompose 'up|-d'
        Assert-Equal $dockerCalls[1].MasterKey 'mock-litellm-master-key'

        Invoke-Case @{ Action = 'start'; Stack = 'adobe' }
        Assert-Equal $opCalls.Count 1
        Assert-Equal $opCalls[0] 'item get Adobe-Okta --no-color --format json'
        Assert-Equal $dockerCalls.Count 2
        Assert-Command 0 $adobeCompose 'pull'
        Assert-Command 1 $adobeCompose 'up|-d'
        Assert-Equal $env:JIRA_PAT_TOKEN 'mock-jira'
        Assert-Equal $env:WIKI_MCP_TOKEN 'mock-confluence'

        Invoke-Case @{ Stack = 'all' }
        Assert-Equal $opCalls.Count 2
        Assert-Equal $dockerCalls.Count 4
        Assert-Command 0 $rootCompose 'pull'
        Assert-Command 1 $rootCompose 'up|-d'
        Assert-Command 2 $adobeCompose 'pull'
        Assert-Command 3 $adobeCompose 'up|-d'

        foreach ($action in @('stop', 'destroy')) {
            foreach ($stack in @('litellm', 'adobe', 'all')) {
                $env:LITELLM_MASTER_KEY = $null
                Invoke-Case @{ Action = $action; Stack = $stack }
                Assert-Equal $opCalls.Count 0
                Assert-Equal $dockerCalls.Count $(if ($stack -eq 'all') { 2 } else { 1 })
                $command = if ($action -eq 'stop') { 'stop' } else { 'down' }
                if ($stack -ne 'adobe') {
                    Assert-Command 0 $rootCompose $command
                    Assert-Equal $dockerCalls[0].MasterKey 'unused-for-teardown'
                }
                if ($stack -ne 'litellm') {
                    Assert-Command ($dockerCalls.Count - 1) $adobeCompose $command
                }
                Assert-Equal ([string]$env:LITELLM_MASTER_KEY) ''
            }
        }

        $env:LITELLM_MASTER_KEY = 'existing-key'
        Invoke-Case @{ Action = 'destroy'; Stack = 'all'; RemoveVolumes = $true }
        Assert-Equal $opCalls.Count 0
        Assert-Command 0 $rootCompose 'down|--volumes'
        Assert-Command 1 $adobeCompose 'down|--volumes'
        Assert-Equal $dockerCalls[0].MasterKey 'existing-key'
        Assert-Equal $env:LITELLM_MASTER_KEY 'existing-key'

        foreach ($action in @('start', 'stop')) {
            Invoke-Case @{ Action = $action; RemoveVolumes = $true } 'only valid'
            Assert-Equal $dockerCalls.Count 0
            Assert-Equal $opCalls.Count 0
        }
        Invoke-Case @{ Action = 'invalid' } 'ValidateSet'
        Invoke-Case @{ Stack = 'invalid' } 'ValidateSet'

        $global:composeLifecycleTestState.OpExitCode = 1
        Invoke-Case @{} 'credential lookup failed'
        Assert-Equal $dockerCalls.Count 0
        $global:composeLifecycleTestState.OpExitCode = 0
        $global:composeLifecycleTestState.DockerExitCode = 1
        Invoke-Case @{ Stack = 'all' } 'exit code 1'
        Assert-Equal $dockerCalls.Count 1
        Assert-Equal $opCalls.Count 1
        $env:LITELLM_MASTER_KEY = $null
        Invoke-Case @{ Action = 'stop' } 'exit code 1'
        Assert-Equal ([string]$env:LITELLM_MASTER_KEY) ''
        Assert-Equal $opCalls.Count 0
    } finally {
        Pop-Location
    }
    Write-Host 'Compose lifecycle tests passed (mocked docker and op).'
} finally {
    foreach ($name in $originalEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $originalEnvironment[$name])
    }
    Remove-Variable composeLifecycleTestState -Scope Global
}