#!/usr/bin/env bash
# ai-edit-kit setup — builds the local Python env and checks external tools.
# Mac / Linux / WSL / Git-Bash. Windows users without bash: see README "手動安裝".
set -u
KIT="$(cd "$(dirname "$0")" && pwd)"
FREECUT="$KIT/tools/freecut"
OK="[OK] "; WARN="[!]  "; ERR="[X]  "

echo "=== ai-edit-kit setup ==="
echo "kit root: $KIT"
echo ""

# --- 1. Python venv + deps -------------------------------------------------
PY3="$(command -v python3 || true)"
if [ -z "$PY3" ]; then
  echo "$ERR python3 not found. Install Python 3.10+ first, then re-run."
  exit 1
fi
echo "$OK python3: $($PY3 --version)"

if [ ! -d "$FREECUT/.venv" ]; then
  echo "   creating venv at tools/freecut/.venv ..."
  "$PY3" -m venv "$FREECUT/.venv"
fi
VPY="$FREECUT/.venv/bin/python3"
[ -f "$VPY" ] || VPY="$FREECUT/.venv/Scripts/python.exe"   # Windows layout
"$VPY" -m pip install -q --upgrade pip >/dev/null 2>&1

echo "   installing core deps (requests, librosa, matplotlib, pillow, numpy) ..."
"$VPY" -m pip install -q requests librosa matplotlib pillow numpy

# --- 2. Whisper backend by platform ---------------------------------------
UNAME="$(uname -s 2>/dev/null || echo unknown)"
ARCH="$(uname -m 2>/dev/null || echo unknown)"
if [ "$UNAME" = "Darwin" ] && [ "$ARCH" = "arm64" ]; then
  echo "   Apple Silicon detected → installing mlx-whisper (fastest) ..."
  "$VPY" -m pip install -q mlx-whisper && echo "$OK mlx-whisper installed"
else
  echo "   $UNAME/$ARCH → installing faster-whisper (CPU/NVIDIA, cross-platform) ..."
  "$VPY" -m pip install -q faster-whisper && echo "$OK faster-whisper installed"
fi

# --- 3. External tools (check, don't force) --------------------------------
echo ""
echo "--- external tools ---"
if command -v ffmpeg >/dev/null 2>&1; then
  echo "$OK ffmpeg: $(ffmpeg -version | head -1 | cut -d' ' -f1-3)"
else
  echo "$ERR ffmpeg missing. Mac: brew install ffmpeg | Windows: choco install ffmpeg | Linux: apt install ffmpeg"
fi

if command -v node >/dev/null 2>&1; then
  NODE_MAJOR="$(node --version | sed 's/v//' | cut -d. -f1)"
  if [ "$NODE_MAJOR" -ge 22 ] 2>/dev/null; then
    echo "$OK node: $(node --version) (npx hyperframes ready)"
  else
    echo "$WARN node $(node --version) is < 22. npx hyperframes needs Node >= 22. Update Node."
  fi
else
  echo "$ERR node missing (needed for captions/FX via npx hyperframes). Install Node >= 22 from nodejs.org"
fi

# font (Source Han Serif / 思源宋體)
if fc-list 2>/dev/null | grep -qi "Source Han Serif" || ls "$HOME/Library/Fonts/SourceHanSerif"* >/dev/null 2>&1; then
  echo "$OK font: Source Han Serif (思源宋體) found"
else
  echo "$WARN font 思源宋體 (Source Han Serif VF) not found. Mac: brew install --cask font-source-han-serif-vf"
  echo "        Others: download from github.com/adobe-fonts/source-han-serif/releases and install the .otf.ttc"
fi

# heygen (optional — SFX/BGM catalog)
if command -v heygen >/dev/null 2>&1; then
  if heygen auth status >/dev/null 2>&1; then
    echo "$OK heygen CLI installed + logged in (SFX/BGM catalog ready)"
  else
    echo "$WARN heygen CLI installed but not logged in. Run: heygen auth login --oauth"
  fi
else
  echo "$WARN heygen CLI not installed (OPTIONAL — only for SFX/BGM catalog)."
  echo "        Install: curl -fsSL https://static.heygen.ai/cli/install.sh | bash   then: heygen auth login --oauth"
fi

echo ""
echo "=== done ==="
echo "Open this folder in Claude Code (or Codex) and the ai-edit skill loads automatically."
echo "Then drop in a video and say what you want. See README.md."
