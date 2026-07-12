#Requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('Status', 'Invoke', 'CompleteTurn')]
    [string]$Command = 'Status',

    [string]$Method,

    [string]$Params,

    [string]$ParamsPath,

    [object]$ParamsObject,

    [string]$Response,

    [string]$ResponsePath,

    [string]$WorkspacePath = $(if ($env:MCP_WORKSPACE_PATH) { $env:MCP_WORKSPACE_PATH } elseif ($env:MCPSERVER_WORKSPACE_PATH) { $env:MCPSERVER_WORKSPACE_PATH } elseif ($env:COPILOT_WORKSPACE_PATH) { $env:COPILOT_WORKSPACE_PATH } elseif ($env:COPILOT_PROJECT_DIR) { $env:COPILOT_PROJECT_DIR } else { (Get-Location).ProviderPath }),

    [string]$PluginRoot = $(if ($env:MCP_PLUGIN_ROOT) { $env:MCP_PLUGIN_ROOT } elseif ($env:COPILOT_PLUGIN_ROOT) { $env:COPILOT_PLUGIN_ROOT } elseif ($env:PLUGIN_ROOT) { $env:PLUGIN_ROOT } else { $PSScriptRoot }),

    [string]$CacheRoot,

    [string]$BashPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-FullPath {
    param([Parameter(Mandatory)][string]$Path)

    $resolved = Resolve-Path -LiteralPath $Path -ErrorAction Stop
    return $resolved.ProviderPath
}

function Resolve-BashExecutable {
    param([string]$Candidate)

    if ($Candidate) {
        return (Resolve-FullPath $Candidate)
    }

    if ($IsWindows) {
        foreach ($root in @(${env:ProgramFiles}, ${env:ProgramFiles(x86)})) {
            if (-not $root) {
                continue
            }

            $gitBash = Join-Path $root 'Git\bin\bash.exe'
            if (Test-Path -LiteralPath $gitBash) {
                return $gitBash
            }
        }
    }

    foreach ($name in @('bash.exe', 'bash')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) {
            return $command.Source
        }
    }

    throw 'Unable to find bash. Install Git for Windows or pass -BashPath.'
}

function ConvertTo-BashPath {
    param([Parameter(Mandatory)][string]$Path)

    $full = Resolve-FullPath $Path
    if ($full -match '^([A-Za-z]):\\(.*)$') {
        $drive = $Matches[1].ToLowerInvariant()
        $tail = $Matches[2] -replace '\\', '/'
        return "/$drive/$tail"
    }

    return ($full -replace '\\', '/')
}

function Read-TextInput {
    param(
        [string]$Inline,
        [bool]$HasInline,
        [string]$Path
    )

    if ($Path) {
        return [System.IO.File]::ReadAllText((Resolve-FullPath $Path))
    }

    if ($HasInline) {
        return $Inline
    }

    if ([Console]::IsInputRedirected) {
        return [Console]::In.ReadToEnd()
    }

    return ''
}

