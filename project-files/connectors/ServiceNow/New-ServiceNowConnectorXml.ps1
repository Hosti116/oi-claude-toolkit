<#
    Generates ServiceNowConnector.xml (One Identity Manager PowerShell connector definition) from the real
    ServiceNow schema, including custom u_ fields. Runs on Windows PowerShell 5.1 and PowerShell 7.

    Online (reads sys_db_object + sys_dictionary for the tables missing from the schema JSON, saves it, then builds
    the XML; -Refresh re-reads every table, e.g. after new fields were added in ServiceNow). -InstanceUrl and
    -Username are mandatory: there is no default instance.
        .\New-ServiceNowConnectorXml.ps1 -InstanceUrl <instance> -Username <integration user>
    Offline (rebuilds the XML from the saved per-table schema JSON, no instance needed; use it after changing
    -Tables / class filters, as long as no new table is involved):
        .\New-ServiceNowConnectorXml.ps1 -Offline

    -Tables maps each class to a table, either as a plain table name or as
    @{ Table = "..."; Query = "<encoded query applied to the listing>"; Defaults = @{ field = value } }.
    Several classes can share one table with different filters; Defaults are applied on Insert when the field is
    not passed, so new records fall inside the class filter. Example on the standard flag core_company.vendor
    (ISEMPTY: a flag may never have been set on older records):
        $t = [ordered]@{
            Vendor       = @{ Table = "core_company"; Query = "vendor=true"; Defaults = @{ vendor = $true } }
            OtherCompany = @{ Table = "core_company"; Query = "vendor=false^ORvendorISEMPTY"; Defaults = @{ vendor = $false } }
        }
        .\New-ServiceNowConnectorXml.ps1 -Offline -Tables $t

    The user needs read access to the target tables; reading sys_dictionary/sys_db_object (e.g. admin or
    personalize_dictionary) gives typed fields. Without it, fields are taken from one sample record, all as String.

    Known OIM schema restrictions (verified in the Synchronization Editor wizard of an earlier project, OIM 9.2;
    to be re-confirmed on 10.0): no Description attribute on Class/Property, no IsAutofill attribute.

    Two layouts:
    - default: all code inline as CustomCommands (ServiceNowConnector.xml). Connect and read verified in the wizard
      of the same earlier project (OIM 9.2).
    - -UseModule: the generic logic (HTTP, retry, paging, type conversion, connect) goes into ServiceNowConnector.psm1,
      the XML (ServiceNowConnector.Module.xml) keeps only the per-class commands plus a Connect-OneIMSnow that
      imports the module from the ModuleLocation connection parameter. Every command referenced by the XML is still
      a CustomCommand: the plain README layout (Import-Module item + module commands in PredefinedCommands) failed in
      the wizard with "Connect-OneIMSnow is not recognized".
        .\New-ServiceNowConnectorXml.ps1 -Offline -UseModule
#>
[CmdletBinding(DefaultParameterSetName = "Online")]
param(
    # ServiceNow instance: name, host or full URL. Mandatory online; never stored in the generated files.
    [Parameter(Mandatory = $true, ParameterSetName = "Online")][ValidateNotNullOrEmpty()][string]$InstanceUrl,
    [Parameter(Mandatory = $true, ParameterSetName = "Online")][ValidateNotNullOrEmpty()][string]$Username,
    [Parameter(ParameterSetName = "Online")][SecureString]$Password,
    # Class name -> ServiceNow table (or @{ Table; Query; Defaults }, see above). Defaults use standard tables only.
    [System.Collections.Specialized.OrderedDictionary]$Tables = ([ordered]@{
        Company      = "core_company"
        BusinessUnit = "business_unit"
        Department   = "cmn_department"
        CostCenter   = "cmn_cost_center"
        Location     = "cmn_location"
        Building     = "cmn_building"
        User         = "sys_user"
        # identity: groups, memberships, roles
        Group        = "sys_user_group"
        GroupMember  = "sys_user_grmember"
        Role         = "sys_user_role"
        UserRole     = "sys_user_has_role"
        # other tables referenced by the classes above (tables missing on the instance are skipped)
        Schedule             = "cmn_schedule"
        LdapServer           = "ldap_server_config"
        LifeCycleStage       = "life_cycle_stage"
        LifeCycleStageStatus = "life_cycle_stage_status"
        HrIntegrFwSource     = "sn_hr_integr_fw_source"
        HrIntegrationSource  = "sn_hr_integrations_source"
        Perspective          = "sys_perspective"
        PhoneTerritory       = "sys_phone_territory"
        UiTheme              = "sys_ui_theme"
        VendorType           = "vendor_type"
    }),
    [string]$SchemaFile = (Join-Path $PSScriptRoot "ServiceNowSchema.json"),
    [string]$OutputXml,
    [Parameter(Mandatory = $true, ParameterSetName = "Offline")][switch]$Offline,
    # online: re-read every table instead of only the ones missing from the schema JSON
    [Parameter(ParameterSetName = "Online")][switch]$Refresh,
    # generic logic in an external module (see above)
    [switch]$UseModule,
    [string]$OutputModule = (Join-Path $PSScriptRoot "ServiceNowConnector.psm1")
)

$ErrorActionPreference = "Stop"
if (-not $OutputXml)
{
    if ($UseModule) { $OutputXml = Join-Path $PSScriptRoot "ServiceNowConnector.Module.xml" }
    else { $OutputXml = Join-Path $PSScriptRoot "ServiceNowConnector.xml" }
}

# ServiceNow internal types that are not plain columns of the Table API response
$SkippedTypes = @("collection", "journal", "journal_input", "journal_list", "password", "password2", "user_image", "image", "video")
# Field names that cannot be PowerShell parameter names (automatic variables)
$ReservedNames = @("input", "args", "host", "this", "error", "pid", "home", "pwd", "matches", "event", "sender",
                   "true", "false", "null", "psitem", "myinvocation", "psboundparameters", "executioncontext", "ofs")

#region Generic CustomCommands (emitted into the XML as-is and also used by this script)

$Generic = [ordered]@{}

$Generic["ConvertTo-OneIMSnowPlainText"] = @'
                param([Parameter(Mandatory=$true)][SecureString]$SecureString)

                # ConvertFrom-SecureString -AsPlainText is PowerShell 7 only; BSTR decoding works on 5.1 too
                $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
                try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
                finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
'@

