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
        booleanParam(name: 'MAIN_CLEAN', defaultValue: false,
               description: 'Tick to DELETE destination files that are not in the source')
    }

    stages {
        stage('Checkout') {
            steps { checkout scm }
        }

        stage('Deploy') {
            steps {
                powershell '''
                    try {
                        & "$env:WORKSPACE\\Deploy-WithMSDeploy.ps1" `
                            -binariesPath $env:BINARIES_PATH `
                            -siteName     $env:SITE_NAME `
                            -physicalPath $env:PHYSICAL_PATH `
                            -appcmd       $env:APPCMD `
                            -MainClean    ([System.Convert]::ToBoolean($env:MAIN_CLEAN))
                        exit $LASTEXITCODE
                    } catch {
                        Write-Host "Deploy script error: $_"
                        exit 1
                    }
                '''
            }
        }
    }
}