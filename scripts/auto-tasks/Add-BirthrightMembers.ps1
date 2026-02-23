<#
.SYNOPSIS
    Adds new joiners (accounts created in the last 24 h) to a birthright group (idempotent).

.PARAMETER Environment   Target environment label (Test | Prod).
.PARAMETER TenantId      Entra tenant ID.
.PARAMETER ClientId      Service principal client ID.
.PARAMETER ClientSecret  Service principal client secret.
.PARAMETER GroupId       Object ID of the target birthright group.
.PARAMETER LogFile       Log file path. Convention: birthright-{group}_{env}_run{n}.log
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)] [string]$Environment,
    [Parameter(Mandatory)] [string]$TenantId,
    [Parameter(Mandatory)] [string]$ClientId,
    [Parameter(Mandatory)] [string]$ClientSecret,
    [Parameter(Mandatory)] [string]$GroupId,
    [Parameter(Mandatory)] [string]$LogFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/../common/Connect-EntraTenant.ps1"
. "$PSScriptRoot/../common/Write-Log.ps1"

# ── Connect ───────────────────────────────────────────────────────────────────
Connect-EntraTenant -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret

$group = Get-EntraGroup -GroupId $GroupId -ErrorAction Stop
Write-Log "[$Environment] Target group: '$($group.DisplayName)' ($GroupId)" -LogFile $LogFile

# ── Query new joiners (last 24 h) ─────────────────────────────────────────────
# Graph OData filter uses ISO 8601 UTC — omit sub-second precision for compatibility
$since    = (Get-Date).ToUniversalTime().AddHours(-24).ToString('yyyy-MM-ddTHH:mm:ssZ')
$newUsers = @(Get-EntraUser -Filter "createdDateTime ge $since" -All)
Write-Log "New joiners since $since UTC: $($newUsers.Count)" -LogFile $LogFile

if ($newUsers.Count -eq 0) {
    Write-Log 'No new joiners found. Nothing to do.' -LogFile $LogFile
    exit 0
}

# ── Load existing membership into a HashSet for O(1) duplicate detection ──────
$existingIds = [System.Collections.Generic.HashSet[string]]::new(
                   [System.StringComparer]::OrdinalIgnoreCase)
@(Get-EntraGroupMember -GroupId $GroupId -All).Id |
    ForEach-Object { $existingIds.Add($_) | Out-Null }

$ok = 0; $skip = 0; $fail = 0

# ── Process new joiners ───────────────────────────────────────────────────────
foreach ($user in $newUsers) {
    try {
        if ($existingIds.Contains($user.Id)) {
            Write-Log "SKIP    | $($user.UserPrincipalName) already a member" -LogFile $LogFile
            $skip++
            continue
        }

        Add-EntraGroupMember -GroupId $GroupId -RefObjectId $user.Id
        $existingIds.Add($user.Id) | Out-Null   # keep set current for this run

        Write-Log "ADDED   | $($user.UserPrincipalName)" -LogFile $LogFile
        $ok++
    }
    catch {
        Write-Log "FAILED  | $($user.UserPrincipalName) | $_" -Level ERROR -LogFile $LogFile
        $fail++
    }
}

Write-Log "Summary | Added: $ok | Skipped: $skip | Failed: $fail" -LogFile $LogFile
if ($fail -gt 0) { exit 1 }
