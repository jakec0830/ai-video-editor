<#
  setup.ps1 — Windows 一鍵安裝(對應 Mac 的 setup.sh)。

  全新 Windows 沒有 bash,也沒有 brew,所以這支用 winget 把系統層工具裝好,
  再建 Python 環境、裝套件、裝字型。設計成可重複執行。

  用法(在 PowerShell 裡,cd 到工具包資料夾):
      powershell -ExecutionPolicy Bypass -File .\setup.ps1

  逐字稿引擎注意:pip 版 faster-whisper 在全新 Windows 11 會被 Smart App Control
  擋掉(未簽章 DLL)。這支會當場驗證,擋住時引導你改用 Faster-Whisper-XXL 獨立版。
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$KIT = Split-Path -Parent $MyInvocation.MyCommand.Path
$FREECUT = Join-Path $KIT "tools\freecut"

Write-Host "=== ai-edit 工具包 安裝 (Windows) ==="
Write-Host "工具包位置: $KIT`n"

function Refresh-Path {
  # winget 裝完不會更新「目前這個」PowerShell 的 PATH,手動重讀一次才找得到新工具。
  $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
              [System.Environment]::GetEnvironmentVariable("Path","User")
}

# --- 0. winget 在不在 -------------------------------------------------------
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  Write-Host "[X] 找不到 winget。請先更新 Windows / 從 Microsoft Store 裝『應用程式安裝程式』後再重跑。"
  exit 1
}

# --- 1. 用 winget 裝系統層工具(一次講清楚要裝什麼)------------------------
$deps = @(
  @{ Name = "Python 3.12"; Id = "Python.Python.3.12";  Probe = "python" },
  @{ Name = "Node.js LTS"; Id = "OpenJS.NodeJS.LTS";    Probe = "node"   },
  @{ Name = "ffmpeg";      Id = "Gyan.FFmpeg";          Probe = "ffmpeg" }
)
Write-Host "--- 系統工具(winget)---"
foreach ($d in $deps) {
  if (Get-Command $d.Probe -ErrorAction SilentlyContinue) {
    Write-Host "[OK] $($d.Name) 已安裝"
    continue
  }
  Write-Host "   安裝 $($d.Name) ..."
  winget install --id $d.Id -e --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity | Out-Null
}
Refresh-Path

# --- 2. Python 環境 + 套件 --------------------------------------------------
# 找真的 python(排除 Microsoft Store 空殼)
$PY = $null
foreach ($name in @("python", "python3")) {
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  if (-not $cmd) { continue }
  if ($cmd.Source -like "*WindowsApps*") { continue }   # 商店空殼,跳過
  try { $v = & $cmd.Source --version 2>&1 } catch { continue }
  if ($v -match "Python 3\.") { $PY = $cmd.Source; break }
}
if (-not $PY) {
  Write-Host "[X] 找不到可用的 Python(裝完可能要把 PowerShell 關掉重開,再重跑一次)。"
  exit 1
}
Write-Host "[OK] python: $(& $PY --version)"

$venv = Join-Path $FREECUT ".venv"
if (-not (Test-Path (Join-Path $venv "Scripts\python.exe"))) {
  Write-Host "   建立 Python 環境 (tools\freecut\.venv) ..."
  & $PY -m venv $venv
}
$VPY = Join-Path $venv "Scripts\python.exe"
if (-not (Test-Path $VPY)) { Write-Host "[X] Python 環境沒建成功。確認 Python 真的裝好再重跑。"; exit 1 }

& $VPY -m pip install -q --upgrade pip 2>&1 | Out-Null
Write-Host "   安裝核心套件 (requests, pillow, numpy, opencc) ..."
# opencc-python-reimplemented: 簡轉繁,純 Python(沒 C++ DLL)。刻意不用 PyPI 的
# `opencc`,那個帶未簽章 DLL,在 Windows 可能又被 Smart App Control 擋。
& $VPY -m pip install -q requests pillow numpy opencc-python-reimplemented 2>&1 | Out-Null

# --- 3. 逐字稿引擎:先試 pip faster-whisper,擋住就引導 XXL 獨立版 --------
Write-Host "   先試 faster-whisper(pip) ..."
& $VPY -m pip install -q faster-whisper 2>&1 | Out-Null
& $VPY -c "import faster_whisper" 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
  Write-Host "[OK] faster-whisper 已安裝且可用"
} else {
  Write-Host "[!] faster-whisper 裝了但無法載入(多半是 Smart App Control 擋未簽章 DLL:"
  Write-Host "    「應用程式控制原則已封鎖此檔案」)。改用 Faster-Whisper-XXL 獨立版:"
  Write-Host "    1. https://github.com/Purfview/whisper-standalone-win/releases"
  Write-Host "    2. 下載 Faster-Whisper-XXL 的 Windows 版,解壓縮"
  Write-Host "    3. 整個資料夾放到 tools\whisper-xxl\(裡面要有 faster-whisper-xxl.exe)"
  Write-Host "    詳見 README「Windows 疑難排解」。"
}
# XXL 兩個可放位置都查(tools\whisper-xxl 或 tools\freecut\whisper-xxl)
$xxl = @( (Join-Path $KIT "tools\whisper-xxl"), (Join-Path $FREECUT "whisper-xxl") ) |
  Where-Object { Test-Path $_ } |
  ForEach-Object { Get-ChildItem $_ -Recurse -Filter "faster-whisper-xxl.exe" -ErrorAction SilentlyContinue } |
  Select-Object -First 1
if ($xxl) { Write-Host "[OK] Faster-Whisper-XXL 獨立版已就位:$($xxl.FullName)" }

# --- 4. 字型 ---------------------------------------------------------------
Write-Host "`n--- 字型 ---"
$fontScript = Join-Path $KIT "scripts\windows\install-font.ps1"
if (Test-Path $fontScript) {
  & $fontScript
} else {
  Write-Host "[!] 找不到 install-font.ps1,請手動裝思源宋體。"
}

# --- 5. 個人偏好檔(範本在 tools/ 底下)------------------------------------
$prefTpl = Join-Path $KIT "tools\我的剪輯偏好.範本.md"
$pref    = Join-Path $KIT "我的剪輯偏好.md"
if ((-not (Test-Path $pref)) -and (Test-Path $prefTpl)) {
  Copy-Item $prefTpl $pref
  Write-Host "[OK] 建立個人偏好檔:我的剪輯偏好.md"
}

# --- 6. 把內部運作用的檔案在檔案總管裡藏起來(純外觀,git 跟指令都不受影響)---
# 使用者打開資料夾只會看到 審片.html、我的影片、素材庫、我的剪輯偏好.md、錯誤回報。
# 想看隱藏檔:檔案總管 → 檢視 → 顯示 → 隱藏的項目。可重複執行。
foreach ($f in @("README.md","LICENSE",".gitignore","setup.sh","setup.ps1","scripts","tools")) {
  $p = Join-Path $KIT $f
  if (Test-Path $p) {
    try { (Get-Item $p -Force).Attributes = (Get-Item $p -Force).Attributes -bor [IO.FileAttributes]::Hidden } catch {}
  }
}

Write-Host "`n=== 完成 ==="
Write-Host "用 Claude Code 打開這個資料夾,ai-edit 技能會自動載入。"
Write-Host "然後把影片丟進來,說你想怎麼剪。詳見 README.md 或跟 AI 問。"
Write-Host "(資料夾裡少了幾個檔案是正常的 — 內部運作用的檔案被藏起來了,不影響功能;"
Write-Host " 檔案總管 → 檢視 → 顯示 → 隱藏的項目 可以隨時看到它們。)"