$Generic["Invoke-OneIMSnowRequest"] = @'
                param(
                    [Parameter(Mandatory=$true)][string]$Method,
                    [Parameter(Mandatory=$true)][string]$Uri,
                    [object]$Body,
                    [int]$MaxRetries = 3
                )

                if (-not (Test-Path variable:global:OneIMSnowSession) -or $null -eq $global:OneIMSnowSession)
                {
                    throw "ServiceNow session not initialized. Run Connect-OneIMSnow first."
                }

                $params = @{
                    Method          = $Method
                    Uri             = $Uri
                    Headers         = $global:OneIMSnowSession.Headers
                    ContentType     = "application/json; charset=utf-8"
                    UseBasicParsing = $true   # 5.1: avoids the Internet Explorer engine dependency in service context
                }
                if ($null -ne $Body)
                {
                    # 5.1 encodes string bodies as ISO-8859-1: send UTF-8 bytes so accented characters survive
                    $params["Body"] = [Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 5 -Compress))
                }

                $attempt = 0
                while ($true)
                {
                    $attempt++
                    try
                    {
                        Write-Verbose "$Method $Uri (attempt $attempt)"
                        return Invoke-RestMethod @params
                    }
                    catch
                    {
                        # 5.1 throws WebException (Response = HttpWebResponse), 7 throws HttpResponseException
                        # (Response = HttpResponseMessage): both expose Response.StatusCode; no Response on DNS/timeout errors
                        $response = $null
                        if ($_.Exception.PSObject.Properties["Response"]) { $response = $_.Exception.Response }
                        $status = $null
                        if ($null -ne $response -and $null -ne $response.StatusCode) { $status = [int]$response.StatusCode }
                        # error body: ErrorDetails.Message first (filled by 7, usually by 5.1 too)
                        $detail = $null
                        if ($_.ErrorDetails) { $detail = $_.ErrorDetails.Message }
                        if (-not $detail -and $null -ne $response -and $response.PSObject.Methods["GetResponseStream"])
                        {
                            # 5.1 only (HttpResponseMessage has no GetResponseStream): read the body from the response
                            $reader = $null
                            try { $reader = New-Object IO.StreamReader($response.GetResponseStream()); $detail = $reader.ReadToEnd() }
                            catch { Write-Verbose "Error body not readable: $($_.Exception.Message)" }
                            finally { if ($null -ne $reader) { $reader.Dispose() } }
                        }
                        $retryable = ($status -eq 429) -or ($status -ge 500)
                        if ($retryable -and $attempt -le $MaxRetries)
                        {
                            $wait = [math]::Pow(2, $attempt)
                            Write-Warning "ServiceNow returned HTTP $status, retrying in $wait s"
                            Start-Sleep -Seconds $wait
                            continue
                        }
                        # keep the status code on the exception message so callers can react (e.g. 404 on delete)
                        throw "ServiceNow request failed ($Method $Uri) HTTP ${status}: $detail $($_.Exception.Message)"
                    }
                }
'@

