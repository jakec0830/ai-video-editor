---
name: ai-edit
description: Edit a talking-head video end to end by conversation - transcribe locally, cut retakes and pauses, add styled Traditional Chinese captions, visual effects, sound effects, and BGM, then render a final MP4. Use when the user drops in raw footage and wants an edited short-form video. Covers the full pipeline (local Whisper cut layer + HyperFrames caption/FX layer) including the ground-truth tools that keep Whisper's timing lies from breaking cuts.
---

# ai-edit — AI 剪輯 pipeline (student kit)

Agent-portable: any coding agent with shell + file tools (Claude Code, Codex, Cursor) can follow this. Commands are plain shell. **All paths are relative to the KIT ROOT** (the folder containing this kit — where `setup.sh`, `tools/`, and `PIPELINE-NOTES.md` live). If your working directory is elsewhere, resolve `KIT` to that folder first. Deep reference: `PIPELINE-NOTES.md` at the kit root.

"Ask the user" = use whatever question mechanism your harness has; if fully autonomous, pick sensible defaults and say so.

## First-time setup — WALK THE USER THROUGH IT (don't just report)

When a student says "help me set up" / "幫我安裝" / it's their first run, actively install the missing pieces for them, one at a time. Do NOT dump a checklist and leave.

1. Run `bash setup.sh` from the kit root and read its output. It builds the Python venv + whisper backend automatically and marks each external tool `[OK]`, `[!]`, or `[X]`.
2. For each `[X]` (missing) or `[!]` (needs attention), handle it interactively:
   - Detect the platform (`uname -s` / `uname -m`). Pick the right install command.
   - **Explain what you're about to install and why** (one line), then run it. In Claude Code it may prompt for permission — that's normal.
   - Re-run `setup.sh` after each install to confirm it flipped to `[OK]` before moving on.
3. Common installs by platform:
   - ffmpeg — Mac `brew install ffmpeg` · Windows `choco install ffmpeg` (admin PowerShell) · Linux `sudo apt install ffmpeg`
   - Node >= 22 — Mac `brew install node` · else nodejs.org installer
   - Homebrew (Mac, if `brew` missing) — the official `curl ... install.sh | bash`; **this asks for the user's password — hand that step to them, you cannot type it**
   - font 思源宋體 — Mac `brew install --cask font-source-han-serif-vf` · else download from github.com/adobe-fonts/source-han-serif and the user double-clicks to install
   - heygen (optional) — `curl -fsSL https://static.heygen.ai/cli/install.sh | bash` then `heygen auth login --oauth` (**the OAuth login opens a browser and is the user's own account — hand it to them**)

**Hand back to the user (you cannot do these):** anything needing a password / sudo / admin prompt, any browser OAuth login, any GUI installer (especially Node/font on Windows). Say clearly "this next step is yours: <what and why>", wait, then continue. On Windows without bash, `setup.sh` won't run — walk them through the README "手動安裝" commands one at a time instead.

**Bootstrap floor:** installing Claude Code itself + logging in is done BEFORE this skill can run (it's how they're talking to you). Never try to install Claude Code from here.

**Transcription is cross-platform.** `transcribe.py` auto-detects `mlx-whisper` on Apple Silicon (fastest) or `faster-whisper` elsewhere (Windows / Intel / Linux, CPU or NVIDIA). Same models, same repeat-collapse behaviour — the xref/waveform ground-truth steps matter equally on both.

Shorthand once set up: the note below (`PY`, `H`) points at the built venv + helpers.

Shorthand for the rest of this file: `PY="$KIT/tools/freecut/.venv/bin/python3"` and `H="$KIT/tools/freecut/helpers"`.

## The pipeline

Work in `<video_dir>/edit/` next to the source video.

### 1. Transcribe + cross-reference (BEFORE any cut)

```bash
$PY $H/transcribe.py <video> --backend whisper --language zh --edit-dir <video_dir>/edit
$PY $H/xref_silence.py <video> <video_dir>/edit/transcripts/<name>.json
```

For every MERGE flag, run `$PY $H/split_blobs.py <video> <start> <end>` and show the user the real speech blobs BEFORE cutting. MERGE regions are where Whisper lies (repeated words collapse into one token; filler absorbs into word spans). Never fine-cut inside a flagged region from transcript timing alone.

### 2. Structural cut (pass 1 — from transcript)

Propose in plain language first: which take to keep, which retakes to drop, which pauses to trim (~300ms between phrases, not 130ms — too tight reads as jumpy). Wait for confirmation, then write `edit/edl.json`:

```json
{"version":1,"sources":{"NAME":"/abs/path.MOV"},
 "ranges":[{"source":"NAME","start":1.53,"end":7.54,"beat":"HOOK","quote":"...","reason":"..."}],
 "grade":"none","overlays":[],"subtitles":null,"total_duration_s":0}
```

All range times are RAW SOURCE seconds. Render: `$PY $H/render.py edit/edl.json -o edit/preview_v1.mp4 --preview --no-subtitles`

### 3. Fine cuts (pass 2 — user-driven, waveform ground truth)

For any correction the user reports:
- `$PY $H/timeline_view.py <RAW video> <start> <end> --n-frames 20 -o wave.png` and show it — the user reads exact timestamps off the waveform axis.
- Corrections given in RAW-source time (stable across re-edits). Output-timeline times drift on every cut change — never chain-offset old numbers.
- You cannot hear audio. Word-content questions are settled by the user's ear or the waveform, not by re-running Whisper (bigger models don't fix repeat-collapse).

