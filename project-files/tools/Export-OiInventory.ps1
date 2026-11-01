#Requires -Version 7.6
<#
.SYNOPSIS
Regenerates docs/inventory/*.md from the environment (READ-ONLY) and returns the customizations that no change record mentions.

.DESCRIPTION
OIM  - SELECT only, as the read-only SQL user (Sql.User in oi-env.psd1). The password comes from the environment variable
       OIM_SQL_RO_PWD (process scope first, then user scope) and is passed as a SqlCredential: never in a string,
       never printed. Every query is a constant of this script; the guard Assert-ReadOnlyQuery refuses anything
       that is not a single SELECT.
       Reports: objects with the custom prefix (scripts, tables, columns, processes, events, schedules,
       configuration parameters), change labels, sync projects, and built-in objects whose XUserUpdated is not
       a system process (= changed by a person, e.g. in the Designer). Configuration parameter VALUES are never read.
SPP  - Get-SafeguardCustomPlatform only, reusing the session saved by the spp-custom-platform workflow
       (.sg-state/sg-session.json). Skipped with a warning when the file is missing; never logs in.

Documentation check: an object is "documented" if its name appears in at least one change record
(docs/changes/<year>/CHG-*.md). Output = one object per inventory item (pipe it to Where-Object Documented -eq $false).

.EXAMPLE
pwsh -NoProfile -File tools/Export-OiInventory.ps1 | Where-Object { -not $_.Documented }
pwsh -NoProfile -File tools/Export-OiInventory.ps1 -SkipSpp
#>
[CmdletBinding()]
param(
    [string]$SqlServer,
    [string]$Database,
    [string]$SqlUser,
    [ValidatePattern('^[A-Za-z]{2,10}_$')]
    [string]$CustomPrefix = 'CCC_',
    # XUserUpdated values written by Identity Manager itself (LIKE patterns): anything else is a manual change
    [string[]]$SystemUpdaters = @('QBM[_]%', 'DBScheduler', 'ISMInitialConfig', 'sa'),
    [string]$SppSessionFile,
    [switch]$SkipSpp,
    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) { $RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
if (-not $SppSessionFile) { $SppSessionFile = Join-Path $RepoRoot '.sg-state/sg-session.json' }
$requiredSettings = @(
    if (-not $SqlServer) { 'Sql.Server' }
    if (-not $Database) { 'Sql.Database' }
    if (-not $SqlUser) { 'Sql.User' }
)
$oiEnv = & (Join-Path $PSScriptRoot 'Get-OiEnv.ps1') -RepoRoot $RepoRoot -Require $requiredSettings
if (-not $SqlServer) { $SqlServer = $oiEnv.Sql.Server }
if (-not $Database) { $Database = $oiEnv.Sql.Database }
if (-not $SqlUser) { $SqlUser = $oiEnv.Sql.User }
$TrustServerCertificate = [bool]$oiEnv.Sql.TrustServerCertificate
$InventoryDir = Join-Path $RepoRoot 'docs/inventory'
$ChangesDir = Join-Path $RepoRoot 'docs/changes'
$GeneratedBanner = '<!-- GENERATO da tools/Export-OiInventory.ps1 - non modificare a mano -->'

#region OIM (SQL, read-only)

function Assert-ReadOnlyQuery([string]$Sql) {
    $body = $Sql.Trim()
    if ($body -notmatch '^(?is)SELECT\s' -or $body.Contains(';')) {
        throw "Refused: inventory queries must be a single SELECT statement."
    }
}

function New-ReadOnlySqlConnection {
    $plain = [Environment]::GetEnvironmentVariable('OIM_SQL_RO_PWD', 'Process')
    if (-not $plain) { $plain = [Environment]::GetEnvironmentVariable('OIM_SQL_RO_PWD', 'User') }
    if (-not $plain) { throw "Environment variable OIM_SQL_RO_PWD is not set (password of $SqlUser)." }
    $secure = ConvertTo-SecureString -String $plain -AsPlainText -Force
    $secure.MakeReadOnly()
    $plain = $null
    $builder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new()
    $builder['Data Source'] = $SqlServer
    $builder['Initial Catalog'] = $Database
    $builder['ApplicationIntent'] = 'ReadOnly'
    $builder['Encrypt'] = $true
    $builder['TrustServerCertificate'] = $TrustServerCertificate   # true only for a self-signed SQL certificate (oi-env.psd1)
    $builder['Application Name'] = 'Export-OiInventory'
    $credential = [System.Data.SqlClient.SqlCredential]::new($SqlUser, $secure)
    $connection = [System.Data.SqlClient.SqlConnection]::new($builder.ConnectionString, $credential)
    $connection.Open()
    return $connection
}

function Invoke-ReadOnlyQuery {
    param([System.Data.SqlClient.SqlConnection]$Connection, [string]$Sql, [hashtable]$Parameters = @{})
    Assert-ReadOnlyQuery $Sql
    $command = $Connection.CreateCommand()
    try {
        $command.CommandText = $Sql
        foreach ($name in $Parameters.Keys) { $null = $command.Parameters.AddWithValue("@$name", $Parameters[$name]) }
        $table = [System.Data.DataTable]::new()
        $reader = $command.ExecuteReader()
        try { $table.Load($reader) } finally { $reader.Dispose() }
        return , $table
    }
    finally { $command.Dispose() }
}

function Get-SystemUpdaterFilter {
    # Column XUserUpdated compared with constant LIKE patterns passed as parameters (@su0, @su1, ...)
    $clauses = for ($i = 0; $i -lt $SystemUpdaters.Count; $i++) { "XUserUpdated LIKE @su$i" }
    $parameters = @{}
    for ($i = 0; $i -lt $SystemUpdaters.Count; $i++) { $parameters["su$i"] = $SystemUpdaters[$i] }
    return @{ Sql = "NOT (" + ($clauses -join ' OR ') + ")"; Parameters = $parameters }
}

function Get-OimCustomObject([System.Data.SqlClient.SqlConnection]$Connection) {
    # Prefix as LIKE pattern with escaped underscore: 'CCC_' -> 'CCC\_%'
    $pattern = ($CustomPrefix -replace '_', '\_') + '%'
    $sql = @"
SELECT 'Script' AS Kind, ScriptName AS Name, XUserUpdated, XDateUpdated FROM DialogScript WHERE ScriptName LIKE @p ESCAPE '\'
UNION ALL SELECT 'Tabella', TableName, XUserUpdated, XDateUpdated FROM DialogTable WHERE TableName LIKE @p ESCAPE '\'
UNION ALL SELECT 'Colonna', t.TableName + '.' + c.ColumnName, c.XUserUpdated, c.XDateUpdated
    FROM DialogColumn c JOIN DialogTable t ON t.UID_DialogTable = c.UID_DialogTable WHERE c.ColumnName LIKE @p ESCAPE '\'
UNION ALL SELECT 'Processo', Name, XUserUpdated, XDateUpdated FROM JobChain WHERE Name LIKE @p ESCAPE '\'
UNION ALL SELECT 'Evento', EventName, XUserUpdated, XDateUpdated FROM QBMEvent WHERE EventName LIKE @p ESCAPE '\'
UNION ALL SELECT 'Schedulazione', Name, XUserUpdated, XDateUpdated FROM DialogSchedule WHERE Name LIKE @p ESCAPE '\'
UNION ALL SELECT 'Parametro di configurazione', FullPath, XUserUpdated, XDateUpdated FROM DialogConfigParm
    WHERE ConfigParm LIKE @p ESCAPE '\' OR FullPath LIKE @c ESCAPE '\' OR FullPath LIKE @cc ESCAPE '\'
"@
    $prefixWord = $CustomPrefix.TrimEnd('_')
    $parameters = @{ p = $pattern; c = "$prefixWord\%"; cc = "Custom\$prefixWord%" }
    ConvertTo-InventoryItem -Table (Invoke-ReadOnlyQuery $Connection $sql $parameters) -Category 'Oggetto custom'
}

function Get-OimManualChange([System.Data.SqlClient.SqlConnection]$Connection) {
    # Built-in catalog rows last changed by a person rather than by an Identity Manager system process.
    # Only names and who/when: configuration parameter values are deliberately not selected (may hold secrets).
    $filter = Get-SystemUpdaterFilter
    $sql = @"
SELECT 'Script' AS Kind, ScriptName AS Name, XUserUpdated, XDateUpdated FROM DialogScript WHERE $($filter.Sql)
UNION ALL SELECT 'Tabella', TableName, XUserUpdated, XDateUpdated FROM DialogTable WHERE $($filter.Sql)
UNION ALL SELECT 'Colonna (template/formato)', t.TableName + '.' + c.ColumnName, c.XUserUpdated, c.XDateUpdated
    FROM DialogColumn c JOIN DialogTable t ON t.UID_DialogTable = c.UID_DialogTable WHERE $($filter.Sql -replace 'XUserUpdated', 'c.XUserUpdated')
UNION ALL SELECT 'Processo', Name, XUserUpdated, XDateUpdated FROM JobChain WHERE $($filter.Sql)
UNION ALL SELECT 'Evento', EventName, XUserUpdated, XDateUpdated FROM QBMEvent WHERE $($filter.Sql)
UNION ALL SELECT 'Schedulazione', Name, XUserUpdated, XDateUpdated FROM DialogSchedule WHERE $($filter.Sql)
UNION ALL SELECT 'Parametro di configurazione', FullPath, XUserUpdated, XDateUpdated FROM DialogConfigParm WHERE $($filter.Sql)
"@
    $items = ConvertTo-InventoryItem -Table (Invoke-ReadOnlyQuery $Connection $sql $filter.Parameters) -Category 'Built-in modificato'
    # Objects with the custom prefix are already reported by Get-OimCustomObject
    $prefixWord = $CustomPrefix.TrimEnd('_')
    @($items | Where-Object { $_.Name -notlike "*$CustomPrefix*" -and $_.Name -notlike "$prefixWord\*" -and $_.Name -notlike "Custom\$prefixWord*" })
}

function Get-OimProjectObject([System.Data.SqlClient.SqlConnection]$Connection) {
    $sql = @"
SELECT 'Change label' AS Kind, Ident_DialogTag AS Name, XUserUpdated, XDateUpdated FROM DialogTag
UNION ALL SELECT 'Progetto di sincronizzazione', DisplayName, XUserUpdated, XDateUpdated FROM DPRShell
"@
    ConvertTo-InventoryItem -Table (Invoke-ReadOnlyQuery $Connection $sql) -Category 'Progetto / change label'
}

function ConvertTo-InventoryItem([System.Data.DataTable]$Table, [string]$Category) {
    foreach ($row in $Table.Rows) {
        [PSCustomObject]@{
            Product   = 'OIM'
            Category  = $Category
            Kind      = [string]$row['Kind']
            Name      = [string]$row['Name']
            ChangedBy = [string]$row['XUserUpdated']
            ChangedOn = if ($row['XDateUpdated'] -is [DBNull]) { '' } else { ([datetime]$row['XDateUpdated']).ToString('yyyy-MM-dd HH:mm') + ' UTC' }
            InRepo    = ''
        }
    }
}

function Get-RepoDraftScript([object[]]$DbItems) {
    # Script-library sources in the repo that are not (yet) in the database = drafts not applied
    $dir = Join-Path $RepoRoot 'oim/designer/scripts'
    if (-not (Test-Path -LiteralPath $dir)) { return }
    $inDb = @($DbItems | Where-Object Kind -eq 'Script' | ForEach-Object Name)
    foreach ($file in Get-ChildItem -LiteralPath $dir -Filter "$CustomPrefix*.vb" -File) {
        if ($inDb -contains $file.BaseName) { continue }
        [PSCustomObject]@{
            Product = 'OIM'; Category = 'Solo nel repo (non applicato)'; Kind = 'Script'; Name = $file.BaseName
            ChangedBy = ''; ChangedOn = ''; InRepo = "oim/designer/scripts/$($file.Name)"
        }
    }
}

#endregion

#region SPP (safeguard-ps Get-* only)

function Get-SppCustomPlatform {
    if ($SkipSpp) { return }
    if (-not (Test-Path -LiteralPath $SppSessionFile)) {
        Write-Warning "SPP skipped: no saved session ($SppSessionFile). Log in with the spp-custom-platform workflow first."
        return
    }
    Import-Module safeguard-ps -MinimumVersion 8.4.3
    $session = Get-Content -LiteralPath $SppSessionFile -Raw | ConvertFrom-Json
    $insecure = [bool]$session.Insecure.IsPresent
    $platforms = Get-SafeguardCustomPlatform -Appliance $session.Appliance -AccessToken $session.AccessToken -Insecure:$insecure
    foreach ($platform in @($platforms)) {
        $names = $platform.PSObject.Properties.Name
        [PSCustomObject]@{
            Product   = 'SPP'
            Category  = 'Custom platform'
            Kind      = 'Custom platform'
            Name      = [string]$platform.DisplayName
            ChangedBy = if ($names -contains 'Version') { "versione $($platform.Version)" } else { '' }
            ChangedOn = ''
            InRepo    = ''
        }
    }
}

#endregion

#region Documentation check and output

function Get-ChangeRecordText {
    if (-not (Test-Path -LiteralPath $ChangesDir)) { return @() }
    foreach ($file in Get-ChildItem -LiteralPath $ChangesDir -Recurse -Filter 'CHG-*.md' -File) {
        [PSCustomObject]@{ Id = $file.BaseName; Text = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 }
    }
}

function Add-DocumentationStatus([object[]]$Items, [object[]]$Records) {
    foreach ($item in $Items) {
        # Columns are written Table.Column in the records too; match whole names, case-insensitive
        $pattern = '(?i)(?<![A-Za-z0-9_])' + [regex]::Escape($item.Name) + '(?![A-Za-z0-9_])'
        $found = @($Records | Where-Object { $_.Text -match $pattern } | ForEach-Object Id)
        $item | Select-Object *, @{ n = 'Documented'; e = { $found.Count -gt 0 } }, @{ n = 'ChangeRecords'; e = { $found -join ', ' } }
    }
}

function ConvertTo-MarkdownCell([string]$Text) {
    return ($Text -replace '\|', '\|' -replace '\r?\n', ' ')
}

function Write-InventoryPage([string]$Path, [string]$Title, [object[]]$Items, [string]$SourceNote) {
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add($GeneratedBanner)
    $lines.Add("# $Title")
    $lines.Add('')
    $lines.Add("Generato il $((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm')) UTC. $SourceNote")
    $lines.Add('')
    if (-not $Items) {
        $lines.Add('Nessun oggetto trovato.')
    }
    else {
        $lines.Add('| Categoria | Tipo | Nome | Ultima modifica (utente) | Ultima modifica (data) | Nel repo | Documentato in |')
        $lines.Add('|---|---|---|---|---|---|---|')
        foreach ($i in $Items | Sort-Object Category, Kind, Name) {
            $doc = if ($i.Documented) { $i.ChangeRecords } else { '**non documentato**' }
            $cells = @($i.Category, $i.Kind, "``$($i.Name)``", $i.ChangedBy, $i.ChangedOn, $i.InRepo, $doc) | ForEach-Object { ConvertTo-MarkdownCell $_ }
            $lines.Add('| ' + ($cells -join ' | ') + ' |')
        }
    }
    Set-Content -LiteralPath $Path -Value $lines -Encoding utf8NoBOM
}

#endregion

$records = @(Get-ChangeRecordText)
$connection = New-ReadOnlySqlConnection
try {
    $dbItems = @(Get-OimCustomObject $connection) + @(Get-OimManualChange $connection) + @(Get-OimProjectObject $connection)
}
finally { $connection.Dispose() }
$oimItems = @(Add-DocumentationStatus -Items ($dbItems + @(Get-RepoDraftScript $dbItems)) -Records $records)
$sppItems = @(Add-DocumentationStatus -Items @(Get-SppCustomPlatform) -Records $records)

$null = New-Item -ItemType Directory -Force -Path $InventoryDir
Write-InventoryPage -Path (Join-Path $InventoryDir 'oim-custom-objects.md') -Title 'Inventario OIM — oggetti custom e modifiche' `
    -Items $oimItems -SourceNote "Fonte: database $Database su $SqlServer, sola lettura (utente $SqlUser). Prefisso custom: ``$CustomPrefix``."
if (-not $SkipSpp -and (Test-Path -LiteralPath $SppSessionFile)) {
    Write-InventoryPage -Path (Join-Path $InventoryDir 'spp-custom-objects.md') -Title 'Inventario SPP — custom platform' `
        -Items $sppItems -SourceNote 'Fonte: Get-SafeguardCustomPlatform (sola lettura).'
}

$oimItems + $sppItems
