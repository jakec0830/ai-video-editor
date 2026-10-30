#!/usr/bin/env bash
# 舊版工具包已經停止更新，換成新版 zip 工具包（不用再裝東西，之後自動更新）。
# 舊版更新完本來就會跑這支，所以現在這支只做一件事：把這個資料夾就地換成新版。
# 你的影片、剪輯偏好、錯誤回報都會保留。詳細見 tools/migrate_to_zip.sh。
exec bash "$(cd "$(dirname "$0")" && pwd)/tools/migrate_to_zip.sh"