### 4. Captions (HyperFrames light path — no matting)

```bash
mkdir <video_dir>/edit/captions && cd there
npx hyperframes init . --non-interactive --video ../preview_vN.mp4
```

Author `index.html` directly (scaffold + these rules):
- Composition + video sized to the footage (vertical = 1080x1920; scaffold defaults to landscape — override)
- `lang="zh-Hant"`, font `"Source Han Serif VF"` via `@font-face { src: local("Source Han Serif VF"); }`
- Remap the word transcript onto the output timeline by walking the EDL (recompute from scratch after EVERY cut change — never incremental offsets)
- Natural sentence-length phrase groups (8-10 chars). Show the group list as editable text for the user to re-break BEFORE rendering
- Phrase-level boxes only, contiguous during continuous speech (no dead gaps). NO per-word karaoke highlight — Whisper word timing is not reliable enough
- Every timed element: `class="clip"` + `data-start` + `data-duration` + `data-track-index`; one paused GSAP timeline on `window.__timelines["main"]`; deterministic only (no Math.random/Date.now/infinite repeats)
- **`data-duration` = the ACTUAL ffprobe'd duration of the cut file, never the EDL sum** (loudnorm adds ~0.2s; the EDL number silently truncates the last word)

Always `npx hyperframes lint` after every edit → fix errors → then render. (Optional richer FX skills: `npx hyperframes skills update` pulls the official HyperFrames skills.)

### 5. Effects (optional)

GSAP overlays in the same composition:
- Gesture-synced FX placement is a VISUAL question: extract frames (`ffmpeg -ss T -i vid -vframes 1 f.png`), look at them, place the element where the hand/gesture is. The transcript can't tell you where a hand is or when a finger snaps.
- Real brand assets over invented ones (user supplies anything the catalogs lack — catalog gaps are normal)
- Finite repeats only, cubic easing, `overwrite:"auto"` on colliding tweens

### 6. Render for viewing

```bash
npx hyperframes render --quality standard --output renders/out.mp4
```

`--quality draft` outputs a codec ONLY for frame-extraction checks — it plays back broken in players. Anything the user watches must be `standard`. Verify output duration with ffprobe; extract 3-5 frames and actually look at them before saying it's done.

### 7. Sound (SFX + BGM) — single ffmpeg pass, video copied

Search catalog (needs heygen auth): `heygen audio sounds list --type sound_effects --query "..." --min-score 0.4 --limit 6` (music: `--type music`). Download candidates and let the USER audition — semantic scores are not ears. Check levels with `ffmpeg -i f.mp3 -af volumedetect -f null -` and boost quiet files (a -18dB-peak SFX needs ~6x).

```bash
ffmpeg -y -i video.mp4 -i sfx1.mp3 -i bgm.mp3 -filter_complex "
[1:a]aformat=channel_layouts=stereo,volume=0.55,adelay=MS|MS[s1];
[2:a]atrim=0:DUR,afade=t=in:st=0:d=0.9,afade=t=out:st=END:d=1.4,volume=0.2[bgm];
[0:a][s1][bgm]amix=inputs=3:normalize=0[mix];[mix]alimiter=limit=0.97[aout]
" -map 0:v -map "[aout]" -c:v copy -c:a aac -b:a 192k out.mp4
```

BGM ~0.15-0.25 volume (under speech); loop short tracks with `-stream_loop`. SFX timing from the output-timeline word timestamps.

## Interaction protocol (why the loop stays short)

1. Propose → confirm → execute → show → iterate. Never re-cut on a guess about audio content.
2. User's ear = ground truth for sound; the waveform = shared pointing device; raw-source timestamps = shared coordinate system.
3. When the user reports something you can't verify (a doubled word, an offbeat sync), investigate with tools (split_blobs, frame extraction) before changing numbers.
4. Version outputs (`preview_v1..vN`), keep the EDL as source of truth, delete superseded renders as you go.
