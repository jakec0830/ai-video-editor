#!/usr/bin/env bash
# 更新工具包到最新版（從 GitHub 拉 Jake 的更新）。
# 你的影片、素材、剪輯偏好都不會被動到 — 那些沒有進 git。
set -u
# 這支腳本住在 KIT/tools/ 底下，KIT 根目錄要往上一層找
KIT="$(cd "$(dirname "$0")/.." && pwd)"

if [ ! -d "$KIT/.git" ]; then
  echo "這個資料夾不是用 git 下載的，沒辦法自動更新。"
  echo "請到 github.com/jakec0830/ai-video-editor 重新下載最新版。"
  exit 0
fi

echo "檢查更新中 ..."
git -C "$KIT" fetch --quiet 2>/dev/null
BEHIND="$(git -C "$KIT" rev-list HEAD..@{u} --count 2>/dev/null || echo 0)"

if [ "${BEHIND:-0}" = "0" ]; then
  echo "已經是最新版，不用更新。"
else
  echo "有 $BEHIND 個更新，拉下來 ..."
  if git -C "$KIT" pull --quiet; then
    echo "更新完成。你的影片、素材、偏好都還在。"
  else
    echo "更新沒成功（可能你改動到工具包內建的檔案）。跟 AI 說「回報問題」產一份報告傳給 Jake。"
  fi
fi
