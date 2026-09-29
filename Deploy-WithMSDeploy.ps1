param(
    [string]$binariesPath = "C:\MedicaPlus\TobeTransfered",
    [string]$siteName     = "Default Web Site",
    [string]$physicalPath = "C:\MedicaPlus",
    [string]$appcmd       = "$env:windir\system32\inetsrv\appcmd.exe",
    [bool]$MainClean      = $false
)

Function Deploy-WithRobocopy {
    param(
        [string]$FolderPath,
        [string]$PhysicalPath,
        [bool]$Clean = $false
    )

    # /MIR = mirror (deletes files not in source); /E = copy all, delete nothing
    $mode = if ($Clean) { '/MIR' } else { '/E' }

    Write-Host "Copying '$FolderPath' -> '$PhysicalPath' | Clean: $Clean"
    robocopy $FolderPath $PhysicalPath $mode /R:2 /W:2 /NP | Out-Host

    # robocopy exit codes: 0-7 = success, 8+ = failure
    if ($LASTEXITCODE -ge 8) {
        Write-Host "robocopy failed (exit code: $LASTEXITCODE)"
        return $false
    }

    Write-Host "Deployment successful."
    return $true
}

# ---- Validate inputs before touching anything ----
if (!(Test-Path $binariesPath)) { Write-Host "binariesPath not found: $binariesPath"; exit 1 }
if (!(Test-Path $appcmd))       { Write-Host "appcmd.exe not found at: $appcmd"; exit 1 }

Write-Output "Scanning for missing IIS apps in: $binariesPath"
Write-Output "Site: $siteName | Target: $physicalPath | Clean: $MainClean"

$failedApps = @()

foreach ($app in (Get-ChildItem $binariesPath -Directory).Name) {
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
            Write-Host "appcmd failed to add app '$app' (exit code: $LASTEXITCODE)"
            $failedApps += $app
            continue
        }
    } else {
        Write-Output "  [OK]  Already exists: $app"
    }

    $result = Deploy-WithRobocopy `
        -FolderPath   (Join-Path $binariesPath $app) `
        -PhysicalPath $fullPath `
        -Clean        $MainClean

    if (($result | Select-Object -Last 1) -ne $true) {
        $failedApps += $app
    }
}

if ($failedApps.Count -gt 0) {
    Write-Output "FAILED apps: $($failedApps -join ', ')"
    exit 1   # turns the Jenkins build red
}

Write-Output "All done."
exit 0