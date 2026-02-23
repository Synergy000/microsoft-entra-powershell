<#
.SYNOPSIS
    Adds new users (created in the last 24 h) to a birthright group.
    Idempotent: skips users who are already members.

.PARAMETER Environment   Environment label shown in logs (Test | Prod).
.PARAMETER TenantId      Entra tenant ID.
.PARAMETER ClientId      Service principal client ID.
.PARAMETER FederatedToken OIDC token from the GitHub Actions identity provider.
.PARAMETER GroupId        Object ID of the target birthright group.
.PARAMETER LogFile        Path to the log file for this run.
#>
param (
    [Parameter(Mandatory)] [string]$Environment,
    [Parameter(Mandatory)] [string]$TenantId,
    [Parameter(Mandatory)] [string]$ClientId,
    [Parameter(Mandatory)] [string]$FederatedToken,
    [Parameter(Mandatory)] [string]$GroupId,
    [Parameter(Mandatory)] [string]$LogFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/../common/Connect-EntraTenant.ps1"
. "$PSScriptRoot/../common/Write-Log.ps1"

Connect-EntraTenant -TenantId $TenantId -ClientId $ClientId -FederatedToken $FederatedToken

$group = Get-EntraGroup -GroupId $GroupId -ErrorAction Stop
Write-Log "[$Environment] Target group: '$($group.DisplayName)'" -LogFile $LogFile

# Find users created in the last 24 hours
# Graph OData filter requires ISO 8601 UTC without sub-second precision
$since    = (Get-Date).ToUniversalTime().AddHours(-24).ToString('yyyy-MM-ddTHH:mm:ssZ')
$newUsers = @(Get-EntraUser -Filter "createdDateTime ge $since" -All)
Write-Log "New users since ${since}: $($newUsers.Count)" -LogFile $LogFile

if ($newUsers.Count -eq 0) {
    Write-Log 'No new users found. Nothing to do.' -LogFile $LogFile; exit 0
}

# Load current members once to detect duplicates
$currentMembers = @(Get-EntraGroupMember -GroupId $GroupId -All).Id

$added = 0; $skipped = 0; $failed = 0

foreach ($user in $newUsers) {
    try {
        if ($user.Id -in $currentMembers) {
            Write-Log "SKIP    | $($user.UserPrincipalName) already a member" -LogFile $LogFile
            $skipped++; continue
        }

        Add-EntraGroupMember -GroupId $GroupId -RefObjectId $user.Id
        $currentMembers += $user.Id   # keep list current for this run

        Write-Log "ADDED   | $($user.UserPrincipalName)" -LogFile $LogFile
        $added++
    }
    catch {
        Write-Log "FAILED  | $($user.UserPrincipalName) | $_" -Level ERROR -LogFile $LogFile
        $failed++
    }
}

Write-Log "Done — Added: $added | Skipped: $skipped | Failed: $failed" -LogFile $LogFile
if ($failed -gt 0) { exit 1 }
