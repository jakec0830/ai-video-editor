#!/usr/bin/env bash
# 把舊版工具包（用終端機裝的）就地換成新版 zip 工具包（Mac）。
# 用法：bash setup.sh（舊版更新後本來就會跑 setup.sh，現在 setup.sh 只做這件事）
#
# 為什麼：新版把 Python、ffmpeg、特效引擎都放在資料夾裡，不用再裝東西，之後從
# github.com/jackie81030/ai-video-editor-zip 自動更新。舊版 GitHub 之後不再更新。
#
# 會做的事（只覆蓋、只新增，不刪任何東西 —— auto mode 下刪除指令常被擋住）：
#   覆蓋：說明書（CLAUDE.md、AGENTS.md、.claude/skills）、tools/、素材庫/預設包、審片.html
#   保留：我的影片、我的剪輯偏好.md、錯誤回報、學員自己加進素材庫的檔案
#   不動：舊的 Python 環境 tools/freecut/.venv（不再使用，約 1GB，之後想清空間可以刪）
set -u
KIT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="https://github.com/jackie81030/ai-video-editor-zip/releases/latest/download"

if [ -f "$KIT/錯誤回報/.我是維護者" ]; then
  echo "這是維護者的工具包（錯誤回報/.我是維護者），不換成新版。"; exit 0
fi
if [ -f "$KIT/tools/run.sh" ] && [ -d "$KIT/tools/python" ]; then
  # 已經換過：再跑一次只做新版的啟動檢查（例如剛下載好模型，要把它裝進來）
  echo "已經是新版了，做一次啟動檢查。"
  exec bash "$KIT/tools/run.sh" python "$KIT/tools/startup.py"
fi

case "$(uname -m)" in
  arm64) ZIP="AI-Cut-Kit-Mac.zip" ;;
  *)     ZIP="AI-Cut-Kit-Mac-Intel.zip" ;;
esac
DL="$HOME/Downloads"; mkdir -p "$DL"
echo "=== 換成新版工具包 ==="
echo "工具包位置：$KIT"

# 1. 下載（已經在「下載」資料夾就不重抓）
if [ -s "$DL/$ZIP" ] && unzip -tq "$DL/$ZIP" >/dev/null 2>&1; then
  echo "[OK] 已經下載過 $ZIP"
else
  echo "下載新版工具包（約 0.5GB，看網速幾分鐘）..."
  if ! curl -fL --retry 3 --progress-bar -o "$DL/$ZIP.part" "$REPO/$ZIP"; then
    echo "[X] 下載失敗。請換一個網路再試一次，或用瀏覽器打開下面的網址下載到「下載」資料夾後再跑一次："
    echo "    $REPO/$ZIP"; exit 1
  fi
  mv "$DL/$ZIP.part" "$DL/$ZIP"
fi

# 2. 解壓縮到暫存資料夾
TMP="$(mktemp -d)"
echo "解壓縮中..."
if ! ditto -x -k "$DL/$ZIP" "$TMP"; then
  echo "[X] 解壓縮失敗，檔案可能沒下載完整。把「下載」裡的 $ZIP 移到垃圾桶後再跑一次。"; exit 1
fi
NEW="$TMP/AI剪片工具包"
[ -d "$NEW" ] || { echo "[X] zip 裡找不到 AI剪片工具包 資料夾"; exit 1; }

# 3. 覆蓋工具和說明書；學員的東西跳過
#    rsync 不加 --delete：舊檔案留著不刪
rsync -a "$NEW/tools/" "$KIT/tools/"
rsync -a "$NEW/.claude/" "$KIT/.claude/"
rsync -a "$NEW/.agents/" "$KIT/.agents/"
rsync -a "$NEW/素材庫/預設包/" "$KIT/素材庫/預設包/"
rsync -a --ignore-existing "$NEW/素材庫/" "$KIT/素材庫/"
for f in CLAUDE.md AGENTS.md VERSION 使用說明.md 審片.html; do
  [ -e "$NEW/$f" ] && cp -f "$NEW/$f" "$KIT/$f"
done
for d in 我的影片 錯誤回報; do mkdir -p "$KIT/$d"; done
[ -f "$KIT/我的剪輯偏好.md" ] || cp "$NEW/我的剪輯偏好.md" "$KIT/我的剪輯偏好.md"

# 4. 第一次啟動新版：解除下載封鎖、檢查更新、確認模型、裝字型
echo ""
bash "$KIT/tools/run.sh" python "$KIT/tools/startup.py"

echo ""
echo "=== 已經換成新版（$(cat "$KIT/VERSION" 2>/dev/null)）==="
echo "你的影片、剪輯偏好、錯誤回報都還在。"
if [ -d "$KIT/tools/freecut/.venv" ]; then
  echo "舊的 Python 環境 tools/freecut/.venv 不再使用（約 $(du -sh "$KIT/tools/freecut/.venv" 2>/dev/null | cut -f1)），之後想清空間可以刪掉。"
fi
echo "請關掉這個對話，開一個新對話再說「幫我剪」：新版的說明書要在新對話才會讀到。"
