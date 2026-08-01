#!/usr/bin/env bash
# send_report.sh — 把學員的回報(復盤/錯誤/建議)送回課程團隊的收集表單。
# 零認證:收件匣是公開的 Google 表單,只能「投遞」,看不到別人的內容。
# 送不出去(離線/被擋)也不會失敗 — 檔案本來就存在 錯誤回報/,照舊用 LINE 傳。
#
# 隱私:送出前會把報告裡的「電腦帳號名稱」洗掉(家目錄 / /Users/<帳號> / /home/<帳號>
#       一律換成 USER),所以路徑類的個資不會外流。學員自己說的稱呼(--name)是他選的
#       綽號,那個照送(那是識別報告用的,不是系統帳號)。
#
# 用法:
#   bash send_report.sh --name "學員名" --project "專案名" --type "復盤|錯誤回報|功能建議|其他" \
#                       --content-file <報告.md> [--env "環境一行"]
set -u

FORM_URL="https://docs.google.com/forms/d/e/1FAIpQLSemFy9dciTJrBG2gRVIKER3GkLdu1WDszQI92CHF-YY319tqg/formResponse"
E_NAME="entry.1502275075"
E_PROJ="entry.531432527"
E_TYPE="entry.969252018"
E_BODY="entry.413630532"
E_ENV="entry.834155630"

NAME=""; PROJ=""; TYPE="其他"; FILE=""; ENVINFO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --name) NAME="$2"; shift 2;;
    --project) PROJ="$2"; shift 2;;
    --type) TYPE="$2"; shift 2;;
    --content-file) FILE="$2"; shift 2;;
    --env) ENVINFO="$2"; shift 2;;
    *) shift;;
  esac
done

if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
  echo "用法: send_report.sh --name <學員名> --project <專案> --type <類型> --content-file <檔案> [--env <環境>]"
  exit 3
fi

# ★ 退出開關由這支腳本自己守,不是靠 AI 記得先檢查。
# README 對學員承諾過「說不要就不會回傳」,但這個承諾原本只寫在 SKILL.md 裡 —— 也就是
# **只有 AI 看得到**,任何一次忘記檢查就是在違反承諾送出他的資料。同一類問題今天踩過
# 好幾次(字幕安全區、素材圖被刪),共通點都是「規則只寫在文件、沒寫進工具」。
#   .回傳關閉    使用者說不要回傳(README 承諾的退出方式)
#   .我是維護者  使用者本人就是課程團隊,寄給自己沒意義,還會污染真正的學員回報
REPORT_DIR="$(cd "$(dirname "$FILE")" && pwd)"
for guard in .回傳關閉 .我是維護者; do
  # 報告檔所在的資料夾、以及工具包的 錯誤回報/ 都看一下
  for d in "$REPORT_DIR" "$(cd "$(dirname "$0")/../../.." 2>/dev/null && pwd)/錯誤回報"; do
    if [ -n "$d" ] && [ -e "$d/$guard" ]; then
      echo "偵測到 $guard — 依設定不回傳,報告保留在 $FILE"
      exit 0
    fi
  done
done

# 類型白名單。表單那題是單選,送一個不在選項裡的值,Google 會直接回 HTTP 400 退件。
# 而這支腳本刻意「送不出去也不報錯」(不該卡住新手),所以不合法的值會變成**靜默失敗** —
# 實測炸過:SKILL.md 叫 AI 用「安裝紀錄」,但表單沒有這個選項,於是每一台新機器的
# 安裝紀錄都送不出去,課程團隊那邊卻是一片空白,還以為沒消息就是好消息。
# 修法:不在清單裡的一律降級成「其他」,並把原始類型寫進內文開頭,語意不會掉。
# 以後 SKILL.md 再新增類型也不會靜默失敗。
VALID_TYPES="復盤 錯誤回報 功能建議 其他"
ORIG_TYPE="$TYPE"
case " $VALID_TYPES " in
  *" $TYPE "*) ;;
  *) TYPE="其他" ;;
esac
[ -z "$ENVINFO" ] && ENVINFO="$(uname -sm) · node $(node --version 2>/dev/null || echo '?') · $(sw_vers -productVersion 2>/dev/null || echo '')"

