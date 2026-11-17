# POB 台服版：交接文件（2026-11-17）

給接手的對話：這份文件說明目前狀態、做法、測試方式與待辦。細節見 `報告_階段3.md`。
含個人資料的原始文件（帳號、角色、截圖、`報告_階段1-2.md`）不在 repo 裡，放在 `C:\Users\User\Desktop\Work_Space\POE相關\POB台服版\POB台服版_私人文件\`。**repo 是公開的，不要把帳號名稱、角色名稱、截圖提交進來。**

## 1. 這是什麼

Path of Building Community（PoE1）的非官方繁體中文版：
- **台服匯入**：輸入台服帳號名稱，就能匯入角色，中文詞綴會轉成英文給 POB 計算。
- **介面中文化**：畫字時翻譯，遊戲內容使用官方中文。
- **中文介面版面改版**。

- Repo：`C:\Users\User\Desktop\Work_Space\POE相關\POB台服版\PathOfBuilding`（11/17 從 `Desktop\POE研究用` 搬過來）。分支 `zhTW` 用來開發；`release` 是朋友的程式追蹤的分支。遠端 `origin` 是 KAI 的 GitHub（`src/Export/zhTWRelease.ini`），`upstream` 是官方 POB。**原始碼資料夾不能刪。**
- 從原始碼執行：`runtime\Path{space}of{space}Building.exe`。這是開發模式，不會自動更新，存檔也放在 `src\` 裡。

### 發佈與自動更新
- 朋友拿到的壓縮檔是單一資料夾的免安裝版（exe 跟 Launch.lua 放在一起，Build 存在同一個資料夾）。裡面的 `manifest.xml` 有 `branch="release" platform="win32"`，所以不是開發模式，會自動檢查更新。更新來源是 `https://raw.githubusercontent.com/<repo>/release/`，永遠不會連到官方 POB。
- **發佈更新**（repo 必須是公開的）：
  1. 在 `zhTW` 提交好、測試通過。
  2. `python src/Export/zhTWRelease.py publish --version 2.67.2-zhTW.<n> --note "更新內容"`：在 changelog.txt 加一筆紀錄、依提交內容重算 manifest.xml，然後提交。版本號要和 changelog 的 `VERSION[...]` 一致，更新視窗才會只顯示新的紀錄。
  3. `git push origin zhTW` 和 `git push origin HEAD:release`。GitHub 的快取大約 5 分鐘後，朋友就會收到。
- **給新朋友的壓縮檔**：`powershell -ExecutionPolicy Bypass -File src\Export\zhTWPackage.ps1`，用最後一次提交產生 `Work_Space\POE相關\POB台服版\POB台服版_<版本>.zip`（repo 的上一層資料夾）。上傳到 GitHub 的 Releases。
- **驗證更新流程**：`python src/Export/zhTWUpdateTest.py <空資料夾>`。它會在本機架一個假的 GitHub，用壓縮檔裡的 exe 跑 POB 自己的 UpdateCheck/UpdateApply 和 Update.exe，檢查只下載變更的檔案、刪除的檔案有刪掉、個人檔案沒被動到、更新來源還是我們的。全程不開視窗，大約 1 分鐘。
- manifest 的 sha1 是對 git 裡的原始內容（GitHub raw 提供的就是原始內容）。上游有些檔案用 CRLF 存，所以不要用 `git archive` 或工作區的檔案來算。
- **跟上官方 POB 改版**：`git fetch upstream`，把 `upstream/master` 合併進 `zhTW`（manifest.xml 衝突時直接用 publish 重算），跑測試後再發佈。

## 2. 架構（新程式都放在新檔案；修改 POB 原檔處都標註 `-- zhTW`）

| 檔案 | 作用 |
|---|---|
| `src/Export/Scripts/zhTW.lua`、`src/Export/zhTWRun.lua` | 從台服客戶端匯出對照資料到 `src/Data/zhTW/`、`src/Data/StatDescriptions/zhTW/{en,tc}/` |
| `src/Export/zhTWFont.ps1` | 產生中文字形圖 `Font12/14/16/18/20/24/32.png/.lua`，收錄資料與程式中所有非英數字 |
| `src/Export/zhTWRelease.py`、`zhTWRelease.ini` | 發佈工具：產生 manifest.xml（publish）、打包可自動更新的壓縮檔（package）；cfg 寫 GitHub repo 和分支 |
| `src/Export/zhTWPackage.ps1` | 打包壓縮檔（呼叫 zhTWRelease.py package），只包含版本控制中的檔案，不含 Settings.xml 和 Builds |
| `src/Export/zhTWUpdateTest.py`、`src/zhTWUpdateTest.lua` | 自動更新的完整流程測試 |
| `src/Modules/ZhTWConverter.lua` | 台服資料（中文）→ 英文：詞綴、物品、寶石、天賦、聯盟名稱 |
| `src/Modules/ZhTWLocale.lua` | 畫字時把英文翻成中文（`tr`）。主表是 `src/Data/zhTW/UI.lua`（strings／formats／patterns，可手改） |
| `src/Modules/ZhTWMods.lua` | 英文詞綴 → 中文顯示。先比對 POB 自己的英文描述，再比對遊戲的英文描述 |
| `src/Modules/ZhTWText.lua` | 中文字繪製：引擎字型只有 ASCII，中文從字形圖貼上；也處理斷行和輸入框 |
| `src/Modules/ZhTWLayout.lua` | 中文介面的版面：左側摘要卡片與分組、裝備頁分組、珠寶收合、右側固定詳細、資料庫切換鈕、頂部列、匯入頁只留台服與「全部匯入」 |
| POB 原檔掛勾 | `Modules/Main.lua`（載入、語言選項）、`Modules/Build.lua`、`Classes/ItemsTab.lua`、`Classes/ImportTab.lua` |

