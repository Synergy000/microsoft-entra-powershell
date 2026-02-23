<#
.SYNOPSIS
    Writes a timestamped log entry to the console and optionally to a log file.

.PARAMETER Message
    The message to log.

.PARAMETER Level
    Log level: INFO, WARN, ERROR. Defaults to INFO.

.PARAMETER LogFile
    Optional. Path to the log file. Directory will be created if it does not exist.
#>
function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO',

        [string]$LogFile
    )

    $Timestamp   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $PaddedLevel = $Level.PadRight(5)   # INFO  / WARN  / ERROR  → aligned columns
    $Entry       = "[$Timestamp] [$PaddedLevel] $Message"

    switch ($Level) {
        'ERROR' { Write-Host $Entry -ForegroundColor Red    }
        'WARN'  { Write-Host $Entry -ForegroundColor Yellow }
        default { Write-Host $Entry }
    }

    if ($LogFile) {
        $LogDir = Split-Path -Path $LogFile -Parent
        if ($LogDir -and -not (Test-Path -Path $LogDir)) {
            New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
        }
        Add-Content -Path $LogFile -Value $Entry -Encoding UTF8
    }
}
