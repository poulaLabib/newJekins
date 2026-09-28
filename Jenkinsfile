pipeline {
    // Must be a Windows agent (needs PowerShell + msdeploy)
    agent { label 'windows-iis' }

    options {
        timestamps()
        disableConcurrentBuilds()   // never run two deployments at once
        timeout(time: 30, unit: 'MINUTES')
    }

    parameters {
        string(name: 'BINARIES_PATH', defaultValue: 'D:\\MedicaPlus\\TobeTransfered',
               description: 'Folder containing one sub-folder per app to deploy')
        string(name: 'SITE_NAME', defaultValue: 'Default Web Site',
               description: 'IIS site name (ignored when SKIP_IIS is ticked)')
        string(name: 'PHYSICAL_PATH', defaultValue: 'D:\\MedicaPlus',
               description: 'Root folder on disk where the apps live')
        string(name: 'APPCMD', defaultValue: 'C:\\Windows\\System32\\inetsrv\\appcmd.exe',
               description: 'Full path to appcmd.exe (ignored when SKIP_IIS is ticked)')
        string(name: 'MSDEPLOY_PATH', defaultValue: 'C:\\Program Files\\IIS\\Microsoft Web Deploy V3\\msdeploy.exe',
               description: 'Full path to msdeploy.exe')
        booleanParam(name: 'MAIN_CLEAN', defaultValue: false,
               description: 'Tick to DELETE destination files that are not in the source')
        booleanParam(name: 'SKIP_IIS', defaultValue: true,
               description: 'Tick to only transfer files (no appcmd / IIS app registration). Untick once IIS is installed')
    }

    stages {
        stage('Checkout') {
            steps { checkout scm }   // pulls Deploy-WithMSDeploy.ps1 from your repo
        }

        stage('Deploy') {
            steps {
                // Single-quoted Groovy string on purpose: values are read from env vars
                // by PowerShell, so nothing typed in the parameters is injected into the command.
                powershell '''
                    & "$env:WORKSPACE\\Deploy-WithMSDeploy.ps1" `
                        -BinariesPath $env:BINARIES_PATH `
                        -SiteName     $env:SITE_NAME `
                        -PhysicalPath $env:PHYSICAL_PATH `
                        -AppCmd       $env:APPCMD `
                        -MsDeployPath $env:MSDEPLOY_PATH `
                        -MainClean:([System.Convert]::ToBoolean($env:MAIN_CLEAN)) `
                        -SkipIIS:([System.Convert]::ToBoolean($env:SKIP_IIS))
                    exit $LASTEXITCODE
                '''
            }
        }
    }
}