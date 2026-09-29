pipeline {
    agent { label 'windows-iis' }

    options {
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 30, unit: 'MINUTES')
    }

    parameters {
        string(name: 'BINARIES_PATH', defaultValue: 'C:\\MedicaPlus\\TobeTransfered',
               description: 'Folder containing one sub-folder per app to deploy')
        string(name: 'SITE_NAME', defaultValue: 'Default Web Site',
               description: 'IIS site name')
        string(name: 'PHYSICAL_PATH', defaultValue: 'C:\\MedicaPlus',
               description: 'Root folder on disk where the apps live')
        string(name: 'APPCMD', defaultValue: 'C:\\Windows\\System32\\inetsrv\\appcmd.exe',
               description: 'Full path to appcmd.exe')
        string(name: 'MSDEPLOY_PATH', defaultValue: 'C:\\Program Files\\IIS\\Microsoft Web Deploy V3\\msdeploy.exe',
               description: 'Full path to msdeploy.exe (Web Deploy must be installed on the agent)')
        booleanParam(name: 'MAIN_CLEAN', defaultValue: false,
               description: 'Tick to DELETE destination files that are not in the source')
    }

    stages {
        stage('Checkout') {
            steps { checkout scm }
        }

        stage('Validate') {
            steps {
                powershell '''
                    $missing = @()
                    foreach ($p in @($env:BINARIES_PATH, $env:APPCMD, $env:MSDEPLOY_PATH)) {
                        if (!(Test-Path $p)) { $missing += $p }
                    }
                    if ($missing.Count -gt 0) {
                        Write-Host "Missing paths on this agent:"
                        $missing | ForEach-Object { Write-Host "  - $_" }
                        exit 1
                    }
                    Write-Host "All required paths exist."
                '''
            }
        }

        stage('Deploy') {
            steps {
                powershell '''
                    $src = Join-Path $env:WORKSPACE 'Deploy-WithMSDeploy.ps1'
                    $tmp = Join-Path $env:WORKSPACE 'Deploy-Runtime.ps1'

                    # Build a temporary copy of the script with the Jenkins parameter values.
                    # The original PS1 in the repo is NOT modified.
                    $lines = Get-Content $src | ForEach-Object {
                        if     ($_ -match '^[$]binariesPath[ ]*=') { '$binariesPath = "' + $env:BINARIES_PATH + '"' }
                        elseif ($_ -match '^[$]siteName[ ]*=')     { '$siteName = "'     + $env:SITE_NAME     + '"' }
                        elseif ($_ -match '^[$]physicalPath[ ]*=') { '$physicalPath = "' + $env:PHYSICAL_PATH + '"' }
                        elseif ($_ -match '^[$]appcmd[ ]*=')       { '$appcmd = "'       + $env:APPCMD        + '"' }
                        elseif ($_ -match '^[$]MsDeployPath[ ]*=') { '$MsDeployPath = "' + $env:MSDEPLOY_PATH + '"' }
                        elseif ($_ -match '^[$]MainClean[ ]*=')    { '$MainClean = $'    + $env:MAIN_CLEAN.ToLower() }
                        else { $_ }
                    }
                    $lines | Set-Content $tmp -Encoding UTF8

                    $exitCode = 0
                    try {
                        # Show output live and also capture it, so failures can be detected
                        & $tmp *>&1 | Tee-Object -Variable out | Out-Host
                        $text = ($out | Out-String)

                        # The PS1 prints "All done." even when a deploy fails,
                        # so scan the output for known failure markers.
                        if ($text -match 'MSDeploy failed|msdeploy\\.exe not found|Cannot find drive|Cannot find path|DriveNotFound|ObjectNotFound') {
                            Write-Host "Deployment failure detected in script output."
                            $exitCode = 1
                        }
                    } catch {
                        Write-Host "Deploy script error: $_"
                        $exitCode = 1
                    } finally {
                        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
                    }
                    exit $exitCode
                '''
            }
        }
    }

    post {
        success { echo 'Deployment finished successfully.' }
        failure { echo 'Deployment FAILED - check the console log above.' }
    }
}