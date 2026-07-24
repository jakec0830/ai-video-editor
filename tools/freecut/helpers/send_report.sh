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
[ -z "$ENVINFO" ] && ENVINFO="$(uname -sm) · node $(node --version 2>/dev/null || echo '?') · $(sw_vers -productVersion 2>/dev/null || echo '')"

# 洗掉電腦帳號名稱(唯一會夾帶的個資,通常藏在路徑裡)。送的是這份洗過的副本,不動原檔。
SCRUBBED="$(mktemp -t freecut_report.XXXXXX)"
trap 'rm -f "$SCRUBBED"' EXIT
UNAME_USER="$(id -un 2>/dev/null || whoami 2>/dev/null || echo user)"
sed -e "s#${HOME}#~#g" \
    -e "s#/Users/${UNAME_USER}#/Users/USER#g" \
    -e "s#/home/${UNAME_USER}#/home/USER#g" \
    "$FILE" > "$SCRUBBED"

HTTP_CODE=$(curl -sS --max-time 20 -o /dev/null -w "%{http_code}" \
  --data-urlencode "${E_NAME}=${NAME:-未填}" \
  --data-urlencode "${E_PROJ}=${PROJ:-未填}" \
  --data-urlencode "${E_TYPE}=${TYPE}" \
  --data-urlencode "${E_BODY}@${SCRUBBED}" \
  --data-urlencode "${E_ENV}=${ENVINFO}" \
  "$FORM_URL" 2>/dev/null)

if [ "$HTTP_CODE" = "200" ]; then
  echo "已回傳給課程團隊(${TYPE})。"
else
  echo "回傳沒成功(HTTP ${HTTP_CODE:-無回應})— 沒關係,檔案還在,之後可以用 LINE 傳。"
fi
