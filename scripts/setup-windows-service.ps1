<powershell>

Write-Output "Installing AWS CLI..."
Invoke-WebRequest "https://awscli.amazonaws.com/AWSCLIV2.msi" -OutFile "C:\AWSCLIV2.msi"
Start-Process msiexec.exe -ArgumentList '/i C:\AWSCLIV2.msi /quiet /norestart' -Wait

Write-Output "Installing .NET 8 Runtime..."
Invoke-WebRequest "https://download.visualstudio.microsoft.com/download/pr/7a8c1d37-5d9d-4d1d-9a1f-0d9d6d8f4fcb/5e0f5b9b9a1cb5a7a85db0b4c2a5b3d2/dotnet-runtime-8.0.14-win-x64.exe" -OutFile "C:\dotnet-runtime.exe"
Start-Process "C:\dotnet-runtime.exe" -ArgumentList "/install /quiet /norestart" -Wait

New-Item -ItemType Directory -Force -Path "C:\app"

Write-Output "Downloading app from S3..."
aws s3 cp "s3://${s3_bucket}/${s3_key}" "C:\app\windows-service.zip"

Expand-Archive "C:\app\windows-service.zip" -DestinationPath "C:\app" -Force

[System.Environment]::SetEnvironmentVariable("MQ_SECRET_NAME", "${secret_name}", "Machine")
[System.Environment]::SetEnvironmentVariable("ASPNETCORE_URLS", "http://+:80", "Machine")

Write-Output "Creating Windows service..."
sc.exe create TiaWindowsApi binPath= "\"C:\Program Files\dotnet\dotnet.exe\" \"C:\app\api-service.dll\"" start= auto

Write-Output "Starting Windows service..."
sc.exe start TiaWindowsApi

Write-Output "Setup complete"

</powershell>