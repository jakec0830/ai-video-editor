# AI 剪輯工具包（ai-edit-kit）

用 AI 幫你剪口播影片。你錄一段對著鏡頭講話的影片，AI 幫你剪掉 NG 跟停頓、上字幕、加特效跟音效、配背景音樂，最後輸出成品。

這個工具包已經在真實影片上完整跑通過一次。

## 這個工具包做什麼

一句話：你講話，AI 剪片。具體流程：

1. 轉逐字稿（本機跑，免費）
2. 剪掉 NG、重拍、停頓
3. 上繁體中文字幕
4. 加特效（例如你的手指一比，畫面就出現東西）
5. 加音效跟背景音樂
6. 輸出成品 MP4

## 安裝

### Step 0（這一步你自己做，AI 幫不了）

先裝好 Claude Code 並登入。因為後面是靠 Claude 帶你裝，所以 Claude 本身一定要先能用：

- 到 claude.ai 開通 **Claude 訂閱（Pro 或 Max）**。整個流程靠這個驅動，課前就要備好。
- 裝 **Claude Code**（或 Codex），用你的帳號登入。

### Step 1（讓 AI 幫你裝其他的）

用 Claude Code 打開這個工具包資料夾，然後直接跟它說：

> 幫我一步一步安裝設定

它會自己跑檢查、看你缺什麼（Node、ffmpeg、字型等），然後一個一個幫你裝，邊裝邊確認。你不用先懂這些是什麼。

有幾步一定要你自己動手，AI 會停下來告訴你（它做不到的）：

- 要輸入電腦密碼的（例如 Mac 第一次裝 Homebrew）
- 要在瀏覽器登入的（例如 heygen 音效庫登入你自己的帳號）
- Windows 上要點安裝視窗的（例如 Node、字型）

這些 AI 會明確說「這步換你做：要做什麼、為什麼」，你做完它接著走。

### 如果你想自己裝（Windows 或不想讓 AI 代勞）

Mac / Linux 可以直接在資料夾裡跑 `bash setup.sh`，它會建好 Python 環境並檢查其他工具。Windows 沒有 bash 的話，照下面「手動安裝」做。

需要的東西一覽（AI 或 setup.sh 都會幫你確認）：

- **Node.js（22 以上）** — 字幕跟特效用。nodejs.org 下載。
- **ffmpeg** — 影音核心。Mac `brew install ffmpeg`，Windows `choco install ffmpeg`，Linux `apt install ffmpeg`。
- **思源宋體（Source Han Serif VF）** — 字幕字型。Mac `brew install --cask font-source-han-serif-vf`，其他系統到 github.com/adobe-fonts/source-han-serif 下載。
- **heygen CLI（選配）** — 只有要用音效／背景音樂資料庫才需要。`curl -fsSL https://static.heygen.ai/cli/install.sh | bash`，再 `heygen auth login --oauth`。不裝就自己準備音檔丟進來。

### 手動安裝（Windows 或 setup.sh 失敗時）

```
# 1. 建 Python 環境（在 tools/freecut/ 底下）
python3 -m venv tools/freecut/.venv

# 2. 啟動環境並裝套件
#    Mac/Linux:  source tools/freecut/.venv/bin/activate
#    Windows:    tools\freecut\.venv\Scripts\activate
pip install requests librosa matplotlib pillow numpy

# 3. 裝轉逐字稿引擎（二選一）
pip install mlx-whisper      # 只有 Apple Silicon Mac 用這個（最快）
pip install faster-whisper   # Windows / Intel Mac / Linux 用這個
```

其餘（Node、ffmpeg、字型、heygen）照上面「你自己要另外裝的東西」裝。

## 怎麼用

1. 把你的影片放進一個資料夾。
2. 用 Claude Code（或 Codex）打開這個工具包資料夾。裡面的 `ai-edit` 技能會自動載入。
3. 跟它說：「幫我剪這支影片」，把影片路徑給它。
4. 它會一步一步帶你走：先轉逐字稿，提議怎麼剪，你確認，再上字幕、加特效音樂。

重點：**用你的耳朵當裁判**。AI 聽不到聲音，它只看得到時間軸。哪裡剪得不對、音效沒對上，你直接講，它會用波形圖跟你對時間點。

## 幾個一定要知道的坑（不然會踩）

- **要看成品，一定用 standard 品質輸出**。有個 draft 快速模式是給 AI 自己檢查用的，那個檔案在播放器裡會播不完整、看起來像被截斷。不是壞掉，是用錯模式。
- **Whisper 轉重複字會出錯**。如果你連講三次「不知道」，它常常只認到一次，時間也會抓歪。這是所有 Whisper 的通病，換大模型不會好。工具包裡有波形工具（`xref_silence.py`、`split_blobs.py`）專門抓這種地方，AI 會在剪之前先標出來給你看。
- **音效／音樂資料庫不一定有你要的**。例如煞車聲、某些特定音效，資料庫可能沒有。這很正常，不是失敗。沒有就自己找一個檔案丟進來，AI 幫你混進去。

## 關於 Clawd 吉祥物

Clawd 是 Anthropic（Claude 的公司）的官方吉祥物。課堂 demo 用沒問題，但如果要放到你對外的行銷影片上當品牌，要注意：把別人家的吉祥物放在你的行銷上，可能會讓人誤會你跟 Anthropic 有官方合作。要用的話用「Claude 標誌」比較安全，表示「這是 Claude 剪的」，而不是拿吉祥物當你自己的品牌。

## 內容清單

- `.claude/skills/ai-edit/` — AI 剪輯技能（Claude/Codex 讀這個知道怎麼做）
- `tools/freecut/helpers/` — 剪接、轉逐字稿、波形檢查的腳本
- `setup.sh` — 一鍵安裝
- `PIPELINE-NOTES.md` — 完整技術筆記（進階參考，一般用不到）
