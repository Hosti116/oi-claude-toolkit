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

Export-ModuleMember -Function ConvertTo-ImxRgb, Get-ImxContrast, New-ImxBrandPalette, Select-ImxDarkAccent, Select-ImxDarkFill, Get-ImxOnColor
