<#
  install-font.ps1 — 在 Windows 上安裝思源宋體(Source Han Serif TC)給目前使用者。

  Mac 用 brew 一行搞定,Windows 沒有對應套件,只能下載 + 註冊。這支腳本把
  「Windows 安裝流程紀錄」裡踩到的兩個坑都避開了:
    1. 不要同一個檔案又 Shell CopyHere 又手動複製 → 會裝兩次、檔名多 _0。
       這裡只手動複製一次 + 寫一筆登錄檔,不用 Shell COM。
    2. 每個字重(Regular/Bold...)登錄檔 key 要「不重複」,不然會互相蓋掉,
       只剩最後一個字重有效。這裡用檔名當 key,天生唯一。

  不需要系統管理員權限(裝在使用者字型目錄 + HKCU)。可重複執行(idempotent)。
#>
[CmdletBinding()]
param(
  # 留空 → 自動去 GitHub Releases API 找最新的繁中子集,不寫死版本號(才不會哪天 404)。
  [string]$AssetUrl = ""
)

$ErrorActionPreference = "Stop"
Write-Host "=== 安裝思源宋體(Source Han Serif TC)==="

# 已經裝過就不重覆(看使用者字型目錄有沒有 SourceHanSerifTC 檔案)
$fontDir = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"
if (Test-Path $fontDir) {
  $already = Get-ChildItem $fontDir -Filter "SourceHanSerif*TC*" -ErrorAction SilentlyContinue
  if ($already) {
    Write-Host "[OK] 思源宋體已安裝($($already.Count) 個檔案),略過。"
    return
  }
}

# 1. 找下載連結
if (-not $AssetUrl) {
  Write-Host "   查詢最新版下載連結 ..."
  $api = "https://api.github.com/repos/adobe-fonts/source-han-serif/releases/latest"
  $rel = Invoke-RestMethod -Uri $api -Headers @{ "User-Agent" = "ai-video-editor" }
  $asset = $rel.assets | Where-Object { $_.name -match "SourceHanSerifTC" -and $_.name -match "\.zip$" } | Select-Object -First 1
  if (-not $asset) { throw "在最新 release 找不到 SourceHanSerifTC 的 zip,請手動指定 -AssetUrl。" }
  $AssetUrl = $asset.browser_download_url
  Write-Host "   找到:$($asset.name)(約 $([math]::Round($asset.size/1MB)) MB)"
}

# 2. 下載 + 解壓(這步 100MB 上下,會跑幾分鐘,屬正常)
$tmp = Join-Path $env:TEMP ("shs-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$zip = Join-Path $tmp "font.zip"
Write-Host "   下載中(檔案偏大,請耐心等)..."
Invoke-WebRequest -Uri $AssetUrl -OutFile $zip -UseBasicParsing
Write-Host "   解壓縮 ..."
Expand-Archive -Path $zip -DestinationPath $tmp -Force

# 3. 逐一安裝(複製一次 + 唯一 key 一筆登錄檔),避開報告裡的兩個坑
New-Item -ItemType Directory -Force -Path $fontDir | Out-Null
$regKey = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts"
$fonts = Get-ChildItem $tmp -Recurse -Include *.otf, *.ttf, *.otc, *.ttc
if (-not $fonts) { throw "解壓後找不到任何字型檔。" }

$installed = 0
foreach ($f in $fonts) {
  $dest = Join-Path $fontDir $f.Name
  if (-not (Test-Path $dest)) { Copy-Item $f.FullName $dest -Force }
  # 用檔名(不含副檔名)當登錄檔 value 名稱 → 每個字重唯一,不會互蓋。
  $valueName = "$($f.BaseName) (OpenType)"
  New-ItemProperty -Path $regKey -Name $valueName -Value $dest -PropertyType String -Force | Out-Null
  $installed++
}
Write-Host "[OK] 已安裝 $installed 個字型檔到使用者字型目錄。"

# 4. 讓系統即時看到新字型(不用重開機)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class FontNotify {
  [DllImport("gdi32.dll")] public static extern int AddFontResource(string lpFileName);
  [DllImport("user32.dll")] public static extern int SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
}
"@
foreach ($f in $fonts) {
  [void][FontNotify]::AddFontResource((Join-Path $fontDir $f.Name))
}
$HWND_BROADCAST = [IntPtr]0xffff
$WM_FONTCHANGE  = 0x001D
[void][FontNotify]::SendMessage($HWND_BROADCAST, $WM_FONTCHANGE, [IntPtr]::Zero, [IntPtr]::Zero)

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "[OK] 思源宋體安裝完成。"