## 3. 測試（全部無介面，不操作畫面）

測試資料在本對話的暫存資料夾，新對話需要重新下載。台服公開 API：
`https://pathofexile.tw/character-window/get-characters?accountName=<URL 編碼的台服帳號，# 寫成 %23>&realm=pc`，
以及 `get-items`、`get-passive-skills`（要加 `&character=<URL 編碼的角色名>`）。
存成 `chars.json`、`items<N>.json`、`passive<N>.json`。

```
cd PathOfBuilding\runtime
set ZHTW_TEST_DIR=<資料夾>   set ZHTW_TEST_CHARS=1,2,3
Path{space}of{space}Building.exe <src\zhTWTest.lua 的完整路徑>       → src\zhTWTest.log（轉換失敗行數、傳奇核對）
Path{space}of{space}Building.exe <src\zhTWCoverage.lua 的完整路徑>   → src\zhTWCoverage.log（未翻譯行、版面座標、畫面耗時、設定頁說明）
```

- 腳本路徑要用完整的 Windows 路徑，並且從 runtime 資料夾執行。
- 腳本有錯時主控台會卡住、不會寫紀錄：先看 log 檔的修改時間有沒有更新。
- 目前基準：三隻角色轉換失敗 0 行；未翻譯 503 行，其中設定頁說明 375 行。

## 4. 踩過的坑

- **Shell 跳脫字元**：用 bash heredoc 加 Python 修改 Lua 時，`\n`、`\128`、`\t` 常被吃掉或變成真的字元。修改含跳脫字元的程式時，用 Edit 工具或 Write 寫腳本檔。
- **POB 類別代理**：實例上覆寫的方法，如果原類別用 `self.Parent:Method()` 呼叫（例如 ItemSlotControl 的 `self.DropDownControl:Draw`），代理會找回覆寫本身，造成無限遞迴。要直接呼叫 `common.classes.X.Method(self, …)`。
- **包裝函數要保留回傳值的個數**：`t_insert(t, 1, f())` 拿到多餘的 nil 會報錯。
- **Windows PowerShell 5.1** 讀沒有 BOM 的 .ps1 會用系統編碼，中文會壞掉：存成 UTF-8 BOM，或改用字碼。
- **台服改版**：描述檔副檔名可能改變（.txt → .csd）、出現 `[代碼|文字]` 標記、詞綴改寫法。改版後要重新匯出：設定 `ZHTW_GGPK` 為 Steam 台服路徑，執行 `zhTWRun.lua`，再跑測試。
- **字形圖**：缺字會顯示成 `[U+xxxx]`。新增文字後要重跑 `zhTWFont.ps1`。

## 5. 使用者（KAI）的偏好

- 一律用繁體中文回覆。
- **操作畫面（截圖、點擊）前要先問**：右邊螢幕在看影片，截圖會把視窗藏起來。優先用無介面測試。
- 處理完整再回報，不要一直問。
- 不要結束 POB 程序（使用者可能開著自己的 POB）。
- 已授權使用 Scenario 生圖做示意圖或風格參考。

## 6. 待辦

0. **目前狀態（11/17 晚上）**：GitHub 公開 repo `silencesky5/PathOfBuilding-zhTW`（官方 POB 的 Fork）已推送 `zhTW`、`release`。已對真的 GitHub 驗證：發佈的壓縮檔檢查更新結果是「沒有可用的更新」，抽樣 33 個檔案 SHA1 都相符。KAI 還要自己做：(a) 到 Releases 上傳 `POB台服版_2.67.2-zhTW.1.zip`（tag `v2.67.2-zhTW.1`）；(b) 到 Settings 把預設分支改成 `zhTW`（Fork 預設是官方的 `dev`）；(c) 解壓縮後雙擊 `Path of Building.exe`，確認視窗能開（還沒人試過）。
1. **全介面重新設計**（KAI 11/17 決定；還沒開始談目標和範圍）：先和 KAI 確認目標與範圍，做整體示意圖，確認後再逐頁改（`ZhTWLayout.lua`，只在中文介面生效）。之前的示意圖 artifact：https://claude.ai/artifact/1kUVnS1CmeLRLPqaMtyHrd
   - GitHub 公開 repo 與自動更新已完成（見上方「發佈與自動更新」）。
2. **設定頁說明文字翻譯**：清單在 `docs/zhTW_config_tooltips_todo.txt`（375 行，保留顏色碼）。翻好後加進 `UI.lua` 的 strings。
3. 其他未翻譯：新角色才會出現的介面數字（點燃 DPS 差異、圖騰放置時間）、風味文字。
4. 已知限制：永恆珠寶第 1、2 種（瓦爾、卡魯）的將軍名稱，新版資料只有通用句，無法轉換。
5. 桌面上的「POB台服版」捷徑被刪了，可以重建（目標：`Work_Space\POE相關\POB台服版\PathOfBuilding\Path of Building.exe`）。
6. **介面改動紀錄（11/17 晚，`ZhTWLayout.lua`，只在中文介面生效）**：
   - 左上角只留「匯入/匯出」、「角色配置」、「設定」三個按鈕。
   - 「角色配置」底下有「裝備／技能／天賦／計算」頁籤。
   - 天賦點、等級、職業、昇華、血液昇華、天賦配置改成天賦頁左上角的直式面板。
   - 拿掉 Current build 名稱欄。
   - 筆記、隊伍、比較按鈕隱藏，但資料仍保留（存檔不受影響）。
