[CmdletBinding()]
param(
    [string]$BinariesPath = "E:\MedicaPlus\TobeTransfered",
    [string]$SiteName     = "Default Web Site",
    [string]$PhysicalPath = "E:\MedicaPlus",
    [string]$AppCmd       = "$env:windir\system32\inetsrv\appcmd.exe",
    [string]$MsDeployPath = "C:\Program Files\IIS\Microsoft Web Deploy V3\msdeploy.exe",
    [switch]$MainClean            # pass -MainClean to delete files on the destination that are not in the source
)

Function Deploy-WithMSDeploy {
    param(
        [string]$FolderPath,
        [string]$PhysicalPath,
        [string]$SiteName,
        [bool]$Clean = $true,
        [string]$MsDeployPath = "C:\Program Files\IIS\Microsoft Web Deploy V3\msdeploy.exe"
    )

    if (!(Test-Path $MsDeployPath)) {
        Write-Error "msdeploy.exe not found at: $MsDeployPath"
        return $false
    }

    $appName    = Split-Path $PhysicalPath -Leaf
    $iisAppPath = "$SiteName/$appName"

    # Ensure destination directory exists before MSDeploy runs (AppOffline rule needs it)
    if (!(Test-Path $PhysicalPath)) {
        Write-Host "  [DIR] Creating missing destination folder: $PhysicalPath"
        New-Item $PhysicalPath -ItemType Directory -Force | Out-Null
    }

    $msdeployArgs = @(
        "-verb:sync",
        "-source:iisApp=`"$FolderPath`"",
        "-dest:iisApp=`"$iisAppPath`"",
        "-enableRule:AppOffline",
        "-useCheckSum"
    )

    if (-not $Clean) {
        $msdeployArgs += "-enableRule:DoNotDeleteRule"
    }

    Write-Host "Deploying '$FolderPath' -> '$iisAppPath' on $env:COMPUTERNAME | Clean: $Clean"
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
if (!(Test-Path $AppCmd))       { throw "appcmd.exe not found at: $AppCmd" }

Write-Output "Scanning for missing IIS apps in: $BinariesPath"
Write-Output "Site: $SiteName | Target: $PhysicalPath | Clean: $($MainClean.IsPresent)"

$failedApps = @()

foreach ($app in (Get-ChildItem $BinariesPath).Name) {
    $fullPath = Join-Path $PhysicalPath $app
    $exists   = & $AppCmd list app "/site.name:$SiteName" "/path:/$app" 2>$null

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

    $result = Deploy-WithMSDeploy `
        -FolderPath   (Join-Path $BinariesPath $app) `
        -PhysicalPath $fullPath `
        -SiteName     $SiteName `
        -Clean        $MainClean.IsPresent `
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
