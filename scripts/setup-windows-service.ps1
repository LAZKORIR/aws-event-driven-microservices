<powershell>
$ErrorActionPreference = "Stop"
Start-Transcript -Path "C:\setup-windows-service.log" -Append

try {
    Write-Output "Installing AWS CLI..."
    Invoke-WebRequest "https://awscli.amazonaws.com/AWSCLIV2.msi" -OutFile "C:\AWSCLIV2.msi"
    Start-Process msiexec.exe -ArgumentList '/i C:\AWSCLIV2.msi /quiet /norestart' -Wait

    # Refresh PATH so aws.exe is available immediately in this session
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")

    New-Item -ItemType Directory -Force -Path "C:\app"

    Write-Output "Downloading app from S3..."
    aws s3 cp "s3://${s3_bucket}/${s3_key}" "C:\app\windows-service.zip"

    Write-Output "Extracting app..."
    Expand-Archive "C:\app\windows-service.zip" -DestinationPath "C:\app" -Force

    Write-Output "Listing extracted files..."
    Get-ChildItem -Path "C:\app" -Recurse | Out-File "C:\app-files.txt"

    # Set MQ_SECRET_NAME for the service process
    [System.Environment]::SetEnvironmentVariable("MQ_SECRET_NAME", "${secret_name}", "Machine")

    Write-Output "Removing old service if it exists..."
    $existing = cmd /c "sc query TiaWindowsApi" 2>&1
    if ($existing -notmatch "does not exist") {
        cmd /c "sc stop TiaWindowsApi"
        Start-Sleep -Seconds 5
        cmd /c "sc delete TiaWindowsApi"
        Start-Sleep -Seconds 3
    }

    Write-Output "Creating Windows service..."
    # Points directly to the self-contained .exe — no dotnet.exe needed
    cmd /c 'sc create TiaWindowsApi binPath= "C:\app\api-service.exe" start= auto'
    cmd /c 'sc description TiaWindowsApi "TIA Windows API Service"'

    Write-Output "Starting Windows service..."
    cmd /c "sc start TiaWindowsApi"
    Start-Sleep -Seconds 8

    # Validate the service actually reached RUNNING state
    $status = cmd /c "sc query TiaWindowsApi"
    Write-Output "Service status: $status"
    $status | Out-File "C:\service-status.txt"

    if ($status -notmatch "RUNNING") {
        Write-Output "ERROR: Service did not reach RUNNING state."
        Get-EventLog -LogName Application -Newest 20 | Out-File "C:\eventlog.txt"
        throw "Service failed to start. Check C:\eventlog.txt and C:\setup-windows-service.log"
    }

    Write-Output "Checking port 80..."
    netstat -ano | findstr :80 | Out-File "C:\port80.txt"

    Write-Output "Setup complete. Service is RUNNING."
}
catch {
    $_ | Out-File "C:\setup-error.txt"
    throw
}
finally {
    Stop-Transcript
}
</powershell>