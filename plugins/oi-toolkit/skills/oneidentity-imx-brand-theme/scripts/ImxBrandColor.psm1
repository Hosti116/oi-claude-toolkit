#Requires -Version 7.6
# Color math of the Web Portal brand theme kit: palettes, WCAG contrast and the dark theme choices
# (rules in ../SKILL.md, "Regole colore").
Set-StrictMode -Version Latest

# Backgrounds of the dark UI where the accent must stay readable (ElementalUI dark theme).
$script:DarkCard = '#444647'
$script:DarkPage = '#1e1e1e'
$script:MinAccentOnCard = 4.0
$script:MinAccentOnPage = 4.5
$script:MinWhiteOnFill = 7.0
$script:MinLargeTextAa = 3.0

# Share of the primary in the tints (mixed with white) and share of black in the shades.
$script:Tints = [ordered]@{ '50' = 0.10; '100' = 0.25; '200' = 0.45; '300' = 0.65; '400' = 0.82 }
$script:Shades = [ordered]@{ '600' = 0.08; '700' = 0.18; '800' = 0.30; '900' = 0.45 }

function ConvertTo-ImxRgb {
    [OutputType([int[]])]
    param([Parameter(Mandatory)][string] $Hex)
    if ($Hex -notmatch '^#[0-9a-fA-F]{6}$') { throw "Not a #rrggbb color: '$Hex'." }
    return @(1, 3, 5 | ForEach-Object { [Convert]::ToInt32($Hex.Substring($_, 2), 16) })
}

function ConvertTo-ImxHex([double[]] $Rgb) {
    return '#' + (($Rgb | ForEach-Object { '{0:x2}' -f [int][Math]::Round([Math]::Min(255, [Math]::Max(0, $_))) }) -join '')
}

function Get-ImxLuminance([string] $Hex) {
    $linear = ConvertTo-ImxRgb $Hex | ForEach-Object {
        $c = $_ / 255
        if ($c -le 0.03928) { $c / 12.92 } else { [Math]::Pow(($c + 0.055) / 1.055, 2.4) }
    }
    return 0.2126 * $linear[0] + 0.7152 * $linear[1] + 0.0722 * $linear[2]
}

function Get-ImxContrast {
    [OutputType([double])]
    param([Parameter(Mandatory)][string] $Fg, [Parameter(Mandatory)][string] $Bg)
    $a = Get-ImxLuminance $Fg
    $b = Get-ImxLuminance $Bg
    return ([Math]::Max($a, $b) + 0.05) / ([Math]::Min($a, $b) + 0.05)
}

function Get-ImxMix([string] $Color, [string] $With, [double] $ShareOfWith) {
    $c = ConvertTo-ImxRgb $Color
    $w = ConvertTo-ImxRgb $With
    return ConvertTo-ImxHex @(0..2 | ForEach-Object { $c[$_] * (1 - $ShareOfWith) + $w[$_] * $ShareOfWith })
}

function New-ImxBrandPalette {
    <# Hues 50..900 of a primary color; 500 is the primary itself. #>
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param([Parameter(Mandatory)][string] $Primary)
    $primaryHex = (ConvertTo-ImxHex (ConvertTo-ImxRgb $Primary))
    $palette = [ordered]@{}
    foreach ($hue in $script:Tints.Keys) { $palette[$hue] = Get-ImxMix $primaryHex '#ffffff' (1 - $script:Tints[$hue]) }
    $palette['500'] = $primaryHex
    foreach ($hue in $script:Shades.Keys) { $palette[$hue] = Get-ImxMix $primaryHex '#000000' $script:Shades[$hue] }
    return $palette
}

function Select-ImxDarkAccent {
    <# Most saturated tint readable on dark cards and pages; the lightest tint when none qualifies. #>
    [OutputType([string])]
    param([Parameter(Mandatory)] $Palette)
    foreach ($hue in '400', '300', '200', '100') {
        $color = $Palette[$hue]
        if ((Get-ImxContrast $color $script:DarkCard) -ge $script:MinAccentOnCard -and
            (Get-ImxContrast $color $script:DarkPage) -ge $script:MinAccentOnPage) { return $color }
    }
    return $Palette['50']
}

function Select-ImxDarkFill {
    <# Lightest hue from the primary down that carries white text at 7:1; the darkest hue when none qualifies. #>
    [OutputType([string])]
    param([Parameter(Mandatory)] $Palette, [Parameter(Mandatory)][string] $Primary)
    foreach ($hue in '500', '600', '700', '800', '900') {
        if ((Get-ImxContrast '#ffffff' $Palette[$hue]) -ge $script:MinWhiteOnFill) { return $Palette[$hue] }
    }
    return $Palette['900']
}

function Get-ImxOnColor {
    <# Text/logo color on a brand surface (masthead, buttons: large text): white when it reaches AA for large text
       (3:1), as brand colors usually carry white; otherwise the one of white and black with the higher contrast. #>
    [OutputType([string])]
    param([Parameter(Mandatory)][string] $Bg)
    $white = Get-ImxContrast '#ffffff' $Bg
    if ($white -ge $script:MinLargeTextAa -or $white -ge (Get-ImxContrast '#000000' $Bg)) { return '#ffffff' }
    return '#000000'
}

