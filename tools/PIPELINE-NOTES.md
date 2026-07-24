# AI 剪輯 Pipeline Notes (freecut + HyperFrames)

Working notes for the AI 剪輯 (Day 2) tool stack. Pipeline validated end to end
2026-07-19; the operational skill is `.claude/skills/ai-edit/SKILL.md` (written
agent-portable so Codex/Cursor can follow it too). This file stays as the deep
reference the skill links to.

Note: the heavy matting path (`embedded-captions` VFX skill) requires a local
hyperframes monorepo build; the 1.8GB checkout was removed 2026-07-19 — revisiting
that path means re-cloning github.com/heygen-com/hyperframes + `bun install && bun run build`.

## Stack
- **Cut / transcribe:** `tools/freecut/` (video-use fork) + local `mlx-whisper` (free, on-device)
- **Captions / overlays:** HyperFrames via published `npx hyperframes` — the LIGHT path
  (hand-authored caption HTML, no matting), NOT the heavy `embedded-captions` skill
- **Source of truth:** the EDL (`edit/edl.json`) references raw source time; the rendered
  cut (`preview_vN.mp4`) is disposable

## Hard-won rules (each cost real time this session — do not relearn)

1. **Whisper lies at repeats + filler.** It merges repeated words (三個「不知道」→ one token)
   and mistimes the surrounding words, regardless of model size (tested `small` AND
   `large-v3` — both collapse them). Trust the transcript for STRUCTURE, never for fine
   sub-word cuts. Bigger model is NOT the fix; the workflow is.

2. **Two-pass editing.**
   - Pass 1 (me): structural cut from the transcript — hook, drop retakes, trim clean pauses.
   - Pass 2 (fine): user reads a **waveform view** (`helpers/timeline_view.py <video> <start> <end>`)
     and gives me the **raw-source timestamp**. Output-timeline timestamps drift on every
     re-edit; raw source time is stable.

3. **Ground-truth ambiguous audio, don't guess.**
   - `helpers/xref_silence.py <video> <transcript.json>` — flags words whose timing
     disagrees with real ffmpeg silence (MERGE = repeated-word collapse or trailing dead air).
   - `helpers/split_blobs.py <video> <start> <end>` — lists the real speech blobs inside a
     flagged region so we pick from ground truth, not a wrong transcript token.
   - I cannot HEAR audio — I read timestamps and silence only. Word CONTENT confirmation is
     the user's ear or a re-transcribe gamble.

4. **Recompute captions from scratch when the cut changes.** Walk the raw transcript through
   the current EDL to get every group's output position. NEVER incrementally offset old
   numbers by a constant — that drift caused a 0.34s TAG misalignment.

