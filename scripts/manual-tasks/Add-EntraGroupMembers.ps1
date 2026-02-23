<#
.SYNOPSIS
    Adds users to Entra security groups from a CSV file (idempotent — skips existing members).

.PARAMETER Environment   Target environment label (Test | Prod).
.PARAMETER TenantId      Entra tenant ID.
.PARAMETER ClientId      Service principal client ID.
.PARAMETER ClientSecret  Service principal client secret.
.PARAMETER CsvPath       CSV with columns: GroupDisplayName, UserPrincipalName
.PARAMETER LogFile       Log file path. Convention: add-members_{env}_run{n}.log
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)] [string]$Environment,
    [Parameter(Mandatory)] [string]$TenantId,
    [Parameter(Mandatory)] [string]$ClientId,
    [Parameter(Mandatory)] [string]$ClientSecret,
    [Parameter(Mandatory)] [string]$CsvPath,
    [Parameter(Mandatory)] [string]$LogFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/../common/Connect-EntraTenant.ps1"
. "$PSScriptRoot/../common/Write-Log.ps1"

# ── Validate CSV ──────────────────────────────────────────────────────────────
if (-not (Test-Path -Path $CsvPath)) {
    Write-Log "CSV file not found: '$CsvPath'" -Level ERROR -LogFile $LogFile
    exit 1
}

$rows = Import-Csv -Path $CsvPath

if ($rows.Count -eq 0) {
    Write-Log "CSV '$CsvPath' contains no data rows. Nothing to do." -LogFile $LogFile
    exit 0
}

$requiredColumns = @('GroupDisplayName', 'UserPrincipalName')
$csvColumns      = $rows[0].PSObject.Properties.Name
$missingColumns  = $requiredColumns | Where-Object { $_ -notin $csvColumns }

if ($missingColumns) {
    Write-Log "CSV is missing required column(s): $($missingColumns -join ', ')" -Level ERROR -LogFile $LogFile
    exit 1
}

# ── Connect ───────────────────────────────────────────────────────────────────
Connect-EntraTenant -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
Write-Log "[$Environment] Connected. Processing '$CsvPath' ($($rows.Count) row(s))..." -LogFile $LogFile

# ── Caches ────────────────────────────────────────────────────────────────────
# GroupDisplayName → GroupId  (avoids repeated Graph lookups for the same group)
$groupCache = @{}

# GroupId → HashSet<string> of member ObjectIds  (O(1) duplicate detection)
$memberCache = @{}

$ok = 0; $skip = 0; $fail = 0

# ── Process rows ──────────────────────────────────────────────────────────────
foreach ($row in $rows) {
    try {
        # ── Resolve group (cached) ────────────────────────────────────────────
        if (-not $groupCache.ContainsKey($row.GroupDisplayName)) {
            $escapedGroup = $row.GroupDisplayName.Replace("'", "''")
            $g = Get-EntraGroup -Filter "DisplayName eq '$escapedGroup'" |
                     Select-Object -First 1
            if (-not $g) { throw "Group '$($row.GroupDisplayName)' not found." }
            $groupCache[$row.GroupDisplayName] = $g.Id
        }
        $groupId = $groupCache[$row.GroupDisplayName]

        # ── Load membership into HashSet on first encounter of this group ─────
        if (-not $memberCache.ContainsKey($groupId)) {
            $set = [System.Collections.Generic.HashSet[string]]::new(
                       [System.StringComparer]::OrdinalIgnoreCase)
            @(Get-EntraGroupMember -GroupId $groupId -All).Id |
                ForEach-Object { $set.Add($_) | Out-Null }
            $memberCache[$groupId] = $set
        }

        # ── Resolve user ──────────────────────────────────────────────────────
        $escapedUPN = $row.UserPrincipalName.Replace("'", "''")
        $user = Get-EntraUser -Filter "UserPrincipalName eq '$escapedUPN'" |
                    Select-Object -First 1
        if (-not $user) { throw "User '$($row.UserPrincipalName)' not found." }

        # ── Skip if already a member ──────────────────────────────────────────
        if ($memberCache[$groupId].Contains($user.Id)) {
            Write-Log "SKIP    | $($row.UserPrincipalName) already a member of '$($row.GroupDisplayName)'" -LogFile $LogFile
            $skip++
            continue
        }

        Add-EntraGroupMember -GroupId $groupId -RefObjectId $user.Id
        $memberCache[$groupId].Add($user.Id) | Out-Null   # keep cache current

        Write-Log "ADDED   | $($row.UserPrincipalName) → $($row.GroupDisplayName)" -LogFile $LogFile
        $ok++
    }
    catch {
        Write-Log "FAILED  | $($row.UserPrincipalName) → $($row.GroupDisplayName) | $_" -Level ERROR -LogFile $LogFile
        $fail++
    }
}

Write-Log "Summary | Added: $ok | Skipped: $skip | Failed: $fail" -LogFile $LogFile
if ($fail -gt 0) { exit 1 }
