#Requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$LockFileName = '.oi-toolkit.lock.json'
$Utf8NoBom = [Text.UTF8Encoding]::new($false)

function Get-OiToolkitInfo {
    param([Parameter(Mandatory)][string]$ToolkitRoot)
    $marketplace = Get-Content -LiteralPath (Join-Path $ToolkitRoot '.claude-plugin/marketplace.json') -Raw | ConvertFrom-Json
    $plugin = Get-Content -LiteralPath (Join-Path $ToolkitRoot 'plugins/oi-toolkit/.claude-plugin/plugin.json') -Raw | ConvertFrom-Json
    [PSCustomObject]@{
        MarketplaceName = $marketplace.name
        PluginId        = "$($plugin.name)@$($marketplace.name)"
        Version         = $plugin.version
    }
}

function Get-OiTreeMap {
    param([string]$ProjectFiles, [string]$SourceDir, [string]$TargetDir, [string]$Mode)
    $root = Join-Path $ProjectFiles $SourceDir
    foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File) {
        $relative = [IO.Path]::GetRelativePath($root, $file.FullName).Replace('\', '/')
        [PSCustomObject]@{ Source = $file.FullName; Target = "$TargetDir/$relative"; Mode = $Mode }
    }
}

function Get-OiFileMap {
    param([Parameter(Mandatory)][string]$ToolkitRoot)
    $projectFiles = Join-Path $ToolkitRoot 'project-files'
    Get-OiTreeMap $projectFiles 'rules' '.claude/rules' 'managed'
    Get-OiTreeMap $projectFiles 'tools' 'tools' 'managed'
    Get-OiTreeMap $projectFiles 'connectors' 'sync/connectors' 'managed'
    Get-OiTreeMap $projectFiles 'docs-templates' 'docs' 'seed'
    [PSCustomObject]@{ Source = (Join-Path $projectFiles 'oi-shared.md'); Target = '.claude/oi-shared.md'; Mode = 'managed' }
    [PSCustomObject]@{ Source = (Join-Path $projectFiles 'gitignore'); Target = '.gitignore'; Mode = 'seed' }
    [PSCustomObject]@{ Source = (Join-Path $projectFiles 'mkdocs.yml'); Target = 'mkdocs.yml'; Mode = 'seed' }
    [PSCustomObject]@{ Source = (Join-Path $projectFiles 'oi-env.template.psd1'); Target = 'oi-env.psd1'; Mode = 'seed' }
    [PSCustomObject]@{ Source = (Join-Path $projectFiles 'CLAUDE.template.md'); Target = 'CLAUDE.md'; Mode = 'seed' }
}

function Get-OiFileAction {
    # Decides what to do with one file. Pure: the caller applies the result.
    param([string]$Mode, [string]$WorkspaceHash, [string]$LockHash, [string]$SourceHash)
    if (-not $WorkspaceHash) { return 'Create' }
    if ($Mode -eq 'seed') { return 'Keep' }
    if ($WorkspaceHash -eq $SourceHash) { return 'Unchanged' }
    if ($LockHash -and $WorkspaceHash -eq $LockHash) { return 'Update' }
    return 'LocalChange'
}

function Get-OiContentHash {
    # Line endings are normalized: git autocrlf must not look like a local change.
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    $bytes = [IO.File]::ReadAllBytes($Path)
    $text = [Text.Encoding]::Latin1.GetString($bytes).Replace("`r`n", "`n")
    $hash = [Security.Cryptography.SHA256]::HashData([Text.Encoding]::Latin1.GetBytes($text))
    return [Convert]::ToHexString($hash)
}

function Read-OiLock {
    param([Parameter(Mandatory)][string]$WorkspaceRoot)
    $path = Join-Path $WorkspaceRoot $LockFileName
    if (-not (Test-Path -LiteralPath $path)) { return @{ version = ''; files = @{} } }
    return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
}

function Write-OiLock {
    param([string]$WorkspaceRoot, [string]$Version, [hashtable]$Files)
    $sorted = [ordered]@{}
    foreach ($key in ($Files.Keys | Sort-Object)) { $sorted[$key] = $Files[$key] }
    $json = [ordered]@{ version = $Version; files = $sorted } | ConvertTo-Json -Depth 4
    [IO.File]::WriteAllText((Join-Path $WorkspaceRoot $LockFileName), "$json`n", $Utf8NoBom)
}

function Copy-OiFile {
    param([string]$Source, [string]$Destination, [hashtable]$Tokens)
    $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination)
    $isTemplate = $Source -match '(CLAUDE\.template\.md|mkdocs\.yml)$'
    if (-not $isTemplate) { Copy-Item -LiteralPath $Source -Destination $Destination -Force; return }
    $text = [IO.File]::ReadAllText($Source)
    foreach ($token in $Tokens.Keys) { $text = $text.Replace($token, $Tokens[$token]) }
    [IO.File]::WriteAllText($Destination, $text, $Utf8NoBom)
}

