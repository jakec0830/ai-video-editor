# bootstrap.ps1 — AI 剪輯工具包 前置安裝(Windows)
# 學員在 PowerShell 貼一行跑這支:裝 Git for Windows + 下載工具包到家目錄。
# 用法(印在課程講義上,永遠不要改這個網址):
#   irm https://raw.githubusercontent.com/jakec0830/ai-video-editor/main/bootstrap.ps1 | iex
#
# 設計原則:跟 bootstrap.sh 一樣 — 對新手講白話、失敗就叫他截圖傳群組。
# 注意:這個檔案必須存成「UTF-8 無 BOM」。有 BOM 的話 irm|iex 在 Windows
# PowerShell 5.1 會把第一行註解當指令跑,噴 CommandNotFoundException 紅字。
# Git 用 winget 裝(Windows 內建),只會跳一次「要允許變更嗎?」點「是」即可。

$ErrorActionPreference = "Stop"
$Dest = Join-Path $HOME "ai-video-editor"
$RepoUrl = "https://github.com/jakec0830/ai-video-editor.git"
$StartTime = Get-Date
$BootLog = New-Object System.Collections.Generic.List[string]

function Log($msg) { Write-Host $msg; $BootLog.Add($msg) | Out-Null }

function Fail($msg) {
  Write-Host ""
  Write-Host "================================================"
  Write-Host "X 卡住了:$msg"
  Write-Host ""
  Write-Host "請把這整個視窗截圖,傳到課程群組,我們幫你看。"
  Write-Host "================================================"
  exit 1
}

Write-Host "================================================"
Write-Host "  AI 剪輯工具包 前置安裝(Windows)"
Write-Host "  這支程式做兩件事:1. 裝 Git  2. 下載工具包"
Write-Host "  全程不用打字,照畫面上的說明做就好。"
Write-Host "================================================"
Write-Host ""

# --- 找 git(可能已裝但不在 PATH) ---
function Find-Git {
  $cmd = Get-Command git -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  foreach ($p in @("$env:ProgramFiles\Git\cmd\git.exe",
                   "${env:ProgramFiles(x86)}\Git\cmd\git.exe",
                   "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe")) {
    if (Test-Path $p) { return $p }
  }
  return $null
}

# --- 1/2. Git ---
$GitExe = Find-Git
if ($GitExe) {
  Log "[1/2] 檢查 Git ... 這台已經有了 OK(跳過安裝)"
} else {
  Log "[1/2] 檢查 Git ... 沒有,現在開始裝(用 Windows 內建的 winget)。"
  Write-Host ""
  Write-Host "   等一下會跳出一個視窗問「要允許此 App 變更你的裝置嗎?」"
  Write-Host "   請點「是」(視窗有時躲在工作列閃爍,找一下)。"
  Write-Host "   下載要幾分鐘,下面會顯示進度,不要關視窗。"
  Write-Host "   注意:不要用滑鼠在這個黑視窗裡點選文字,程式會被暫停;"
  Write-Host "   如果不小心點到、畫面很久都沒動,按一下 Enter 就會繼續。"
  Write-Host ""
  $winget = Get-Command winget -ErrorAction SilentlyContinue
  if (-not $winget) {
    Fail "這台 Windows 沒有 winget(通常是太久沒更新 Windows)。請先到 git-scm.com/downloads/win 下載 Git 安裝檔,像裝一般軟體一樣一直按下一步裝完,再重新貼一次這行指令。"
  }
  # 不要把輸出丟掉:讓學員看得到下載進度,才不會以為當機。
  # winget 失敗不會丟例外,要看 $LASTEXITCODE。
  winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
  if ($LASTEXITCODE -ne 0) {
    Fail "Git 安裝沒有成功。請到 git-scm.com/downloads/win 下載 Git 安裝檔,手動裝完再重新貼一次這行指令。"
  }
  $GitExe = Find-Git
  if (-not $GitExe) {
    Fail "Git 裝完了但找不到它(通常重開 PowerShell 就好)。請關掉這個視窗,重新開 PowerShell,再貼一次同一行指令。"
  }
  Log "[1/2] Git 裝好了 OK"
}

# --- 2/2. 下載工具包 ---
Write-Host ""
if (Test-Path (Join-Path $Dest ".git")) {
  Log "[2/2] 工具包已經在 $Dest,不用重新下載 OK"
} elseif (Test-Path $Dest) {
  Fail "家目錄裡已經有一個叫 ai-video-editor 的東西,但它不是這個工具包。為了不覆蓋你的檔案,我先停下來。"
} else {
  Log "[2/2] 下載剪輯工具包到你的家目錄 ..."
  & $GitExe clone --quiet $RepoUrl $Dest
  if ($LASTEXITCODE -ne 0) {
    Fail "工具包下載失敗。最常見的原因是網路不穩,換個網路(例如手機熱點)再貼一次指令試試。"
  }
  Log "[2/2] 下載完成 OK($Dest)"
}

# --- 留安裝紀錄(之後 AI 會自動回傳給課程團隊,個資會先洗掉) ---
$Elapsed = [math]::Round(((Get-Date) - $StartTime).TotalMinutes)
$ReportDir = Join-Path $Dest "錯誤回報"
New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
$OsInfo = (Get-CimInstance Win32_OperatingSystem).Caption
$GitVer = & $GitExe --version
# 跟後面 setup 的紀錄寫同一份檔(安裝紀錄-<日期>.md),SKILL.md 會接著補、最後整份回傳。
$ReportPath = Join-Path $ReportDir ("安裝紀錄-" + (Get-Date -Format "yyyy-MM-dd") + ".md")
@(
  "# 安裝紀錄 " + (Get-Date -Format "yyyy-MM-dd")
  ""
  "## 前置安裝(bootstrap.ps1)" + (Get-Date -Format "HH:mm")
  ""
  "- $OsInfo / $env:PROCESSOR_ARCHITECTURE"
  "- 總耗時:約 $Elapsed 分鐘"
  "- git:$GitVer"
  ""
  "### 過程輸出"
  '```'
) + $BootLog + @('```') | Add-Content -Path $ReportPath -Encoding UTF8

# --- 收尾 ---
Write-Host ""
Write-Host "================================================"
Write-Host "V 全部完成!這個視窗的任務結束了,可以關掉。"
Write-Host ""
Write-Host "接下來:"
Write-Host "1. 打開 Claude App,點上面的「Code」"
Write-Host "   (如果 Claude App 本來就開著,先完全關掉重開,"
Write-Host "    它才會發現 Git 裝好了)"
Write-Host "2. 環境選「Local」,按「Select folder」"
Write-Host "3. 選家目錄裡的「ai-video-editor」資料夾"
Write-Host "4. 開新對話,打:幫我一步一步安裝設定"
Write-Host "================================================"
