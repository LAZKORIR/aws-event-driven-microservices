import json
import os

bucket = os.environ["ARTIFACTS_BUCKET"]
instance_id = os.environ["INSTANCE_ID"]

aws_exe = r"C:\Program Files\Amazon\AWSCLIV2\aws.exe"
zip_path = r"C:\app\windows-service.zip"
app_dir = r"C:\app"
exe_path = r"C:\app\api-service.exe"
s3_uri = f"s3://{bucket}/windows-service/windows-service.zip"

payload = {
  "InstanceIds": [instance_id],
  "DocumentName": "AWS-RunPowerShellScript",
  "Parameters": {
    "commands": [
      "cmd /c sc stop TiaWindowsApi",
      "Start-Sleep -Seconds 3",
      "cmd /c sc delete TiaWindowsApi",
      "Start-Sleep -Seconds 3",
      f'& "{aws_exe}" s3 cp {s3_uri} {zip_path}',
      f"Expand-Archive -Path {zip_path} -DestinationPath {app_dir} -Force",
      f"cmd /c sc create TiaWindowsApi binPath= {exe_path} start= auto",
      "netsh advfirewall firewall add rule name=AllowHTTP80 dir=in action=allow protocol=TCP localport=80",
      "cmd /c sc start TiaWindowsApi",
      "Start-Sleep -Seconds 5",
      "cmd /c sc query TiaWindowsApi"
    ]
  }
}

with open("/tmp/ssm-command.json", "w") as f:
  json.dump(payload, f, indent=2)

print("JSON written successfully")