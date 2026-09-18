# Download ReTool offline payload to THIS Windows machine.
# Default: C:\StudyMaterials\RL\verl\retool
#
# Run in PowerShell (this PC must have internet):
#   Set-ExecutionPolicy -Scope Process Bypass
#   powershell -File C:\StudyMaterials\RL\verl\retool\download_payload.ps1

param(
  [string]$Dest = "C:\StudyMaterials\RL\verl\retool",
  [string]$HfEndpoint = $(if ($env:HF_ENDPOINT) { $env:HF_ENDPOINT } else { "https://huggingface.co" }),
  [switch]$DownloadModel
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$PbsTag = "20260901"
$Py310 = "3.10.21"
$Payload = Join-Path $Dest "payload"

function Download-File {
  param([string]$Url, [string]$OutFile)
  $dir = Split-Path -Parent $OutFile
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  if (Test-Path $OutFile) {
    Write-Host "exists $OutFile"
    return
  }
  $tmp = "$OutFile.partial"
  Write-Host "GET $Url"
  & curl.exe -fL --retry 5 --retry-delay 3 -o $tmp $Url
  if ($LASTEXITCODE -ne 0) { throw "download failed: $Url" }
  Move-Item -Force $tmp $OutFile
}

function Download-PypiWheel {
  param([string]$Name, [string]$Version, [string]$Substring, [string]$DestDir)
  $meta = Invoke-RestMethod "https://pypi.org/pypi/$Name/$Version/json"
  $url = $null
  foreach ($f in $meta.urls) {
    if ($f.filename -like "*$Substring*") { $url = $f.url; $fn = $f.filename; break }
  }
  if (-not $url) { throw "no wheel for $Name $Version matching $Substring" }
  Download-File $url (Join-Path $DestDir $fn)
}

New-Item -ItemType Directory -Force -Path $Dest | Out-Null
New-Item -ItemType Directory -Force -Path "$Payload\python" | Out-Null
New-Item -ItemType Directory -Force -Path "$Payload\wheels\cp310-manylinux2014_aarch64" | Out-Null
New-Item -ItemType Directory -Force -Path "$Payload\wheels\cp310-manylinux2014_x86_64" | Out-Null
New-Item -ItemType Directory -Force -Path "$Payload\wheels\generic" | Out-Null
New-Item -ItemType Directory -Force -Path "$Payload\datasets" | Out-Null
New-Item -ItemType Directory -Force -Path "$Payload\models" | Out-Null
New-Item -ItemType Directory -Force -Path "$Payload\src" | Out-Null

Write-Host "== portable CPython 3.10 =="
$base = "https://github.com/astral-sh/python-build-standalone/releases/download/$PbsTag"
foreach ($arch in @("aarch64", "x86_64")) {
  $fn = "cpython-${Py310}+${PbsTag}-${arch}-unknown-linux-gnu-install_only_stripped.tar.gz"
  Download-File "$base/$fn" (Join-Path "$Payload\python" $fn)
}

Write-Host "== linux cp310 wheels (for 910B, not for Windows python) =="
$aarch = "$Payload\wheels\cp310-manylinux2014_aarch64"
$x64 = "$Payload\wheels\cp310-manylinux2014_x86_64"
$gen = "$Payload\wheels\generic"
Download-PypiWheel numpy 1.26.4 "cp310-cp310-manylinux_2_17_aarch64" $aarch
Download-PypiWheel scipy 1.11.4 "cp310-cp310-manylinux_2_17_aarch64" $aarch
Download-PypiWheel pandas 2.2.2 "cp310-cp310-manylinux_2_17_aarch64" $aarch
Download-PypiWheel numpy 1.26.4 "cp310-cp310-manylinux_2_17_x86_64" $x64
Download-PypiWheel scipy 1.11.4 "cp310-cp310-manylinux_2_17_x86_64" $x64
Download-PypiWheel pandas 2.2.2 "cp310-cp310-manylinux_2_17_x86_64" $x64
foreach ($dir in @($aarch, $x64, $gen)) {
  Download-PypiWheel sympy 1.13.3 "py3-none-any" $dir
  Download-PypiWheel mpmath 1.3.0 "py3-none-any" $dir
  Download-PypiWheel "python-dateutil" "2.9.0.post0" "py2.py3-none-any" $dir
  Download-PypiWheel pytz 2024.2 "py2.py3-none-any" $dir
  Download-PypiWheel tzdata 2024.2 "py2.py3-none-any" $dir
  Download-PypiWheel six 1.16.0 "py2.py3-none-any" $dir
}

Write-Host "== datasets ($HfEndpoint) =="
Download-File "$HfEndpoint/datasets/JoeYing/ReTool-SFT/resolve/main/train_2000.parquet" `
  "$Payload\datasets\JoeYing\ReTool-SFT\train_2000.parquet"
Download-File "$HfEndpoint/datasets/BytedTsinghua-SIA/DAPO-Math-17k/resolve/main/data/dapo-math-17k.parquet" `
  "$Payload\datasets\BytedTsinghua-SIA\DAPO-Math-17k\data\dapo-math-17k.parquet"
Download-File "$HfEndpoint/datasets/Maxwell-Jia/AIME_2024/resolve/main/aime_2024_problems.parquet" `
  "$Payload\datasets\Maxwell-Jia\AIME_2024\aime_2024_problems.parquet"
Download-File "$HfEndpoint/datasets/yentinglin/aime_2025/resolve/main/data/train-00000-of-00001-243207c6c994e1bd.parquet" `
  "$Payload\datasets\yentinglin\aime_2025\data\train-00000-of-00001-243207c6c994e1bd.parquet"

if ($DownloadModel) {
  Write-Host "== Qwen2.5-7B-Instruct (large) =="
  Write-Host "Use huggingface-cli or modelscope into $Payload\models\Qwen\Qwen2.5-7B-Instruct"
}

Write-Host ""
Write-Host "Done. Files are in: $Dest"
Write-Host "Payload: $Payload"
Write-Host "Copy this folder to the 910B machine, then:"
Write-Host "  export PAYLOAD_DIR=<that>/payload"
Write-Host "  bash kit/offline/install_on_intranet.sh"
