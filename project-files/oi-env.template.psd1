# Environment settings read by tools/Get-OiEnv.ps1. Never put secrets here.
@{
    Oim = @{
        AppServer        = ''      # Application Server URL
        AcceptSelfSigned = $false
        SecretName       = ''      # SecretManagement entry with the OIM credential
        ProductPath      = ''      # Identity Manager installation folder
    }
    Sql = @{
        Server                 = ''
        Database               = ''
        User                   = '' # read-only login; password in environment variable OIM_SQL_RO_PWD
        TrustServerCertificate = $false
    }
}