function Sync-OiFile {
    # Applies the toolkit files to a workspace and returns one result object per file.
    param(
        [Parameter(Mandatory)][string]$ToolkitRoot,
        [Parameter(Mandatory)][string]$WorkspaceRoot,
        [hashtable]$Tokens = @{},
        [switch]$DryRun
    )
    $info = Get-OiToolkitInfo -ToolkitRoot $ToolkitRoot
    $lock = Read-OiLock -WorkspaceRoot $WorkspaceRoot
    $newLock = @{}
    $results = foreach ($entry in Get-OiFileMap -ToolkitRoot $ToolkitRoot) {
        $destination = Join-Path $WorkspaceRoot $entry.Target
        $lockHash = if ($lock.files.ContainsKey($entry.Target)) { $lock.files[$entry.Target] } else { '' }
        $sourceHash = Get-OiContentHash $entry.Source
        $action = Get-OiFileAction -Mode $entry.Mode -WorkspaceHash (Get-OiContentHash $destination) -LockHash $lockHash -SourceHash $sourceHash
        if ($action -in 'Create', 'Update' -and -not $DryRun) { Copy-OiFile $entry.Source $destination $Tokens }
        if ($entry.Mode -eq 'managed') { $newLock[$entry.Target] = if ($action -eq 'LocalChange') { $lockHash } else { $sourceHash } }
        [PSCustomObject]@{ Target = $entry.Target; Mode = $entry.Mode; Action = $action }
    }
    $orphans = foreach ($target in $lock.files.Keys) {
        if (-not $newLock.ContainsKey($target)) { [PSCustomObject]@{ Target = $target; Mode = 'managed'; Action = 'NoLongerInToolkit' } }
    }
    if (-not $DryRun) { Write-OiLock -WorkspaceRoot $WorkspaceRoot -Version $info.Version -Files $newLock }
    @($results) + @($orphans)
}

function Merge-OiPermission {
    # Union of the lists: an update can add a rule, never remove one. defaultMode stays as the workspace set it.
    param([hashtable]$Base, [hashtable]$Existing)
    $merged = [ordered]@{}
    foreach ($key in @($Existing.Keys) + @($Base.Keys) | Select-Object -Unique) {
        $hasBoth = $Base.ContainsKey($key) -and $Existing.ContainsKey($key)
        $isList = $hasBoth -and $Base[$key] -is [array]
        $merged[$key] = if ($isList) { @(@($Existing[$key]) + @($Base[$key]) | Select-Object -Unique) }
        elseif ($Existing.ContainsKey($key)) { $Existing[$key] } else { $Base[$key] }
    }
    return $merged
}

function Get-OiMergedSettings {
    # Returns new settings; the inputs are left untouched.
    param(
        [Parameter(Mandatory)][hashtable]$Base,
        [Parameter(Mandatory)][hashtable]$Existing,
        [Parameter(Mandatory)][string]$MarketplaceName,
        [Parameter(Mandatory)][string]$PluginId,
        [Parameter(Mandatory)][ValidatePattern('^[\w.-]+/[\w.-]+$')][string]$Repo,
        [Parameter(Mandatory)][string]$Ref
    )
    $merged = [ordered]@{}
    foreach ($key in $Existing.Keys) { $merged[$key] = $Existing[$key] }
    $existingPermissions = if ($Existing.ContainsKey('permissions')) { $Existing['permissions'] } else { @{} }
    $merged['permissions'] = Merge-OiPermission -Base $Base['permissions'] -Existing $existingPermissions

    $marketplaces = [ordered]@{}
    if ($Existing.ContainsKey('extraKnownMarketplaces')) { foreach ($k in $Existing['extraKnownMarketplaces'].Keys) { $marketplaces[$k] = $Existing['extraKnownMarketplaces'][$k] } }
    $marketplaces[$MarketplaceName] = [ordered]@{ source = [ordered]@{ source = 'github'; repo = $Repo; ref = $Ref } }
    $merged['extraKnownMarketplaces'] = $marketplaces

    $plugins = [ordered]@{}
    if ($Existing.ContainsKey('enabledPlugins')) { foreach ($k in $Existing['enabledPlugins'].Keys) { $plugins[$k] = $Existing['enabledPlugins'][$k] } }
    $plugins[$PluginId] = $true
    $merged['enabledPlugins'] = $plugins
    return $merged
}

function Read-OiJsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @{} }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
}

function Update-OiSettingsFile {
    param(
        [string]$ToolkitRoot,
        [string]$WorkspaceRoot,
        [string]$Repo,
        [string]$Ref,
        [switch]$DryRun
    )
    $info = Get-OiToolkitInfo -ToolkitRoot $ToolkitRoot
    $path = Join-Path $WorkspaceRoot '.claude/settings.json'
    $existing = Read-OiJsonFile $path
    if (-not $Repo) {
        $known = if ($existing.ContainsKey('extraKnownMarketplaces')) { $existing['extraKnownMarketplaces'] } else { @{} }
        if (-not $known.ContainsKey($info.MarketplaceName)) { throw "Marketplace $($info.MarketplaceName) is not in ${path}: pass -MarketplaceRepo owner/repo." }
        $Repo = $known[$info.MarketplaceName]['source']['repo']
    }
    $base = Read-OiJsonFile (Join-Path $ToolkitRoot 'project-files/settings.base.json')
    $merged = Get-OiMergedSettings -Base $base -Existing $existing -MarketplaceName $info.MarketplaceName -PluginId $info.PluginId -Repo $Repo -Ref $Ref
    if ($DryRun) { return $merged }
    $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path)
    [IO.File]::WriteAllText($path, (($merged | ConvertTo-Json -Depth 8) + "`n"), $Utf8NoBom)
    return $merged
}

Export-ModuleMember -Function Get-OiToolkitInfo, Get-OiFileMap, Get-OiFileAction, Get-OiContentHash, Read-OiLock, Sync-OiFile, Get-OiMergedSettings, Update-OiSettingsFile
