[CmdletBinding()]
param(
    [string]$BinariesPath = "D:\MedicaPlus\TobeTransfered",
    [string]$SiteName     = "Default Web Site",
    [string]$PhysicalPath = "D:\MedicaPlus",
    [string]$AppCmd       = "$env:windir\system32\inetsrv\appcmd.exe",
    [string]$MsDeployPath = "C:\Program Files\IIS\Microsoft Web Deploy V3\msdeploy.exe",
    [switch]$MainClean,           # pass -MainClean to delete destination files that are not in the source
    [switch]$SkipIIS              # pass -SkipIIS to only transfer files (no appcmd, no IIS app registration)
)

Function Deploy-WithMSDeploy {
    param(
        [string]$FolderPath,
        [string]$PhysicalPath,
        [string]$SiteName,
        [bool]$Clean = $true,
        [bool]$FilesOnly = $false,
        [string]$MsDeployPath = "C:\Program Files\IIS\Microsoft Web Deploy V3\msdeploy.exe"
    )

    if (!(Test-Path $MsDeployPath)) {
        Write-Error "msdeploy.exe not found at: $MsDeployPath"
        return $false
    }

    # Ensure destination directory exists before MSDeploy runs
    if (!(Test-Path $PhysicalPath)) {
        Write-Host "  [DIR] Creating missing destination folder: $PhysicalPath"
        New-Item $PhysicalPath -ItemType Directory -Force | Out-Null
    }

    if ($FilesOnly) {
        # Plain folder-to-folder sync, works without IIS installed
        $msdeployArgs = @(
            "-verb:sync",
            "-source:dirPath=`"$FolderPath`"",
            "-dest:dirPath=`"$PhysicalPath`"",
            "-useCheckSum"
        )
        Write-Host "Transferring '$FolderPath' -> '$PhysicalPath' on $env:COMPUTERNAME | Clean: $Clean"
    }
    else {
        $appName    = Split-Path $PhysicalPath -Leaf
        $iisAppPath = "$SiteName/$appName"
        $msdeployArgs = @(
            "-verb:sync",
            "-source:iisApp=`"$FolderPath`"",
            "-dest:iisApp=`"$iisAppPath`"",
            "-enableRule:AppOffline",
            "-useCheckSum"
        )
        Write-Host "Deploying '$FolderPath' -> '$iisAppPath' on $env:COMPUTERNAME | Clean: $Clean"
    }

    if (-not $Clean) {
        $msdeployArgs += "-enableRule:DoNotDeleteRule"
    }

    & $MsDeployPath @msdeployArgs

    if ($LASTEXITCODE -ne 0) {
        Write-Error "MSDeploy failed (exit code: $LASTEXITCODE)"
        return $false
    }

    Write-Host "Deployment successful."
    return $true
}

# ---- Validate inputs early so Jenkins fails fast with a clear message ----
if (!(Test-Path $BinariesPath)) { throw "BinariesPath not found: $BinariesPath" }
if (!(Test-Path $MsDeployPath)) { throw "msdeploy.exe not found at: $MsDeployPath" }
if (-not $SkipIIS -and !(Test-Path $AppCmd)) { throw "appcmd.exe not found at: $AppCmd (use -SkipIIS if IIS is not installed)" }

Write-Output "Scanning apps in: $BinariesPath"
Write-Output "Mode: $(if ($SkipIIS) { 'FILES ONLY (IIS skipped)' } else { 'IIS deploy' }) | Target: $PhysicalPath | Clean: $($MainClean.IsPresent)"
if (-not $SkipIIS) { Write-Output "Site: $SiteName" }

$failedApps = @()

foreach ($app in (Get-ChildItem $BinariesPath).Name) {
    $fullPath = Join-Path $PhysicalPath $app

    if (-not $SkipIIS) {
        $exists = & $AppCmd list app "/site.name:$SiteName" "/path:/$app" 2>$null

        if (!$exists) {
            Write-Output "  [NEW] Adding app: $app"

            if (!(Test-Path $fullPath)) {
                Write-Output "  [DIR] Creating folder: $fullPath"
                New-Item $fullPath -ItemType Directory -Force | Out-Null
            }

            & $AppCmd add app "/site.name:$SiteName" "/path:/$app" "/physicalPath:$fullPath"
            if ($LASTEXITCODE -ne 0) {
                Write-Error "appcmd failed to add app '$app' (exit code: $LASTEXITCODE)" -ErrorAction Continue
                $failedApps += $app
                continue
            }
        } else {
            Write-Output "  [OK]  Already exists: $app"
        }
    }
    else {
        Write-Output "  [COPY] $app"
    }

    $result = Deploy-WithMSDeploy `
        -FolderPath   (Join-Path $BinariesPath $app) `
        -PhysicalPath $fullPath `
        -SiteName     $SiteName `
        -Clean        $MainClean.IsPresent `
        -FilesOnly    $SkipIIS.IsPresent `
        -MsDeployPath $MsDeployPath

    # Function may emit extra output; the last item is the $true/$false result
    if (($result | Select-Object -Last 1) -ne $true) {
        $failedApps += $app
    }
}

if ($failedApps.Count -gt 0) {
    Write-Output "FAILED apps: $($failedApps -join ', ')"
    exit 1   # makes the Jenkins build go red
}

Write-Output "All done."
exit 0