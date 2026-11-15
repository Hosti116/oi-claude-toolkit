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
        if ($parts.Count -gt 1) {
            foreach ($p in $parts[0..($parts.Count - 2)]) { if (-not $target.ContainsKey($p)) { $target[$p] = @{} }; $target = $target[$p] }
        }
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
$explicit = @{ '50' = '#fde5e7'; '100' = '#fabcc1'; '200' = '#f69097'; '300' = '#f1646d'; '400' = '#ee424d'; '500' = '#eb212e'; '600' = '#d81c28'; '700' = '#c11723'; '800' = '#a9131d'; '900' = '#861016' }
$fixed = Read-ImxBrand (New-TestBrand @{ 'colors.primary' = '#eb212e'; 'colors.palette' = $explicit; 'colors.paletteContrast' = @{ '300' = 'dark' } } 'explicit-palette')
Assert-True ($fixed.Colors.Palette['700'] -eq '#c11723' -and $fixed.Colors.PaletteContrast['300'] -eq 'dark' -and $fixed.Colors.PaletteContrast['400'] -eq 'light') 'explicit palette and contrast overrides'
Assert-True (Test-ImxThrows { Read-ImxBrand (New-TestBrand @{ 'colors.palette' = @{ '500' = '#eb212e' } } 'partial-palette') }) 'partial palette is rejected'
Assert-True ($brand.Colors.NeutralPalette['800'] -eq '#2e3236' -and $brand.Colors.WarnPalette['300'] -eq '#ffbd66') 'default neutral and warn palettes'
Assert-True (Test-ImxThrows { Read-ImxBrand (New-TestBrand @{ 'layout' = @{ lightMasthead = 'light' } } 'light-without-logo') }) 'light masthead requires logos.onLight'
$pale = Read-ImxBrand (New-TestBrand @{ 'colors.primary' = '#fff3b0' } 'pale-primary')
Assert-True ((($pale.Warnings -join ' ') -match 'dark.fill') -and (Get-ImxContrast $pale.Colors.OnDarkFill $pale.Colors.DarkFill) -ge 4.5) 'computed dark fill below 7:1 warns and keeps readable fill text'
#endregion

