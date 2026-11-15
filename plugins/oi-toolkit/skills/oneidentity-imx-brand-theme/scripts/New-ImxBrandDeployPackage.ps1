#Requires -Version 7.6
<#
.SYNOPSIS
    Prepares the Software Loader package of the brand themes: Web Portal with ccc and the theme CSS, plugin config,
    theme config. Deploys nothing.
.DESCRIPTION
    1. Build-ImxBrandTheme.ps1 (blocking checks) -> <BrandDir>/dist/<id>/<class>.css.
    2. ccc unit tests (unless -SkipTests).
    3. qer-app-portal production build with --skip-nx-cache: Nx does not count dist/ccc as a portal input, a cached
       portal bundle would ship the previous ccc code (unless -SkipPortalBuild).
    4. The portal bundle must contain BrandThemeService (marker --ccc-brand-light-class), otherwise status blocked.
    5. New staging folder <StagingRoot>/<timestamp>/imxweb mirroring the API Server bin\imxweb:
         custom\Html_qer-app-portal.zip            portal build + <id>/<class>.css (served under html/qer-app-portal/)
         Html_ccc\imx-plugin-config.json           loads ccc in qer-app-portal
         Html_<light class>\imx-theme-config.json  both themes, Urls ../qer-app-portal/<id>/<class>.css
    Each file is compared with -ApiServerImxWeb: importNeeded = missing there or different.
    Procedure: HTML Development Guide 10.0, "Compiling and deploying web applications" and "Adding plugins".
    Last output line: JSON { status, staging, files: [{ path, bytes, sha, importNeeded }], problems }.
