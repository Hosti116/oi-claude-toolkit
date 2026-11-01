<#
    ServiceNow Table API module for the One Identity Manager PowerShell connector ("module" layout).

    Implements connector contract v1 (CONTRACT.md). This file is the whole integration logic: endpoints, paging,
    authentication, retries, type conversion and the list of classes/fields (manifest). It can be maintained by a
    third party without touching Identity Manager:
      - logic change (same classes/fields)  -> replace this file on the Job servers, nothing to do in OIM;
      - classes/fields change (manifest)     -> also regenerate the XML with New-ConnectorXmlFromModule.ps1,
                                                load it in the connection and update the schema.
    Runs on Windows PowerShell 5.1 (Identity Manager <= 9.2) and PowerShell 7 (9.3 / 10.0).
    RULE: functions write ONLY the objects meant for the connector to the output stream;
    use Write-Host / Write-Verbose / Write-Warning for logging (mapped to NLog). Never log secrets.
#>

Set-StrictMode -Version 2.0

$script:ContractVersion = 1
$script:ModuleVersion = '1.0.0'
$script:SysIdPattern = '^[0-9a-fA-F]{32}$'
$script:SnowDateTimeFormat = 'yyyy-MM-dd HH:mm:ss'   # Table API with sysparm_display_value=false: UTC
$script:Session = $null

# Options connection parameter: "Name=Value;Name=Value". Defaults and allowed ranges.
$script:OptionDefaults = [ordered]@{ AuthType = 'Basic'; PageSize = 500; TimeoutSec = 100; MaxRetries = 4; CacheSeconds = 300 }
$script:OptionRanges = @{ PageSize = @(1, 10000); TimeoutSec = @(1, 600); MaxRetries = @(0, 10); CacheSeconds = @(0, 3600) }
$script:SupportedAuthTypes = @('Basic')

#region manifest: classes and fields exposed to Identity Manager

function New-SnowProperty
{
    param(
        [Parameter(Mandatory = $true, Position = 0)][string]$Name,
        [ValidateSet('String', 'Int', 'Bool', 'DateTime')][string]$Type = 'String',
        [ValidateSet('Read', 'ReadWrite', 'InsertOnly')][string]$Access = 'ReadWrite',
        [string]$Reference,
        [switch]$Mandatory
    )
    $referenceClass = $null
    if ($Reference) { $referenceClass = $Reference }
    [PSCustomObject]@{ Name = $Name; Type = $Type; Access = $Access; Mandatory = [bool]$Mandatory; Reference = $referenceClass }
}

function New-SnowClass
{
    # Every ServiceNow table has sys_id (key) and sys_updated_on (revision): added here to every class
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Table,
        [Parameter(Mandatory = $true)][string]$Display,
        [string[]]$Operations = @(),
        [string]$Query,            # encoded query applied to the listing (optional)
        [Parameter(Mandatory = $true)][object[]]$Properties
    )
    $system = @(
        (New-SnowProperty sys_id -Access Read),
        (New-SnowProperty sys_updated_on -Type DateTime -Access Read)
    )
    [PSCustomObject]@{
        Name = $Name; Table = $Table; Key = 'sys_id'; Display = $Display; Revision = 'sys_updated_on'
        Operations = @($Operations); Query = $Query; Properties = @($system + $Properties)
    }
}

