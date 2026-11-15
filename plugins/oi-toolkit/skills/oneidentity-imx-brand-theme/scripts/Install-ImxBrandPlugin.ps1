#Requires -Version 7.6
<#
.SYNOPSIS
    Installs (or updates) the generic BrandThemeService in the ccc plugin of an IdentityManager.Imx workspace.
.DESCRIPTION
    Copies templates/ccc/brand-theme/*.ts into projects/ccc/src/lib/brand-theme/ and registers
    BrandThemeService.start() in InitService (import, constructor parameter, onInit call) when missing.
    - No projects/ccc: status needs-ccc, nothing written (create the plugin first: reference.md, "Plugin ccc").
    - A template file changed by hand since the last install (hashes in brand-theme/.kit.json): status blocked.
    - InitService not in the expected shape: status blocked with the manual step.
    Never edits upstream files. Last output line: JSON { status, written, unchanged, actions }.
.EXAMPLE
    pwsh -NoProfile -File Install-ImxBrandPlugin.ps1 -ImxWebDir oim/webportal/imx/imxweb
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string] $ImxWebDir)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$templates = Join-Path (Split-Path -Parent $PSScriptRoot) 'templates/ccc/brand-theme'
$importLine = "import { BrandThemeService } from './brand-theme/brand-theme.service';"
$written = [Collections.Generic.List[string]]::new()
$unchanged = [Collections.Generic.List[string]]::new()
$actions = [Collections.Generic.List[string]]::new()

function Write-Result([string] $Status) {
    [ordered]@{ status = $Status; written = $written.ToArray(); unchanged = $unchanged.ToArray(); actions = $actions.ToArray() } | ConvertTo-Json -Compress
}

function Get-NormalizedText([string] $Path) { return (Get-Content -LiteralPath $Path -Raw) -replace "`r`n", "`n" }
function Get-TextHash([string] $Text) { return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Text))) }

$imxWeb = (Resolve-Path -LiteralPath $ImxWebDir).Path
$lib = Join-Path $imxWeb 'projects/ccc/src/lib'
if (-not (Test-Path -LiteralPath $lib)) {
    $actions.Add('Create the ccc plugin library first: reference.md, section "Plugin ccc" (skeleton in templates/ccc/skeleton).')
    Write-Result 'needs-ccc'
    return
}

#region Template files
$target = Join-Path $lib 'brand-theme'
$recordPath = Join-Path $target '.kit.json'
$record = if (Test-Path -LiteralPath $recordPath) { Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json -AsHashtable } else { @{} }
$plan = [ordered]@{}
$blocked = [Collections.Generic.List[string]]::new()
foreach ($file in Get-ChildItem -LiteralPath $templates -Filter '*.ts' | Sort-Object Name) {
    $content = Get-NormalizedText $file.FullName
    $path = Join-Path $target $file.Name
    if (Test-Path -LiteralPath $path) {
        $current = Get-NormalizedText $path
        if ($current -eq $content) { $unchanged.Add("brand-theme/$($file.Name)"); continue }
        if (-not $record.ContainsKey($file.Name) -or $record[$file.Name] -ne (Get-TextHash $current)) { $blocked.Add("brand-theme/$($file.Name)"); continue }
    }
    $plan[$file.Name] = $content
}
if ($blocked.Count -gt 0) {
    $actions.Add("Changed by hand since the last install, nothing written: $($blocked -join ', '). Move the change into the kit or revert it.")
    Write-Result 'blocked'
    return
}
#endregion

#region InitService
$initPath = Join-Path $lib 'init.service.ts'
if (-not (Test-Path -LiteralPath $initPath)) {
    $actions.Add('projects/ccc/src/lib/init.service.ts not found: register BrandThemeService.start() by hand (reference.md, "Plugin ccc").')
    Write-Result 'blocked'
    return
}
$init = Get-NormalizedText $initPath
$newInit = $init
if (-not $newInit.Contains($importLine)) {
    $lastImport = [regex]::Matches($newInit, '(?m)^import .*;$') | Select-Object -Last 1
    if (-not $lastImport) { $actions.Add('init.service.ts: no import found; add the registration by hand.'); Write-Result 'blocked'; return }
    $newInit = $newInit.Insert($lastImport.Index + $lastImport.Length, "`n$importLine")
}
if ($newInit -notmatch 'brandTheme:\s*BrandThemeService') {
    $ctor = [regex]::Match($newInit, 'constructor\(([\s\S]*?)\)\s*\{\s*\}')
    if (-not $ctor.Success) { $actions.Add('init.service.ts: constructor not in the form constructor(...) {}; add the BrandThemeService parameter by hand.'); Write-Result 'blocked'; return }
    $params = $ctor.Groups[1].Value.Trim().TrimEnd(',')
    $replacement = "constructor(`n    $(($params -split ',\s*' | Where-Object { $_ }) -join ",`n    "),`n    private readonly brandTheme: BrandThemeService,`n  ) {}"
    $newInit = $newInit.Remove($ctor.Index, $ctor.Length).Insert($ctor.Index, $replacement)
}
if ($newInit -notmatch 'this\.brandTheme\.start\(\);') {
    $onInit = [regex]::Match($newInit, '(public\s+)?onInit\(\)(:\s*void)?\s*\{([\s\S]*?)\n  \}')
    if (-not $onInit.Success) { $actions.Add('init.service.ts: onInit() not found; call this.brandTheme.start() there by hand.'); Write-Result 'blocked'; return }
    $insertAt = $onInit.Index + $onInit.Length - 4
    $newInit = $newInit.Insert($insertAt, "`n    this.brandTheme.start();")
}
#endregion

#region Write
New-Item -ItemType Directory -Force $target | Out-Null
foreach ($name in $plan.Keys) {
    Set-Content -LiteralPath (Join-Path $target $name) -Value $plan[$name] -NoNewline -Encoding utf8NoBOM
    $written.Add("brand-theme/$name")
}
$newRecord = [ordered]@{}
foreach ($file in Get-ChildItem -LiteralPath $templates -Filter '*.ts' | Sort-Object Name) { $newRecord[$file.Name] = Get-TextHash (Get-NormalizedText $file.FullName) }
$recordText = ($newRecord | ConvertTo-Json) + "`n"
if (-not (Test-Path -LiteralPath $recordPath) -or (Get-Content -LiteralPath $recordPath -Raw) -ne $recordText) {
    Set-Content -LiteralPath $recordPath -Value $recordText -NoNewline -Encoding utf8NoBOM
}
if ($newInit -ne $init) {
    Set-Content -LiteralPath $initPath -Value $newInit -NoNewline -Encoding utf8NoBOM
    $written.Add('init.service.ts')
    $actions.Add('Update init.service.spec.ts: InitService now takes a BrandThemeService (pass a jasmine spy object with start()).')
}
if ($newInit -match 'LegacyThemeService|ThemeService(?<!BrandThemeService)\b' -and $newInit -match 'class InitService') {
    $legacy = [regex]::Matches($newInit, '\b(\w+ThemeService)\b') | ForEach-Object { $_.Value } | Where-Object { $_ -ne 'BrandThemeService' } | Select-Object -Unique
    foreach ($name in $legacy) { $actions.Add("init.service.ts still uses ${name}: remove it by hand (replaced by BrandThemeService), with its files and spec.") }
}
Write-Result 'ok'
#endregion
