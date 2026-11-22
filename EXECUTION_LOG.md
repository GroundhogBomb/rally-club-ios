# Rally Club R1 施工紀錄

日期 2026-11-22。施工與模擬器驗證由 Codex 執行，獨立驗收由 boom 負責。

| 順序 | 施工與檢查 | 提交 |
| --- | --- | --- |
| 1 | 更新 Rally Club 顯示名稱、Bundle ID、登入回呼、回饋信箱和版本設定網址。核對識別資料與 Apple 登入權限，Debug 建置通過。 | `15664f6` |
| 2 | 專案、target、scheme、程式資料夾及 App 入口統一為 ProjectL。Xcode 列出 ProjectL target 與 scheme，Debug 建置通過。 | `b142b80` |
| 3 | 介面固定英文，使用兩份 String Catalog 並移除語言設定頁。依 boom 確認，保留貼文語言選擇、內容篩選和公告翻譯。Debug 建置通過。 | `72fd3c7` |
| 4 | 完成球場、社團動態、約球、提醒、比賽照片的更名，更新本機儲存及後端欄位名稱，換上虛構內容。Debug 建置通過。 | `5c96431` |
| 5 | 空白後端設定可直接執行，Demo 透過共用 Store 使用記憶體資料與離線球場圖。Debug 和 Release 建置通過。 | `225ad1d` |
| 6 | 換上中性 PNG、無聲 MP4、Metal 開場效果及 SF Symbols。核對尺寸、影片規格與設計清單，Debug 建置通過。 | `591738f` |
| 7 | 補英文 README、維護入口與驗收紀錄。修正 Demo 標示遮住導覽列，再複驗操作並保存截圖。最終 Debug 和 Release 建置通過。 | 本次提交 |

## 模擬器驗收

使用 iPhone 17 Pro、iOS 26.5 與 Release 建置。已從冷啟動點選 Continue in demo mode，開啟 Courts、Feed、Club、Training Lounge 和 Me，成功發出一則動態及一則約球請求。已允許本機通知，新增 Cedar Lane Courts 每週六上午 10 點的提醒，並讀回該筆已啟用的本機紀錄。

- [冷啟動入口](Evidence/R1/01-demo-entry.png)與[球場](Evidence/R1/02-courts.png)
- [發文結果](Evidence/R1/03-feed-posted.png)與[約球結果](Evidence/R1/04-game-request-posted.png)
- [Club](Evidence/R1/05-club.png)、[Training Lounge](Evidence/R1/06-training-lounge.png)與[Me](Evidence/R1/07-me.png)
- [已儲存的每週提醒](Evidence/R1/08-session-reminder.png)

截圖取自修正導覽後的 Release。後續移除動態切換的重複輔助標籤，兩種建置皆通過，該標籤調整未另重跑模擬器。

Debug 模擬器的後端解碼、提醒持久化、待上傳照片資料與版本判斷合約檢查均通過。專案原始碼的 Release 路徑掃描為零筆強制解包、強制轉型、強制 try 或直接中止呼叫。工作檔案樹的脫敏掃描通過，含檔名和二進位檔。

## 未驗證與範圍

真機、實際通知送達、已配置的 Supabase／Apple 登入、線上球場搜尋和裝置端公告翻譯未驗證。啟用後端的 Rally Club 環境須提供新版資料欄位和服務設定，才能跑完整帳號流程。Demo 的貼文、約球與個人修改隨工作階段重置，提醒留存在模擬器。

S1–S5 架構工作及發行用的乾淨 Git 歷史由後續流程處理。

## R1.1 移除贊助與廣告（2026-11-22）

依 boom 派工移除 Club 分頁、廣告翻書、贊助畫面、專用圖示與 52 筆 String Catalog 條目。意見回饋仍由 `SUPPORT-001` 開啟郵件草稿。已更新入口、維護地圖、設計素材及交接文件。S5 翻書遷移取消。