5. **data-duration = actual ffprobe'd file length, NEVER the EDL sum.** loudnorm's two-pass
   adds ~0.2s to the real cut file. Setting the composition duration to the EDL theoretical
   sum silently truncates the last ~0.2s (= the final word's tail). Always:
   `ffprobe -v error -show_entries format=duration ... preview_vN.mp4` and use that number.

6. **Render `--quality standard` for anything the user WATCHES.** `--quality draft` outputs a
   `wrapped_avframe` codec meant only for frame-extraction verification; it plays back broken
   / stops abruptly in QuickTime. Draft is fine for my own `ffmpeg -ss ... -vframes 1` frame
   checks, never for playback.

7. **Karaoke word-highlight: dropped.** Depends on per-word Whisper timing (rule 1) which is
   too unreliable to QA at student scale. Phrase-level box show/hide timing is solid — that's
   the timing precision Whisper IS reliable at. Default = captions yes, karaoke no.

8. **Line-break control for students:** show the caption groups as an editable plain-text
   list (script-style) BEFORE rendering, so they say "combine lines 3+4" / "break after 現在"
   — editing a doc, not describing a video from memory.

## Environment facts
- **Every .ps1 in this repo MUST be UTF-8 *with BOM* (file starts with EF BB BF).** Windows
  PowerShell 5.1 — the built-in edition on every student machine (not pwsh) — parses a BOM-less
  .ps1 with the system codepage (Big5/cp950 on 繁中 systems), so the Chinese strings garble and
  the parser dies before printing anything. This killed setup.ps1 entirely in real Win11 testing
  (2026-07-20 report §7.1). If you edit setup.ps1 / scripts/windows/*.ps1, verify afterward:
  `xxd setup.ps1 | head -1` must start with `efbb bf`. Editors and agents can silently strip it.
- **Windows transcription: pip faster-whisper is blocked by Smart App Control.** On a fresh
  Windows 11 machine, `pip install faster-whisper` "succeeds" but `import faster_whisper` dies
  with 「應用程式控制原則已封鎖此檔案」 — Smart App Control blocks the unsigned FFmpeg DLLs that
  the `av` (PyAV) dependency bundles with random-hash filenames. Do NOT disable Smart App Control
  (irreversible without a Windows reinstall). Fix = the Purfview **Faster-Whisper-XXL** standalone
  exe (bundles everything, no unsigned-DLL import, survives the block; verified on Win11 2026-07-20:
  not blocked, ~real-time on CPU, good 繁中). `transcribe.py` has a `whisper_xxl` backend for it,
  auto-selected on Windows; drop the exe in `tools/whisper-xxl/` or set `WHISPER_XXL_EXE`.
  XXL output is Simplified even with `--language zh`, so the backend runs OpenCC `s2twp` to convert
  to 繁體 (needs `pip install opencc-python-reimplemented` — deliberately NOT the PyPI `opencc`,
  which ships an unsigned DLL that could get blocked again). Windows also needs `setup.ps1`
  (winget) + the font script, because there is no brew equivalent; a Store-stub `python` fools
  naive detection.
- Standard Homebrew ffmpeg has **no** libass/`subtitles` filter (official homebrew-core
  formula never enables it). This is why captions go through HyperFrames HTML overlay, not
  ffmpeg burn-in.
- Font 思源宋體 (Adobe official, `brew install --cask font-source-han-serif-vf`).
  The installed families are region-suffixed (TC/SC/HC/K/J) — there is NO plain
  "Source Han Serif VF" family, so for 繁中 use **`"Source Han Serif TC VF"`** in
  CSS (`local("Source Han Serif TC VF")` + `@font-face`). Using the plain name
  silently falls back to a sans font (verified via fc-list 2026-07-20). Set
  `lang="zh-Hant"` on the composition for correct TC glyphs.
- HyperFrames caption composition must be 1080x1920 (vertical); the scaffold defaults to
  1920x1080 landscape — always override.

## GAP flag (xref_silence) — swallowed-speech detection

- Whisper drops half-said words / false starts / quiet repeats entirely: they
  never appear as a token, so no downstream tool (verify_cut, edl_to_captions)
  can see them. Only cross-checking transcript word spans against real audio
  silence exposes them. `xref_silence.py` GAP flag does this.
- GAP fires on a space BETWEEN two words (`gap-span >= 0.30s`) whose voiced
  portion (`>= 0.20s`) is NOT covered by silence. It uses a SEPARATE, more
  sensitive silence pass than MERGE/LONG (which keep the -30 pass): a mumbled
  half-word reads as silence at -30 and is missed.
- **The GAP threshold is ADAPTIVE, not a fixed dB.** `--gap-noise auto` (default)
  = this file's own `mean_volume` (ffmpeg volumedetect) + `--gap-offset` (default
  +6 dB). Why: a fixed value can't work across recordings — measured noise floors
  differ wildly (sonnet ~-56 dB during silence, demo ~-45 dB). A fixed -40 is
  clean on sonnet but floods demo with breath/room-noise false positives.
  Calibrated on 2 clips: sonnet mean -41.3 → -35.3 (catches the swallowed 怎麼 at
  131.80-132.50, invisible at -30); demo mean -35.9 → -29.9 (1 clean GAP on a real
  「不知道 不知道」repeat, no flood). n=2, and only sonnet's 怎麼 is a confirmed
  true positive — offset may need re-tuning on more diverse recordings; widen if
  it over-flags, tighten if it misses. Pass a number to `--gap-noise` to force
  an absolute threshold.
- Cost: silencedetect + volumedetect are AUDIO-ONLY (`-vn`) — decoding 4K video
  frames just to scan the audio track cost minutes; with `-vn` the whole 3-pass
  xref (MERGE silence + GAP silence + volumedetect) runs in <0.5s on a 4K source.
  MERGE/LONG behavior is unchanged.

## Future options (evaluated 2026-07-24, NOT implemented)

Compared the toolkit against browser-use/video-use and Jaycheng1103/chatgpt-
video-editing-skills (same EDL / 30ms-fade / timeline_view lineage). Both use
ElevenLabs Scribe as the primary transcriber and treat local Whisper as a
degraded fallback that needs "extra boundary QA".

- **ElevenLabs Scribe as an optional backend**: verbatim ASR, keeps umm /
  half-words / false starts, so it eliminates the Whisper swallow blind spot at
  the source. Rejected for now: cloud API, paid, uploads the user's raw audio —
  conflicts with the toolkit's local-first, zero-setup, zero-cost design for
  students. The GAP flag is the local-only equivalent patch.
- **verify_cut self-eval on rendered output**: video-use re-checks each cut on
  the rendered frames/audio (visual jumps, audio pops). Possible future hardening
  of verify_cut. Note it would NOT have caught the 怎麼 case — what the ASR can't
  hear, a rendered-output re-listen can't hear either. GAP is the right layer.
