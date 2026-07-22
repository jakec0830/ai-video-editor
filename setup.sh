#!/usr/bin/env bash
# ai-edit-kit 安裝 — 建立本機 Python 環境並檢查外部工具。
# Mac / Linux / WSL / Git-Bash 適用。Windows 沒 bash 的話,見 README「手動安裝」。
set -u
KIT="$(cd "$(dirname "$0")" && pwd)"
FREECUT="$KIT/tools/freecut"
OK="[OK] "; WARN="[!]  "; ERR="[X]  "

echo "=== ai-edit 工具包 安裝 ==="
echo "工具包位置: $KIT"
echo ""

# --- 1. Python 環境 + 套件 --------------------------------------------------
PY3="$(command -v python3 || true)"
if [ -z "$PY3" ]; then
  echo "$ERR 找不到 python3。先裝 Python 3.10 以上,再重跑一次。"
  exit 1
fi
echo "$OK python3: $($PY3 --version)"

if [ ! -d "$FREECUT/.venv" ]; then
  echo "   建立 Python 環境 (tools/freecut/.venv) ..."
  "$PY3" -m venv "$FREECUT/.venv"
fi
VPY="$FREECUT/.venv/bin/python3"
[ -f "$VPY" ] || VPY="$FREECUT/.venv/Scripts/python.exe"   # Windows 路徑
"$VPY" -m pip install -q --upgrade pip >/dev/null 2>&1

echo "   安裝核心套件 (requests, pillow, numpy) ..."
"$VPY" -m pip install -q requests pillow numpy

# --- 2. 依平台裝 Whisper 引擎 -----------------------------------------------
UNAME="$(uname -s 2>/dev/null || echo unknown)"
ARCH="$(uname -m 2>/dev/null || echo unknown)"
if [ "$UNAME" = "Darwin" ] && [ "$ARCH" = "arm64" ]; then
  echo "   偵測到 Apple Silicon → 安裝 mlx-whisper(最快) ..."
  "$VPY" -m pip install -q mlx-whisper && echo "$OK mlx-whisper 已安裝"
else
  echo "   $UNAME/$ARCH → 安裝 faster-whisper(CPU/NVIDIA,跨平台) ..."
  "$VPY" -m pip install -q faster-whisper && echo "$OK faster-whisper 已安裝"
fi

# --- 3. 外部工具(只檢查,不強裝)-------------------------------------------
echo ""
echo "--- 外部工具 ---"
if command -v ffmpeg >/dev/null 2>&1; then
  echo "$OK ffmpeg: $(ffmpeg -version | head -1 | cut -d' ' -f1-3)"
else
  echo "$ERR 缺 ffmpeg。 Mac: brew install ffmpeg | Windows: choco install ffmpeg | Linux: apt install ffmpeg"
fi

if command -v node >/dev/null 2>&1; then
  NODE_MAJOR="$(node --version | sed 's/v//' | cut -d. -f1)"
  if [ "$NODE_MAJOR" -ge 22 ] 2>/dev/null; then
    echo "$OK node: $(node --version)(npx hyperframes 可用)"
  else
    echo "$WARN node $(node --version) 版本太舊。 npx hyperframes 需要 Node 22 以上,請更新。"
  fi
else
  echo "$ERR 缺 node(字幕／特效要用 npx hyperframes)。到 nodejs.org 裝 Node 22 以上"
fi

# 字型(思源宋體 / Source Han Serif)
if fc-list 2>/dev/null | grep -qi "Source Han Serif" || ls "$HOME/Library/Fonts/SourceHanSerif"* >/dev/null 2>&1; then
  echo "$OK 字型: 思源宋體(Source Han Serif)有裝"
else
  echo "$WARN 找不到思源宋體(Source Han Serif VF)。 Mac: brew install --cask font-source-han-serif-vf"
  echo "        其他系統: 到 github.com/adobe-fonts/source-han-serif/releases 下載 .otf.ttc 安裝"
fi

# heygen(選配 — 音效／背景音樂資料庫)
if command -v heygen >/dev/null 2>&1; then
  if heygen auth status >/dev/null 2>&1; then
    echo "$OK heygen CLI 已裝 + 已登入(音效／音樂資料庫可用)"
  else
    echo "$WARN heygen CLI 有裝但沒登入。 執行: heygen auth login --oauth"
  fi
else
  echo "$WARN heygen CLI 沒裝(選配 — 只有要用音效／音樂資料庫才需要)。"
  echo "        安裝: curl -fsSL https://static.heygen.ai/cli/install.sh | bash   再: heygen auth login --oauth"
fi

# --- 4. 首次建立個人偏好檔（從範本複製，之後不進 git，更新才不會蓋掉）---
if [ ! -f "$KIT/我的剪輯偏好.md" ] && [ -f "$KIT/tools/我的剪輯偏好.範本.md" ]; then
  cp "$KIT/tools/我的剪輯偏好.範本.md" "$KIT/我的剪輯偏好.md"
  echo "$OK 建立個人偏好檔：我的剪輯偏好.md"
fi

# --- 5. 把內部運作用的檔案在 Finder/檔案總管裡藏起來（純外觀，git 跟指令都不受影響）---
# 這樣使用者打開資料夾只會看到 審片.html、我的影片/、素材庫/、我的剪輯偏好.md、錯誤回報/。
# 純粹是每台機器的顯示設定，不影響 git 追蹤或任何腳本行為，隨時可以在 Finder 用
# Cmd+Shift+. 切換顯示；重跑這段也不會出錯（已經隱藏的檔案再隱藏一次沒有副作用）。
HIDE_LIST=("README.md" "LICENSE" ".gitignore" "setup.sh" "tools")
if [ "$UNAME" = "Darwin" ]; then
  for f in "${HIDE_LIST[@]}"; do
    [ -e "$KIT/$f" ] && chflags hidden "$KIT/$f" 2>/dev/null
  done
elif command -v attrib >/dev/null 2>&1; then
  for f in "${HIDE_LIST[@]}"; do
    [ -e "$KIT/$f" ] && attrib +h "$KIT/$f" 2>/dev/null
  done
fi
# Linux 檔案總管沒有統一的隱藏機制，跳過（不影響功能，只差在看不看得到而已）。

echo ""
echo "=== 完成 ==="
echo "用 Claude Code(或 Codex)打開這個資料夾,ai-edit 技能會自動載入。"
echo "然後把影片丟進來,說你想怎麼剪。詳見 README.md 或跟 AI 問。"
echo "(資料夾裡少了幾個檔案是正常的 — setup.sh 把工具包內部運作用的檔案藏起來了,"
echo " 不影響任何功能;Finder/檔案總管開隱藏檔案的快速鍵可以隨時看到它們。)"