Debug 和 Release 的 iPhone 模擬器建置及脫敏掃描通過。iPhone 17 Pro（iOS 26.5）以 Release 冷啟動後，從 [Demo 入口](Evidence/R1.1/01-demo-entry.png) 進入，依序開啟 [Courts](Evidence/R1.1/02-courts.png)、[Feed](Evidence/R1.1/03-feed.png)、[Training Lounge](Evidence/R1.1/04-training-lounge.png) 與 [Me](Evidence/R1.1/05-me.png)。球場清單、動態與約球入口、訓練室佔位及個人頁提醒入口均可見。Me 留在模擬器上，可繼續操作。

本次驗收範圍為四個分頁的開啟與顯示。真機和郵件草稿開啟未驗證。

## R1.2 收尾清理（2026-11-22）

使用者於 2026-11-22 改定，原先保留貼文語言選擇、內容篩選與公告翻譯的決定作廢。移除發文選語、動態與約球的語言篩選、貼文語言標籤及公告翻譯。示範貼文、留言、約球與公告統一改寫成英文。貼文、留言與約球的後端寫入填 `en`，資料欄位與讀取格式沿用。公告編輯只提供英文，沿用原有的管理權限與版本衝突檢查。

合十手勢與鳥形圖示改成球類或對話圖示，包含示範動圖。逐一核對 SF Symbols 與英文文案，個人頁統計改為 Joined，照片文案改成比賽與練球題材。`MATCH-MOMENT-PENDING-001` 已和維護地圖及 Debug 訊息對齊。

iPhone 17 Pro（iOS 26.5）的 Debug 分項建置與最終 Release 建置通過。Release 冷啟動從 [Demo 入口](Evidence/R1.2/01-demo-entry.png) 進入，開啟 [Courts](Evidence/R1.2/02-courts.png)、[Feed](Evidence/R1.2/03-feed.png)、[Training Lounge](Evidence/R1.2/06-training-lounge.png) 與 [Me](Evidence/R1.2/07-me.png)。已發布 [Great rally today.](Evidence/R1.2/04-feed-posted.png) 並新增 [Sunday doubles](Evidence/R1.2/05-game-request-posted.png)，兩筆都在清單讀回。Demo 留在 Me 分頁。

脫敏掃描通過，含七張 R1.2 截圖。驗收使用模擬器專用的暫時簽名與執行設定，驗收後已還原。Git 建立索引鎖被工作區權限拒絕，分項提交未完成。未驗證項目為真機、已配置的 Supabase 及管理員公告儲存。

## R1.3 個人頁與英文語言碼（2026-11-22）

接續 boom 驗收並提交的 R1.2（`aae7944`）。Me 的 Account settings 與 Safety & privacy 共用同一張卡片，分隔線留在卡片內，Account settings 使用齒輪圖示。

App 語言與 VersionGate 訊息統一取英文。後端保留 `language_code` 欄位，各寫入路徑一律送 `en`，讀取到未知或缺少語言碼時仍讀入原紀錄並使用英文。新照片與舊的待上傳照片都使用 `en`，沿用原本的照片內容、路徑與排序。已同步更新 Debug 合約測例。

指定的五種語言殘留搜尋零命中。待提交檔案的脫敏掃描通過，整個工作目錄另有兩筆命中，皆為 Git 忽略的 Xcode 使用者狀態。R1.3 的 Release 模擬器版本在桌面 Xcode 建出並啟動。後續指令列的 Debug 與 Release 建置都因預設 DerivedData 無法寫入而中止，`simctl spawn` 也無法連線至 CoreSimulator。Debug 建置、合約執行、修正後的 Me 畫面與 R1.3 截圖未驗證。暫時的建置設定與 scheme 已還原。

Git 建立 `.git/index.lock` 被拒絕，改動留在工作區，由 boom 接手提交。

## R2 換上正式美術（2026-11-22）

採用 GPT 交付的六張原圖，以 sips 等比縮放並置中裁切到設計清單的尺寸。App 圖示為 1024 × 1024 的不透明 PNG，開場球為 720 × 720 的透明 PNG。六張圖沿用各自的資產名稱。ProjectL scheme 的 LaunchAction debugger 與 launcher 設定已恢復為 `aae7944` 的值。