#region Theme generator (Task 3)
$gen = Join-Path $kit 'scripts/New-ImxBrandTheme.ps1'
function Invoke-Gen([string] $Brand, [string] $Imx, [string] $Cust) {
    $args = @{ Brand = $Brand; ImxWebDir = $Imx }
    if ($Cust) { $args.CustomizationsPath = $Cust }
    return (& $gen @args | Select-Object -Last 1 | ConvertFrom-Json)
}
$brandDir = Join-Path $tmp 'brand/acme'
New-Item -ItemType Directory -Force $brandDir | Out-Null
Copy-Item (Join-Path $kit 'examples/acme/*') $brandDir
$genBrand = Join-Path $brandDir 'brand.json'
(Get-Content $genBrand -Raw).Replace('"$schema": "../../brand.schema.json",', '') | Set-Content $genBrand -Encoding utf8NoBOM
$tmpImx = Join-Path $tmp 'imxweb'
New-Item -ItemType Directory -Force (Join-Path $tmpImx 'custom-theme') | Out-Null
$out = Invoke-Gen $genBrand $tmpImx
$themeDir = Join-Path $tmpImx 'custom-theme/acme'
Assert-True ($out.status -eq 'ok' -and (Test-Path (Join-Path $themeDir 'acme-dark.scss')) -and (Test-Path (Join-Path $themeDir 'acme-light.scss'))) 'theme files generated'
Assert-True ((Get-Content (Join-Path $themeDir 'acme-dark.scss') -TotalCount 1) -match 'GENERATED by oi-toolkit') 'generated header'
$palettePartial = Get-Content (Join-Path $themeDir '_brand-palette.scss') -Raw
Assert-True ($palettePartial -match '\$light-class: acme-light-theme' -and $palettePartial -match '\$dark-fill: #') 'palette partial carries classes and dark colors'
Assert-True ((Get-Content (Join-Path $themeDir '_brand-logos.scss') -Raw) -match "logo-on-brand: url\('data:image/png;base64,") 'logos embedded as data URIs'
$config = Get-Content (Join-Path $brandDir 'imx-theme-config.json') -Raw | ConvertFrom-Json
Assert-True ($config.Themes.Count -eq 2 -and $config.Themes[1].Urls[0] -eq '../qer-app-portal/acme/acme-dark-theme.css' -and $config.Themes[0].DisplayName -eq 'Acme chiaro') 'imx-theme-config.json'
Assert-True ($out.manualChecks -contains 'CompanyLogoUrl empty') 'manual check reported'
Assert-True (@((Invoke-Gen $genBrand $tmpImx).written).Count -eq 0) 'idempotent'
$crlfFile = Join-Path $themeDir 'acme-light.scss'
[IO.File]::WriteAllText($crlfFile, ([IO.File]::ReadAllText($crlfFile) -replace "`r?`n", "`r`n"))
$afterCheckout = Invoke-Gen $genBrand $tmpImx
Assert-True ($afterCheckout.status -eq 'ok' -and @($afterCheckout.blocked).Count -eq 0) 'CRLF checkout of a generated file is not a hand edit'
Add-Content (Join-Path $themeDir 'acme-dark.scss') '// local edit'
$blocked = Invoke-Gen $genBrand $tmpImx
Assert-True ($blocked.status -eq 'blocked' -and ($blocked.blocked -join ' ') -match 'acme-dark.scss') 'stops on edited generated file'
$tmpImx2 = Join-Path $tmp 'imxweb2'
New-Item -ItemType Directory -Force (Join-Path $tmpImx2 'custom-theme') | Out-Null
$cust = Join-Path $tmp 'CUSTOMIZATIONS.md'
Set-Content $cust "# x`n<!-- oi-brand-theme:acme:begin -->`nold`n<!-- oi-brand-theme:acme:end -->`nkeep" -Encoding utf8NoBOM
Invoke-Gen $genBrand $tmpImx2 $cust | Out-Null
$custText = Get-Content $cust -Raw
Assert-True ($custText -match 'acme-dark-theme' -and $custText -match 'keep' -and $custText -notmatch 'old') 'only the generated block is replaced'
#endregion

#region Plugin installer (Task 6)
$install = Join-Path $kit 'scripts/Install-ImxBrandPlugin.ps1'
function New-TestCcc([string] $Root, [string] $InitService) {
    $lib = Join-Path $Root 'projects/ccc/src/lib'
    New-Item -ItemType Directory -Force $lib | Out-Null
    Set-Content (Join-Path $lib 'init.service.ts') $InitService -Encoding utf8NoBOM
    return $lib
}
$plainInit = @'
import { Injectable } from '@angular/core';
import { ExtService } from 'qbm';

@Injectable({
  providedIn: 'root',
})
export class InitService {
  constructor(private readonly extService: ExtService) {}

  public onInit(): void {
    this.extService.register('Dashboard-SmallTiles', { instance: SomeTile });
  }
}
'@
$imxA = Join-Path $tmp 'install-a'
$libA = New-TestCcc $imxA $plainInit
$res = & $install -ImxWebDir $imxA | Select-Object -Last 1 | ConvertFrom-Json
$initA = Get-Content (Join-Path $libA 'init.service.ts') -Raw
Assert-True ($res.status -eq 'ok' -and (Test-Path (Join-Path $libA 'brand-theme/brand-theme.service.ts'))) 'plugin files installed'
Assert-True ($initA -match "import \{ BrandThemeService \} from './brand-theme/brand-theme.service';" -and $initA -match 'private readonly brandTheme: BrandThemeService' -and $initA -match 'this\.brandTheme\.start\(\);') 'InitService registration inserted'
Assert-True (($res.actions -join ' ') -match 'init.service.spec.ts') 'spec update reported'
& $install -ImxWebDir $imxA | Out-Null
Assert-True (([regex]::Matches((Get-Content (Join-Path $libA 'init.service.ts') -Raw), 'brandTheme\.start\(\)')).Count -eq 1) 'registration inserted once on reruns'
Add-Content (Join-Path $libA 'brand-theme/brand-theme.service.ts') '// local edit'
Assert-True ((& $install -ImxWebDir $imxA | Select-Object -Last 1 | ConvertFrom-Json).status -eq 'blocked') 'stops on edited template file'

