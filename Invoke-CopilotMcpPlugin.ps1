#Requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('Status', 'Invoke', 'CompleteTurn')]
    [string]$Command = 'Status',

    [string]$Method,

    [string]$Params,

    [string]$ParamsPath,

    [string]$Response,

    [string]$ResponsePath,

    [string]$WorkspacePath = (Get-Location).ProviderPath,

    [string]$PluginRoot = $PSScriptRoot,

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

function Invoke-BashPluginScript {
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [string[]]$Arguments = @(),
        [string]$StandardInput = ''
    )

    $bash = Resolve-BashExecutable $BashPath
    $pluginRootFull = Resolve-FullPath $PluginRoot
    $workspaceFull = Resolve-FullPath $WorkspacePath
    $cacheRootFull = if ($CacheRoot) {
        Resolve-FullPath $CacheRoot
    } elseif ($env:PLUGIN_ROOT_OVERRIDE) {
        Resolve-FullPath $env:PLUGIN_ROOT_OVERRIDE
    } else {
        $pluginRootFull
    }

    $pluginRootForBash = ConvertTo-BashPath $pluginRootFull
    $workspaceForBash = ConvertTo-BashPath $workspaceFull
    $cacheRootForBash = ConvertTo-BashPath $cacheRootFull

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $bash
    $startInfo.WorkingDirectory = $workspaceFull
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.ArgumentList.Add((ConvertTo-BashPath $ScriptPath))
    foreach ($argument in $Arguments) {
        $startInfo.ArgumentList.Add($argument)
    }
    $startInfo.Environment['COPILOT_PLUGIN_ROOT'] = $pluginRootForBash
    $startInfo.Environment['PLUGIN_ROOT'] = $pluginRootForBash
    $startInfo.Environment['PLUGIN_ROOT_OVERRIDE'] = $cacheRootForBash
    $startInfo.Environment['MCP_WORKSPACE_PATH'] = $workspaceForBash
    $startInfo.Environment['MCPSERVER_WORKSPACE_PATH'] = $workspaceForBash
    $startInfo.Environment['PLUGIN_AGENT_NAME'] = 'Copilot'

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

switch ($Command) {
    'Status' {
        Invoke-BashPluginScript -ScriptPath (Join-Path $pluginRootFull 'lib\mcp.copilot.status.sh')
    }
    'Invoke' {
        if (-not $Method) {
            throw '-Method is required when -Command Invoke is used.'
        }

        $paramsText = Read-TextInput -Inline $Params -HasInline:$($PSBoundParameters.ContainsKey('Params')) -Path $ParamsPath
        Invoke-BashPluginScript -ScriptPath (Join-Path $pluginRootFull 'lib\repl-invoke.sh') -Arguments @($Method) -StandardInput $paramsText
    }
    'CompleteTurn' {
        $responseText = Read-TextInput -Inline $Response -HasInline:$($PSBoundParameters.ContainsKey('Response')) -Path $ResponsePath
        if (-not $responseText) {
            $responseText = 'Turn completed.'
        }

        Invoke-BashPluginScript -ScriptPath (Join-Path $pluginRootFull 'lib\final-response.sh') -StandardInput $responseText
    }
}
