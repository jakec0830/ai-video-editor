#!/bin/bash
# bootstrap.sh — AI 剪輯工具包 前置安裝(Mac)
# 學員在終端機貼一行跑這支:裝 git(Command Line Tools)+ 下載工具包到家目錄。
# 用法(印在課程講義上,永遠不要改這個網址):
#   curl -fsSL https://raw.githubusercontent.com/jakec0830/ai-video-editor/main/bootstrap.sh | bash
#
# 設計原則:
# - 對象是完全新手。每一步都用白話講在做什麼、要等多久、要不要動手。
# - 不裝 Homebrew、不碰 softwareupdate(會拖到 macOS 大更新)、不要密碼。
#   git 走 xcode-select --install:跳 Mac 原生視窗,學員只要點「安裝」。
# - 失敗就明講「截圖傳到課程群組」,不要讓學員自己猜。
set -u

DEST="$HOME/ai-video-editor"
REPO_URL="https://github.com/jakec0830/ai-video-editor.git"
START_TS=$(date +%s)
BOOTLOG="$(mktemp -t aiedit_bootstrap.XXXXXX)"

log() { echo "$1"; echo "$1" >> "$BOOTLOG"; }

fail() {
  echo ""
  echo "================================================"
  echo "❌ 卡住了:$1"
  echo ""
  echo "請把這整個視窗截圖,傳到課程群組,我們幫你看。"
  echo "================================================"
  exit 1
}

echo "================================================"
echo "  AI 剪輯工具包 前置安裝"
echo "  這支程式做兩件事:1. 裝 git  2. 下載工具包"
echo "  全程不用打字,照畫面上的說明做就好。"
echo "================================================"
echo ""

# --- 0. 環境檢查 ---
OS_VER="$(sw_vers -productVersion 2>/dev/null || echo 0)"
OS_MAJOR="${OS_VER%%.*}"
log "macOS 版本:$OS_VER"
if [ "${OS_MAJOR:-0}" -lt 13 ] 2>/dev/null; then
  fail "這台 Mac 的系統是 macOS $OS_VER,但 Claude Code 需要 macOS 13 以上。這台電腦沒辦法上這門課(如果還沒訂閱 Claude Pro,先不要訂)。"
fi

DISK_FREE_GB="$(df -g "$HOME" 2>/dev/null | awk 'NR==2 {print $4}')"
log "剩餘空間:約 ${DISK_FREE_GB:-?} GB"
if [ "${DISK_FREE_GB:-999}" -lt 20 ] 2>/dev/null; then
  echo "⚠️  磁碟空間只剩 ${DISK_FREE_GB}GB,建議至少 30GB。可以先繼續,但剪片時可能不夠用,建議先清出空間。"
fi

# --- 1/2. git ---
echo ""
if xcode-select -p >/dev/null 2>&1 && git --version >/dev/null 2>&1; then
  log "[1/2] 檢查 git ... 這台已經有了 ✅(跳過安裝)"
else
  log "[1/2] 檢查 git ... 沒有,現在開始裝。"
  echo ""
  echo "   ┌──────────────────────────────────────────────┐"
  echo "   │  等一下螢幕上會跳出一個視窗,問你要不要安裝    │"
  echo "   │  「命令列開發者工具」。                        │"
  echo "   │                                              │"
  echo "   │  請點「安裝」,同意條款,然後等它跑完。         │"
  echo "   │  依網路速度可能要 10~30 分鐘。                │"
  echo "   │                                              │"
  echo "   │  裝完不用回來按任何東西,我會自己繼續。        │"
  echo "   └──────────────────────────────────────────────┘"
  echo ""
  xcode-select --install >/dev/null 2>&1

  WAITED=0
  until xcode-select -p >/dev/null 2>&1 && git --version >/dev/null 2>&1; do
    sleep 30
    WAITED=$((WAITED + 30))
    MIN=$((WAITED / 60))
    if [ $((WAITED % 60)) -eq 0 ]; then
      echo "   ... 還在等安裝完成(第 ${MIN} 分鐘),正常,不用動 ..."
    fi
    if [ $((WAITED % 300)) -eq 0 ]; then
      echo "   (如果螢幕上「沒有」正在跑的安裝視窗,可能是視窗被關掉了。"
      echo "    沒關係:關掉這個終端機視窗,重新貼一次同一行指令就好。)"
    fi
    if [ "$WAITED" -ge 5400 ]; then
      fail "等了 90 分鐘 git 還沒裝好。可能是網路太慢或安裝視窗被關掉了。"
    fi
  done
  log "[1/2] git 裝好了 ✅(等了約 $((WAITED / 60)) 分鐘)"
fi

# --- 2/2. 下載工具包 ---
echo ""
if [ -d "$DEST/.git" ]; then
  log "[2/2] 工具包已經在 $DEST,不用重新下載 ✅"
elif [ -e "$DEST" ]; then
  fail "家目錄裡已經有一個叫 ai-video-editor 的東西,但它不是這個工具包。為了不覆蓋你的檔案,我先停下來。"
else
  log "[2/2] 下載剪輯工具包到你的家目錄 ..."
  if git clone --quiet "$REPO_URL" "$DEST" 2>>"$BOOTLOG"; then
    log "[2/2] 下載完成 ✅($DEST)"
  else
    fail "工具包下載失敗。最常見的原因是網路不穩,換個網路(例如手機熱點)再貼一次指令試試。"
  fi
fi

# --- 留安裝紀錄(之後 AI 會自動回傳給課程團隊,個資會先洗掉) ---
ELAPSED=$(( ($(date +%s) - START_TS) / 60 ))
REPORT_DIR="$DEST/錯誤回報"
mkdir -p "$REPORT_DIR"
{
  echo "# 前置安裝紀錄(bootstrap.sh)$(date +%Y-%m-%d\ %H:%M)"
  echo ""
  echo "- macOS $OS_VER / $(uname -m)"
  echo "- 剩餘空間:約 ${DISK_FREE_GB:-?} GB"
  echo "- 總耗時:約 ${ELAPSED} 分鐘"
  echo "- git:$(git --version 2>/dev/null || echo '?')"
  echo ""
  echo "## 過程輸出"
  echo '```'
  cat "$BOOTLOG"
  echo '```'
} > "$REPORT_DIR/前置安裝-$(date +%Y-%m-%d).md"
rm -f "$BOOTLOG"

# --- 收尾 ---
echo ""
echo "================================================"
echo "✅ 全部完成!終端機的任務結束了,可以關掉這個視窗。"
echo ""
echo "接下來:"
echo "1. 打開 Claude App,點上面的「Code」"
echo "   (如果 Claude App 本來就開著,先完全關掉重開:"
echo "    按 Cmd+Q 再重新打開,它才會發現 git 裝好了)"
echo "2. 環境選「Local」,按「Select folder」"
echo "3. 選家目錄裡的「ai-video-editor」資料夾"
echo "4. 開新對話,打:幫我一步一步安裝設定"
echo "================================================"