$script:Classes = @(
    New-SnowClass -Name Company -Table core_company -Display name -Operations Insert, Update, Delete -Properties @(
        (New-SnowProperty name -Mandatory)
        (New-SnowProperty street)
        (New-SnowProperty city)
        (New-SnowProperty state)
        (New-SnowProperty zip)
        (New-SnowProperty country)
        (New-SnowProperty phone)
        (New-SnowProperty website)
        (New-SnowProperty parent -Reference Company)
        (New-SnowProperty contact -Reference User)
        (New-SnowProperty customer -Type Bool)
        (New-SnowProperty vendor -Type Bool)
        (New-SnowProperty manufacturer -Type Bool)
    )
    New-SnowClass -Name Department -Table cmn_department -Display name -Operations Insert, Update, Delete -Properties @(
        (New-SnowProperty name -Mandatory)
        (New-SnowProperty id)
        (New-SnowProperty code)
        (New-SnowProperty description)
        (New-SnowProperty head_count -Type Int)
        (New-SnowProperty parent -Reference Department)
        (New-SnowProperty dept_head -Reference User)
        (New-SnowProperty primary_contact -Reference User)
        (New-SnowProperty company -Reference Company)
        (New-SnowProperty cost_center -Reference CostCenter)
    )
    New-SnowClass -Name Location -Table cmn_location -Display name -Operations Insert, Update, Delete -Properties @(
        (New-SnowProperty name -Mandatory)
        (New-SnowProperty full_name -Access Read)
        (New-SnowProperty street)
        (New-SnowProperty city)
        (New-SnowProperty state)
        (New-SnowProperty zip)
        (New-SnowProperty country)
        (New-SnowProperty phone)
        (New-SnowProperty parent -Reference Location)
        (New-SnowProperty company -Reference Company)
        (New-SnowProperty contact -Reference User)
    )
    New-SnowClass -Name CostCenter -Table cmn_cost_center -Display name -Operations Insert, Update, Delete -Properties @(
        (New-SnowProperty name -Mandatory)
        (New-SnowProperty code)
        (New-SnowProperty account_number)
        (New-SnowProperty valid_from -Type DateTime)
        (New-SnowProperty valid_to -Type DateTime)
        (New-SnowProperty parent -Reference CostCenter)
        (New-SnowProperty manager -Reference User)
        (New-SnowProperty location -Reference Location)
    )
    New-SnowClass -Name User -Table sys_user -Display user_name -Operations Insert, Update, Delete -Properties @(
        (New-SnowProperty user_name -Mandatory)
        (New-SnowProperty first_name)
        (New-SnowProperty middle_name)
        (New-SnowProperty last_name)
        (New-SnowProperty name -Access Read)
        (New-SnowProperty email)
        (New-SnowProperty title)
        (New-SnowProperty employee_number)
        (New-SnowProperty phone)
        (New-SnowProperty mobile_phone)
        (New-SnowProperty active -Type Bool)
        (New-SnowProperty locked_out -Type Bool)
        (New-SnowProperty web_service_access_only -Type Bool)
        (New-SnowProperty last_login_time -Type DateTime -Access Read)
        (New-SnowProperty department -Reference Department)
        (New-SnowProperty company -Reference Company)
        (New-SnowProperty location -Reference Location)
        (New-SnowProperty cost_center -Reference CostCenter)
        (New-SnowProperty manager -Reference User)
    )
    New-SnowClass -Name Group -Table sys_user_group -Display name -Operations Insert, Update, Delete -Properties @(
        (New-SnowProperty name -Mandatory)
        (New-SnowProperty description)
        (New-SnowProperty email)
        (New-SnowProperty active -Type Bool)
        (New-SnowProperty manager -Reference User)
        (New-SnowProperty parent -Reference Group)
        (New-SnowProperty cost_center -Reference CostCenter)
    )
    # membership row: created and deleted, never updated
    New-SnowClass -Name GroupMember -Table sys_user_grmember -Display sys_id -Operations Insert, Delete -Properties @(
        (New-SnowProperty user -Access InsertOnly -Mandatory -Reference User)
        (New-SnowProperty group -Access InsertOnly -Mandatory -Reference Group)
    )
    New-SnowClass -Name Role -Table sys_user_role -Display name -Properties @(
        (New-SnowProperty name -Access Read)
        (New-SnowProperty description -Access Read)
        (New-SnowProperty suffix -Access Read)
        (New-SnowProperty elevated_privilege -Type Bool -Access Read)
    )
    # direct role assignments only: inherited rows are managed by ServiceNow and cannot be deleted
    New-SnowClass -Name UserRole -Table sys_user_has_role -Display sys_id -Operations Insert, Delete -Query 'inherited=false' -Properties @(
        (New-SnowProperty user -Access InsertOnly -Mandatory -Reference User)
        (New-SnowProperty role -Access InsertOnly -Mandatory -Reference Role)
        (New-SnowProperty state -Access Read)
        (New-SnowProperty inherited -Type Bool -Access Read)
    )
)