.EXAMPLE
    pwsh -NoProfile -File New-ImxBrandDeployPackage.ps1 -Id acme -ImxWebDir oim/webportal/imx/imxweb `
        -BrandDir oim/webportal/brand/acme -StagingRoot oim/webportal/deploy-staging -ApiServerImxWeb <ApiServer>\bin\imxweb
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[a-z][a-z0-9-]{1,30}$')][string] $Id,
    [Parameter(Mandatory)][string] $ImxWebDir,
    # Folder of brand.json and of the generated imx-theme-config.json.
    [Parameter(Mandatory)][string] $BrandDir,
    [Parameter(Mandatory)][string] $StagingRoot,
    # bin\imxweb of the API Server (read only), to tell which files need an import.
    [Parameter(Mandatory)][string] $ApiServerImxWeb,
    [string] $PortalDistDir,
    [switch] $SkipTests,
    [switch] $SkipPortalBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PortalApp = 'qer-app-portal'
# BrandThemeService builds the variable names from a prefix (minified bundles keep the two parts apart).
$BundleMarkers = '"--ccc-brand-"', '"light-class"'
$problems = [Collections.Generic.List[string]]::new()
# Resolve relative paths against the current PowerShell location (not the process folder) before any Push-Location.
$StagingRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($StagingRoot)
$ApiServerImxWeb = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ApiServerImxWeb)
$imxWeb = (Resolve-Path -LiteralPath $ImxWebDir).Path
$brandFull = (Resolve-Path -LiteralPath $BrandDir).Path
if (-not $PortalDistDir) { $PortalDistDir = Join-Path $imxWeb "dist/$PortalApp" } else { $PortalDistDir = (Resolve-Path -LiteralPath $PortalDistDir).Path }

function Write-Result([string] $Status, [string] $Staging, $Files) {
    [ordered]@{ status = $Status; staging = $Staging; files = @($Files); problems = $problems.ToArray() } | ConvertTo-Json -Compress -Depth 4
}

function Invoke-InImxWeb([scriptblock] $Command, [string] $What) {
    Push-Location $imxWeb
    try { $output = & $Command 2>&1; if ($LASTEXITCODE -ne 0) { $problems.Add("$What failed (exit $LASTEXITCODE): $(($output | Select-Object -Last 5) -join ' ')") } }
    finally { Pop-Location }
}

# 1. Themes
$themeDist = Join-Path $brandFull 'dist'
$build = & (Join-Path $PSScriptRoot 'Build-ImxBrandTheme.ps1') -Id $Id -ImxWebDir $imxWeb -OutDir $themeDist | Select-Object -Last 1 | ConvertFrom-Json
if ($build.status -ne 'ok') { $problems.Add("theme build blocked: $($build.checks | ConvertTo-Json -Compress -Depth 3)"); Write-Result 'blocked' $null @(); return }

# 2-3. Tests and portal build
if (-not $SkipTests) { Invoke-InImxWeb { npx nx test ccc --watch=false --browsers ChromeHeadless } 'ccc tests' }
if (-not $SkipPortalBuild -and $problems.Count -eq 0) { Invoke-InImxWeb { npx nx build $PortalApp --configuration production --skip-nx-cache } 'portal build' }
if ($problems.Count -gt 0) { Write-Result 'blocked' $null @(); return }

# 4. Bundle check
if (-not (Test-Path -LiteralPath (Join-Path $PortalDistDir 'index.html'))) { $problems.Add("no portal build in $PortalDistDir"); Write-Result 'blocked' $null @(); return }
$withPlugin = Get-ChildItem -LiteralPath $PortalDistDir -Filter 'chunk-*.js' | Where-Object { $text = Get-Content -LiteralPath $_.FullName -Raw; @($BundleMarkers | Where-Object { -not $text.Contains($_) }).Count -eq 0 }
if (-not $withPlugin) { $problems.Add("portal bundle without BrandThemeService ($($BundleMarkers -join ' + ') not found in one chunk): install the plugin (Install-ImxBrandPlugin.ps1) and rebuild"); Write-Result 'blocked' $null @(); return }

# 5. Staging
$configSource = Join-Path $brandFull 'imx-theme-config.json'
if (-not (Test-Path -LiteralPath $configSource)) { $problems.Add("$configSource missing: run New-ImxBrandTheme.ps1"); Write-Result 'blocked' $null @(); return }
$lightClass = ((Get-Content -LiteralPath $configSource -Raw | ConvertFrom-Json).Themes | Select-Object -First 1).Class
$stage = [IO.Path]::GetFullPath((Join-Path $StagingRoot ((Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '\imxweb')))
$work = Join-Path (Split-Path -Parent $stage) "work\$PortalApp"
New-Item -ItemType Directory -Force $work, (Join-Path $stage 'custom'), (Join-Path $stage 'Html_ccc'), (Join-Path $stage "Html_$lightClass") | Out-Null
Copy-Item -Path (Join-Path $PortalDistDir '*') -Destination $work -Recurse
Copy-Item -LiteralPath (Join-Path $themeDist $Id) -Destination $work -Recurse
Compress-Archive -Path (Join-Path $work '*') -DestinationPath (Join-Path $stage "custom\Html_$PortalApp.zip")
Remove-Item -LiteralPath (Split-Path -Parent $work) -Recurse -Force
Copy-Item -LiteralPath (Join-Path $imxWeb 'projects/ccc/imx-plugin-config.json') -Destination (Join-Path $stage 'Html_ccc')
Copy-Item -LiteralPath $configSource -Destination (Join-Path $stage "Html_$lightClass")

$files = Get-ChildItem -LiteralPath $stage -Recurse -File | Sort-Object FullName | ForEach-Object {
    $rel = $_.FullName.Substring($stage.Length + 1)
    $sha = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    $deployed = Join-Path $ApiServerImxWeb $rel
    [ordered]@{
        path         = $rel
        bytes        = $_.Length
        sha          = $sha.Substring(0, 12)
        importNeeded = -not (Test-Path -LiteralPath $deployed) -or (Get-FileHash -LiteralPath $deployed -Algorithm SHA256).Hash -ne $sha
    }
}
Write-Result 'ok' $stage $files
