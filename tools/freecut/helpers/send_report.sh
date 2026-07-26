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
SCRUBBED="$(mktemp -t freecut_report.XXXXXX)"
trap 'rm -f "$SCRUBBED"' EXIT
UNAME_USER="$(id -un 2>/dev/null || whoami 2>/dev/null || echo user)"
{
  # 類型被降級的話,把原始類型記在內文開頭,課程團隊還是分得出這份是什麼。
  [ "$ORIG_TYPE" != "$TYPE" ] && printf '【原始類型:%s(表單無此選項,已降級為 %s)】\n\n' "$ORIG_TYPE" "$TYPE"
  sed -e "s#${HOME}#~#g" \
      -e "s#/Users/${UNAME_USER}#/Users/USER#g" \
      -e "s#/home/${UNAME_USER}#/home/USER#g" \
      "$FILE"
} > "$SCRUBBED"

HTTP_CODE=$(curl -sS --max-time 20 -o /dev/null -w "%{http_code}" \
  --data-urlencode "${E_NAME}=${NAME:-未填}" \
  --data-urlencode "${E_PROJ}=${PROJ:-未填}" \
  --data-urlencode "${E_TYPE}=${TYPE}" \
  --data-urlencode "${E_BODY}@${SCRUBBED}" \
  --data-urlencode "${E_ENV}=${ENVINFO}" \
  "$FORM_URL" 2>/dev/null)

if [ "$HTTP_CODE" = "200" ]; then
  if [ "$ORIG_TYPE" != "$TYPE" ]; then
    echo "已回傳給課程團隊(${ORIG_TYPE} → 表單無此選項,以「${TYPE}」送出,原始類型已記在內文)。"
  else
    echo "已回傳給課程團隊(${TYPE})。"
  fi
else
  echo "回傳沒成功(HTTP ${HTTP_CODE:-無回應})— 沒關係,檔案還在,之後可以用 LINE 傳。"
fi
