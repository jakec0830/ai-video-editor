#!/usr/bin/env bash
# 清理工具 — 只刪一個專案「工作檔/」裡的大媒體檔,保留「配方」文字檔。
#
# 為什麼這樣設計:
#   真正佔空間的是 mp4/mov/png/wav/mp3 跟 node_modules;
#   但 edl.json、transcripts/、captions/*.json/*.html 這些文字檔加起來通常 < 1MB,
#   卻是整個專案的「配方」— 留著它們,隔天回來只要重跑 render 就好,
#   不用重轉逐字稿、重 init、重對時間軸(那些才是燒時間跟 token 的地方)。
#
# 用法: bash tools/cleanup.sh <專案資料夾>
set -u

PROJ="${1:-}"
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ]; then
  echo "用法: bash tools/cleanup.sh <專案資料夾>"
  echo "(專案資料夾裡面應該有 原始影片、成品.mp4、工作檔/)"
  exit 1
fi

WORK="$PROJ/工作檔"
REVIEW="$PROJ/審片區"
if [ ! -d "$WORK" ] && [ ! -d "$REVIEW" ]; then
  echo "這個專案沒有「工作檔/」或「審片區/」資料夾,沒東西要清。"
  exit 0
fi
SCAN_DIRS=()
[ -d "$WORK" ] && SCAN_DIRS+=("$WORK")
[ -d "$REVIEW" ] && SCAN_DIRS+=("$REVIEW")

# 會刪的:大媒體檔(可重生)+ 已知的大型可重生資料夾
#   注意:captions/index.html、captions/*.json 這些「配方」不在刪除範圍。
MEDIA_EXT=(mp4 mov m4v webm mkv wav mp3 m4a aac png jpg jpeg gif)
BIG_DIRS=(node_modules clips_preview __pycache__ chk .hyperframes)

echo "掃描: ${SCAN_DIRS[*]}"
echo ""

# 蒐集要刪的清單
TMP_LIST="$(mktemp)"
for dir in "${SCAN_DIRS[@]}"; do
  for ext in "${MEDIA_EXT[@]}"; do
    find "$dir" -type f -iname "*.${ext}" -print >> "$TMP_LIST" 2>/dev/null
  done
  for d in "${BIG_DIRS[@]}"; do
    find "$dir" -type d -name "$d" -print >> "$TMP_LIST" 2>/dev/null
  done
done

if [ ! -s "$TMP_LIST" ]; then
  echo "沒有找到可清理的媒體檔或大資料夾,工作檔已經很乾淨。"
  rm -f "$TMP_LIST"
  exit 0
fi

DEL_SIZE="$(du -sch $(cat "$TMP_LIST") 2>/dev/null | tail -1 | cut -f1)"
DEL_COUNT="$(wc -l < "$TMP_LIST" | tr -d ' ')"

echo "會刪掉(約 ${DEL_SIZE:-未知}, ${DEL_COUNT} 項)— 大媒體檔 + 可重生資料夾:"
sed 's#^#  - #' "$TMP_LIST" | head -20
[ "$DEL_COUNT" -gt 20 ] && echo "  … 還有 $((DEL_COUNT-20)) 項"
echo ""
echo "會保留(專案配方,重做只要重跑 render):"
echo "  - edl.json、transcripts/(逐字稿 + words.txt)"
echo "  - captions/index.html、captions/captions.json、fixes.json、build 設定"
echo "  - 專案筆記.md、任何 .md / .srt / .txt"
echo "  - 原始影片、成品.mp4(在專案最上層,本來就不動)"
echo ""
printf "確定要刪嗎? 輸入 yes 確認: "
read -r ANS
if [ "$ANS" = "yes" ]; then
  while IFS= read -r p; do rm -rf "$p"; done < "$TMP_LIST"
  echo "已清理。配方文字檔、原始影片、成品.mp4 都還在。"
  echo "下次回來:cd 進 captions/ 跑 npm install(如果刪了 node_modules)再 render 即可。"
else
  echo "取消,沒有刪任何東西。"
fi
rm -f "$TMP_LIST"
