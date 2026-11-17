# POB 台服版：交接文件（2026-11-17）

給接手的對話：這份文件說明目前狀態、做法、測試方式與待辦。細節見同資料夾的 `報告_階段3.md`。

**文件位置（11/17 起）**：`docs\zhTW\`（本檔、`報告_階段3.md`、`zhTW_config_tooltips_todo.txt`）。
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
| `src/Modules/ZhTWTheme.lua` | 可愛（亮色）主題：繪圖時改色，暗色主題或英文介面不作用 |
| `src/Modules/ZhTWCraftEngine.lua`、`src/Classes/ZhTWCraftTab.lua` | 「製作」頁籤：製裝網站（Poe-tool 的 craft-engine.js）規則的 Lua 版＋頁籤畫面 |
| `src/Export/zhTWCraftData.py` → `src/Data/zhTW/CraftData.lua` | 從製裝網站的 `craft-data.js` 產生製作頁資料（兩邊同一份 RePoE 來源）。網站資料更新後重跑 |
| `src/Export/zhTWCraftCompare.js/.py`、`src/zhTWCraftTest.lua`、`src/zhTWCraftCompare.lua` | 製作頁引擎與網站 JS 引擎的對照測試 |
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
- 目前基準：三隻角色轉換失敗 0 行；未翻譯約 502～505 行（隨測試抽到的傳奇物品浮動），缺字 0。
- 製作頁引擎對照（JS 與 Lua 各跑 20000 次）：指令寫在 `src/Export/zhTWCraftCompare.py` 開頭；文字、階層、錯誤訊息要完全相同，詞綴出現機率在亂數誤差內。

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
2. **設定頁說明文字翻譯**：清單在 `docs/zhTW/zhTW_config_tooltips_todo.txt`（375 行，保留顏色碼）。翻好後加進 `UI.lua` 的 strings。
3. 其他未翻譯：新角色才會出現的介面數字（點燃 DPS 差異、圖騰放置時間）、風味文字。
4. 已知限制：永恆珠寶第 1、2 種（瓦爾、卡魯）的將軍名稱，新版資料只有通用句，無法轉換。
5. 桌面上的「POB台服版」捷徑被刪了，可以重建（已重建在 `Work_Space\POE相關\POB台服版\開啟 POB 台服版.lnk`，目標 `PathOfBuilding\runtime\Path{space}of{space}Building.exe`）。
6. **介面改動紀錄（11/17 晚，`ZhTWLayout.lua`，只在中文介面生效）**：
   - 左上角只留「匯入/匯出」、「角色配置」、「設定」三個按鈕。
   - 「角色配置」底下有「裝備／技能／天賦／計算」頁籤。
   - 天賦點、等級、職業、昇華、血液昇華、天賦配置改成天賦頁左上角的直式面板。
   - 拿掉 Current build 名稱欄。
   - 筆記、隊伍、比較按鈕隱藏，但資料仍保留（存檔不受影響）。
7. **介面改動紀錄（11/18 凌晨）**：
   - 「主要技能」選單從左側欄移到技能頁（「使用提示」與「寶石選項」之間的「主要技能（DPS 計算）」框；`ZhTWLayout.setupSkillsTab`）。左側欄 DPS 卡片下方寫目前計算的技能。
   - 左側欄各大項改成卡片標題列（金框、重點數字、點擊收合；`setupGroupCards`）。
   - 圖示：`src/Assets/zhTW/icons.png`（6×5 格、每格 32px，順序見 `ZhTWLayout.lua` 的 `iconIndex`），用在左側欄卡片與頁籤／模式按鈕。關閉：把 `SHOW_ICONS` 改成 false。Scenario 原圖與預覽放在 repo 外的 `POB台服版\素材_圖示\`。
8. **介面改動紀錄（11/18 凌晨，續）**：
   - 左側欄：拿掉 4 張摘要卡；11 張固定卡片（無數值寫 0），順序 屬性/攻擊/生命/能量護盾/魔力/抗性/護甲/閃避/格擋與抑制/其他/承受能力。
   - 裝備頁：國際服交易按鈕全部隱藏；當前裝備清單（使用中＝綠色小方塊、[尚未使用]、[其他組]）；武器/防具/飾品/藥劑/珠寶分組框。
   - 顏色：我們加的框線、標題改暖灰／米白，金色只留強調。字形圖沒有任何圖形符號（● ■ ▲ ✓），要用就自己畫；測試會列出缺字。
   - 主題：選項（Options）→「Interface theme (介面主題)」可選 暗色／可愛（亮色），存在 Settings.xml 的 zhTWTheme。可愛版由 `Modules/ZhTWTheme.lua` 在繪圖時改色（無圖片的色塊變亮、文字顏色變深），圖示改用 `Assets/zhTW/icons_cute.png`；天賦樹畫面維持暗色。
9. **貼上台服物品文字（11/18 凌晨）**：遊戲內 Ctrl+C／Ctrl+Alt+C 的繁中物品文字，可以在裝備頁直接 Ctrl+V，或貼進「從文字建立自訂物品」。
   - 原本變 ??? 的原因：POB 貼上時把所有非 ASCII 位元組換成 `?`（`EditControl` 與 `sanitiseText`），不是剪貼簿編碼（`Paste()` 回傳的就是 UTF-8），也不是字形缺字。
   - `Modules/ZhTWItemText.lua` 把繁中文字轉成英文遊戲複製格式再交給 POB：稀有度、名稱、基底、品質、需求、插槽、物品等級、`{ 前綴/後綴 }` 註解（含詞綴英文名、階層、大師工藝/破裂等旗標）、數值範圍 `40(33-43)`、已汙染等。轉不了的行會略過，並跳出視窗列出。
   - `StatDescriber.lua` 的 `{:+d}` 改成保留正負號（台服資料用這種寫法，原本 `+850 最大生命…` 會變成 `850 …` 而無法解析；台服匯入也受益）。
   - 測試：`Path{space}of{space}Building.exe <src\zhTWItemTextTest.lua 完整路徑>` → `src\zhTWItemTextTest.log`。範例在 `docs/zhTW/samples/`；另做傳奇物品往返測試（英文→中文→英文），目前 441 件中 434 件通過，失敗的是多行一組的特殊詞綴（深淵眼珠寶、Bound Fate 等）。
   - 物品說明框（中文介面）把稀有／魔法物品的詞綴分成「前綴」「後綴」兩組（`Modules/ZhTWAffixType.lua`）：匯入的物品沒有詞綴資訊，用基底可出現的詞綴比對每一行；工藝詞綴比對工藝台資料。稀有範本 722 行中 716 行能判斷，判斷不了的放在最後、不加標題。
   - **輸入中文（11/18）**：引擎把打進來的非英文字元一律交給 OnChar 成 `?`。`Modules/ZhTWIme.lua` 用 LuaJIT FFI 子類化視窗（`SetWindowSubclass`），記下 WM_CHAR 的真實字元，再把 `?` 換回來（掛在 `launch.OnChar`）。貼上中文不再換成 `?`；倒退／刪除會刪整個中文字。
   - 搜尋用中文：幽魂庫、傳奇資料庫（名稱、基底、詞綴）、技能寶石都會比對中文名稱（`ZhTWLocale.searchMatch`）。
   - 怪物名稱：`Export/Scripts/zhTWMonsters.lua` 從台服 MonsterVarieties 匯出 `Data/zhTW/Monsters.lua`（`set ZHTW_SCRIPT=Scripts/zhTWMonsters.lua` 再跑 `zhTWRun.lua`）。之前的「遠古 構造」是把怪物名當成稀有物品名逐字翻的。測試：`src/zhTWSearchTest.lua`。
10. **製作頁籤第一階段（11/18 凌晨）**：角色配置的第 5 個頁籤「製作」（只在中文介面）。
   - 能做的：選類別／底材／物品等級（或從當前裝備帶入底材與物品等級）；十種基本通貨＋精髓＋化石（1～4 顆，鑄新儀）；上一步；物品卡用 POB 自己的物品提示（中文、裝上後的變化）；詞綴與階層列表；「加入 Build」。
   - 還沒做：園藝、工藝台（引擎沒移植）；批次模擬器；倉庫／背包畫面；公會分享（第二階段，需要改 Worker 的登入流程，先問 KAI）；帶入時不帶詞綴（POB 物品 → 網站詞綴 id 的對照還沒做）。
   - 設計：製作頁的物品轉成英文遊戲格式文字再交給 POB 解析；存 Build 時若停在製作頁，存成「裝備」頁（避免官方 POB 開到不存在的頁籤）。

11. **製作頁第二階段：公會分享（11/18 凌晨）**：`Modules/ZhTWGuild.lua`＋製作頁右邊的「公會分享架／分享到公會／登入公會」。
   - 瀏覽、搜尋、複製到製作頁或 Build 不用登入（網站分享架 API 公開）。分享要用 Discord 登入（RKSA 成員）。
   - 登入：本機 127.0.0.1:49090～49093 接回呼，Worker 只回一次性代碼，POB 用 PKCE verifier 到 `/auth/pob-token` 換 token；token 存 Settings.xml 的 zhTWGuildToken。
   - Worker 改動在 Poe-tool 的 `pob-login` 分支（只新增 client=pob 模式與 /auth/pob-token）。**部署前要 KAI 本人確認**；回滾：在 Poe-tool\worker 執行 `npx wrangler rollback ba2365a0-8150-45ee-a095-01446014dd46`（11/18 時的正式版）。
   - 還沒做：裝備頁物品右鍵分享（POB 物品 → 網站詞綴 id 對照）、在 POB 撤下分享、分享附圖。

12. **稀有裝備傷害最佳化（11/18）**：裝備頁「製作物品／自訂物品」右邊的按鈕（只在中文介面），程式在 `Modules/ZhTWOptimize.lua`，ItemsTab.lua 只加一行掛勾。
   - 選欄位（或全部稀有裝備）→ 用 POB 自己的詞綴表（`item.affixes`）找出該底材在遊戲規則內 DPS 最高的組合：最多 3 前綴 3 後綴、同 mod group 不重複、詞綴等級 ≤ 物品等級、權重 > 0（含物品本身的影響力），排除化石專屬與瑪文的 Elevated 詞綴；數值取最高。
   - 計算用 `GetMiscCalculator`，比較主要技能的 `CombinedDPS`（召喚物技能用 Minion.CombinedDPS），DPS 相同時用生命＋能量護盾決定。搜尋：每個詞綴單獨算一次 → 前綴、後綴各取前 8 名 → 逐一加入最好的 → 兩輪逐一替換。每件約 100～170 次計算、約 1 秒；視窗用 coroutine 分散到每個畫面（每畫面 25ms）。
   - 「保留抗性」（預設勾選，KAI 11/18 同意改成總量制）：火／冰／電／混沌各自的抗性總量不低於目前（不含破裂），在可出現的抗性詞綴（含全抗、雙抗）中找欄位最少、多出抗性最多的組合固定下來，剩下欄位放傷害詞綴；最大抗性詞綴原樣保留。湊不到時（例如原本的抗性來自精髓或工藝台）才把原本的抗性詞綴原樣留著（判斷前綴／後綴用 `ZhTWAffixType.getType`）。破裂詞綴一律保留。
   - 結果以「最佳化 <原名>」加入裝備清單（[尚未使用]），提升不到 0.1% 不加入；身上的裝備不換。已汙染的物品照樣算，結果不帶汙染。
   - 測試：`Path{space}of{space}Building.exe <src\zhTWOptimizeTest.lua 完整路徑>` → `src\zhTWOptimizeTest.log`（用 spec/TestBuilds 的兩個 Build，檢查前後綴數量、group 不重複、等級，並模擬按鈕流程）。
   - 可再做：工藝台詞綴、珠寶（2 前綴 2 後綴）、選擇比較的數值（例如 FullDPS、有效生命）。
