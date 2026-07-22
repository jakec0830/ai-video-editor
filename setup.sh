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
# 找一個「真的」的 Python。Windows 全新機器上 python3/python 指令可能是
# Microsoft Store 的空殼(App Execution Alias):command -v 找得到,但一執行
# 只會跳商店頁、不會真的跑。所以要實際跑 --version 確認吐得出版本號。
find_python() {
  for cand in python3 python; do
    p="$(command -v "$cand" 2>/dev/null || true)"
    [ -z "$p" ] && continue
    case "$p" in *WindowsApps*) continue ;; esac   # 明確排除商店空殼
    if v="$("$p" --version 2>&1)" && echo "$v" | grep -qiE 'python 3\.'; then
      echo "$p"; return 0
    fi
  done
  return 1
}
PY3="$(find_python || true)"
if [ -z "$PY3" ]; then
  echo "$ERR 找不到可用的 python3。"
  echo "     Windows 若看到「Microsoft Store」跳出來,代表 Python 沒真的裝。"
  echo "     裝法: winget install Python.Python.3.12  (或到 python.org 下載)"
  echo "     裝完把終端機關掉重開,再重跑一次。"
  exit 1
fi
echo "$OK python3: $("$PY3" --version)  ($PY3)"

if [ ! -d "$FREECUT/.venv" ]; then
  echo "   建立 Python 環境 (tools/freecut/.venv) ..."
  "$PY3" -m venv "$FREECUT/.venv"
fi
VPY="$FREECUT/.venv/bin/python3"
[ -f "$VPY" ] || VPY="$FREECUT/.venv/Scripts/python.exe"   # Windows 路徑
# venv 建好要當場確認,不然後面 pip 才爆、錯誤訊息還對不上病因。
if [ ! -f "$VPY" ]; then
  echo "$ERR Python 環境沒建成功(找不到 $VPY)。"
  echo "     多半是上面那支 python 是空殼。確認 Python 真的裝好再重跑。"
  exit 1
fi
"$VPY" -m pip install -q --upgrade pip >/dev/null 2>&1

echo "   安裝核心套件 (requests, pillow, numpy, opencc) ..."
# opencc-python-reimplemented: 簡轉繁,純 Python(沒有 C++ DLL)。刻意不用 PyPI 的
# `opencc`,因為那個帶未簽章 DLL,在 Windows 上可能又被 Smart App Control 擋 —
# 我們就是為了躲這個才走 XXL,不能在轉繁這步又踩回去。API 一樣是 OpenCC("s2twp")。
"$VPY" -m pip install -q requests pillow numpy opencc-python-reimplemented

# --- 2. 依平台裝 Whisper 引擎 -----------------------------------------------
UNAME="$(uname -s 2>/dev/null || echo unknown)"
ARCH="$(uname -m 2>/dev/null || echo unknown)"
case "$UNAME" in *_NT*|MINGW*|MSYS*|CYGWIN*) IS_WINDOWS=1 ;; *) IS_WINDOWS=0 ;; esac

if [ "$UNAME" = "Darwin" ] && [ "$ARCH" = "arm64" ]; then
  echo "   偵測到 Apple Silicon → 安裝 mlx-whisper(最快) ..."
  "$VPY" -m pip install -q mlx-whisper && echo "$OK mlx-whisper 已安裝"
elif [ "$IS_WINDOWS" = "1" ]; then
  # Windows: pip 版 faster-whisper 會被 Smart App Control 擋(它依賴的 av 套件
  # 帶未簽章 DLL)。pip 會「裝成功」但一 import 就死。所以裝完一定要當場驗證,
  # 失敗就改走 Purfview 的 Faster-Whisper-XXL standalone exe(不含未簽章 DLL)。
  echo "   Windows → 先試 faster-whisper(pip) ..."
  "$VPY" -m pip install -q faster-whisper >/dev/null 2>&1
  if "$VPY" -c "import faster_whisper" >/dev/null 2>&1; then
    echo "$OK faster-whisper 已安裝且可用"
  else
    echo "$WARN faster-whisper 裝了但無法載入(多半是 Windows Smart App Control"
    echo "        擋掉未簽章 DLL:「應用程式控制原則已封鎖此檔案」)。"
    echo "        改用 Faster-Whisper-XXL 獨立版(不會被擋),請手動下載:"
    echo "        1. https://github.com/Purfview/whisper-standalone-win/releases"
    echo "        2. 下載 Faster-Whisper-XXL 的 Windows 版,解壓縮"
    echo "        3. 把整個資料夾放到 tools/whisper-xxl/(裡面要有 faster-whisper-xxl.exe)"
    echo "        或設環境變數 WHISPER_XXL_EXE 指到那個 exe。詳見 README「Windows 疑難排解」。"
  fi
else
  echo "   $UNAME/$ARCH → 安裝 faster-whisper(CPU/NVIDIA,跨平台) ..."
  "$VPY" -m pip install -q faster-whisper && echo "$OK faster-whisper 已安裝"
fi

# 若已放了 XXL standalone exe,回報一下(Windows fallback 就緒)
if find "$KIT/tools/whisper-xxl" "$FREECUT/whisper-xxl" -name "faster-whisper-xxl*" -type f 2>/dev/null | grep -q .; then
  echo "$OK Faster-Whisper-XXL 獨立版已就位(tools/whisper-xxl/)"
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
HIDE_LIST=("README.md" "LICENSE" ".gitignore" "setup.sh" "setup.ps1" "scripts" "tools")
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