Debug 與 Release 的 iPhone 模擬器建置通過。在 iPhone 17 Pro（iOS 26.5）用 Release 冷啟動，核對開場球、Demo 球場頁、Me 頭像及訓練室插圖。[R2 驗收截圖](Evidence/R2/)

Demo 球場頁顯示離線地圖。已確認 Release 包含 1200 × 640 的 `CourtPreview`，球場介紹頁實際顯示及真機未驗證。

全工作目錄的脫敏掃描仍命中六張已提交原圖與兩筆本機 Xcode 狀態。本次提交的圖檔、文件與截圖零命中。

## S1 球場地圖遷移與測試基礎（2026-11-22）

球場頁與球場詳情共用 iOS 17 的 SwiftUI Map。鏡頭規則可獨立測試，高亮球場採 1.6 公里範圍，附近球場以使用者位置採 10 公里範圍。MapKit 顯示系統定位，地圖採平面樣式並隱藏興趣點。球拍標記選取後顯示球場名稱與地址。離線示範使用自繪的 DemoCourtMapView。

在 iPhone 17 Pro（iOS 26.5）透過共用 scheme 跑 `xcodebuild test`。Swift Testing 的三個鏡頭測例與 XCTest 的地圖、標記識別碼及地址操作測例全數通過。Debug 與 Release 模擬器建置通過。真機與已配置環境下的實際定位未驗證。[模擬器地圖截圖](Evidence/S1/01-court-map-callout.png)

依 boom 確認，以更新後的掃描器驗收，提交前全目錄脫敏掃描通過。

## S2 動態貼文 GIF 原生播放（2026-11-22）

動態貼文改用 ImageIO 解幀及 SwiftUI TimelineView 播放，支援本機資料、遠端網址和具名資產。遠端沿用縮圖的下載設定與 8 MB 檔案上限。保留貼文原本的 GIF 高度及圓角，圖片等比顯示。解碼失敗使用既有的媒體錯誤圖示。

按顯示尺寸縮小，保留最多 60 幀及 24 MiB 的縮圖資料。超過 16 百萬像素的來源顯示媒體錯誤。每幀最短 20 毫秒，無效延遲使用 100 毫秒。減少動態效果只解並顯示第一幀。

iPhone 17 Pro（iOS 26.5）上執行完整 `xcodebuild test`，含 S1 共 7 個單元測試與 2 個 UI 測試，全數通過。Debug 和 Release 的模擬器建置通過。Release 執行檔查無 S1、S2 與 App 原有合約測試的啟動參數，也查無 WebKit 連結。全目錄脫敏掃描通過。[GIF 貼文截圖](Evidence/S2/01-feed-gif.png)

UI 測試使用本機 GIF。遠端與具名資產路徑、真機與系統減少動態效果的切換未做端到端驗證。第一幀解碼已在單元測試涵蓋。

## S3 第一步：Repository 變更通知（2026-11-22）

兩個 Repository 在主執行緒上以 AsyncStream 多播。三個 Store 各有一條串流，一次保留最新的一個待處理通知。Store 釋放時取消收聽，串流結束後移除訂閱。Me 的貼文計數沿用原本的 ClubFeedStore。背景影片型別改用 ClubBackdrop 命名。

iPhone 17 Pro（iOS 26.5）上，單元測試用一次暱稱更新確認三個 Store 都收到通知並讀到新暱稱。新增的 Demo 發文 UI 測試確認 Feed 出現新貼文，Me 的 Posts 從 1 變 2。測試等開場動畫結束後點進正常 Demo 入口。

9 個 Swift Testing 單元測試和 3 個 XCTest UI 測試全數通過，含 S1、S2。Debug 與 Release 模擬器建置和全目錄脫敏掃描通過。

## S3 第二步改用 Observation（2026-11-22）

ClubFeedStore、GameRequestStore 和 ProfileStore 使用 `@Observable`。持有它們的畫面改用 `@State`，子畫面直接讀取 Store。每個 Store 將 Repository 的資料讀取註冊為一項觀察依賴，收到 AsyncStream 通知就更新相關畫面。同一次通知可以讓同一個 Store 的多個欄位刷新。Repository 維持載入和送出狀態的既有觀察方式。