#endregion

#region internal helpers

function Get-SnowClass
{
    param([Parameter(Mandatory = $true)][string]$Class)
    $definition = $script:Classes | Where-Object { $_.Name -eq $Class }
    if (-not $definition) { throw "Unknown class '$Class'. Known classes: $(($script:Classes | ForEach-Object { $_.Name }) -join ', ')" }
    $definition
}

function Get-SnowSession
{
    if ($null -eq $script:Session) { throw "ServiceNow session not connected: Connect-OneIMConnectorSession must run first" }
    $script:Session
}

function ConvertTo-SnowPlainText
{
    param([Parameter(Mandatory = $true)][SecureString]$SecureString)
    # ConvertFrom-SecureString -AsPlainText is PowerShell 7 only; BSTR decoding works on 5.1 too
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function ConvertFrom-SnowOptions
{
    param([string]$Options)
    $result = [ordered]@{}
    foreach ($name in $script:OptionDefaults.Keys) { $result[$name] = $script:OptionDefaults[$name] }
    if ([string]::IsNullOrWhiteSpace($Options)) { return $result }

    foreach ($pair in ($Options -split ';'))
    {
        if ([string]::IsNullOrWhiteSpace($pair)) { continue }
        if ($pair -notmatch '^\s*([A-Za-z]+)\s*=\s*(.*?)\s*$') { throw "Options: '$pair' is not in the form Name=Value" }
        $name = @($script:OptionDefaults.Keys | Where-Object { $_ -eq $Matches[1] })
        $value = $Matches[2]
        if ($name.Count -eq 0) { throw "Options: unknown option '$($Matches[1])'. Allowed: $($script:OptionDefaults.Keys -join ', ')" }
        $name = $name[0]
        if ($script:OptionRanges.ContainsKey($name))
        {
            $number = 0
            $range = $script:OptionRanges[$name]
            if (-not [int]::TryParse($value, [ref]$number) -or $number -lt $range[0] -or $number -gt $range[1])
            {
                throw "Options: $name must be an integer between $($range[0]) and $($range[1]) (got '$value')"
            }
            $result[$name] = $number
        }
        else { $result[$name] = $value }
    }
    if ($script:SupportedAuthTypes -notcontains $result.AuthType)
    {
        throw "Options: AuthType '$($result.AuthType)' is not supported by module $script:ModuleVersion. Supported: $($script:SupportedAuthTypes -join ', ')"
    }
    $result
}

function Resolve-SnowInstanceUrl
{
    # Accepts "myinstance", "myinstance.service-now.com" or "https://host". http only for loopback (offline tests)
    param([string]$InstanceUrl)
    if ([string]::IsNullOrWhiteSpace($InstanceUrl)) { throw "InstanceUrl is mandatory: instance name, host or https URL of the ServiceNow instance" }
    $value = $InstanceUrl.Trim().TrimEnd('/')
    if ($value -notmatch '^[A-Za-z][A-Za-z0-9+.-]*://')
    {
        if ($value -notmatch '\.') { $value = "$value.service-now.com" }
        $value = "https://$value"
    }
    $uri = $null
    if (-not [uri]::TryCreate($value, [UriKind]::Absolute, [ref]$uri)) { throw "InstanceUrl '$InstanceUrl' is not a valid instance name or URL" }
    if ($uri.Scheme -ne 'https' -and -not ($uri.Scheme -eq 'http' -and $uri.IsLoopback)) { throw "InstanceUrl must use https (got '$($uri.Scheme)')" }
    if ($uri.AbsolutePath -ne '/' -or $uri.Query) { throw "InstanceUrl must be the instance root, without path or query (got '$InstanceUrl')" }
    "$($uri.Scheme)://$($uri.Authority)"
}

function Get-SnowErrorBody
{
    # Error body on both engines: ErrorDetails.Message (always on 7; on 5.1 only with Content-Length),
    # else the response stream (5.1 only: HttpResponseMessage on 7 has no GetResponseStream)
    param([Parameter(Mandatory = $true)][Management.Automation.ErrorRecord]$ErrorRecord, [object]$Response)
    if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) { return $ErrorRecord.ErrorDetails.Message }
    if ($null -eq $Response -or -not $Response.PSObject.Methods['GetResponseStream']) { return $null }
    $reader = $null
    try { $reader = New-Object IO.StreamReader($Response.GetResponseStream()); $reader.ReadToEnd() }
    catch { Write-Verbose "Error body not readable: $($_.Exception.Message)" }
    finally { if ($null -ne $reader) { $reader.Dispose() } }
}

