#!/usr/bin/env bash
# 清理工具 — 只刪一個專案裡的「工作檔/」,保留原始影片跟成品.mp4。
# 用法: bash cleanup.sh <專案資料夾>
set -u

PROJ="${1:-}"
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ]; then
  echo "用法: bash cleanup.sh <專案資料夾>"
  echo "(專案資料夾裡面應該有 原始影片、成品.mp4、工作檔/)"
  exit 1
fi

WORK="$PROJ/工作檔"
if [ ! -d "$WORK" ]; then
  echo "這個專案沒有「工作檔/」資料夾,沒東西要清。"
  exit 0
fi

SIZE="$(du -sh "$WORK" 2>/dev/null | cut -f1)"
echo "準備清理: $WORK"
echo "大小: ${SIZE:-未知}"
echo ""
echo "會保留: 原始影片、成品.mp4"
echo "會刪掉: 工作檔/ 裡的全部中間檔(逐字稿、預覽、字幕專案、擷取的畫面等)"
echo ""
printf "確定要刪嗎? 輸入 yes 確認: "
read -r ANS
if [ "$ANS" = "yes" ]; then
  rm -rf "$WORK"
  echo "已清理。原始影片跟成品.mp4 都還在。"
else
  echo "取消,沒有刪任何東西。"
fi
