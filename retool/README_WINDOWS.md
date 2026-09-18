# 下载到本机 Windows 目录

云端 Agent **不能**直接写入 `C:\`。在这台已经能上网的 Windows 上执行下面命令，文件会落到：

`C:\StudyMaterials\RL\verl\retool`

```powershell
cd C:\StudyMaterials\RL\verl
git fetch origin cursor/retool-windows-download-1916
git checkout origin/cursor/retool-windows-download-1916 -- retool
Set-ExecutionPolicy -Scope Process Bypass
powershell -File .\retool\download_payload.ps1
```

若当前仓库的 `origin` 不是 `konfan12345678/verl`：

```powershell
cd C:\StudyMaterials\RL\verl
git remote add fork https://github.com/konfan12345678/verl.git
git fetch fork cursor/retool-windows-download-1916
git checkout fork/cursor/retool-windows-download-1916 -- retool
powershell -ExecutionPolicy Bypass -File .\retool\download_payload.ps1
```

国内 Hugging Face 慢时：

```powershell
$env:HF_ENDPOINT = "https://hf-mirror.com"
powershell -ExecutionPolicy Bypass -File C:\StudyMaterials\RL\verl\retool\download_payload.ps1
```

脚本会创建 `C:\StudyMaterials\RL\verl\retool\payload\`（CPython、wheel、数据集）。kit 脚本在 `retool\` 下。再把整个 `retool` 目录拷到 910B。