function Invoke-SnowRequest
{
    param(
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][string]$Uri,
        [System.Collections.IDictionary]$Body
    )
    $session = Get-SnowSession
    $params = @{
        Method = $Method; Uri = $Uri; Headers = $session.Headers; TimeoutSec = $session.Options.TimeoutSec
        ContentType = 'application/json; charset=utf-8'
        UseBasicParsing = $true   # 5.1: no Internet Explorer engine in service context
    }
    # 5.1 encodes string bodies as ISO-8859-1: send UTF-8 bytes so accented characters survive
    if ($null -ne $Body) { $params.Body = [Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 5 -Compress)) }

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
            # 5.1: WebException (HttpWebResponse); 7: HttpResponseException (HttpResponseMessage); none on DNS/timeout
            $response = $null
            if ($_.Exception.PSObject.Properties['Response']) { $response = $_.Exception.Response }
            $status = $null
            if ($null -ne $response -and $null -ne $response.StatusCode) { $status = [int]$response.StatusCode }
            # 429 = not processed, safe to repeat. 5xx only for idempotent methods: a POST may have created the
            # record before failing, and repeating it would create a duplicate
            $retryable = ($status -eq 429) -or ($status -ge 500 -and $Method -ne 'POST')
            if ($retryable -and $attempt -le $session.Options.MaxRetries)
            {
                $wait = [math]::Pow(2, $attempt)
                Write-Warning "ServiceNow returned HTTP $status, retrying in $wait s"
                Start-Sleep -Seconds $wait
                continue
            }
            $statusText = 'no HTTP response'
            if ($null -ne $status) { $statusText = "HTTP $status" }
            # not $body: variables are case-insensitive, it would be the typed $Body parameter
            $errorBody = Get-SnowErrorBody -ErrorRecord $_ -Response $response
            $exception = New-Object Exception("ServiceNow request failed ($Method $Uri) ${statusText}: $errorBody $($_.Exception.Message)")
            $exception.Data['HttpStatus'] = $status
            throw $exception
        }
    }
}

function ConvertFrom-SnowValue
{
    # Table API value (always a string) -> typed value; empty -> $null; date/times are UTC
    param([object]$Value, [Parameter(Mandatory = $true)][string]$Type)
    if ($null -eq $Value -or "$Value" -eq '') { return $null }
    switch ($Type)
    {
        'Int'      { $number = 0; if ([int]::TryParse("$Value", [ref]$number)) { return $number }; Write-Warning "Not an integer: '$Value'"; return $null }
        'Bool'     { return ("$Value" -eq 'true') }
        'DateTime' { return [datetime]::SpecifyKind([datetime]::ParseExact("$Value", $script:SnowDateTimeFormat, [cultureinfo]::InvariantCulture), [DateTimeKind]::Utc) }
        default    { return "$Value" }
    }
}

