# Project L（Rally Club）長期工作規則

等級：小工具／作品集（不上架、沒有真實用戶），但**工程要求比照正式產品**（使用者 2026-11-22 指示「工程要求不變」）。通用工程標準見 `~/.codex/AGENTS.md`，全部條文照做。

## 這個專案是什麼

- 這是從一個私人 App 匯出原始碼、**完整脫敏換皮**後的作品集版本，用來展示 iOS 工程能力（UIKit→SwiftUI、Combine→Swift Concurrency、GRDB 持久化與安全遷移、單元＋UI 測試）。
- 題材：**球友社區 Rally Club**（找球場、約球揪團、球友動態、打球提醒、個人資料）。
- 原始私人專案**不准碰、不准提、不准回寫**。本專案任何檔案、註解、commit 訊息都不得出現原專案的名稱、題材用語、網域、信箱、Bundle ID 或作者身分。

## 脫敏底線

- 不放任何真實金鑰、網址、信箱、帳號、截圖。後端一律走本機「示範模式」與虛構資料；Supabase 程式碼可保留作為架構展示，但沒有設定時 App 必須能以示範模式完整操作。
- 示範模式要在畫面上明示是 Demo（例如登入頁的「Continue in demo mode」），不偽裝成真服務。
- 每次提交前跑 `~/Desktop/AI生成文件集中保管區/Project-L-脫敏掃描/leak-scan.sh`，目標零命中。這支掃描器**故意放在 repo 外**（字詞清單本身是敏感資訊），不准複製進本專案、不准把命中的字詞寫進任何檔案或 commit 訊息。
- 對外發布前，用最終檔案樹建立全新 Git 歷史（目前歷史含未脫敏的匯入基線），這一步由 boom 執行並經使用者同意。

## 工程

- 介面語言只有英文，文案走 String Catalog（`Localizable.xcstrings`、`InfoPlist.xcstrings`）。
- 改動要小、可驗證；每完成一個小項目就提交一次，提交前建置通過。
- 建置只在進程內設 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`，DerivedData 放專案外的 Xcode 預設位置，不改系統設定。
- 正式路徑不准 `try!`、強制解包、`fatalError`、`preconditionFailure`（DEBUG 檢查除外）。
- 美術由設計方（GPT）提供；工程方只放中性的佔位資產，並保留原資產名稱清單供替換。

## 文件

- `README.md`：專案入口與現況。`EXECUTION_LOG.md`：施工紀錄。`NEXT_TASK.md`：下一步。
