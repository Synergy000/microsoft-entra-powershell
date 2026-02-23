<#
.SYNOPSIS
    Adds users to Entra groups as defined in data/input/members.csv.
    Idempotent: skips users who are already members.

.PARAMETER Environment   Environment label shown in logs (Test | Prod).
.PARAMETER TenantId      Entra tenant ID.
.PARAMETER ClientId      Service principal client ID.
.PARAMETER ClientSecret  Service principal client secret.
.PARAMETER LogFile       Path to the log file for this run.
#>
param (
    [Parameter(Mandatory)] [string]$Environment,
    [Parameter(Mandatory)] [string]$TenantId,
    [Parameter(Mandatory)] [string]$ClientId,
    [Parameter(Mandatory)] [string]$ClientSecret,
    [Parameter(Mandatory)] [string]$LogFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/../common/Connect-EntraTenant.ps1"
. "$PSScriptRoot/../common/Write-Log.ps1"

# Load shared config (CSV path, etc.)
$config  = Import-PowerShellDataFile (Join-Path $PSScriptRoot '../../config/pipeline.psd1')
$csvPath = $config.MembersCsv

# Validate the CSV before connecting
if (-not (Test-Path $csvPath)) {
    Write-Log "CSV not found: $csvPath" -Level ERROR -LogFile $LogFile; exit 1
}
$rows = @(Import-Csv $csvPath)
if ($rows.Count -eq 0) {
    Write-Log 'CSV has no data rows. Nothing to do.' -LogFile $LogFile; exit 0
}

Connect-EntraTenant -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
Write-Log "[$Environment] Processing '$csvPath' ($($rows.Count) rows)..." -LogFile $LogFile

# Caches — avoids repeated Graph API calls for the same group
$groupIdCache  = @{}   # GroupDisplayName → GroupId
$memberIdCache = @{}   # GroupId          → array of member ObjectIds

$added = 0; $skipped = 0; $failed = 0

foreach ($row in $rows) {
    try {
        # Resolve group (cached)
        if (-not $groupIdCache.ContainsKey($row.GroupDisplayName)) {
            $safeName = $row.GroupDisplayName.Replace("'", "''")
            $g = Get-EntraGroup -Filter "DisplayName eq '$safeName'" | Select-Object -First 1
            if (-not $g) { throw "Group '$($row.GroupDisplayName)' not found" }

            $groupIdCache[$row.GroupDisplayName] = $g.Id
            $memberIdCache[$g.Id] = @(Get-EntraGroupMember -GroupId $g.Id -All).Id
        }
        $gid = $groupIdCache[$row.GroupDisplayName]

        # Resolve user
        $safeUPN = $row.UserPrincipalName.Replace("'", "''")
        $user = Get-EntraUser -Filter "UserPrincipalName eq '$safeUPN'" | Select-Object -First 1
        if (-not $user) { throw "User '$($row.UserPrincipalName)' not found" }

        # Skip if already a member
        if ($user.Id -in $memberIdCache[$gid]) {
            Write-Log "SKIP    | $($row.UserPrincipalName) already in '$($row.GroupDisplayName)'" -LogFile $LogFile
            $skipped++; continue
        }

        Add-EntraGroupMember -GroupId $gid -RefObjectId $user.Id
        $memberIdCache[$gid] += $user.Id   # keep cache current for this run

        Write-Log "ADDED   | $($row.UserPrincipalName) → $($row.GroupDisplayName)" -LogFile $LogFile
        $added++
    }
    catch {
        Write-Log "FAILED  | $($row.UserPrincipalName) → $($row.GroupDisplayName) | $_" -Level ERROR -LogFile $LogFile
        $failed++
    }
}

Write-Log "Done — Added: $added | Skipped: $skipped | Failed: $failed" -LogFile $LogFile
if ($failed -gt 0) { exit 1 }