$Generic["Connect-OneIMSnow"] = @'
                param(
                    [Parameter(Mandatory=$true)][string]$InstanceUrl,
                    [Parameter(Mandatory=$true)][string]$Username,
                    [Parameter(Mandatory=$true)][SecureString]$Password
                )

                # Windows PowerShell 5.1 (.NET Framework) may not offer TLS 1.2 by default; ServiceNow requires it
                [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

                # Accept "myinstance", "myinstance.service-now.com" or the full URL
                $base = $InstanceUrl.Trim().TrimEnd("/")
                if ($base -notmatch "^https?://")
                {
                    if ($base -notmatch "\.") { $base = "$base.service-now.com" }
                    $base = "https://$base"
                }

                $plain = ConvertTo-OneIMSnowPlainText -SecureString $Password
                $token = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${Username}:$plain"))
                $plain = $null

                $global:OneIMSnowSession = @{
                    BaseUrl = $base
                    Headers = @{ Authorization = "Basic $token"; Accept = "application/json" }
                }

                # connection test: read one record
                $null = Invoke-OneIMSnowRequest -Method GET -Uri "$base/api/now/table/__TESTTABLE__?sysparm_limit=1&sysparm_fields=sys_id"
                Write-Host "Connected to ServiceNow instance $base as $Username (PowerShell $($PSVersionTable.PSVersion))"
'@

$Generic["Disconnect-OneIMSnow"] = @'
                $global:OneIMSnowSession = $null
                Write-Host "ServiceNow session closed"
'@

$Generic["Get-OneIMSnowTypeKind"] = @'
                # Maps a ServiceNow internal type to the conversion used by the connector
                param([string]$SnType)

                switch ($SnType)
                {
                    "integer" { "Int"; break }
                    "boolean" { "Bool"; break }
                    { $_ -in "glide_date_time", "due_date", "calendar_date_time", "datetime" } { "DateTime"; break }
                    { $_ -in "glide_date", "date" } { "Date"; break }
                    default { "String" }
                }
'@

$Generic["ConvertFrom-OneIMSnowValue"] = @'
                # Table API value (always a string) -> typed value; empty -> $null. Date/times are UTC
                param([object]$Value, [string]$SnType)

                if ($null -eq $Value -or ($Value -is [string] -and $Value -eq "")) { return $null }
                switch (Get-OneIMSnowTypeKind -SnType $SnType)
                {
                    "Int"      { $i = 0; if ([int]::TryParse("$Value", [ref]$i)) { return $i }; return $null }
                    "Bool"     { return ("$Value" -eq "true") }
                    "DateTime" { return [datetime]::SpecifyKind([datetime]::ParseExact("$Value", "yyyy-MM-dd HH:mm:ss", [cultureinfo]::InvariantCulture), [DateTimeKind]::Utc) }
                    "Date"     { return [datetime]::SpecifyKind([datetime]::ParseExact("$Value", "yyyy-MM-dd", [cultureinfo]::InvariantCulture), [DateTimeKind]::Utc) }
                    default    { return "$Value" }
                }
'@

$Generic["ConvertTo-OneIMSnowRecord"] = @'
                # Normalizes a Table API record to a flat object with every field of the class (null if missing)
                param([Parameter(Mandatory=$true)][PSObject]$Record, [Parameter(Mandatory=$true)][hashtable]$Types)

                $out = [ordered]@{}
                foreach ($f in ($Types.Keys | Sort-Object))
                {
                    $value = $null
                    if ($Record.PSObject.Properties[$f]) { $value = ConvertFrom-OneIMSnowValue -Value $Record.$f -SnType $Types[$f] }
                    $out[$f] = $value
                }
                [PSCustomObject]$out
'@

$Generic["ConvertTo-OneIMSnowBody"] = @'
                # Bound parameters -> JSON body with Table API string values; only passed fields are sent, $null clears
                param([System.Collections.IDictionary]$Values, [Parameter(Mandatory=$true)][hashtable]$Types)

                $body = @{}
                foreach ($k in @($Values.Keys))
                {
                    if ($k -eq "sys_id" -or -not $Types.ContainsKey($k)) { continue }
                    $v = $Values[$k]
                    if ($null -eq $v) { $body[$k] = ""; continue }
                    switch (Get-OneIMSnowTypeKind -SnType $Types[$k])
                    {
                        "Bool"
                        {
                            if ($v -is [string]) { $body[$k] = $v.ToLowerInvariant() } else { $body[$k] = ([bool]$v).ToString().ToLowerInvariant() }
                        }
                        "DateTime"
                        {
                            $d = [datetime]$v
                            if ($d.Kind -eq [DateTimeKind]::Local) { $d = $d.ToUniversalTime() }
                            $body[$k] = $d.ToString("yyyy-MM-dd HH:mm:ss", [cultureinfo]::InvariantCulture)
                        }
                        "Date"     { $body[$k] = ([datetime]$v).ToString("yyyy-MM-dd", [cultureinfo]::InvariantCulture) }
                        default    { $body[$k] = [string]::Format([cultureinfo]::InvariantCulture, "{0}", $v) }
                    }
                }
                $body
'@

$Generic["Get-OneIMSnowRecord"] = @'
                # Without -SysId: lists all records (paged). With -SysId: returns the single record
                param(
                    [Parameter(Mandatory=$true)][string]$Table,
                    [Parameter(Mandatory=$true)][hashtable]$Types,
                    [string]$SysId,
                    [string[]]$PropertiesToRequest,
                    [int]$PageSize = 1000,
                    [string]$Query
                )

                $fields = @($Types.Keys)
                if ($PropertiesToRequest)
                {
                    # sys_id is always needed as key
                    $fields = @("sys_id") + @($PropertiesToRequest | Where-Object { $_ -ne "sys_id" -and $Types.ContainsKey($_) })
                }
                $select = "sysparm_fields=$($fields -join ',')&sysparm_exclude_reference_link=true&sysparm_display_value=false"
                $base = "$($global:OneIMSnowSession.BaseUrl)/api/now/table/$Table"

                if ($SysId)
                {
                    Write-Host "Loading $Table $SysId"
                    $res = Invoke-OneIMSnowRequest -Method GET -Uri "$base/${SysId}?$select"
                    ConvertTo-OneIMSnowRecord -Record $res.result -Types $Types
                    return
                }

                Write-Host "Loading $Table (page size $PageSize)"
                $offset = 0
                do
                {
                    # stable ordering is required for consistent offset paging
                    $q = "ORDERBYsys_id"
                    if ($Query) { $q = "$Query^$q" }
                    $uri = "${base}?$select&sysparm_limit=$PageSize&sysparm_offset=$offset&sysparm_query=$([uri]::EscapeDataString($q))"
                    $res = Invoke-OneIMSnowRequest -Method GET -Uri $uri
                    $records = @($res.result)
                    foreach ($r in $records) { ConvertTo-OneIMSnowRecord -Record $r -Types $Types }
                    $offset += $PageSize
                } while ($records.Count -eq $PageSize)
'@

$Generic["New-OneIMSnowRecord"] = @'
                param(
                    [Parameter(Mandatory=$true)][string]$Table,
                    [Parameter(Mandatory=$true)][hashtable]$Types,
                    [System.Collections.IDictionary]$Values
                )

                $body = ConvertTo-OneIMSnowBody -Values $Values -Types $Types
                Write-Host "Creating $Table record ($($body.Keys -join ', '))"
                $uri = "$($global:OneIMSnowSession.BaseUrl)/api/now/table/${Table}?sysparm_exclude_reference_link=true"
                $res = Invoke-OneIMSnowRequest -Method POST -Uri $uri -Body $body
                ConvertTo-OneIMSnowRecord -Record $res.result -Types $Types
'@

$Generic["Set-OneIMSnowRecord"] = @'
                param(
                    [Parameter(Mandatory=$true)][string]$Table,
                    [Parameter(Mandatory=$true)][hashtable]$Types,
                    [Parameter(Mandatory=$true)][string]$SysId,
                    [System.Collections.IDictionary]$Values
                )

                $body = ConvertTo-OneIMSnowBody -Values $Values -Types $Types
                if ($body.Count -eq 0) { Write-Host "Nothing to update for $Table $SysId"; return }

                Write-Host "Updating $Table $SysId ($($body.Keys -join ', '))"
                # PATCH = partial update
                $uri = "$($global:OneIMSnowSession.BaseUrl)/api/now/table/$Table/${SysId}?sysparm_exclude_reference_link=true"
                $null = Invoke-OneIMSnowRequest -Method PATCH -Uri $uri -Body $body
'@

$Generic["Remove-OneIMSnowRecord"] = @'
                param([Parameter(Mandatory=$true)][string]$Table, [Parameter(Mandatory=$true)][string]$SysId)

                Write-Host "Deleting $Table $SysId"
                try
                {
                    $null = Invoke-OneIMSnowRequest -Method DELETE -Uri "$($global:OneIMSnowSession.BaseUrl)/api/now/table/$Table/$SysId"
                }
                catch
                {
                    # already gone = success
                    if ($_.Exception.Message -match "HTTP 404") { Write-Warning "$Table $SysId not found, treated as deleted"; return }
                    throw
                }
'@

# -UseModule: the inline Connect-OneIMSnow only loads the module, then delegates to the module's Connect-OneIMSnowSession
$ModuleLoader = @'
                param(
                    [Parameter(Mandatory=$true)][string]$InstanceUrl,
                    [Parameter(Mandatory=$true)][string]$Username,
                    [Parameter(Mandatory=$true)][SecureString]$Password,
                    [string]$ModuleLocation
                )

                if (-not $ModuleLocation) { throw "Connection parameter ModuleLocation is empty: set the full path of ServiceNowConnector.psm1" }
                $path = $ModuleLocation.Trim().Trim('"')
                if ($path -notmatch "\.psm1$") { $path = "$path.psm1" }   # README convention: path without the suffix
                if (-not (Test-Path -LiteralPath $path -PathType Leaf))
                {
                    throw "ServiceNow module not found: '$path' on $env:COMPUTERNAME (user $env:USERNAME). It must exist at this path on every Job server and admin client that uses the connector."
                }

                # -Global: visible to the injected commands; -Force: reloaded on every connect, so edits apply to the next sync
                Import-Module -Name $path -Global -Force -DisableNameChecking -ErrorAction Stop
                if (-not (Get-Command Connect-OneIMSnowSession -ErrorAction SilentlyContinue))
                {
                    throw "Module '$path' loaded but Connect-OneIMSnowSession is missing: wrong file or old version"
                }
                $info = Get-OneIMSnowModuleInfo
                Write-Host "ServiceNow module $path (API $($info.ApiVersion), generated $($info.Generated)) loaded on $env:COMPUTERNAME, PowerShell $($PSVersionTable.PSVersion), execution policy $(Get-ExecutionPolicy)"
                if ($info.ApiVersion -ne __APIVERSION__) { throw "Module API version $($info.ApiVersion) does not match the connector XML (__APIVERSION__): regenerate both" }

                Connect-OneIMSnowSession -InstanceUrl $InstanceUrl -Username $Username -Password $Password
'@
# bump when the signature of a module function used by the XML changes
$ModuleApiVersion = 1

#endregion

#region Schema discovery (online)

function Get-SnowValue($Record, [string]$Name)
{
    # reads a (possibly dot-walked) field; reference fields may come back as {link, value}
    $p = $Record.PSObject.Properties[$Name]
    if (-not $p -or $null -eq $p.Value) { return "" }
    if ($p.Value -is [string]) { return $p.Value }
    if ($p.Value.PSObject.Properties["value"]) { return [string]$p.Value.value }
    return [string]$p.Value
}

function Get-SnowTableSchema([string]$ClassName, [string]$Table, [string[]]$KnownTables)
{
    $base = "$($global:OneIMSnowSession.BaseUrl)/api/now/table"
    $source = "sys_dictionary"
    $fields = [ordered]@{}
    $display = $null

    try
    {
        # table + parents (child first, so child definitions override inherited ones)
        $chain = @()
        $cur = $Table
        while ($cur -and $chain -notcontains $cur)
        {
            $chain += $cur
            $r = Invoke-OneIMSnowRequest -Method GET -Uri "$base/sys_db_object?sysparm_query=name=$cur&sysparm_fields=name,super_class.name&sysparm_limit=1"
            $rec = @($r.result)
            if ($rec.Count -eq 0) { if ($cur -eq $Table) { throw "Table $Table not found in sys_db_object" }; break }
            $cur = Get-SnowValue $rec[0] "super_class.name"
        }
        Write-Host "  $Table hierarchy: $($chain -join ' -> ')"

        foreach ($t in $chain)
        {
            $q = [uri]::EscapeDataString("name=$t^elementISNOTEMPTY^active=true")
            $flds = "element,column_label,internal_type,internal_type.name,reference,reference.name,mandatory,display"
            $r = Invoke-OneIMSnowRequest -Method GET -Uri "$base/sys_dictionary?sysparm_query=$q&sysparm_fields=$flds&sysparm_exclude_reference_link=true&sysparm_limit=10000"
            foreach ($d in @($r.result))
            {
                $name = Get-SnowValue $d "element"
                if (-not $name -or $fields.Contains($name)) { continue }
                $type = Get-SnowValue $d "internal_type.name"
                if (-not $type) { $type = Get-SnowValue $d "internal_type" }
                $ref = Get-SnowValue $d "reference.name"
                if (-not $ref) { $ref = Get-SnowValue $d "reference" }
                $fields[$name] = [ordered]@{
                    Name = $name; Type = $type; Label = (Get-SnowValue $d "column_label"); Reference = $ref
                    Mandatory = ((Get-SnowValue $d "mandatory") -eq "true")
                }
                if (-not $display -and (Get-SnowValue $d "display") -eq "true") { $display = $name }
            }
        }
        if ($fields.Count -eq 0) { throw "sys_dictionary returned no fields for $Table (missing read access?)" }
    }
    catch
    {
        Write-Warning "  $Table : cannot read the dictionary ($($_.Exception.Message)). Falling back to a sample record: all fields typed as String."
        $source = "sample record"
        $fields = [ordered]@{}
        $r = Invoke-OneIMSnowRequest -Method GET -Uri "$base/${Table}?sysparm_limit=1&sysparm_exclude_reference_link=true"
        $rec = @($r.result)
        if ($rec.Count -eq 0) { throw "Table $Table is empty or not readable: cannot determine its fields" }
        foreach ($p in $rec[0].PSObject.Properties)
        {
            $type = "string"
            if ($p.Name -in "sys_created_on", "sys_updated_on") { $type = "glide_date_time" }
            if ($p.Name -eq "sys_mod_count") { $type = "integer" }
            $fields[$p.Name] = [ordered]@{ Name = $p.Name; Type = $type; Label = ""; Reference = ""; Mandatory = $false }
        }
    }

    if (-not $display) { if ($fields.Contains("name")) { $display = "name" } else { $display = "sys_id" } }
    [ordered]@{ Class = $ClassName; Table = $Table; Source = $source; Display = $display; Fields = @($fields.Values) }
}

#endregion

#region XML generation

function ConvertTo-XmlAttr([string]$s) { [Security.SecurityElement]::Escape($s) }
function ConvertTo-XmlComment([string]$s) { ($s -replace "-{2,}", "-" -replace "[\r\n]", " ").Trim().TrimEnd("-") }

function Get-ConnectorDataType([string]$SnType)
{
    switch (Get-OneIMSnowTypeKind -SnType $SnType)
    {
        "Int"      { "Int" }
        "Bool"     { "Bool" }
        "DateTime" { "DateTime" }
        "Date"     { "DateTime" }
        default    { "String" }
    }
}

function Add-CustomCommand([Text.StringBuilder]$sb, [string]$Name, [string]$Code, [string]$Comment)
{
    if ($Comment) { [void]$sb.AppendLine("            <!-- $(ConvertTo-XmlComment $Comment) -->") }
    [void]$sb.AppendLine("            <CustomCommand Name=`"$Name`">")
    [void]$sb.AppendLine("            <![CDATA[")
    [void]$sb.AppendLine($Code.TrimEnd())
    [void]$sb.AppendLine("            ]]>")
    [void]$sb.AppendLine("            </CustomCommand>")
    [void]$sb.AppendLine("")
}

function ConvertTo-PsLiteral($v)
{
    if ($v -is [bool]) { if ($v) { return '$true' } else { return '$false' } }
    if ($v -is [int] -or $v -is [long]) { return "$v" }
    "'" + ("$v" -replace "'", "''") + "'"
}

function Get-TestTable($Schema)
{
    # connection test table: cmn_department if present, else the first one
    $tables = @($Schema.Classes | ForEach-Object { $_.Table })
    if ($tables -contains "cmn_department") { return "cmn_department" }
    $tables[0]
}

function New-ConnectorModule($Schema)
{
    $testTable = Get-TestTable $Schema
    $sb = New-Object Text.StringBuilder
    [void]$sb.AppendLine("<#")
    [void]$sb.AppendLine("    ServiceNow Table API - generic logic for the One Identity Manager PowerShell connector (Windows PowerShell 5.1 and PowerShell 7).")
    [void]$sb.AppendLine("    Loaded by Connect-OneIMSnow in ServiceNowConnector.Module.xml (connection parameter ModuleLocation), reloaded on")
    [void]$sb.AppendLine("    every connect. Must exist at the same path on every Job server and admin client that uses the connector.")
    [void]$sb.AppendLine("    GENERATED by New-ServiceNowConnectorXml.ps1 -UseModule on $($Schema.Generated). Editing it by hand is fine for")
    [void]$sb.AppendLine("    fixes, but a regeneration overwrites it (previous copy kept as .bak): port the change into the generator.")
    [void]$sb.AppendLine("    RULE: functions write ONLY the objects meant for the connector to the output stream;")
    [void]$sb.AppendLine("    use Write-Host / Write-Verbose / Write-Warning for logging (mapped to NLog).")
    [void]$sb.AppendLine("#>")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("function Get-OneIMSnowModuleInfo")
    [void]$sb.AppendLine("{")
    [void]$sb.AppendLine("    # ApiVersion must match the connector XML (checked by Connect-OneIMSnow)")
    [void]$sb.AppendLine("    [PSCustomObject]@{ ApiVersion = $ModuleApiVersion; Generated = '$($Schema.Generated)' }")
    [void]$sb.AppendLine("}")
    $names = @("Get-OneIMSnowModuleInfo")
    foreach ($n in $Generic.Keys)
    {
        if ($n -eq "Disconnect-OneIMSnow") { continue }   # stays inline in the XML
        $fn = $n
        if ($n -eq "Connect-OneIMSnow") { $fn = "Connect-OneIMSnowSession" }   # the inline Connect-OneIMSnow wraps it
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("function $fn")
        [void]$sb.AppendLine("{")
        [void]$sb.AppendLine($Generic[$n].Replace("__TESTTABLE__", $testTable).TrimEnd())
        [void]$sb.AppendLine("}")
        $names += $fn
    }
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("Export-ModuleMember -Function $($names -join ', ')")
    $sb.ToString()
}

function New-ConnectorXml($Schema, [bool]$UseModule)
{
    $classes = @($Schema.Classes)
    # a table can back several classes (e.g. internal/external companies): references point to all of them
    $tableToClass = @{}
    foreach ($c in $classes)
    {
        if (-not $tableToClass.ContainsKey($c.Table)) { $tableToClass[$c.Table] = @() }
        $tableToClass[$c.Table] += $c.Class
    }
    $testTable = Get-TestTable $Schema

    $sb = New-Object Text.StringBuilder
    [void]$sb.AppendLine('<?xml version="1.0" encoding="utf-8" ?>')
    [void]$sb.AppendLine("<!-- GENERATED by New-ServiceNowConnectorXml.ps1 from the schema cache ServiceNowSchema.json ($($Schema.Generated)). Do not edit by hand: change the generator or ServiceNowSchema.json and regenerate. -->")
    [void]$sb.AppendLine("<PowershellConnectorDefinition Id=`"ServiceNow`" Version=`"2.0`" Description=`"ServiceNow Table API connector ($(ConvertTo-XmlAttr (($classes | ForEach-Object { $_.Table } | Select-Object -Unique) -join ', '))), Basic authentication`">")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("    <PluginAssemblies/>")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("    <ConnectionParameters>")
    [void]$sb.AppendLine('        <ConnectionParameter Name="InstanceUrl" Description="ServiceNow instance: name (myinstance), host (myinstance.service-now.com) or full URL" />')
    [void]$sb.AppendLine('        <ConnectionParameter Name="Username" Description="ServiceNow user with access to the Table API" />')
    [void]$sb.AppendLine('        <ConnectionParameter Name="Password" Description="Password of the ServiceNow user" IsSensibleData="true" />')
    if ($UseModule)
    {
        [void]$sb.AppendLine('        <ConnectionParameter Name="ModuleLocation" Description="Full path of ServiceNowConnector.psm1 (same path on every Job server and admin client), e.g. C:\OneIdentity\ServiceNow\ServiceNowConnector.psm1" />')
    }
    [void]$sb.AppendLine("    </ConnectionParameters>")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("    <Initialization>")
    [void]$sb.AppendLine("        <!--")
    if ($UseModule)
    {
        [void]$sb.AppendLine("            Generic logic is in ServiceNowConnector.psm1 (ModuleLocation), imported by Connect-OneIMSnow on every connect.")
        [void]$sb.AppendLine("            Every command referenced below is still a custom command, injected before Connect runs. Windows PowerShell 5.1.")
    }
    else
    {
        [void]$sb.AppendLine("            All logic is inline: custom commands are injected into the session before Connect runs. Windows PowerShell 5.1.")
    }
    [void]$sb.AppendLine("            RULE: functions write ONLY the objects meant for the connector to the output stream;")
    [void]$sb.AppendLine("            use Write-Host / Write-Verbose / Write-Warning for logging (mapped to NLog).")
    [void]$sb.AppendLine("        -->")
    [void]$sb.AppendLine("        <CustomCommands>")
    [void]$sb.AppendLine("")

    if ($UseModule)
    {
        Add-CustomCommand $sb "Connect-OneIMSnow" ($ModuleLoader.Replace("__APIVERSION__", "$ModuleApiVersion")) "loads ServiceNowConnector.psm1, then connects"
        Add-CustomCommand $sb "Disconnect-OneIMSnow" $Generic["Disconnect-OneIMSnow"] ""
    }
    else
    {
        foreach ($n in $Generic.Keys)
        {
            Add-CustomCommand $sb $n ($Generic[$n].Replace("__TESTTABLE__", $testTable)) ""
        }
    }

    foreach ($c in $classes)
    {
        $cls = $c.Class; $tbl = $c.Table
        $writable = @($c.Fields | Where-Object { $_.Name -ne "sys_id" -and $_.Name -notlike "sys_*" } | ForEach-Object { $_.Name } | Sort-Object)
        $typesLines = @($c.Fields | Sort-Object Name | ForEach-Object { "                    '$($_.Name)' = '$($_.Type)'" })

        $filterText = ""
        if ($c.Query) { $filterText = ", filter: $($c.Query)" }
        Add-CustomCommand $sb "Get-OneIMSnow${cls}Types" ("                # field -> ServiceNow internal type ($tbl, source: $($c.Source))`r`n                @{`r`n" + ($typesLines -join "`r`n") + "`r`n                }") "===== $cls ($tbl$filterText) ====="
        $queryArg = ""
        if ($c.Query) { $queryArg = " -Query $(ConvertTo-PsLiteral $c.Query)" }
        Add-CustomCommand $sb "Get-OneIMSnow${cls}" @"
                # the filter applies to the listing; a single record is always loaded by sys_id
                param([string]`$sys_id, [string[]]`$PropertiesToRequest)
                Get-OneIMSnowRecord -Table '$tbl' -Types (Get-OneIMSnow${cls}Types) -SysId `$sys_id -PropertiesToRequest `$PropertiesToRequest$queryArg
"@ ""
        $paramBlock = ($writable | ForEach-Object { "                    [object]`$$_" }) -join ",`r`n"
        $defaultLines = @()
        if ($c.Defaults)
        {
            foreach ($k in @($c.Defaults.Keys | Sort-Object))
            {
                $defaultLines += "                if (-not `$values.ContainsKey('$k')) { `$values['$k'] = $(ConvertTo-PsLiteral $c.Defaults[$k]) }"
            }
        }
        if ($defaultLines.Count -gt 0)
        {
            $newBody = @"
                # class defaults (keep new records inside the class filter)
                `$values = @{}
                foreach (`$k in `$PSBoundParameters.Keys) { `$values[`$k] = `$PSBoundParameters[`$k] }
$($defaultLines -join "`r`n")
                New-OneIMSnowRecord -Table '$tbl' -Types (Get-OneIMSnow${cls}Types) -Values `$values
"@
        }
        else
        {
            $newBody = "                New-OneIMSnowRecord -Table '$tbl' -Types (Get-OneIMSnow${cls}Types) -Values `$PSBoundParameters"
        }
        Add-CustomCommand $sb "New-OneIMSnow${cls}" @"
                # parameters = writable fields; only the ones passed are sent
                param(
$paramBlock
                )
$newBody
"@ ""
        $setParams = (@("                    [string]`$sys_id") + @($writable | ForEach-Object { "                    [object]`$$_" })) -join ",`r`n"
        Add-CustomCommand $sb "Set-OneIMSnow${cls}" @"
                # parameters = writable fields; only the ones passed are sent, `$null clears the field
                param(
$setParams
                )
                if (-not `$sys_id) { throw "Set-OneIMSnow${cls}: sys_id is required" }
                Set-OneIMSnowRecord -Table '$tbl' -Types (Get-OneIMSnow${cls}Types) -SysId `$sys_id -Values `$PSBoundParameters
"@ ""
        Add-CustomCommand $sb "Remove-OneIMSnow${cls}" @"
                param([string]`$sys_id)
                if (-not `$sys_id) { throw "Remove-OneIMSnow${cls}: sys_id is required" }
                Remove-OneIMSnowRecord -Table '$tbl' -SysId `$sys_id
"@ ""
    }

    [void]$sb.AppendLine("        </CustomCommands>")
    [void]$sb.AppendLine("")
    if ($UseModule) { [void]$sb.AppendLine("        <!-- no external commandlets are called directly (module functions are called only from custom commands) -->") }
    else { [void]$sb.AppendLine("        <!-- no external commandlets are called directly -->") }
    [void]$sb.AppendLine("        <PredefinedCommands/>")
    [void]$sb.AppendLine("")
    $moduleParam = ""
    if ($UseModule) { $moduleParam = "`r`n" + '                        <SetParameter Param="ModuleLocation" Source="ConnectionParameter" Value="ModuleLocation" />' }
    [void]$sb.AppendLine(@"
        <EnvironmentInitialization>
            <Connect>
                <CommandSequence>
                    <Item Command="Connect-OneIMSnow" Order="1">
                        <SetParameter Param="InstanceUrl" Source="ConnectionParameter" Value="InstanceUrl" />
                        <SetParameter Param="Username" Source="ConnectionParameter" Value="Username" />
                        <SetParameter Param="Password" Source="ConnectionParameter" Value="Password" ConversionMethod="ToSecureString" />$moduleParam
                    </Item>
"@.TrimEnd())
    [void]$sb.AppendLine(@'
                </CommandSequence>
            </Connect>
            <Disconnect>
                <CommandSequence>
                    <Item Command="Disconnect-OneIMSnow" Order="1" />
                </CommandSequence>
            </Disconnect>
        </EnvironmentInitialization>
    </Initialization>
'@)
    [void]$sb.AppendLine("    <Schema>")

    foreach ($c in $classes)
    {
        $cls = $c.Class
        $get = "Get-OneIMSnow$cls"; $new = "New-OneIMSnow$cls"; $set = "Set-OneIMSnow$cls"; $rem = "Remove-OneIMSnow$cls"
        $hasRevision = @($c.Fields | Where-Object { $_.Name -eq "sys_updated_on" }).Count -gt 0

        [void]$sb.AppendLine("")
        $classFilter = ""
        if ($c.Query) { $classFilter = ", filter: $($c.Query)" }
        [void]$sb.AppendLine("        <!-- $(ConvertTo-XmlComment "$($c.Table) - $(@($c.Fields).Count) fields, source: $($c.Source)$classFilter") -->")
        [void]$sb.AppendLine("        <Class Name=`"$cls`">")
        [void]$sb.AppendLine("            <Properties>")

        # sys_id first, then display, then alphabetical
        $ordered = @($c.Fields | Sort-Object @{ Expression = { if ($_.Name -eq "sys_id") { 0 } elseif ($_.Name -eq $c.Display) { 1 } else { 2 } } }, Name)
        foreach ($f in $ordered)
        {
            $n = $f.Name
            $isKey = ($n -eq "sys_id")
            $readOnly = $n -like "sys_*"
            $attrs = "Name=`"$n`" DataType=`"$(Get-ConnectorDataType $f.Type)`""
            if ($n -eq $c.Display -and -not $isKey) { $attrs += ' IsDisplay="true"' }
            if ($isKey -or $f.Mandatory) { $attrs += ' IsMandatory="true"' }
            if ($isKey) { $attrs += ' IsUniqueKey="true"' }
            if ($n -eq "sys_updated_on") { $attrs += ' IsRevision="true"' }
            if ($readOnly) { $attrs += ' AccessConstraint="ReadOnly"' }

            $comment = "$($f.Label) ($($f.Type)$(if ($f.Reference) { " -> $($f.Reference)" }))"
            if ($n -like "u_*") { $comment = "CUSTOM: $comment" }
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("                <!-- $(ConvertTo-XmlComment $comment) -->")
            [void]$sb.AppendLine("                <Property $attrs>")
            if ($f.Reference -and $tableToClass.ContainsKey($f.Reference))
            {
                [void]$sb.AppendLine("                    <ReferenceTargets>")
                foreach ($target in $tableToClass[$f.Reference])
                {
                    [void]$sb.AppendLine("                        <ReferenceTarget Class=`"$target`" Property=`"sys_id`" />")
                }
                [void]$sb.AppendLine("                    </ReferenceTargets>")
            }
            [void]$sb.AppendLine("                    <ReturnBindings>")
            [void]$sb.AppendLine("                        <Bind CommandResultOf=`"$get`" Path=`"$n`" />")
            [void]$sb.AppendLine("                        <Bind CommandResultOf=`"$new`" Path=`"$n`" />")
            [void]$sb.AppendLine("                    </ReturnBindings>")
            if ($isKey)
            {
                [void]$sb.AppendLine("                    <CommandMappings>")
                foreach ($cmd in $get, $set, $rem) { [void]$sb.AppendLine("                        <Map ToCommand=`"$cmd`" Parameter=`"sys_id`" />") }
                [void]$sb.AppendLine("                    </CommandMappings>")
            }
            elseif (-not $readOnly)
            {
                [void]$sb.AppendLine("                    <CommandMappings>")
                [void]$sb.AppendLine("                        <Map ToCommand=`"$new`" Parameter=`"$n`" />")
                [void]$sb.AppendLine("                        <Map ToCommand=`"$set`" Parameter=`"$n`" />")
                [void]$sb.AppendLine("                    </CommandMappings>")
                [void]$sb.AppendLine("                    <ModifiedBy>")
                [void]$sb.AppendLine("                        <ModBy Command=`"$new`" Method=`"Insert`" />")
                [void]$sb.AppendLine("                        <ModBy Command=`"$set`" Method=`"Update`" />")
                [void]$sb.AppendLine("                    </ModifiedBy>")
            }
            [void]$sb.AppendLine("                </Property>")
        }

        $listProps = @("sys_id", $c.Display)
        if ($hasRevision) { $listProps += "sys_updated_on" }
        $listProps = @($listProps | Select-Object -Unique)

        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("            </Properties>")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("            <ReadConfiguration>")
        [void]$sb.AppendLine("                <!-- list only key, display and revision properties -->")
        [void]$sb.AppendLine("                <ListingCommand Command=`"$get`">")
        [void]$sb.AppendLine("                    <SetParameter Param=`"PropertiesToRequest`" Source=`"FixedArray`" Value=`"$($listProps -join ',')`" />")
        [void]$sb.AppendLine("                </ListingCommand>")
        [void]$sb.AppendLine("                <CommandSequence>")
        [void]$sb.AppendLine("                    <Item Command=`"$get`" Order=`"1`" />")
        [void]$sb.AppendLine("                </CommandSequence>")
        [void]$sb.AppendLine("            </ReadConfiguration>")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("            <MethodConfiguration>")
        [void]$sb.AppendLine("                <Method Name=`"Insert`">")
        [void]$sb.AppendLine("                    <CommandSequence>")
        [void]$sb.AppendLine("                        <Item Command=`"$new`" Order=`"1`" />")
        [void]$sb.AppendLine("                    </CommandSequence>")
        [void]$sb.AppendLine("                </Method>")
        [void]$sb.AppendLine("                <Method Name=`"Update`">")
        [void]$sb.AppendLine("                    <CommandSequence>")
        [void]$sb.AppendLine("                        <Item Command=`"$set`" Order=`"1`" Condition=`"ModificationExists`" />")
        [void]$sb.AppendLine("                    </CommandSequence>")
        [void]$sb.AppendLine("                </Method>")
        [void]$sb.AppendLine("                <Method Name=`"Delete`">")
        [void]$sb.AppendLine("                    <CommandSequence>")
        [void]$sb.AppendLine("                        <Item Command=`"$rem`" Order=`"1`" />")
        [void]$sb.AppendLine("                    </CommandSequence>")
        [void]$sb.AppendLine("                </Method>")
        [void]$sb.AppendLine("            </MethodConfiguration>")
        [void]$sb.AppendLine("        </Class>")
    }

    [void]$sb.AppendLine("    </Schema>")
    [void]$sb.AppendLine("</PowershellConnectorDefinition>")
    $sb.ToString()
}

#endregion

# make the generic commands available to this script too (same code that goes into the XML)
foreach ($n in $Generic.Keys)
{
    Set-Item -Path "function:script:$n" -Value ([scriptblock]::Create($Generic[$n].Replace("__TESTTABLE__", "sys_user")))
}

# normalize -Tables: class -> @{ Table; Query; Defaults }
$specs = [ordered]@{}
foreach ($cls in $Tables.Keys)
{
    $v = $Tables[$cls]
    if ($v -is [string]) { $specs[$cls] = @{ Table = $v; Query = ""; Defaults = @{} } }
    else
    {
        $d = @{}
        if ($v.Defaults) { $d = $v.Defaults }
        $specs[$cls] = @{ Table = [string]$v.Table; Query = [string]$v.Query; Defaults = $d }
    }
}
$uniqueTables = @($specs.Values | ForEach-Object { $_.Table } | Select-Object -Unique)

# the schema file is a per-table cache (older files stored one entry per class under "Classes")
$schema = $null
$cached = @()
if (Test-Path -LiteralPath $SchemaFile)
{
    $schema = Get-Content -LiteralPath $SchemaFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $cached = if ($schema.PSObject.Properties["Tables"]) { @($schema.Tables) } else { @($schema.Classes) }
}
elseif ($Offline) { throw "Schema file $SchemaFile not found: run once online first" }

$byTable = @{}
if (-not $Refresh) { foreach ($ts in $cached) { if (-not $byTable.ContainsKey($ts.Table)) { $byTable[$ts.Table] = $ts } } }
$missing = @($uniqueTables | Where-Object { -not $byTable.ContainsKey($_) })

if (-not $Offline -and $missing.Count -gt 0)
{
    if (-not $Password) { $Password = Read-Host -AsSecureString "Password for $Username" }

    # connection test on the same table the generated XML uses (cmn_department if present, else the first one)
    $testTable = $uniqueTables[0]
    if ($uniqueTables -contains "cmn_department") { $testTable = "cmn_department" }
    Set-Item -Path "function:script:Connect-OneIMSnow" -Value ([scriptblock]::Create($Generic["Connect-OneIMSnow"].Replace("__TESTTABLE__", $testTable)))
    Connect-OneIMSnow -InstanceUrl $InstanceUrl -Username $Username -Password $Password

    # each table is read once even if several classes use it; an unreadable table (missing plugin, no ACL)
    # skips its classes instead of failing the whole run, and is retried on the next online run
    foreach ($t in $missing)
    {
        Write-Host "Reading schema of $t"
        try { $byTable[$t] = Get-SnowTableSchema -ClassName "" -Table $t }
        catch { Write-Warning "  $t skipped: $($_.Exception.Message)" }
    }
    # keep cached tables no longer used by -Tables: they cost nothing and avoid a re-read if they come back
    foreach ($ts in $cached) { if (-not $byTable.ContainsKey($ts.Table)) { $byTable[$ts.Table] = $ts } }
    # the instance URL is not saved: generated files must not identify an instance
    $save = [ordered]@{
        Generated = (Get-Date).ToString("yyyy-MM-dd HH:mm")
        Tables    = @($byTable.Keys | Sort-Object | ForEach-Object { $byTable[$_] })
    }
    [IO.File]::WriteAllText($SchemaFile, ($save | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
    Write-Host "Schema saved to $SchemaFile (read: $($missing -join ', '))"
    Disconnect-OneIMSnow

    # reload so new and cached entries have the same (deserialized) shape
    $schema = Get-Content -LiteralPath $SchemaFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $byTable = @{}
    foreach ($ts in @($schema.Tables)) { $byTable[$ts.Table] = $ts }
}
elseif (-not $Offline) { Write-Host "All tables are in $SchemaFile, nothing to read (use -Refresh to re-read them)" }

# drop fields that cannot be handled, with a visible reason
foreach ($ts in $byTable.Values)
{
    $keep = @()
    foreach ($f in @($ts.Fields))
    {
        if ($SkippedTypes -contains $f.Type) { Write-Warning "$($ts.Table).$($f.Name) skipped (type $($f.Type) is not a plain column)"; continue }
        if ($ReservedNames -contains $f.Name.ToLowerInvariant()) { Write-Warning "$($ts.Table).$($f.Name) skipped (reserved PowerShell name)"; continue }
        if ($f.Name -notmatch "^[A-Za-z_][A-Za-z0-9_]*$") { Write-Warning "$($ts.Table).$($f.Name) skipped (not a valid parameter name)"; continue }
        $keep += $f
    }
    $ts.Fields = $keep
}

$classes = @()
foreach ($cls in $specs.Keys)
{
    $sp = $specs[$cls]
    if (-not $byTable.ContainsKey($sp.Table))
    {
        if ($Offline -or $missing -notcontains $sp.Table) { throw "Table $($sp.Table) (class $cls) is not in $SchemaFile : run the generator online" }
        Write-Warning "Class $cls not generated: table $($sp.Table) could not be read"
        continue
    }
    $ts = $byTable[$sp.Table]
    $fieldNames = @($ts.Fields | ForEach-Object { $_.Name })
    foreach ($k in @($sp.Defaults.Keys)) { if ($fieldNames -notcontains $k) { throw "Default field $k of class $cls does not exist in $($sp.Table)" } }
    $classes += [pscustomobject]@{
        Class = $cls; Table = $sp.Table; Source = $ts.Source; Display = $ts.Display; Fields = @($ts.Fields)
        Query = $sp.Query; Defaults = $sp.Defaults
    }
}
$model = [pscustomobject]@{ Generated = $schema.Generated; Classes = $classes }

$xml = New-ConnectorXml $model $UseModule.IsPresent
[xml]$xml | Out-Null   # must be well-formed

$outputs = @(@{ Path = $OutputXml; Text = $xml; Encoding = (New-Object Text.UTF8Encoding($false)) })
if ($UseModule)
{
    $psm = New-ConnectorModule $model
    $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseInput($psm, [ref]$null, [ref]$parseErrors)
    if ($parseErrors) { throw "Generated module does not parse: $($parseErrors[0].Message)" }
    # BOM: Windows PowerShell 5.1 reads BOM-less scripts as ANSI
    $outputs += @{ Path = $OutputModule; Text = $psm; Encoding = (New-Object Text.UTF8Encoding($true)) }
}
foreach ($o in $outputs)
{
    if (Test-Path -LiteralPath $o.Path)
    {
        Copy-Item -LiteralPath $o.Path -Destination "$($o.Path).bak" -Force
        Write-Host "Previous file saved as $($o.Path).bak"
    }
    [IO.File]::WriteAllText($o.Path, $o.Text, $o.Encoding)
}

Write-Host ""
Write-Host "Generated $OutputXml"
if ($UseModule) { Write-Host "Generated $OutputModule (copy it to the ModuleLocation path on every Job server and admin client)" }
foreach ($c in $classes)
{
    $custom = @($c.Fields | Where-Object { $_.Name -like "u_*" }).Count
    $filter = ""
    if ($c.Query) { $filter = ", filter=$($c.Query)" }
    Write-Host ("  {0,-16} {1,-16} {2,3} fields ({3} custom u_), display={4}, source={5}{6}" -f $c.Class, $c.Table, @($c.Fields).Count, $custom, $c.Display, $c.Source, $filter)
}