#region brand.json
$script:SchemaPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'brand.schema.json'
$script:Defaults = @{ Warn = '#b45309'; Neutral = '#5f666d'; MastheadLogo = 52; LoginLogo = 120 }

function Get-ImxValue($Object, [string] $Name, $Default) {
    if ($null -ne $Object -and $Object.ContainsKey($Name) -and $null -ne $Object[$Name]) { return $Object[$Name] }
    return $Default
}

function Resolve-ImxLogo([string] $BaseDir, [string] $Relative, [string] $Field) {
    if (-not $Relative) { return $null }
    $path = [IO.Path]::GetFullPath((Join-Path $BaseDir $Relative))
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "brand.json: logos.$Field not found: $path" }
    return $path
}

function Read-ImxBrand {
    <# Validates brand.json against brand.schema.json and resolves defaults, logo paths and dark colors. #>
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][string] $Path)
    $full = (Resolve-Path -LiteralPath $Path).Path
    $raw = Get-Content -LiteralPath $full -Raw
    $errors = $null
    if (-not (Test-Json -Json $raw -SchemaFile $script:SchemaPath -ErrorVariable errors -ErrorAction SilentlyContinue)) {
        throw "brand.json is not valid ($full): $(($errors | ForEach-Object { $_.Exception.Message }) -join '; ')"
    }
    $json = $raw | ConvertFrom-Json -AsHashtable
    $baseDir = Split-Path -Parent $full
    $colors = $json.colors
    $dark = Get-ImxValue $colors 'dark' @{}
    $primary = (ConvertTo-ImxHex (ConvertTo-ImxRgb $colors.primary))
    $palette = New-ImxBrandPalette $primary
    $warnings = [Collections.Generic.List[string]]::new()

    $accent = Get-ImxValue $dark 'accent' $null
    if ($accent) {
        $accent = $accent.ToLowerInvariant()
        if ((Get-ImxContrast $accent $script:DarkCard) -lt $script:MinAccentOnCard -or (Get-ImxContrast $accent $script:DarkPage) -lt $script:MinAccentOnPage) {
            $warnings.Add("colors.dark.accent $accent is below $($script:MinAccentOnCard):1 on cards or $($script:MinAccentOnPage):1 on the page.")
        }
    } else { $accent = Select-ImxDarkAccent $palette }
    $fill = Get-ImxValue $dark 'fill' $null
    if ($fill) {
        $fill = $fill.ToLowerInvariant()
        if ((Get-ImxContrast '#ffffff' $fill) -lt $script:MinWhiteOnFill) { $warnings.Add("colors.dark.fill $fill carries white text below $($script:MinWhiteOnFill):1.") }
    } else { $fill = Select-ImxDarkFill $palette $primary }

    $logos = $json.logos
    $layout = Get-ImxValue $json 'layout' @{}
    $heights = Get-ImxValue $json 'logoHeight' @{}
    return [pscustomobject]@{
        Id          = $json.id
        LightClass  = "$($json.id)-light-theme"
        DarkClass   = "$($json.id)-dark-theme"
        DisplayName = [pscustomobject]@{ Light = $json.displayName.light; Dark = $json.displayName.dark }
        Colors      = [pscustomobject]@{
            Primary    = $primary
            Palette    = $palette
            Warn       = (Get-ImxValue $colors 'warn' $script:Defaults.Warn).ToLowerInvariant()
            Neutral    = (Get-ImxValue $colors 'accentNeutral' $script:Defaults.Neutral).ToLowerInvariant()
            DarkAccent = $accent
            DarkFill   = $fill
            OnDarkFill = '#ffffff'
            OnPrimary  = Get-ImxOnColor $primary
        }
        Logos       = [pscustomobject]@{
            OnBrand = Resolve-ImxLogo $baseDir $logos.onBrand 'onBrand'
            OnDark  = Resolve-ImxLogo $baseDir $logos.onDark 'onDark'
            OnLight = Resolve-ImxLogo $baseDir (Get-ImxValue $logos 'onLight' $null) 'onLight'
        }
        LogoHeight  = [pscustomobject]@{ Masthead = Get-ImxValue $heights 'masthead' $script:Defaults.MastheadLogo; Login = Get-ImxValue $heights 'login' $script:Defaults.LoginLogo }
        Layout      = [pscustomobject]@{ LightMasthead = Get-ImxValue $layout 'lightMasthead' 'brand'; DarkMasthead = Get-ImxValue $layout 'darkMasthead' 'surface-with-line' }
        DeviceTheme = Get-ImxValue $json 'deviceTheme' 'brand'
        Notes       = @(Get-ImxValue $json 'notes' @())
        Warnings    = $warnings.ToArray()
        SourceDir   = $baseDir
    }
}
#endregion

Export-ModuleMember -Function ConvertTo-ImxRgb, ConvertTo-ImxHex, Get-ImxContrast, New-ImxBrandPalette, Select-ImxDarkAccent, Select-ImxDarkFill, Get-ImxOnColor, Read-ImxBrand
