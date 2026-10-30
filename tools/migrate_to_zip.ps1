<#
  把舊版工具包（用終端機裝的）就地換成新版 zip 工具包（Windows）。
  用法：powershell -ExecutionPolicy Bypass -File .\setup.ps1
  （舊版更新後本來就會跑 setup.ps1，現在 setup.ps1 只做這件事）

  只覆蓋、只新增，不刪任何東西（auto mode 下刪除指令常被擋住）：
    覆蓋：說明書（CLAUDE.md、AGENTS.md、.claude/skills）、tools\、素材庫\預設包、審片.html
    保留：我的影片、我的剪輯偏好.md、錯誤回報、學員自己加進素材庫的檔案
    不動：舊的 Python 環境 tools\freecut\.venv（不再使用，之後想清空間可以刪）
#>
$ErrorActionPreference = "Stop"
$KIT = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$URL = "https://github.com/jackie81030/ai-video-editor-zip/releases/latest/download/AI-Cut-Kit-Windows.zip"

if (Test-Path (Join-Path $KIT "錯誤回報\.我是維護者")) { Write-Host "這是維護者的工具包，不換成新版。"; exit 0 }
if ((Test-Path (Join-Path $KIT "tools\run.cmd")) -and (Test-Path (Join-Path $KIT "tools\python"))) {
  # 已經換過：再跑一次只做新版的啟動檢查（例如剛下載好模型，要把它裝進來）
  Write-Host "已經是新版了，做一次啟動檢查。"
  & (Join-Path $KIT "tools\run.cmd") python (Join-Path $KIT "tools\startup.py"); exit $LASTEXITCODE
}

$DL = Join-Path $env:USERPROFILE "Downloads"
New-Item -ItemType Directory -Force $DL | Out-Null
$ZIP = Join-Path $DL "AI-Cut-Kit-Windows.zip"
Write-Host "=== 換成新版工具包 ==="
Write-Host "工具包位置：$KIT"

# 1. 下載（已經在「下載」資料夾就不重抓）
$ok = $false
if (Test-Path $ZIP) {
  try { Add-Type -AssemblyName System.IO.Compression.FileSystem; $z = [IO.Compression.ZipFile]::OpenRead($ZIP); $z.Dispose(); $ok = $true } catch { $ok = $false }
}
if ($ok) { Write-Host "[OK] 已經下載過 AI-Cut-Kit-Windows.zip" }
else {
  Write-Host "下載新版工具包（約 1GB，看網速幾分鐘）..."
  try {
    $ProgressPreference = "SilentlyContinue"   # 進度條會讓 Invoke-WebRequest 慢十倍
    Invoke-WebRequest -Uri $URL -OutFile "$ZIP.part" -UseBasicParsing
    Move-Item -Force "$ZIP.part" $ZIP
  } catch {
    Write-Host "[X] 下載失敗。請換一個網路再試，或用瀏覽器打開下面網址下載到「下載」資料夾後再跑一次："
    Write-Host "    $URL"; exit 1
  }
}

# 2. 解壓縮到暫存資料夾
$TMP = Join-Path $env:TEMP ("aicut-" + [guid]::NewGuid().ToString("N"))
Write-Host "解壓縮中（1GB，約 1-3 分鐘）..."
try { Expand-Archive -LiteralPath $ZIP -DestinationPath $TMP -Force }
catch { Write-Host "[X] 解壓縮失敗，檔案可能沒下載完整。把「下載」裡的 AI-Cut-Kit-Windows.zip 刪掉後再跑一次。"; exit 1 }
$NEW = Join-Path $TMP "AI剪片工具包"
if (-not (Test-Path $NEW)) { Write-Host "[X] zip 裡找不到 AI剪片工具包 資料夾"; exit 1 }

# 3. 覆蓋工具和說明書；學員的東西跳過（robocopy 不加 /MIR：舊檔案留著不刪）
function Copy-Over($src, $dst) { robocopy $src $dst /E /NFL /NDL /NJH /NJS /NP | Out-Null; if ($LASTEXITCODE -ge 8) { throw "複製失敗：$src" } }
Copy-Over (Join-Path $NEW "tools") (Join-Path $KIT "tools")
Copy-Over (Join-Path $NEW ".claude") (Join-Path $KIT ".claude")
Copy-Over (Join-Path $NEW ".agents") (Join-Path $KIT ".agents")
Copy-Over (Join-Path $NEW "素材庫\預設包") (Join-Path $KIT "素材庫\預設包")
robocopy (Join-Path $NEW "素材庫") (Join-Path $KIT "素材庫") /E /XC /XN /XO /NFL /NDL /NJH /NJS /NP | Out-Null   # 只補沒有的
foreach ($f in "CLAUDE.md","AGENTS.md","VERSION","使用說明.md","審片.html") {
  $s = Join-Path $NEW $f; if (Test-Path $s) { Copy-Item -Force $s (Join-Path $KIT $f) }
}
foreach ($d in "我的影片","錯誤回報") { New-Item -ItemType Directory -Force (Join-Path $KIT $d) | Out-Null }
if (-not (Test-Path (Join-Path $KIT "我的剪輯偏好.md"))) { Copy-Item (Join-Path $NEW "我的剪輯偏好.md") (Join-Path $KIT "我的剪輯偏好.md") }

# 4. 第一次啟動新版：檢查更新、確認模型、裝字型
Write-Host ""
& (Join-Path $KIT "tools\run.cmd") python (Join-Path $KIT "tools\startup.py")

Write-Host ""
Write-Host ("=== 已經換成新版（" + (Get-Content (Join-Path $KIT "VERSION") -ErrorAction SilentlyContinue) + "）===")
Write-Host "你的影片、剪輯偏好、錯誤回報都還在。"
if (Test-Path (Join-Path $KIT "tools\freecut\.venv")) { Write-Host "舊的 Python 環境 tools\freecut\.venv 不再使用，之後想清空間可以刪掉。" }
Write-Host "請關掉這個對話，開一個新對話再說「幫我剪」：新版的說明書要在新對話才會讀到。"