iPhone 17 Pro（iOS 26.5）上的 Debug 和 Release 建置，以及完整 `xcodebuild test` 全數通過，包含 9 個單元測試和 3 個 UI 測試。單元測試確認一次暱稱變更通知到三個 Store，三者都讀到新值。Demo UI 測試確認 [Feed 出現新貼文](Evidence/S3/01-feed-after-publish.png)，[Me 的 Posts 從 1 增到 2](Evidence/S3/02-me-post-count.png)。

四項 Debug 合約檢查通過，涵蓋後端解碼、提醒保存、照片待上傳和版本檢查。Release 執行檔查無測試及預覽啟動參數，App 內沒有測試套件。全目錄脫敏掃描通過。真機與已設定的 Supabase 後端未驗證。

## S4 第一步修正登入後的 Store 建立時機（2026-11-22）

登入畫面評估時先傳入工廠，等 SwiftUI 掛載該次登入的畫面才建立 Repository 和三個 Store。Swift Testing 用 UIHostingController 驗證父畫面重算三次仍只建立一組，切換畫面識別後才再建立一組。指定的 iPhone 17 Pro 模擬器 Debug 測試建置、該測試及全目錄脫敏掃描通過。

## S4 第二步遷移比賽照片待上傳佇列（2026-11-22）

SPM 新增並鎖定 GRDB.swift 7.12.0。佇列使用有版本的 SQLite 檔案，以帳號和照片 ID 區分資料。資料庫使用 complete file protection，資料庫和所在目錄排除系統備份。

完整舊檔在交易成功後改名備份。部分可讀或完全無法解碼的舊檔依 boom 確認的規則先搬到 `.unreadable` 備份，再將可讀且屬於該帳號的照片一次寫入。檔案搬不動時保留原檔並暫停寫入。單元測試用 SQLite 觸發器讓交易最後一步失敗，確認資料回滾、舊檔位元組保留，重試後只匯入一次。也驗證資料庫打不開時舊檔留在原位，以及刪除帳號時只清該帳號的列和備份。[遷移與復原說明](MIGRATION.md)

iPhone 17 Pro（iOS 26.5）的 Debug、Release 建置通過。完整 `xcodebuild test` 共 18 個單元測試和 3 個 UI 測試，包含 S1 到 S3，全部通過。四項 Debug 合約檢查通過。Release 查無測試啟動參數、測試套件及舊檔測例。全目錄脫敏掃描通過。[Demo Feed 截圖](Evidence/S4/01-demo-feed.png)、[Demo 比賽照片區截圖](Evidence/S4/02-demo-match-moments.png)

真機鎖定時的檔案保護、已設定 Supabase 的實際上傳及降版復原未驗證。

## S6 收斂標準外觀（2026-11-23）

移除 Debug 替代主題、偏好設定讀寫、主題專用檢查、背景影片及 AppPalette 的 UIKit 橋接。分頁列沿用 SwiftUI 的背景與 tint，導覽標題採系統樣式。App 啟動時沿用原生分段選擇器的配色設定，原因和取捨已寫入 README。靜態背景及 Metal 開場效果沿用既有資產。

用同一台 iPhone 17 Pro（iOS 26.5）模擬器在改動前後各啟動 Release Demo，分別拍下 Courts、Feed、Training lounge、Me 與 Feed 切到 Game requests 的畫面。比對確認版面、主要配色與選取狀態一致。逐像素仍有狀態列時間、示範貼文時間及部分半透明區塊邊緣的小差異。[改動前](Evidence/S6/before/)、[改動後](Evidence/S6/after/)

Debug、Release 模擬器建置均通過。18 個 Swift Testing 單元測試、3 個 XCTest UI 測試與 4 項 Debug 合約檢查全部通過。Release 執行檔查無測試入口，App 中查無移除的影片。工作目錄的脫敏掃描通過，指定的舊名稱查無命中。真機、iOS 17 實際執行與執行中切換減少透明度未驗證。