function ConvertTo-SnowFieldValue
{
    # typed value -> Table API string; $null clears the field
    param([object]$Value, [Parameter(Mandatory = $true)][string]$Type)
    if ($null -eq $Value) { return '' }
    switch ($Type)
    {
        'Bool'
        {
            if ($Value -is [string]) { return $Value.ToLowerInvariant() }
            return ([bool]$Value).ToString().ToLowerInvariant()
        }
        'DateTime'
        {
            $date = [datetime]$Value
            if ($date.Kind -eq [DateTimeKind]::Local) { $date = $date.ToUniversalTime() }
            return $date.ToString($script:SnowDateTimeFormat, [cultureinfo]::InvariantCulture)
        }
        default { return [string]::Format([cultureinfo]::InvariantCulture, '{0}', $Value) }
    }
}

function ConvertTo-SnowObject
{
    # flat object with every property of the class, typed; missing field -> $null
    param([Parameter(Mandatory = $true)][PSObject]$Record, [Parameter(Mandatory = $true)][PSObject]$Definition)
    $result = [ordered]@{}
    foreach ($property in $Definition.Properties)
    {
        $value = $null
        if ($Record.PSObject.Properties[$property.Name]) { $value = ConvertFrom-SnowValue -Value $Record.($property.Name) -Type $property.Type }
        $result[$property.Name] = $value
    }
    [PSCustomObject]$result
}

function ConvertTo-SnowBody
{
    # only the passed values are sent; the key is ignored; read-only fields are rejected
    param([System.Collections.IDictionary]$Values, [Parameter(Mandatory = $true)][PSObject]$Definition, [ValidateSet('Insert', 'Update')][string]$Mode)
    $body = @{}
    if ($null -eq $Values) { return $body }
    foreach ($name in @($Values.Keys))
    {
        if ($name -eq $Definition.Key) { continue }
        $property = $Definition.Properties | Where-Object { $_.Name -eq $name }
        if (-not $property) { throw "$($Definition.Name): unknown property '$name'" }
        $writable = ($property.Access -eq 'ReadWrite') -or ($property.Access -eq 'InsertOnly' -and $Mode -eq 'Insert')
        if (-not $writable) { throw "$($Definition.Name): property '$name' is $($property.Access), it cannot be written on $Mode" }
        $body[$name] = ConvertTo-SnowFieldValue -Value $Values[$name] -Type $property.Type
    }
    $body
}

function Assert-SnowKey
{
    param([string]$Key, [Parameter(Mandatory = $true)][PSObject]$Definition)
    if ($Key -notmatch $script:SysIdPattern) { throw "$($Definition.Name): '$Key' is not a valid sys_id (32 hexadecimal characters)" }
}

function Get-SnowTableUri
{
    param([Parameter(Mandatory = $true)][PSObject]$Definition, [string]$Key)
    $uri = "$((Get-SnowSession).BaseUrl)/api/now/table/$($Definition.Table)"
    if ($Key) { $uri = "$uri/$Key" }
    $uri
}

function Remove-SnowCacheEntry
{
    param([Parameter(Mandatory = $true)][string]$Class, [Parameter(Mandatory = $true)][string]$Key)
    $entry = (Get-SnowSession).Cache[$Class]
    if ($null -ne $entry) { $entry.Items.Remove($Key) }
}

function Get-SnowCachedObject
{
    # objects of the last full listing, reused when the engine reloads them one by one right after the listing
    param([Parameter(Mandatory = $true)][string]$Class, [Parameter(Mandatory = $true)][string]$Key)
    $session = Get-SnowSession
    $entry = $session.Cache[$Class]
    if ($null -eq $entry) { return $null }
    if (([datetime]::UtcNow - $entry.Loaded).TotalSeconds -ge $session.Options.CacheSeconds) { $session.Cache.Remove($Class); return $null }
    if ($entry.Items.ContainsKey($Key)) { return $entry.Items[$Key] }
    $null
}

