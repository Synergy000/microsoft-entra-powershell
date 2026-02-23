<#
.SYNOPSIS
    Creates Entra security groups defined in data/input/groups.csv.
    Idempotent: skips groups that already exist.

.PARAMETER Environment   Environment label shown in logs (Test | Prod).
.PARAMETER TenantId      Entra tenant ID.
.PARAMETER ClientId      Service principal client ID.
.PARAMETER FederatedToken OIDC token from the GitHub Actions identity provider.
.PARAMETER LogFile        Path to the log file for this run.
#>
param (
    [Parameter(Mandatory)] [string]$Environment,
    [Parameter(Mandatory)] [string]$TenantId,
    [Parameter(Mandatory)] [string]$ClientId,
    [Parameter(Mandatory)] [string]$FederatedToken,
    [Parameter(Mandatory)] [string]$LogFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/../common/Connect-EntraTenant.ps1"
. "$PSScriptRoot/../common/Write-Log.ps1"

# Load shared config (CSV path, etc.)
$config  = Import-PowerShellDataFile (Join-Path $PSScriptRoot '../../config/pipeline.psd1')
$csvPath = $config.GroupsCsv

# Validate the CSV before connecting
if (-not (Test-Path $csvPath)) {
    Write-Log "CSV not found: $csvPath" -Level ERROR -LogFile $LogFile; exit 1
}
$rows = @(Import-Csv $csvPath)
if ($rows.Count -eq 0) {
    Write-Log 'CSV has no data rows. Nothing to do.' -LogFile $LogFile; exit 0
}

Connect-EntraTenant -TenantId $TenantId -ClientId $ClientId -FederatedToken $FederatedToken
Write-Log "[$Environment] Processing '$csvPath' ($($rows.Count) rows)..." -LogFile $LogFile

$created = 0; $skipped = 0; $failed = 0

foreach ($row in $rows) {
    try {
        # Check if the group already exists (idempotency)
        $safeName = $row.DisplayName.Replace("'", "''")
        $existing = Get-EntraGroup -Filter "DisplayName eq '$safeName'" | Select-Object -First 1

        if ($existing) {
            Write-Log "SKIP    | $($row.DisplayName) — already exists" -LogFile $LogFile
            $skipped++; continue
        }

        New-EntraGroup `
            -DisplayName     $row.DisplayName `
            -MailEnabled     $false `
            -SecurityEnabled $true `
            -MailNickname    $row.MailNickname `
            -Description     $row.Description | Out-Null

        Write-Log "CREATED | $($row.DisplayName)" -LogFile $LogFile
        $created++
    }
    catch {
        Write-Log "FAILED  | $($row.DisplayName) | $_" -Level ERROR -LogFile $LogFile
        $failed++
    }
}

Write-Log "Done — Created: $created | Skipped: $skipped | Failed: $failed" -LogFile $LogFile
if ($failed -gt 0) { exit 1 }