function Invoke-PowerShellPluginScript {
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [string[]]$Arguments = @(),
        [string]$StandardInput = ''
    )

    $pwsh = (Get-Command pwsh.exe -ErrorAction Stop).Source
    $pluginRootFull = Resolve-FullPath $PluginRoot
    $workspaceFull = Resolve-FullPath $WorkspacePath
    $cacheOverrideFull = if ($CacheRoot) {
        Resolve-FullPath $CacheRoot
    } elseif ($env:MCP_CACHE_DIR_OVERRIDE) {
        Resolve-FullPath $env:MCP_CACHE_DIR_OVERRIDE
    } else {
        $null
    }
    $legacyCacheRootFull = if (-not $cacheOverrideFull -and $env:PLUGIN_ROOT_OVERRIDE) {
        $legacyFull = Resolve-FullPath $env:PLUGIN_ROOT_OVERRIDE
        if (-not [string]::Equals($legacyFull.TrimEnd('\\'), $pluginRootFull.TrimEnd('\\'), [System.StringComparison]::OrdinalIgnoreCase)) {
            $legacyFull
        }
    }

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $pwsh
    $startInfo.WorkingDirectory = $workspaceFull
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.ArgumentList.Add('-NoLogo')
    $startInfo.ArgumentList.Add('-NoProfile')
    $startInfo.ArgumentList.Add('-NonInteractive')
    $startInfo.ArgumentList.Add('-File')
    $startInfo.ArgumentList.Add((Resolve-FullPath $ScriptPath))
    foreach ($argument in $Arguments) {
        $startInfo.ArgumentList.Add($argument)
    }
    $startInfo.Environment['COPILOT_PLUGIN_ROOT'] = $pluginRootFull
    $startInfo.Environment['PLUGIN_ROOT'] = $pluginRootFull
    $startInfo.Environment['MCP_PLUGIN_ROOT'] = $pluginRootFull
    [void]$startInfo.Environment.Remove('MCP_CACHE_DIR_OVERRIDE')
    [void]$startInfo.Environment.Remove('PLUGIN_ROOT_OVERRIDE')
    if ($cacheOverrideFull) {
        $startInfo.Environment['MCP_CACHE_DIR_OVERRIDE'] = $cacheOverrideFull
    } elseif ($legacyCacheRootFull) {
        $startInfo.Environment['PLUGIN_ROOT_OVERRIDE'] = $legacyCacheRootFull
    }
    $startInfo.Environment['MCP_WORKSPACE_PATH'] = $workspaceFull
    $startInfo.Environment['MCPSERVER_WORKSPACE_PATH'] = $workspaceFull
    $startInfo.Environment['MCP_WORKSPACE_START_DIR'] = $workspaceFull
    $startInfo.Environment['COPILOT_WORKSPACE_PATH'] = $workspaceFull
    $startInfo.Environment['MCP_PLUGIN_HOST'] = 'copilot'
    $startInfo.Environment['PLUGIN_AGENT_NAME'] = 'Copilot'
    $startInfo.Environment['PLUGIN_AGENT_DEFAULT'] = 'Copilot'
    $startInfo.Environment['MCP_AGENT_NAME'] = 'Copilot'

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    [void]$process.Start()

    if ($StandardInput.Length -gt 0) {
        $process.StandardInput.Write($StandardInput)
    }
    $process.StandardInput.Close()

    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    if ($stderr.Length -gt 0) {
        [Console]::Error.Write($stderr)
    }

    if ($stdout.Length -gt 0) {
        Write-Output ($stdout.TrimEnd("`r", "`n"))
    }

    if ($process.ExitCode -ne 0) {
        $msg = "Plugin command failed with exit code $($process.ExitCode)."
        if ($stdout) { $msg += "`n" + $stdout }
        throw $msg
    }
}

$pluginRootFull = Resolve-FullPath $PluginRoot

$paramsObjectBound = $PSBoundParameters.ContainsKey('ParamsObject')
if ($paramsObjectBound -and ($PSBoundParameters.ContainsKey('Params') -or $PSBoundParameters.ContainsKey('ParamsPath'))) {
    throw '-ParamsObject cannot be combined with -Params or -ParamsPath.'
}

$paramsFromObject = ''
if ($paramsObjectBound) {
    . (Join-Path $pluginRootFull 'lib\yaml-object-mutation.ps1')
    Import-McpYamlSerializer
    $paramsFromObject = ConvertTo-Yaml -Data $ParamsObject -Options WithIndentedSequences
}

switch ($Command) {
    'Status' {
        Invoke-PowerShellPluginScript -ScriptPath (Join-Path $pluginRootFull 'lib\mcp-status.ps1')
    }
    'Invoke' {
        if (-not $Method) {
            throw '-Method is required when -Command Invoke is used.'
        }

        $paramsText = if ($paramsObjectBound) {
            $paramsFromObject
        } else {
            Read-TextInput -Inline $Params -HasInline:$($PSBoundParameters.ContainsKey('Params')) -Path $ParamsPath
        }
        Invoke-PowerShellPluginScript -ScriptPath (Join-Path $pluginRootFull 'lib\repl-invoke.ps1') -Arguments @('-Method', $Method, '-ParamsYaml', ($paramsText ?? ''))
    }
    'CompleteTurn' {
        $responseText = Read-TextInput -Inline $Response -HasInline:$($PSBoundParameters.ContainsKey('Response')) -Path $ResponsePath
        if (-not $responseText) {
            $responseText = 'Turn completed.'
        }

        Invoke-PowerShellPluginScript -ScriptPath (Join-Path $pluginRootFull 'lib\final-response.ps1') -StandardInput $responseText
    }
}