#endregion

#region contract v1 (exported)

function Get-OneIMConnectorManifest
{
    $classes = foreach ($definition in $script:Classes)
    {
        [PSCustomObject]@{
            Name = $definition.Name; Key = $definition.Key; Display = $definition.Display; Revision = $definition.Revision
            Operations = @($definition.Operations)
            Properties = @($definition.Properties | ForEach-Object {
                    [PSCustomObject]@{ Name = $_.Name; Type = $_.Type; Access = $_.Access; Mandatory = $_.Mandatory; Reference = $_.Reference } })
        }
    }
    [PSCustomObject]@{
        ContractVersion = $script:ContractVersion
        Id              = 'ServiceNow'
        Version         = $script:ModuleVersion
        Description     = 'ServiceNow Table API (module layout, contract v1)'
        Classes         = @($classes)
    }
}

function Connect-OneIMConnectorSession
{
    param([string]$InstanceUrl, [string]$Username, [SecureString]$Password, [string]$Options)

    $parsedOptions = ConvertFrom-SnowOptions -Options $Options
    $baseUrl = Resolve-SnowInstanceUrl -InstanceUrl $InstanceUrl
    if ([string]::IsNullOrWhiteSpace($Username)) { throw "Username is mandatory for AuthType Basic" }
    if ($null -eq $Password -or $Password.Length -eq 0) { throw "Password is mandatory for AuthType Basic" }

    # Windows PowerShell 5.1 (.NET Framework) may not offer TLS 1.2 by default; ServiceNow requires it
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $plain = ConvertTo-SnowPlainText -SecureString $Password
    $token = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${Username}:$plain"))
    $plain = $null
    $script:Session = @{
        BaseUrl = $baseUrl; Options = $parsedOptions; Cache = @{}
        Headers = @{ Authorization = "Basic $token"; Accept = 'application/json' }
    }
    try
    {
        # connection test: read one key of the first class
        $first = $script:Classes[0]
        $null = Invoke-SnowRequest -Method GET -Uri "$(Get-SnowTableUri -Definition $first)?sysparm_limit=1&sysparm_fields=$($first.Key)"
    }
    catch
    {
        $script:Session = $null
        throw
    }
    $optionText = ($parsedOptions.Keys | ForEach-Object { "$_=$($parsedOptions[$_])" }) -join ';'
    Write-Host "Connected to ServiceNow $baseUrl as $Username (module $script:ModuleVersion, $optionText, PowerShell $($PSVersionTable.PSVersion))"
}

function Disconnect-OneIMConnectorSession
{
    $script:Session = $null
    Write-Host "ServiceNow session closed"
}

function Get-OneIMConnectorObject
{
    # without -Key: every object of the class (paged); with -Key: one object, error if missing
    param([Parameter(Mandatory = $true)][string]$Class, [string]$Key)
    $definition = Get-SnowClass -Class $Class
    $session = Get-SnowSession
    $fields = ($definition.Properties | ForEach-Object { $_.Name }) -join ','
    $select = "sysparm_fields=$fields&sysparm_exclude_reference_link=true&sysparm_display_value=false"

    if ($Key)
    {
        Assert-SnowKey -Key $Key -Definition $definition
        $cached = Get-SnowCachedObject -Class $Class -Key $Key
        if ($null -ne $cached) { Write-Verbose "$Class $Key from listing cache"; return $cached }
        Write-Host "Loading $Class $Key"
        $response = Invoke-SnowRequest -Method GET -Uri "$(Get-SnowTableUri -Definition $definition -Key $Key)?$select"
        return ConvertTo-SnowObject -Record $response.result -Definition $definition
    }

    $pageSize = $session.Options.PageSize
    Write-Host "Loading $Class from $($definition.Table) (page size $pageSize)"
    # stable ordering is required for consistent offset paging
    $query = 'ORDERBYsys_id'
    if ($definition.Query) { $query = "$($definition.Query)^$query" }
    $items = @{}
    $offset = 0
    do
    {
        $uri = "$(Get-SnowTableUri -Definition $definition)?$select&sysparm_limit=$pageSize&sysparm_offset=$offset&sysparm_query=$([uri]::EscapeDataString($query))"
        $records = @((Invoke-SnowRequest -Method GET -Uri $uri).result)
        foreach ($record in $records)
        {
            $object = ConvertTo-SnowObject -Record $record -Definition $definition
            $items[$object.($definition.Key)] = $object
            $object
        }
        $offset += $pageSize
    } while ($records.Count -eq $pageSize)
    if ($session.Options.CacheSeconds -gt 0) { $session.Cache[$Class] = @{ Loaded = [datetime]::UtcNow; Items = $items } }
}

