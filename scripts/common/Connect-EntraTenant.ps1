<#
.SYNOPSIS
    Connects to a Microsoft Entra tenant using a service principal (client secret).

.PARAMETER TenantId
    The Azure AD / Entra tenant ID.

.PARAMETER ClientId
    The service principal (app registration) client ID.

.PARAMETER ClientSecret
    The service principal client secret.
#>
function Connect-EntraTenant {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$TenantId,

        [Parameter(Mandatory = $true)]
        [string]$ClientId,

        [Parameter(Mandatory = $true)]
        [string]$ClientSecret
    )

    try {
        $SecureSecret = ConvertTo-SecureString -String $ClientSecret -AsPlainText -Force
        $Credential   = New-Object -TypeName System.Management.Automation.PSCredential `
                                   -ArgumentList $ClientId, $SecureSecret

        Connect-Entra -TenantId $TenantId -ClientSecretCredential $Credential `
                      -NoWelcome -ErrorAction Stop
    }
    catch {
        throw "Failed to connect to Entra tenant '$TenantId': $_"
    }
}
