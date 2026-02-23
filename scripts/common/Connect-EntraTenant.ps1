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
        # Microsoft.Entra 1.x has no direct federated-token parameter.
        # Exchange the OIDC JWT for an Azure AD access token using the
        # client_credentials grant with a JWT client assertion (federated credential flow),
        # then connect with the resulting access token.
        $tokenResponse = Invoke-RestMethod `
            -Method      Post `
            -Uri         "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
            -ContentType 'application/x-www-form-urlencoded' `
            -Body        @{
                grant_type            = 'client_credentials'
                client_id             = $ClientId
                client_assertion_type = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
                client_assertion      = $FederatedToken
                scope                 = 'https://graph.microsoft.com/.default'
            } `
            -ErrorAction Stop

        $SecureToken = ConvertTo-SecureString -String $tokenResponse.access_token -AsPlainText -Force

        Connect-Entra -AccessToken $SecureToken -TenantId $TenantId `
                      -NoWelcome -ErrorAction Stop
    }
    catch {
        throw "Failed to connect to Entra tenant '$TenantId': $_"
    }
}
