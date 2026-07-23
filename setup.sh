#!/usr/bin/env bash
# ai-edit-kit 安裝 — 建立本機 Python 環境並檢查外部工具。
# Mac / Linux / WSL / Git-Bash 適用。Windows 沒 bash 的話,見 README「手動安裝」。
set -u
KIT="$(cd "$(dirname "$0")" && pwd)"
FREECUT="$KIT/tools/freecut"
OK="[OK] "; WARN="[!]  "; ERR="[X]  "
# 缺了會讓剪片直接炸的必要工具,記在這裡,結尾據此決定印「完成」還是「未完成」。
# (學員實測回報:缺 ffmpeg/node 也照印「=== 完成 ===」,新手以為裝好了,剪到一半才爆。)
MISSING=""

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
    echo "        這個封鎖有時候幾小時後會自己解除(雲端信譽評分重新判定),"
    echo "        不急的話可以先重開機或晚點重跑一次 setup 試試,說不定就通了。"
    echo "        還是被擋的話,改用 Faster-Whisper-XXL 獨立版(不會被擋),請手動下載:"
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

# 沒有 Homebrew 的 Mac(全新機器很常見)會把工具裝到 ~/.local/bin。那個位置預設不在
# PATH 裡,於是「明明裝好了,setup 還是說缺」— 實測回報裡最容易誤判的一關。
# 所以 command -v 找不到時,再去 ~/.local/bin 撈一次,分清楚是「真的沒裝」還是「PATH 沒設」。
# 重點:PATH 要寫進 ~/.zshenv,不是 ~/.zshrc — zsh 只有互動模式才讀 .zshrc,
# 這支腳本是非互動 shell,寫在 .zshrc 它永遠讀不到(已實測確認)。
LOCALBIN="$HOME/.local/bin"
found_tool() {  # $1=指令名;有的話印出可執行檔路徑
  command -v "$1" 2>/dev/null && return 0
  [ -x "$LOCALBIN/$1" ] && { echo "$LOCALBIN/$1"; return 0; }
  return 1
}
PATH_HINT=0   # 有東西只在 ~/.local/bin 找到 → 結尾提示怎麼設 PATH

FFMPEG_BIN="$(found_tool ffmpeg || true)"
if [ -n "$FFMPEG_BIN" ]; then
  echo "$OK ffmpeg: $("$FFMPEG_BIN" -version | head -1 | cut -d' ' -f1-3)"
  command -v ffmpeg >/dev/null 2>&1 || { echo "$WARN     (裝在 $LOCALBIN,但 PATH 沒設 — 見最後說明)"; PATH_HINT=1; }
else
  echo "$ERR 缺 ffmpeg。 Mac: brew install ffmpeg | Windows: choco install ffmpeg | Linux: apt install ffmpeg"
  echo "        Mac 沒有 Homebrew 又不想裝(要密碼)的話,可以裝免密碼的家目錄版 — 請 AI 幫你,或見 README。"
  MISSING="$MISSING ffmpeg"
fi

NODE_BIN="$(found_tool node || true)"
if [ -n "$NODE_BIN" ]; then
  NODE_VER="$("$NODE_BIN" --version)"
  NODE_MAJOR="$(echo "$NODE_VER" | sed 's/v//' | cut -d. -f1)"
  if [ "$NODE_MAJOR" -ge 22 ] 2>/dev/null; then
    echo "$OK node: $NODE_VER(npx hyperframes 可用)"
  else
    echo "$WARN node $NODE_VER 版本太舊。 npx hyperframes 需要 Node 22 以上,請更新。"
    MISSING="$MISSING node(版本太舊)"
  fi
  command -v node >/dev/null 2>&1 || { echo "$WARN     (裝在 $LOCALBIN,但 PATH 沒設 — 見最後說明)"; PATH_HINT=1; }
else
  echo "$ERR 缺 node(字幕／特效要用 npx hyperframes)。到 nodejs.org 裝 Node 22 以上"
  MISSING="$MISSING node"
fi

# 字型(思源宋體 / Source Han Serif)
if fc-list 2>/dev/null | grep -qi "Source Han Serif" || ls "$HOME/Library/Fonts/SourceHanSerif"* >/dev/null 2>&1; then
  echo "$OK 字型: 思源宋體(Source Han Serif)有裝"
else
  echo "$WARN 找不到思源宋體(Source Han Serif VF)。 Mac: brew install --cask font-source-han-serif-vf"
  echo "        其他系統: 到 github.com/adobe-fonts/source-han-serif/releases 下載 .otf.ttc 安裝"
  MISSING="$MISSING 思源宋體"
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
# README.md 刻意留在外面不藏 — 學員照 README 走到一半跑完 setup,回頭想再看就找不到了(實測回報)。
HIDE_LIST=("LICENSE" ".gitignore" "setup.sh" "setup.ps1" "scripts" "tools")
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
if [ "$PATH_HINT" = "1" ]; then
  echo "--- PATH 設定(重要)---"
  echo "上面有工具裝在 $LOCALBIN,但這個位置不在 PATH 裡,所以每次都要打完整路徑才叫得動。"
  echo "把下面這段貼進 ~/.zshenv(注意:是 .zshenv,不是 .zshrc),然後**開一個新的終端機視窗**:"
  echo ""
  echo '  case ":$PATH:" in'
  echo '    *":$HOME/.local/bin:"*) ;;'
  echo '    *) export PATH="$HOME/.local/bin:$PATH" ;;'
  echo '  esac'
  echo ""
  echo "為什麼一定要 .zshenv:zsh 只有「互動模式」才讀 .zshrc,這支腳本跟 AI 跑的指令都是非互動的,"
  echo "寫在 .zshrc 它們永遠讀不到,就會變成「明明裝好了卻說沒裝」。"
  echo "為什麼要開新視窗:已經開著的終端機不會回頭重讀設定檔。"
  echo ""
fi
if [ -n "$MISSING" ]; then
  echo "=== 還沒完成 — 缺:$MISSING ==="
  echo "上面標 $ERR 的項目要裝好,不然一開始剪片就會出錯。"
  echo "最簡單的做法:用 Claude Code 打開這個資料夾,跟它說「幫我一步一步安裝設定」,"
  echo "它會照上面的清單一個一個幫你補,補完會再跑一次這支確認。"
  echo "(資料夾裡少了幾個檔案是正常的 — setup.sh 把工具包內部運作用的檔案藏起來了,"
  echo " 不影響任何功能;Finder/檔案總管開隱藏檔案的快速鍵可以隨時看到它們。)"
  exit 1
fi
echo "=== 完成 ==="
echo "用 Claude Code(或 Codex)打開這個資料夾,ai-edit 技能會自動載入。"
echo "然後把影片丟進來,說你想怎麼剪。詳見 README.md 或跟 AI 問。"
echo "(資料夾裡少了幾個檔案是正常的 — setup.sh 把工具包內部運作用的檔案藏起來了,"
echo " 不影響任何功能;Finder/檔案總管開隱藏檔案的快速鍵可以隨時看到它們。)"
