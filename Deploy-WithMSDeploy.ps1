param(
    [string]$binariesPath = "C:\MedicaPlus\TobeTransfered",
    [string]$siteName     = "Default Web Site",
    [string]$physicalPath = "C:\MedicaPlus",
    [string]$appcmd       = "$env:windir\system32\inetsrv\appcmd.exe",
    [string]$MsDeployPath = "C:\Program Files\IIS\Microsoft Web Deploy V3\msdeploy.exe",
    [bool]$MainClean      = $false
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

Write-Output "Scanning for missing IIS apps in: $binariesPath"

foreach ($app in (Get-ChildItem $binariesPath).Name) {
    $fullPath = Join-Path $physicalPath $app
    $exists   = & $appcmd list app "/site.name:$siteName" "/path:/$app" 2>$null

    if (!$exists) {
        Write-Output "  [NEW] Adding app: $app"

        if (!(Test-Path $fullPath)) {
            Write-Output "  [DIR] Creating folder: $fullPath"
            New-Item $fullPath -ItemType Directory -Force | Out-Null
        }

        & $appcmd add app "/site.name:$siteName" "/path:/$app" "/physicalPath:$fullPath"
    } else {
        Write-Output "  [OK]  Already exists: $app"
    }

    Deploy-WithMSDeploy `
        -FolderPath  (Join-Path $binariesPath $app) `
        -PhysicalPath $fullPath `
        -SiteName    $siteName `
        -Clean       $MainClean `
        -MsDeployPath $MsDeployPath
}

Write-Output "All done."