$legacyInit = $plainInit.Replace('constructor(private readonly extService: ExtService) {}', "constructor(`n    private readonly extService: ExtService,`n    private readonly legacyTheme: LegacyThemeService,`n  ) {}").Replace("{ instance: SomeTile });", "{ instance: SomeTile });`n    this.legacyTheme.start();")
$imxB = Join-Path $tmp 'install-b'
New-TestCcc $imxB $legacyInit | Out-Null
$resB = & $install -ImxWebDir $imxB | Select-Object -Last 1 | ConvertFrom-Json
Assert-True ($resB.status -eq 'ok' -and ($resB.actions -join ' ') -match 'LegacyThemeService') 'legacy theme service reported for manual removal'

$imxC = Join-Path $tmp 'install-c'
New-Item -ItemType Directory -Force (Join-Path $imxC 'projects') | Out-Null
$resC = & $install -ImxWebDir $imxC | Select-Object -Last 1 | ConvertFrom-Json
Assert-True ($resC.status -eq 'needs-ccc' -and -not (Test-Path (Join-Path $imxC 'projects/ccc'))) 'no ccc: needs-ccc, nothing written'

$bodyInit = $plainInit.Replace('constructor(private readonly extService: ExtService) {}', 'constructor(private readonly extService: ExtService) { this.ready = true; }').Replace('  public onInit(): void {', "  private ready = false;`n`n  public tryLoad(): void {`n    try { this.ready = true; } catch (e) {}`n  }`n`n  public onInit(): void {")
$imxD = Join-Path $tmp 'install-d'
$libD = New-TestCcc $imxD $bodyInit
$beforeD = Get-Content (Join-Path $libD 'init.service.ts') -Raw
$resD = & $install -ImxWebDir $imxD | Select-Object -Last 1 | ConvertFrom-Json
Assert-True ($resD.status -eq 'blocked' -and (Get-Content (Join-Path $libD 'init.service.ts') -Raw) -eq $beforeD) 'constructor with a body: stops, InitService untouched'
#endregion