# 洗掉電腦帳號名稱(唯一會夾帶的個資,通常藏在路徑裡)。送的是這份洗過的副本,不動原檔。
# Windows 學員實測(2026-07-31):原本只洗 /Users//home 形式,C:\Users\帳號 完全沒洗到,
# 帳號名真的外洩過 — Windows 的三種路徑寫法(C:\、C:/、/c/)都要洗。
WORKDIR="$(mktemp -d -t freecut_send.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT
SCRUBBED="$WORKDIR/report.md"
UNAME_USER="$(id -un 2>/dev/null || whoami 2>/dev/null || echo user)"
{
  # 類型被降級的話,把原始類型記在內文開頭,課程團隊還是分得出這份是什麼。
  [ "$ORIG_TYPE" != "$TYPE" ] && printf '【原始類型:%s(表單無此選項,已降級為 %s)】\n\n' "$ORIG_TYPE" "$TYPE"
  sed -e "s#[Cc]:\\\\[Uu]sers\\\\${UNAME_USER}#C:\\\\Users\\\\USER#g" \
      -e "s#[Cc]:/[Uu]sers/${UNAME_USER}#C:/Users/USER#g" \
      -e "s#/c/[Uu]sers/${UNAME_USER}#/c/Users/USER#g" \
      -e "s#${HOME}#~#g" \
      -e "s#/Users/${UNAME_USER}#/Users/USER#g" \
      -e "s#/home/${UNAME_USER}#/home/USER#g" \
      "$FILE"
} > "$SCRUBBED"

# Windows(Git Bash)的 curl 是原生 exe:
# 1. 讀不懂 MSYS 的 /tmp/... 路徑 → 有 cygpath 就轉成原生路徑再餵給它。
# 2. 命令列上的中文參數會被轉成系統 ANSI codepage(繁中 = Big5),單選題的值對不上
#    選項,Google 直接回 400 → 所有含中文的值一律寫成檔案、用 name@file 餵,
#    讀檔是原始位元組,不經轉換。這做法在 Mac/Linux 行為完全相同,不用分平台。
topath() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi
}
printf '%s' "${NAME:-未填}"  > "$WORKDIR/name"
printf '%s' "${PROJ:-未填}"  > "$WORKDIR/proj"
printf '%s' "${TYPE}"        > "$WORKDIR/type"
printf '%s' "${ENVINFO}"     > "$WORKDIR/env"

# 失敗不能再靜默:Windows 上兩個 bug 疊著被 2>/dev/null 吞掉,課程團隊整整一個梯次
# 沒收到任何 Windows 回報。錯誤訊息要留下來、要印出來。
CURL_ERR="$WORKDIR/curl_err"
HTTP_CODE=$(curl -sS --max-time 20 -o /dev/null -w "%{http_code}" \
  --data-urlencode "${E_NAME}@$(topath "$WORKDIR/name")" \
  --data-urlencode "${E_PROJ}@$(topath "$WORKDIR/proj")" \
  --data-urlencode "${E_TYPE}@$(topath "$WORKDIR/type")" \
  --data-urlencode "${E_BODY}@$(topath "$SCRUBBED")" \
  --data-urlencode "${E_ENV}@$(topath "$WORKDIR/env")" \
  "$FORM_URL" 2>"$CURL_ERR")

if [ "$HTTP_CODE" = "200" ]; then
  if [ "$ORIG_TYPE" != "$TYPE" ]; then
    echo "已回傳給課程團隊(${ORIG_TYPE} → 表單無此選項,以「${TYPE}」送出,原始類型已記在內文)。"
  else
    echo "已回傳給課程團隊(${TYPE})。"
  fi
else
  echo "回傳沒成功(HTTP ${HTTP_CODE:-無回應})— 沒關係,檔案還在,之後可以用 LINE 傳。"
  if [ -s "$CURL_ERR" ]; then
    echo "curl 錯誤訊息(給 AI 診斷用,不用理它):"
    sed 's/^/  /' "$CURL_ERR"
  fi
fi
