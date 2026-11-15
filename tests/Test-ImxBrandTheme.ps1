#Requires -Version 7.6
<#
.SYNOPSIS
    Tests of the Web Portal brand theme kit (skill oneidentity-imx-brand-theme).
.PARAMETER ImxWebDir
    Optional: an imxweb folder with node_modules (the IdentityManager.Imx workspace). Without it the integration
    blocks (sass, postcss, nx) are skipped.
#>
[CmdletBinding()]
param([string] $ImxWebDir)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$toolkit = Split-Path -Parent $PSScriptRoot
$kit = Join-Path $toolkit 'plugins/oi-toolkit/skills/oneidentity-imx-brand-theme'
$script:failures = 0

function Assert-True([bool]$Condition, [string]$Name) {
    if ($Condition) { Write-Host "ok   $Name" } else { Write-Host "FAIL $Name"; $script:failures++ }
}

function Test-ImxThrows([scriptblock]$Action) {
    try { & $Action | Out-Null; return $false } catch { return $true }
}

#region Color math (Task 1)
Import-Module (Join-Path $kit 'scripts/ImxBrandColor.psm1') -Force
Assert-True ([Math]::Round((Get-ImxContrast '#f69097' '#444647'), 1) -eq 4.2) 'contrast accent on card'
Assert-True ([Math]::Round((Get-ImxContrast '#ee424d' '#444647'), 1) -eq 2.5) 'contrast bright red on card'
Assert-True ((Get-ImxContrast '#ffffff' '#a4262c') -ge 7.0) 'white on dark fill'
Assert-True ((ConvertTo-ImxRgb '#EB212E') -join ',' -eq '235,33,46') 'hex to rgb, any case'
$palette = New-ImxBrandPalette '#eb212e'
Assert-True ($palette['500'] -eq '#eb212e' -and $palette.Count -eq 10) 'palette keeps primary as 500'
Assert-True ((Get-ImxContrast $palette['50'] '#ffffff') -lt (Get-ImxContrast $palette['900'] '#ffffff')) 'palette goes from light to dark'
$accent = Select-ImxDarkAccent $palette
Assert-True ((Get-ImxContrast $accent '#444647') -ge 4.0 -and (Get-ImxContrast $accent '#1e1e1e') -ge 4.5) 'dark accent meets thresholds'
Assert-True ((Get-ImxContrast '#ffffff' (Select-ImxDarkFill $palette '#eb212e')) -ge 7.0) 'dark fill carries white text'
Assert-True ((Get-ImxOnColor '#ffd200') -eq '#000000' -and (Get-ImxOnColor '#eb212e') -eq '#ffffff') 'on-color by contrast'
#endregion

#region brand.json (Task 2)
$acme = Join-Path $kit 'examples/acme/brand.json'
$tmp = Join-Path ([IO.Path]::GetTempPath()) "imx-brand-test-$PID"
New-Item -ItemType Directory -Force $tmp | Out-Null
Copy-Item (Join-Path $kit 'examples/acme/*.png') $tmp

function New-TestBrand([hashtable] $Changes, [string] $Name) {
    $json = Get-Content -LiteralPath $acme -Raw | ConvertFrom-Json -AsHashtable
    foreach ($key in $Changes.Keys) {
        $target = $json; $parts = $key -split '\.'
        foreach ($p in $parts[0..($parts.Count - 2)]) { if (-not $target.ContainsKey($p)) { $target[$p] = @{} }; $target = $target[$p] }
        if ($null -eq $Changes[$key]) { $target.Remove($parts[-1]) } else { $target[$parts[-1]] = $Changes[$key] }
    }
    $path = Join-Path $tmp "$Name.json"
    $json | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path -Encoding utf8NoBOM
    return $path
}

$brand = Read-ImxBrand $acme
Assert-True ($brand.LightClass -eq 'acme-light-theme' -and $brand.DarkClass -eq 'acme-dark-theme') 'classes from id'
Assert-True ($brand.DeviceTheme -eq 'brand' -and $brand.Layout.LightMasthead -eq 'brand' -and $brand.Layout.DarkMasthead -eq 'surface-with-line') 'layout and device theme defaults'
Assert-True ($brand.Colors.Warn -eq '#b45309' -and $brand.LogoHeight.Masthead -eq 52 -and $brand.LogoHeight.Login -eq 120) 'color and logo defaults'
Assert-True ((Get-ImxContrast $brand.Colors.DarkAccent '#444647') -ge 4.0 -and $brand.Colors.OnDarkFill -eq '#ffffff') 'computed dark colors'
Assert-True ((Test-Path -LiteralPath $brand.Logos.OnBrand) -and [IO.Path]::IsPathRooted($brand.Logos.OnBrand)) 'logo paths resolved from the brand.json folder'
Assert-True (Test-ImxThrows { Read-ImxBrand (New-TestBrand @{ 'id' = 'Acme Corp' } 'bad-id') }) 'id not kebab-case is rejected'
Assert-True (Test-ImxThrows { Read-ImxBrand (New-TestBrand @{ 'colors.primary' = $null } 'no-primary') }) 'missing colors.primary is rejected'
Assert-True (Test-ImxThrows { Read-ImxBrand (New-TestBrand @{ 'logos.onBrand' = 'missing.png' } 'no-logo') }) 'missing logo file is rejected'
$low = Read-ImxBrand (New-TestBrand @{ 'colors.dark' = @{ accent = '#ee424d' } } 'low-accent')
Assert-True ($low.Colors.DarkAccent -eq '#ee424d' -and ($low.Warnings -join ' ') -match 'dark.accent') 'override below threshold kept with warning'
#endregion

Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
if ($script:failures -gt 0) { Write-Host "$($script:failures) failure(s)"; exit 1 }
Write-Host 'All brand theme tests passed.'