#region Theme build (Task 4, integration)
if ($ImxWebDir) {
    $build = Join-Path $kit 'scripts/Build-ImxBrandTheme.ps1'
    $kitBrandDir = Join-Path $tmp 'brand/kittest'
    New-Item -ItemType Directory -Force $kitBrandDir | Out-Null
    Copy-Item (Join-Path $kit 'examples/acme/*.png') $kitBrandDir
    $kitBrand = New-TestBrand @{ 'id' = 'kittest' } 'kittest-brand'
    Move-Item $kitBrand (Join-Path $kitBrandDir 'brand.json') -Force
    (Get-Content (Join-Path $kitBrandDir 'brand.json') -Raw).Replace('"$schema": "../../brand.schema.json",', '') | Set-Content (Join-Path $kitBrandDir 'brand.json') -Encoding utf8NoBOM
    $kitThemeDir = Join-Path $ImxWebDir 'custom-theme/kittest'
    $buildOut = Join-Path $tmp 'build'
    try {
        Assert-True ((Invoke-Gen (Join-Path $kitBrandDir 'brand.json') $ImxWebDir).status -eq 'ok') 'build fixture generated'
        $res = & $build -Id kittest -ImxWebDir $ImxWebDir -OutDir $buildOut | Select-Object -Last 1 | ConvertFrom-Json
        Assert-True ($res.status -eq 'ok' -and $res.checks.scopeDiffs -eq 0 -and $res.checks.fontFaces -eq 0) 'build ok, scoped, no @font-face'
        Assert-True ((Test-Path (Join-Path $buildOut 'kittest/kittest-dark-theme.css')) -and @($res.checks.contractMissing).Count -eq 0) 'css written with the full contract'
        Push-Location $tmp
        try {
            $relative = & $build -Id kittest -ImxWebDir $ImxWebDir -OutDir 'build-relative' | Select-Object -Last 1 | ConvertFrom-Json
            Assert-True ($relative.status -eq 'ok' -and (Test-Path (Join-Path $tmp 'build-relative/kittest/kittest-light-theme.css'))) 'relative OutDir resolved from the current folder'
        } finally { Pop-Location }
        $darkCss = Get-Content (Join-Path $buildOut 'kittest/kittest-dark-theme.css') -Raw
        Assert-True ($darkCss -match '--ccc-brand-dark-fill:\s*#[0-9a-f]{6}[;}]' -and $darkCss -match '--ccc-brand-light-class:\s*kittest-light-theme[;}]') 'contract values in the css (#rrggbb, class names)'
        # Light primary with the brand-colored dark masthead: text on the masthead and the login card header readable.
        $sunDir = Join-Path $tmp 'brand/kitsun'
        New-Item -ItemType Directory -Force $sunDir | Out-Null
        Copy-Item (Join-Path $kit 'examples/acme/*.png') $sunDir
        $sunBrand = New-TestBrand @{ 'id' = 'kitsun'; 'colors.primary' = '#ffd200'; 'layout' = @{ darkMasthead = 'brand' } } 'kitsun-brand'
        Move-Item $sunBrand (Join-Path $sunDir 'brand.json') -Force
        (Get-Content (Join-Path $sunDir 'brand.json') -Raw).Replace('"$schema": "../../brand.schema.json",', '') | Set-Content (Join-Path $sunDir 'brand.json') -Encoding utf8NoBOM
        try {
            $null = Invoke-Gen (Join-Path $sunDir 'brand.json') $ImxWebDir
            $sunRes = & $build -Id kitsun -ImxWebDir $ImxWebDir -OutDir $buildOut | Select-Object -Last 1 | ConvertFrom-Json
            $colorsOf = { param($css, $selector)
                @(node -e "const p=require(require('module').createRequire(process.argv[3]+'/package.json').resolve('postcss'));p.parse(require('fs').readFileSync(process.argv[1],'utf8')).walkRules(r=>{if(r.selectors.some(x=>x.trim().endsWith(process.argv[2])))r.walkDecls('color',d=>console.log(d.value))})" $css $selector $ImxWebDir) }
            $mastheadText = @(& $colorsOf (Join-Path $buildOut 'kitsun/kitsun-dark-theme.css') 'header.eui-masthead .mat-toolbar.mat-primary')
            $headerText = @(& $colorsOf (Join-Path $buildOut 'kitsun/kitsun-light-theme.css') '.imx-loginPage .imx-card-header')
            $sun = Read-ImxBrand (Join-Path $sunDir 'brand.json')
            Assert-True ($sunRes.status -eq 'ok' -and $mastheadText.Count -gt 0 -and @($mastheadText | Where-Object { $_ -match '^#([0-9a-f]{3}){1,2}$' -and (Get-ImxContrast ($_ -replace '^#(.)(.)(.)$', '#$1$1$2$2$3$3') $sun.Colors.Primary) -ge 4.5 }).Count -eq $mastheadText.Count) 'light primary: dark brand masthead text readable'
            Assert-True ($headerText.Count -gt 0 -and @($headerText | Where-Object { $_ -match 'white|#fff' }).Count -eq 0) 'light primary: login card header text not white'
        } finally { Remove-Item -LiteralPath (Join-Path $ImxWebDir 'custom-theme/kitsun') -Recurse -Force -ErrorAction SilentlyContinue }
        # Deploy package (Task 7): fake portal build, with and without the plugin in the bundle.
        $package = Join-Path $kit 'scripts/New-ImxBrandDeployPackage.ps1'
        $fakeDist = Join-Path $tmp 'dist-portal'
        New-Item -ItemType Directory -Force $fakeDist | Out-Null
        Set-Content (Join-Path $fakeDist 'index.html') '<script src="main-TEST.js"></script>'
        Set-Content (Join-Path $fakeDist 'chunk-TEST.js') 'const P="--ccc-brand-";function r(s,n){return s.getPropertyValue(P+n)}r(x,"light-class")'
        $emptyBin = Join-Path $tmp 'bin-imxweb'
        New-Item -ItemType Directory -Force $emptyBin | Out-Null
        $pkgArgs = @{ Id = 'kittest'; ImxWebDir = $ImxWebDir; BrandDir = $kitBrandDir; StagingRoot = (Join-Path $tmp 'staging'); ApiServerImxWeb = $emptyBin; PortalDistDir = $fakeDist; SkipTests = $true; SkipPortalBuild = $true }
        $pkg = & $package @pkgArgs | Select-Object -Last 1 | ConvertFrom-Json
        $paths = @($pkg.files | ForEach-Object { $_.path })
        Assert-True ($pkg.status -eq 'ok' -and $paths.Count -eq 3 -and ($paths -contains 'custom\Html_qer-app-portal.zip') -and ($paths -contains 'Html_kittest-light-theme\imx-theme-config.json')) 'package with the three files'
        Assert-True (@($pkg.files | Where-Object { -not $_.importNeeded }).Count -eq 0) 'everything to import against an empty bin'
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [IO.Compression.ZipFile]::OpenRead((Join-Path $pkg.staging 'custom\Html_qer-app-portal.zip'))
        $entries = @($zip.Entries | ForEach-Object { $_.FullName }); $zip.Dispose()
        Assert-True (($entries -contains 'kittest/kittest-light-theme.css') -and ($entries -contains 'index.html')) 'theme css inside the portal package'
        Copy-Item (Join-Path $pkg.staging '*') $emptyBin -Recurse
        $again = & $package @pkgArgs | Select-Object -Last 1 | ConvertFrom-Json
        Assert-True ((@($again.files | Where-Object { $_.path -ne 'custom\Html_qer-app-portal.zip' -and $_.importNeeded }).Count) -eq 0) 'unchanged config files need no import'
        Set-Content (Join-Path $fakeDist 'chunk-TEST.js') 'no plugin here'
        Assert-True ((& $package @pkgArgs | Select-Object -Last 1 | ConvertFrom-Json).status -eq 'blocked') 'portal bundle without BrandThemeService blocks the package'

        Add-Content (Join-Path $kitThemeDir 'kittest-dark.scss') 'html { --mat-app-text-color: red; }'
        $bad = & $build -Id kittest -ImxWebDir $ImxWebDir -OutDir $buildOut | Select-Object -Last 1 | ConvertFrom-Json
        Assert-True ($bad.status -eq 'blocked' -and $bad.checks.scopeDiffs -ge 1) 'unscoped declaration blocks the build'
    } finally {
        Remove-Item -LiteralPath $kitThemeDir -Recurse -Force -ErrorAction SilentlyContinue
    }
} else {
    Write-Host 'skip theme build tests (no -ImxWebDir)'
}
#endregion

Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
if ($script:failures -gt 0) { Write-Host "$($script:failures) failure(s)"; exit 1 }
Write-Host 'All brand theme tests passed.'
