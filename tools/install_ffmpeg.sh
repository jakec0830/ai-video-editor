#!/usr/bin/env bash
# install_ffmpeg.sh — Mac 免密碼安裝 ffmpeg/ffprobe(指定來源 + 指定版本 + 驗寫死的 SHA256)
#
# 為什麼要這支:12 台學員機器的安裝紀錄顯示,SKILL 只寫「社群 static build + 驗 SHA256」
# 沒指名來源,每個 session 都自己找、每台選的還不一樣,而且三個常見來源各有雷:
#   - evermeet.cx 只有 x86_64(Apple Silicon 裝了跑不動,8 台踩過)
#   - osxexperts.net 頁面公布的 SHA256 時對時錯
#   - martin-riedl.de 的下載 API 已 404
# 這支把來源跟指紋直接寫死:eugeneware/ffmpeg-static b6.1.1(GitHub Releases,
# arm64/x64 都有、含 ffprobe、含 subtitles/drawtext/loudnorm/ebur128 全部需要的濾鏡,
# 2026-08-01 實機驗證)。驗證對象是「本檔案裡寫死的 SHA256」,不是網站當天說什麼。
#
# 用法: bash tools/install_ffmpeg.sh
# 裝到 ~/.local/bin(免密碼、免 Homebrew),裝完會實跑驗證。
set -euo pipefail

RELEASE="https://github.com/eugeneware/ffmpeg-static/releases/download/b6.1.1"
DEST="$HOME/.local/bin"

ARCH="$(uname -m)"
case "$ARCH" in
  arm64)
    FFMPEG_SHA="a90e3db6a3fd35f6074b013f948b1aa45b31c6375489d39e572bea3f18336584"
    FFPROBE_SHA="bb2db6f5d8cef919da12fbf592119a987202a8c060a886f3cab091f9cab90b64"
    SUFFIX="darwin-arm64"
    ;;
  x86_64)
    FFMPEG_SHA="ebdddc936f61e14049a2d4b549a412b8a40deeff6540e58a9f2a2da9e6b18894"
    FFPROBE_SHA="fa3add0ce901f7241abe0dfc0155d958fc834aca3f8ce61f87cc712ae669c1e0"
    SUFFIX="darwin-x64"
    ;;
  *)
    echo "不認得的架構:$ARCH(這支只管 Mac;Windows 走 setup.ps1 的 winget)"; exit 1
    ;;
esac

mkdir -p "$DEST"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

for tool in ffmpeg ffprobe; do
  echo "下載 $tool($SUFFIX,約 45-80MB,慢的網路要幾分鐘)..."
  curl -fL --retry 3 --retry-delay 2 -o "$TMP/$tool" "$RELEASE/$tool-$SUFFIX"

  GOT="$(shasum -a 256 "$TMP/$tool" | cut -d' ' -f1)"
  WANT="$([ "$tool" = "ffmpeg" ] && echo "$FFMPEG_SHA" || echo "$FFPROBE_SHA")"
  if [ "$GOT" != "$WANT" ]; then
    echo "✗ $tool 的 SHA256 對不上(下載到 $GOT,預期 $WANT)。"
    echo "  檔案沒裝。可能是下載壞掉(重跑一次)或來源被動過(回報課程團隊)。"
    exit 1
  fi
  chmod +x "$TMP/$tool"
  mv "$TMP/$tool" "$DEST/$tool"
  echo "✓ $tool 裝好(SHA256 驗過)"
done

# 實跑驗證:會動、而且字幕濾鏡在(靜態包缺 libass 的話 render 字幕那步必炸,先驗掉)
"$DEST/ffmpeg" -version | head -1
"$DEST/ffprobe" -version | head -1
# 注意:這裡不能用 `ffmpeg -filters | grep -q`。grep -q 一比中就先退出,ffmpeg 吃到
# SIGPIPE 回 141,配上 set -o pipefail 整條 pipeline 變失敗 — 明明有濾鏡卻報沒有(實測)。
FILTERS="$("$DEST/ffmpeg" -filters 2>/dev/null)"
if ! printf '%s' "$FILTERS" | grep -q " subtitles "; then
  echo "✗ 這份 ffmpeg 沒有 subtitles 濾鏡 — 不該發生,回報課程團隊。"; exit 1
fi
echo "✓ subtitles/drawtext 濾鏡都在,可以上字幕"
echo ""
echo "裝在 $DEST(PATH 沒包含的話,source tools/env.sh 或重開終端機)"
