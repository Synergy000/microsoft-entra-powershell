<#
.SYNOPSIS
    Creates Entra security groups from a CSV file (idempotent — skips existing groups).

.PARAMETER Environment   Target environment label (Test | Prod).
.PARAMETER TenantId      Entra tenant ID.
.PARAMETER ClientId      Service principal client ID.
.PARAMETER ClientSecret  Service principal client secret.
.PARAMETER CsvPath       CSV with columns: DisplayName, MailNickname, Description
.PARAMETER LogFile       Log file path. Convention: create-groups_{env}_run{n}.log
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

$requiredColumns = @('DisplayName', 'MailNickname', 'Description')
$csvColumns      = $rows[0].PSObject.Properties.Name
$missingColumns  = $requiredColumns | Where-Object { $_ -notin $csvColumns }

if ($missingColumns) {
    Write-Log "CSV is missing required column(s): $($missingColumns -join ', ')" -Level ERROR -LogFile $LogFile
    exit 1
}

# ── Connect ───────────────────────────────────────────────────────────────────
Connect-EntraTenant -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
Write-Log "[$Environment] Connected. Processing '$CsvPath' ($($rows.Count) row(s))..." -LogFile $LogFile

# ── Process rows ──────────────────────────────────────────────────────────────
$ok = 0; $skip = 0; $fail = 0

foreach ($row in $rows) {
    try {
        # Escape single quotes in OData filter values
        $escapedName = $row.DisplayName.Replace("'", "''")
        $existing    = Get-EntraGroup -Filter "DisplayName eq '$escapedName'" |
                           Select-Object -First 1

        if ($existing) {
            Write-Log "SKIP    | $($row.DisplayName) — group already exists" -LogFile $LogFile
            $skip++
            continue
        }

        New-EntraGroup `
            -DisplayName     $row.DisplayName `
            -MailEnabled     $false `
            -SecurityEnabled $true `
            -MailNickname    $row.MailNickname `
            -Description     $row.Description | Out-Null

        Write-Log "CREATED | $($row.DisplayName)" -LogFile $LogFile
        $ok++
    }
    catch {
        Write-Log "FAILED  | $($row.DisplayName) | $_" -Level ERROR -LogFile $LogFile
        $fail++
    }
}

Write-Log "Summary | Created: $ok | Skipped: $skip | Failed: $fail" -LogFile $LogFile
if ($fail -gt 0) { exit 1 }
