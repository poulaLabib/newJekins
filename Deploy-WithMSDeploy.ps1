[CmdletBinding()]
param(
    [string]$binariesPath = "C:\MedicaPlus\TobeTransfered",
    [string]$siteName     = "Default Web Site",
    [string]$physicalPath = "C:\MedicaPlus",
    [string]$appcmd       = "$env:windir\system32\inetsrv\appcmd.exe",
    [bool]$MainClean      = $false   # $true = delete destination files that are not in the source
)

$ErrorActionPreference = 'Stop'

Function Deploy-WithRobocopy {
    param(
        [string]$SourcePath,
        [string]$DestPath,
        [bool]$Clean = $false
    )

    if (!(Test-Path $DestPath)) {
        Write-Host "  [DIR] Creating missing destination folder: $DestPath"
        New-Item $DestPath -ItemType Directory -Force | Out-Null
    }

    # /MIR = mirror (deletes extra files at destination), /E = copy subfolders, delete nothing
    $mode = if ($Clean) { '/MIR' } else { '/E' }

    Write-Host "Copying '$SourcePath' -> '$DestPath' | Clean: $Clean"
    robocopy $SourcePath $DestPath $mode /R:2 /W:2 /NP | Out-Host

    # robocopy exit codes: 0-7 = success, 8+ = failure
    if ($LASTEXITCODE -ge 8) {
        throw "robocopy failed (exit code: $LASTEXITCODE)"
    }

    Write-Host "Deployment successful."
}

try {
    # ---- Validate inputs first, before creating anything ----
    if (!(Test-Path $binariesPath)) { throw "binariesPath not found: $binariesPath" }
    if (!(Test-Path $appcmd))       { throw "appcmd.exe not found at: $appcmd" }

    Write-Output "Scanning for IIS apps in: $binariesPath"
    Write-Output "Site: $siteName | Target: $physicalPath | Clean: $MainClean"

    $failedApps = @()
    $apps = @(Get-ChildItem $binariesPath -Directory).Name

    if ($apps.Count -eq 0) {
        Write-Output "No app folders found in $binariesPath - nothing to deploy."
    }

    foreach ($app in $apps) {
        try {
            $fullPath = Join-Path $physicalPath $app
            $exists   = & $appcmd list app "/site.name:$siteName" "/path:/$app" 2>$null

            if (!$exists) {
                Write-Output "  [NEW] Adding app: $app"

                if (!(Test-Path $fullPath)) {
                    Write-Output "  [DIR] Creating folder: $fullPath"
                    New-Item $fullPath -ItemType Directory -Force | Out-Null
                }

                & $appcmd add app "/site.name:$siteName" "/path:/$app" "/physicalPath:$fullPath"
                if ($LASTEXITCODE -ne 0) {
                    throw "appcmd failed to add app '$app' (exit code: $LASTEXITCODE)"
                }
            } else {
                Write-Output "  [OK]  Already exists: $app"
            }

            Deploy-WithRobocopy `
                -SourcePath (Join-Path $binariesPath $app) `
                -DestPath   $fullPath `
                -Clean      $MainClean
        }
        catch {
            Write-Output "  [FAIL] $app : $($_.Exception.Message)"
            $failedApps += $app
        }
    }

    if ($failedApps.Count -gt 0) {
        throw "FAILED apps: $($failedApps -join ', ')"
    }
}
catch {
    Write-Output "ERROR: $($_.Exception.Message)"
    exit 1   # makes the Jenkins build go red
}

Write-Output "All done."
exit 0