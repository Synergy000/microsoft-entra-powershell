<#
.SYNOPSIS
    Connects to a Microsoft Entra tenant using a service principal (federated credential / OIDC).

.PARAMETER TenantId
    The Azure AD / Entra tenant ID.

.PARAMETER ClientId
    The service principal (app registration) client ID.

.PARAMETER FederatedToken
    The OIDC token obtained from the GitHub Actions identity provider.
    Used to authenticate without a client secret (workload identity federation).
#>
function Connect-EntraTenant {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$TenantId,

        [Parameter(Mandatory = $true)]
        [string]$ClientId,

        [Parameter(Mandatory = $true)]
        [string]$FederatedToken
    )

    try {
        Connect-Entra -TenantId $TenantId -ClientId $ClientId -ClientAssertion $FederatedToken `
                      -NoWelcome -ErrorAction Stop
    }
    catch {
        throw "Failed to connect to Entra tenant '$TenantId': $_"
    }
}
