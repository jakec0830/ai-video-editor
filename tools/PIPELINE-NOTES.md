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