function New-OneIMConnectorObject
{
    param([Parameter(Mandatory = $true)][string]$Class, [System.Collections.IDictionary]$Values)
    $definition = Get-SnowClass -Class $Class
    if ($definition.Operations -notcontains 'Insert') { throw "$Class does not support Insert" }
    $body = ConvertTo-SnowBody -Values $Values -Definition $definition -Mode Insert
    $missing = @($definition.Properties | Where-Object { $_.Mandatory -and [string]::IsNullOrEmpty($body[$_.Name]) } | ForEach-Object { $_.Name })
    if ($missing.Count) { throw "${Class}: mandatory properties missing for Insert: $($missing -join ', ')" }
    Write-Host "Creating $Class ($($body.Keys -join ', '))"
    $response = Invoke-SnowRequest -Method POST -Uri "$(Get-SnowTableUri -Definition $definition)?sysparm_exclude_reference_link=true" -Body $body
    ConvertTo-SnowObject -Record $response.result -Definition $definition
}

function Set-OneIMConnectorObject
{
    param([Parameter(Mandatory = $true)][string]$Class, [string]$Key, [System.Collections.IDictionary]$Values)
    $definition = Get-SnowClass -Class $Class
    if ($definition.Operations -notcontains 'Update') { throw "$Class does not support Update" }
    Assert-SnowKey -Key $Key -Definition $definition
    $body = ConvertTo-SnowBody -Values $Values -Definition $definition -Mode Update
    if ($body.Count -eq 0) { Write-Host "Nothing to update for $Class $Key"; return }
    Write-Host "Updating $Class $Key ($($body.Keys -join ', '))"
    Remove-SnowCacheEntry -Class $Class -Key $Key
    # PATCH = partial update
    $null = Invoke-SnowRequest -Method PATCH -Uri "$(Get-SnowTableUri -Definition $definition -Key $Key)?sysparm_exclude_reference_link=true" -Body $body
}

function Remove-OneIMConnectorObject
{
    param([Parameter(Mandatory = $true)][string]$Class, [string]$Key)
    $definition = Get-SnowClass -Class $Class
    if ($definition.Operations -notcontains 'Delete') { throw "$Class does not support Delete" }
    Assert-SnowKey -Key $Key -Definition $definition
    Write-Host "Deleting $Class $Key"
    Remove-SnowCacheEntry -Class $Class -Key $Key
    try { $null = Invoke-SnowRequest -Method DELETE -Uri (Get-SnowTableUri -Definition $definition -Key $Key) }
    catch
    {
        # already gone = success
        if ($_.Exception.Data['HttpStatus'] -eq 404) { Write-Warning "$Class $Key not found, treated as deleted"; return }
        throw
    }
}

#endregion

Export-ModuleMember -Function Get-OneIMConnectorManifest, Connect-OneIMConnectorSession, Disconnect-OneIMConnectorSession,
    Get-OneIMConnectorObject, New-OneIMConnectorObject, Set-OneIMConnectorObject, Remove-OneIMConnectorObject
