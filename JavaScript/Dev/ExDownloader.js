// ==UserScript==
// @name         [E/Ex-Hentai] Downloader
// @name:zh-TW   [E/Ex-Hentai] 下載器
// @name:zh-CN   [E/Ex-Hentai] 下载器
// @name:ja      [E/Ex-Hentai] ダウンローダー
// @name:ko      [E/Ex-Hentai] 다운로더
// @name:en      [E/Ex-Hentai] Downloader
// @version      0.0.16-Beta8
// @author       Canaan HS
// @description         漫畫頁面創建下載按鈕, 可切換 (壓縮下載 | 單圖下載), 無須複雜設置一鍵點擊下載, 自動獲取(非原圖)進行下載
// @description:zh-TW   漫畫頁面創建下載按鈕, 可切換 (壓縮下載 | 單圖下載), 無須複雜設置一鍵點擊下載, 自動獲取(非原圖)進行下載
// @description:zh-CN   漫画页面创建下载按钮, 可切换 (压缩下载 | 单图下载), 无须复杂设置一键点击下载, 自动获取(非原图)进行下载
// @description:ja      マンガページにダウンロードボタンを作成し、（圧缩ダウンロード | シングルイメージダウンロード）を切り替えることができ、复雑な设定は必要なく、ワンクリックでダウンロードできます。自动的に（オリジナルではない）画像を取得してダウンロードします
// @description:ko      만화 페이지에 다운로드 버튼을 만들어 (압축 다운로드 | 단일 이미지 다운로드)를 전환할 수 있으며, 복잡한 설정이 필요하지 않고, 원클릭 다운로드 기능으로 (원본이 아닌) 이미지를 자동으로 가져와 다운로드합니다
// @description:en      Create download buttons on manga pages, switchable between (compressed download | single image download), without the need for complex settings, one-click download capability, automatically fetches (non-original) images for downloading

// @connect      *
// @match        *://e-hentai.org/g/*
// @match        *://exhentai.org/g/*
// @icon         https://e-hentai.org/favicon.ico

// @license      MPL-2.0
// @namespace    https://greasyfork.org/users/989635

// @run-at       document-body
// @grant        window.close
// @grant        GM_setValue
// @grant        GM_getValue
// @grant        GM_download
// @grant        GM_addElement
// @grant        GM_xmlhttpRequest
// @grant        GM_registerMenuCommand
// @grant        GM_unregisterMenuCommand

// @require      https://update.greasyfork.org/scripts/495339/1532088/ObjectSyntax_min.js
// @require      https://cdnjs.cloudflare.com/ajax/libs/FileSaver.js/2.0.5/FileSaver.min.js
// @require      https://raw.githubusercontent.com/Canaan-HS/ProjectsLab/refs/heads/main/JavaScript/API/JSZip.min.js
// ==/UserScript==

/*
Todo - 預計新開發功能

* 1. 下載設置菜單 (在下載按鈕的右邊)

? 可配置項目

* 1. 下載線程數 (1~16 預設 5) [完成後將移除動態調整]
* 2. 下載模式切換 (單圖下載 | 單圖下載)
* 3. 下載的類型 (重採樣 | 原始圖)
* 4. 限制下載圖片類型 (副檔名限制)
* 5. 設置壓縮等級 (1~9 預設 5)
* 6. 設置壓縮檔名格式
* 7. 設置圖片檔名格式
* 8. 錯誤重試次數
* 9. 下載完成後自動關閉
* 10. 下載範圍設置
* 11. 開發模式開關
* 12. 下載元數據文件 (相關配置類型)

? 下方特殊顯示框 (壓縮下載時才顯示)

* 個別下載進行狀況
* 強制壓縮按鈕

*/

(async () => {

    /* 使用者配置 */
    const Config = {
        Dev: true,           // 開發模式 (會顯示除錯訊息)
        ReTry: 10,            // 下載錯誤重試次數, 超過這個次數該圖片會被跳過
        Original: false,      // 是否下載原圖
        ResetScope: true,     // 下載完成後 重置範圍設置
        CompleteClose: false, // 下載完成自動關閉
    };

    /* 下載配置 (不清楚不要修改) */
    const DConfig = {
        Compr_Level: 5,      // 壓縮的等級
        MIN_CONCURRENCY: 5,  // 最小併發數
        MAX_CONCURRENCY: 16, // 最大併發數
        TIME_THRESHOLD: 1000, // 響應時間閥值

        MAX_Delay: 2000,     // 最大延遲
        Home_ID: 100,        // 主頁初始延遲
        Home_ND: 80,         // 主頁最小延遲
        Image_ID: 34,        // 圖頁初始延遲
        Image_ND: 28,        // 圖頁最小延遲
        Download_IT: 8,      // 下載初始線程
        Download_ID: 600,    // 下載初始延遲
        Download_ND: 300,    // 下載最小延遲

        Lock: false, // 鎖定狀態
        SortReverse: false, // 排序反轉

        Scope: undefined, // 下載範圍
        DisplayCache: undefined, // 緩存展示時的字串
        CurrentDownloadMode: undefined, // 紀錄當前模式

        KeyCache: undefined, // 緩存鍵
        GetKey: function () {
            if (!this.KeyCache) this.KeyCache = `DownloadCache_${Syn.Device.Path.split("/").slice(2, 4).join("")}`;
            return this.KeyCache;
        },
        Dynamic: function (Time, Delay, Thread = null, MIN_Delay) { // Todo - 等待優化動態調整邏輯
            let ResponseTime = (Date.now() - Time), delay, thread;

            if (ResponseTime > this.TIME_THRESHOLD) {
                delay = Math.floor(Math.min(Delay * 1.1, this.MAX_Delay));
                if (Thread != null) {
                    thread = Math.floor(Math.max(Thread * (this.TIME_THRESHOLD / ResponseTime), this.MIN_CONCURRENCY));
                    return [delay, thread];
                } else { return delay }
            } else {
                delay = Math.ceil(Math.max(Delay * 0.9, MIN_Delay));
                if (Thread != null) {
                    thread = Math.ceil(Math.min(Thread * 1.2, this.MAX_CONCURRENCY));
                    return [delay, thread];
                } else { return delay }
            }
        }
    };

    const Url = Syn.Device.Url.split("?p=")[0];
    let Lang, OriginalTitle, CompressMode, ModeDisplay;

    class DownloadCore {
        constructor(Button) {
            this.Button = Button;
            this.ComicName = null;

            /* 後台請求工作 */
            this.Worker = Syn.WorkerCreation(`
                let queue = [], processing = false;
                onmessage = function(e) {
                    queue.push(e.data);
                    !processing && (processing = true, processQueue());
                }
                async function processQueue() {
                    if (queue.length > 0) {
                        const {index, url, time, delay} = queue.shift();
                        FetchRequest(index, url, time, delay);
                        setTimeout(processQueue, delay);
                    } else {processing = false}
                }
                async function FetchRequest(index, url, time, delay) {
                    try {
                        const response = await fetch(url);
                        const html = await response.text();
                        postMessage({index, url, html, time, delay, error: false});
                    } catch {
                        postMessage({index, url, html, time, delay, error: true});
                    }
                }
            `);

            /* 取得總頁數 */
            this.GetTotal = (page) => Math.ceil(+page[page.length - 2].textContent.replace(/\D/g, '') / 20);
            /* 實例化後立即調用 */
            this.GetHomeData();
        };

        /* 按鈕與狀態重置 */
        async Reset() {
            Config.CompleteClose && window.close();
            Config.ResetScope && (DConfig.Scope = false);

            // 切換下載狀態時, 原先的按鈕會被刪除, 所以需要重新找到按鈕
            const Button = Syn.$$("#ExDB");
            DConfig.Lock = false;
            Button.disabled = false;
            Button.textContent = `✓ ${ModeDisplay}`;
        };

        /* 獲取主頁連結數據 */
        async GetHomeData() {
            const Name = Syn.NameFilter((Syn.$$("#gj").textContent || Syn.$$("#gn").textContent).trim()); // 取得漫畫名稱
            const CacheData = Syn.Storage(DConfig.GetKey()); // 嘗試獲取緩存數據
            const ImgSet = Syn.$$("#gdc .ct6"); // 嘗試 取得圖片集 標籤

            DConfig.CurrentDownloadMode = CompressMode; // 將當前下載模式緩存
            this.ComicName = Name; // 將漫畫名稱緩存

            /* 判斷是否為圖片集 (每次下載都可重新設置) */
            if (ImgSet) {
                const yes = confirm(Lang.Transl("檢測到圖片集 !!\n\n是否反轉排序後下載 ?"));
                yes ? (DConfig.SortReverse = true) : (DConfig.SortReverse = false);
            };

            /* 當存在緩存時, 直接啟動下載任務 */
            if (CacheData) {
                this.StartTask(CacheData);
                return;
            };

            /* ----- 數據請求 ----- */

            const Pages = this.GetTotal(Syn.$$("#gdd td.gdt2", { all: true })); // 取得總共頁數
            let Delay = DConfig.Home_ID; // 初始延遲

            // 發起請求訊息
            this.Worker.postMessage({ index: 0, url: Url, time: Date.now(), delay: Delay });
            for (let index = 1; index < Pages; index++) {
                this.Worker.postMessage({ index: index, url: `${Url}?p=${index}`, time: Date.now(), delay: Delay });
            };

            // 接收請求訊息
            this.Worker.onmessage = (e) => {
                const { index, url, html, time, delay, error } = e.data;
                Delay = DConfig.Dynamic(time, delay, null, DConfig.Home_ND);
                error
                    ? this.Worker.postMessage({ index: index, url: url, time: time, delay: delay })
                    : GetLink(index, Syn.DomParse(html));
            };

            /* ----- 解析請求數據並保存 ----- */

            const self = this;
            const HomeData = new Map(); // 保存主頁數據
            let Task = 0; // 下載任務進度

            // 獲取連結
            function GetLink(index, page) {
                try {
                    const Cache = [];

                    // 不使用 foreach, 是避免異步可能的錯誤
                    for (const link of Syn.$$("#gdt a", { all: true, root: page })) {
                        Cache.push(link.href);
                    };

                    HomeData.set(index, Cache); // 添加數據
                    DConfig.DisplayCache = `[${++Task}/${Pages}]`;

                    document.title = DConfig.DisplayCache;
                    self.Button.textContent = `${Lang.Transl("獲取頁面")}: ${DConfig.DisplayCache}`;

                    if (Task === Pages) {
                        const Cache = [];

                        for (let index = 0; index < HomeData.size; index++) {
                            Cache.push(...HomeData.get(index));
                        };

                        const Processed = [...new Set(Cache)]; // 排除重複連結
                        Syn.Log(
                            Lang.Transl("內頁跳轉數據"),
                            `${Name}\n${JSON.stringify(Processed, null, 4)}`, { dev: Config.Dev }
                        );
                        self.GetImageData(Processed); // 處理圖片數據
                    };
                } catch (error) {
                    alert(Lang.Transl("請求錯誤重新加載頁面"));
                    location.reload();
                }
            };
        };

        /* 獲取圖片連結數據 */
        async GetImageData(JumpList) {
            const Pages = JumpList.length; // 取得頁數
            let Delay = DConfig.Image_ID; // 初始延遲
            let Task = 0; // 下載任務進度

            // 發起請求訊息
            for (let index = 0; index < Pages; index++) {
                this.Worker.postMessage({ index, url: JumpList[index], time: Date.now(), delay: Delay });
            };

            // 接收請求訊息
            this.Worker.onmessage = (e) => {
                const { index, url, html, time, delay, error } = e.data;
                Delay = DConfig.Dynamic(time, delay, null, DConfig.Image_ND);
                error
                    ? this.Worker.postMessage({ index: index, url: url, time: time, delay: delay })
                    : GetLink(index, url, Syn.DomParse(html));
            };

            const self = this;
            const ImageData = []; // 保存圖片數據
            function GetLink(index, url, page) {
                try {
                    const Resample = Syn.$$("#img", { root: page });
                    const Original = Syn.$$("#i6 div:last-of-type a", { root: page })?.href || "#";

                    if (!Resample) { // 處理找不到圖片的錯誤
                        self.Worker.postMessage({ index: index, url: url, time: Date.now(), delay: Delay });
                        return;
                    };

                    // 處理圖片連結
                    const Link = Config.Original && !Original.endsWith("#")
                        ? Original : Resample.src || Resample.href;

                    ImageData.push([index, {
                        PageUrl: url,
                        ImageUrl: Link
                    }]);

                    DConfig.DisplayCache = `[${++Task}/${Pages}]`;
                    document.title = DConfig.DisplayCache;
                    self.Button.textContent = `${Lang.Transl("獲取連結")}: ${DConfig.DisplayCache}`;

                    if (Task === Pages) {
                        ImageData.sort((a, b) => a[0] - b[0]); // 進行排序 (方便範圍設置)
                        const Processed = new Map(ImageData);

                        Syn.Storage(DConfig.GetKey(), { value: Processed }); // 緩存數據
                        self.StartTask(Processed);
                    };
                } catch (error) { // 錯誤的直接跳過
                    Syn.Log(null, error, { dev: Config.Dev, type: "error" });
                    Task++;
                }
            };
        };

        /* 重新獲取圖片數據 (試錯) -> [索引, 頁面連結, 圖片連結] */
        ReGetImageData(Index, Url) {
            function GetLink(index, url, page) {
                const Resample = Syn.$$("#img", { root: page });
                const Original = Syn.$$("#i6 div:last-of-type a", { root: page })?.href || "#";

                if (!Resample) return false;

                const Link = Config.Original && !Original.endsWith("#")
                    ? Original : Resample.src || Resample.href;

                // 索引, 頁面連結, 圖片連結
                return [index, url, Link]; 
            };

            let Token = Config.ReTry; // 取得試錯次數
            return new Promise((resolve, reject) => {
                this.Worker.postMessage({ index: Index, url: Url, time: Date.now(), delay: DConfig.Image_ID});
                this.Worker.onmessage = (e) => {
                    const { index, url, html, time, delay, error } = e.data;

                    if (error) {
                        this.Worker.postMessage({ Index, url: Url, time: time, delay: delay});
                    } else {
                        if (Token <= 0) reject(false); // 真的一直失敗的結束 (應該很難被觸發)

                        const result = GetLink(index, url, Syn.DomParse(html));
                        if (result) resolve(result);
                        else {
                            this.Worker.postMessage({ Index, url: Url, time: time, delay: delay});
                            Token-1;
                        }
                    }
                };
            });
        };

        /* 任務啟動器 (配置處理) */
        StartTask(DataMap) {
            Syn.Log(
                Lang.Transl("圖片連結數據"),
                `${this.ComicName}\n${JSON.stringify([...DataMap], null, 4)}`, { dev: Config.Dev }
            );

            // 範圍設置
            if (DConfig.Scope) {
                DataMap = new Map(Syn.ScopeParsing(DConfig.Scope, [...DataMap]));
            };

            // 反向排序 (需要再範圍設置後, 才運行反向)
            if (DConfig.SortReverse) {
                const Size = DataMap.size - 1; // 取得真實長度
                DataMap = new Map(
                    [...DataMap.entries()].map(([index, url]) => [Size - index, url]) // 用原始長度 - 索引值 進行反向替換
                );
            };

            Syn.Log(
                Lang.Transl("任務配置"),
                {
                    ReTry: Config.ReTry,
                    Original: Config.Original,
                    ResetScope: Config.ResetScope,
                    CompleteClose: Config.CompleteClose,
                    SortReverse: DConfig.SortReverse,
                    DownloadMode: DConfig.CurrentDownloadMode,
                    CompressionLevel: DConfig.Compr_Level
                },
                { dev: Config.Dev }
            );

            this.Button.textContent = Lang.Transl("開始下載");
            DConfig.CurrentDownloadMode
                ? this.PackDownload(DataMap)
                : this.SingleDownload(DataMap);
        };

        /* 打包壓縮 下載 */
        async PackDownload(Data) {
            const self = this;
            const Zip = new JSZip();

            let Total = Data.size;
            const Fill = Syn.GetFill(Total); // 取得填充量

            let Enforce = false; // 判斷強制下載狀態
            let ClearCache = false; // 判斷緩存是否被清除
            let ReTry = Config.ReTry; // 重試次數
            let Task, Progress, Thread, Delay; // 宣告變數

            // 初始化變數
            function Init() {
                Task = 0; // 初始任務數
                Progress = 0; // 初始進度
                Delay = DConfig.Download_ID; // 初始延遲
                Thread = DConfig.Download_IT; // 初始線程數
            };

            // 強制下載
            function Force() {
                if (Total > 0) { // 如果總數 > 0, 代表有下載失敗的數據
                    const SortData = [...Data].sort((a, b) => a[0] - b[0]); // 排序
                    SortData.splice(0, 0, {ErrorPage: SortData.map(item => ++item[0]).join(",")}); // 在 SortData 索引 0 加入 ErrorPage, ++item[0] 是因為使用者設置的範圍, 與數據的索引不同
                    Syn.Log(Lang.Transl("下載失敗數據"), JSON.stringify(SortData, null, 4), { type: "error" });
                };

                Enforce = true; // 強制下載 (實驗性)
                Init(); // 數據初始化
                self.Compression(Zip); // 觸發壓縮
            };

            // 清除緩存
            function RunClear() {
                if (!ClearCache) {
                    ClearCache = true;
                    sessionStorage.removeItem(DConfig.GetKey()); // 清除緩存
                    Syn.Log(Lang.Transl("清理警告"), Lang.Transl("下載數據不完整將清除緩存, 建議刷新頁面後重載"), { type: "warn" });
                }
            };

            // 更新請求狀態 (開始請求時間, 數據的索引, 圖片連結, 圖片數據, 錯誤狀態)
            function StatusUpdate(time, index, iurl, blob, error = false) {
                if (Enforce) return;
                [Delay, Thread] = DConfig.Dynamic(time, Delay, Thread, DConfig.Download_ND); // 動態變更延遲與線程

                DConfig.DisplayCache = `[${++Progress}/${Total}]`;

                // 為了避免移除指向導致的錯誤
                self.Button && (self.Button.textContent = `${Lang.Transl("下載進度")}: ${DConfig.DisplayCache}`);
                document.title = DConfig.DisplayCache;

                // Todo: 等待調整更完善判斷, 是否下載成功的條件
                if (!error && blob) {
                    Data.delete(index); // 清除完成的任務
                    Zip.file(`${self.ComicName}/${Syn.Mantissa(index, Fill, "0", iurl)}`, blob); // 保存正確的數據 (有資料夾)
                };

                if (Progress === Total) {
                    Total = Data.size; // 再次取得數據量

                    if (Total > 0 && ReTry-- > 0) { // 重試次數足夠

                        DConfig.DisplayCache = Lang.Transl("等待失敗重試...");
                        document.title = DConfig.DisplayCache;
                        self.Button.textContent = DConfig.DisplayCache;

                        setTimeout(()=> {Start(Data, true)}, 2e3); // 等待 2 秒後重新下載
                    } else Force(); // 直接強制壓縮
                } else if (Progress > Total) Init(); // 避免進度超過總數, 當超過時初始化

                --Task; // 完成任務後扣除計數
            };

            // 請求數據
            function Request(Index, Iurl) {
                if (Enforce) return;
                ++Task; // 任務開始計數
                let timeout = null;
                const time = Date.now(); // 請求開始時間

                if (typeof Iurl !== "undefined") {
                    GM_xmlhttpRequest({
                        url: Iurl,
                        timeout: 15000,
                        method: "GET",
                        responseType: "blob",
                        onload: response => {
                            clearTimeout(timeout);

                            if (response.finalUrl !== Iurl && `${response.status}`.startsWith("30")) {
                                Request(Index, response.finalUrl);
                            } else {
                                const blob = response.response;
                                response.status == 200 && blob instanceof Blob && blob.size > 0
                                    ? StatusUpdate(time, Index, Iurl, blob)
                                    : StatusUpdate(time, Index, Iurl, null, true);
                            }
                        }, onerror: () => {
                            clearTimeout(timeout);
                            StatusUpdate(time, Index, Iurl, null, true);
                        }
                    });
                } else {
                    RunClear();
                    clearTimeout(timeout);
                    StatusUpdate(time, Index, Iurl, null, true);
                }

                timeout = setTimeout(() => {
                    StatusUpdate(time, Index, Iurl, null, true);
                }, 15000);
            };

            // 發起請求任務
            async function Start(DataMap, ReGet=false) {
                if (Enforce) return;
                Init(); // 進行初始化

                for (const [Index, Uri] of DataMap.entries()) {
                    if (Enforce) break;

                    if (ReGet) {
                        Syn.Log(Lang.Transl("重新取得數據"), { Uri: Uri.PageUrl }, { dev: Config.Dev });
                        const Result = await self.ReGetImageData(Index, Uri.PageUrl);
                        Syn.Log(Lang.Transl("取得結果"), { Result: Result }, { dev: Config.Dev });

                        if (Result) {
                            const [Index, Purl, Iurl] = Result;
                            Request(Index, Iurl);
                        } else {
                            RunClear();
                            Request(Index, Uri.ImageUrl);
                        }
                    } else {

                        while (Task >= Thread) { // 根據線程數量暫時卡住迴圈
                            await Syn.Sleep(Delay);
                        }

                        Request(Index, Uri.ImageUrl);
                    }
                }
            };

            Start(Data);
            Syn.Menu({
                [Lang.Transl("📥 強制壓縮下載")]: {
                    func: () => Force(), hotkey: "d"
                }
            }, "Enforce");
        };

        /* 單圖 下載 */
        async SingleDownload(Data) {
            const self = this;

            let Total = Data.size;
            const Fill = Syn.GetFill(Total);
            const TaskPromises = []; // 紀錄任務完成

            let Task = 0;
            let Progress = 0;
            let RetryDelay = 1e3;
            let ClearCache = false;
            let ReTry = Config.ReTry;
            let Delay = DConfig.Download_ID;
            let Thread = DConfig.Download_IT;

            function RunClear() {
                if (!ClearCache) {
                    ClearCache = true;
                    sessionStorage.removeItem(DConfig.GetKey()); // 清除緩存
                    Syn.Log(Lang.Transl("清理警告"), Lang.Transl("下載數據不完整將清除緩存, 建議刷新頁面後重載"), { type: "warn" });
                }
            };

            async function Request(Index, Purl, Iurl, Retry) {
                return new Promise((resolve, reject) => {
                    if (typeof Iurl !== "undefined") {

                        const time = Date.now();
                        ++Task;

                        GM_download({
                            url: Iurl,
                            name: `${self.ComicName}-${Syn.Mantissa(Index, Fill, "0", Iurl)}`,
                            onload: () => {
                                [Delay, Thread] = DConfig.Dynamic(time, Delay, Thread, DConfig.Download_ND);

                                DConfig.DisplayCache = `[${++Progress}/${Total}]`;
                                document.title = DConfig.DisplayCache;
                                self.Button && (self.Button.textContent = `${Lang.Transl("下載進度")}: ${DConfig.DisplayCache}`);
                                --Task;
                                resolve();
                            },
                            onerror: () => {
                                if (Retry > 0) {
                                    [Delay, Thread] = DConfig.Dynamic(time, Delay, Thread, DConfig.Download_ND);
                                    Syn.Log(null, `[Delay:${Delay}|Thread:${Thread}|Retry:${Retry}] : [${Iurl}]`, { dev: Config.Dev, type: "error" });

                                    --Task;
                                    setTimeout(() => {
                                        self.ReGetImageData(Index, Purl)
                                            .then((data) => {
                                                const [Index, Purl, Iurl] = data;
                                                Request(Index, Purl, Iurl, Retry-1);
                                                reject();
                                            })
                                            .catch((err) => {
                                                RunClear();
                                                reject();
                                            });
                                    }, RetryDelay += 1e3); // 如果取得數據失敗, 代表資源衝突了, 就需要設置更高的延遲
                                } else {
                                    --Task;
                                    reject(new Error("Request error"));
                                }
                            }
                        });
                    } else {
                        RunClear();
                        reject();
                    }
                });
            };

            /* 發起請求任務 */
            for (const [Index, Uri] of Data.entries()) {

                while (Task >= Thread) {
                    await Syn.Sleep(Delay);
                }

                TaskPromises.push(Request(Index, Uri.PageUrl, Uri.ImageUrl, ReTry));
            };
            await Promise.allSettled(TaskPromises); // 等待任務完成

            this.Button.textContent = Lang.Transl("下載完成");
            this.Button = null; // 避免後續意外, 直接移除指針

            setTimeout(() => {
                document.title = `✓ ${OriginalTitle}`;
                this.Reset();
            }, 3000);
        };

        /* 壓縮輸出 */
        async Compression(Zip) {
            const self = this;
            GM_unregisterMenuCommand("Enforce-1"); // 刪除強制下載按鈕

            function ErrorProcess(result) {
                document.title = OriginalTitle;

                DConfig.DisplayCache = Lang.Transl("壓縮失敗");
                self.Button.textContent = DConfig.DisplayCache;
                Syn.Log(DConfig.DisplayCache, result, { dev: Config.Dev, type: "error", collapsed: false });

                setTimeout(() => {
                    self.Button.disabled = false;
                    self.Button.textContent = ModeDisplay;
                    self.Button = null;
                }, 4500);
            };

            if (Object.keys(Zip.files).length == 0) {
                ErrorProcess("無數據可壓縮");
                return;
            };

            Zip.generateAsync({
                type: "blob",
                compression: "DEFLATE",
                compressionOptions: { level: DConfig.Compr_Level }
            }, (progress) => {
                DConfig.DisplayCache = `${progress.percent.toFixed(1)} %`;
                document.title = DConfig.DisplayCache;
                this.Button.textContent = `${Lang.Transl("壓縮進度")}: ${DConfig.DisplayCache}`;
            }).then(zip => {
                saveAs(zip, `${this.ComicName}.zip`);
                document.title = `✓ ${OriginalTitle}`;

                this.Button.textContent = Lang.Transl("壓縮完成");
                this.Button = null;

                setTimeout(() => {
                    this.Reset();
                }, 3000);
            }).catch(result => {
                ErrorProcess(result);
            })
        };
    };
    class ButtonCore {
        constructor() {
            this.E = /https:\/\/e-hentai\.org\/g\/\d+\/[a-zA-Z0-9]+/;
            this.Ex = /https:\/\/exhentai\.org\/g\/\d+\/[a-zA-Z0-9]+/;
            this.Allow = (Uri) => this.E.test(Uri) || this.Ex.test(Uri);
            this.InitStyle = () => {
                const Position = `
                    .Download_Button {
                        float: right;
                        width: 12rem;
                        cursor: pointer;
                        font-weight: 800;
                        line-height: 20px;
                        border-radius: 5px;
                        position: relative;
                        padding: 5px 5px;
                        font-family: arial, helvetica, sans-serif;
                    }
                `;

                const E_Style = `
                    .Download_Button {
                    color: #5C0D12;
                    border: 2px solid #9a7c7e;
                    background-color: #EDEADA;
                    }
                    .Download_Button:hover {
                        color: #8f4701;
                        border: 2px dashed #B5A4A4;
                    }
                    .Download_Button:disabled {
                        color: #B5A4A4;
                        border: 2px dashed #B5A4A4;
                        cursor: default;
                    }
                `;

                const Ex_Style = `
                    .Download_Button {
                        color: #b3b3b3;
                        border: 2px solid #34353b;
                        background-color: #2c2b2b;
                    }
                    .Download_Button:hover {
                        color: #f1f1f1;
                        border: 2px dashed #4f535b;
                    }
                    .Download_Button:disabled {
                        color: #4f535b;
                        border: 2px dashed #4f535b;
                        cursor: default;
                    }
                `;

                const Style = Syn.Device.Host === "e-hentai.org" ? E_Style : Ex_Style;
                Syn.AddStyle(`${Position}${Style}`, "Button-style", false);
            };
        };

        /* 下載模式切換 */
        async DownloadModeSwitch() {
            CompressMode
                ? Syn.Store("s", "CompressedMode", false)
                : Syn.Store("s", "CompressedMode", true);

            Syn.$$("#ExDB").remove();
            this.ButtonCreation();
        };

        /* 下載範圍設置 */
        async DownloadRangeSetting() {
            let scope = prompt(Lang.Transl("範圍設置")) || false;
            if (scope) {
                const yes = confirm(`${Lang.Transl("確認設置範圍")}:\n${scope}`);
                if (yes) DConfig.Scope = scope;
            }
        };

        /* 按鈕創建 */
        async ButtonCreation() {
            Syn.WaitElem("#gd2", null, { raf: true}).then(gd2 => {
                CompressMode = Syn.Store("g", "CompressedMode", []);
                ModeDisplay = CompressMode ? Lang.Transl("壓縮下載") : Lang.Transl("單圖下載");

                const download_button = GM_addElement(gd2, "button", {
                    id: "ExDB", class: "Download_Button"
                });

                download_button.disabled = DConfig.Lock ? true : false;
                download_button.textContent = DConfig.Lock ? Lang.Transl("下載中鎖定") : ModeDisplay;

                Syn.AddListener(download_button, "click", () => {
                    DConfig.Lock = true;
                    download_button.disabled = true;
                    download_button.textContent = Lang.Transl("開始下載");
                    this.TaskInstance = new DownloadCore(download_button);
                }, { capture: true, passive: true });
            });
        };

        /* 初始化創建 */
        static async Init() {
            const Core = new ButtonCore();
            if (Core.Allow(Url)) {
                Core.InitStyle();
                OriginalTitle = document.title;
                Lang = Language(Syn.Device.Lang);
                Core.ButtonCreation();
                // Todo - 等待添加設置菜單

                if (Syn.Storage(DConfig.GetKey())) {
                    const menu = GM_registerMenuCommand(Lang.Transl("🚮 清除數據緩存"), ()=> {
                        sessionStorage.removeItem(DConfig.GetKey());
                        GM_unregisterMenuCommand(menu);
                    });
                };

                Syn.Menu({
                    [Lang.Transl("🔁 切換下載模式")]: {
                        func: () => Core.DownloadModeSwitch()
                    },
                    [Lang.Transl("⚙️ 下載範圍設置")]: {
                        func: () => Core.DownloadRangeSetting()
                    }
                });
            };
        };
    };

    function Language(lang) {
        const Word = {
            Traditional: {
                "範圍設置": "下載完成後自動重置\n\n單項設置: 1. 2, 3\n範圍設置: 1~5, 6-10\n排除設置: !5, -10\n",
            },
            Simplified: {
                "🚮 清除數據緩存": "🚮 清除数据缓存",
                "🔁 切換下載模式": "🔁 切换下载模式",
                "⚙️ 下載範圍設置": "⚙️ 下载范围设置",
                "📥 強制壓縮下載": "📥 强制压缩下载",
                "⛔️ 終止下載": "⛔️ 终止下载",
                "壓縮下載": "压缩下载",
                "單圖下載": "单图下载",
                "下載中鎖定": "下载中锁定",
                "開始下載": "开始下载",
                "獲取頁面": "获取页面",
                "獲取連結": "获取链接",
                "下載進度": "下载进度",
                "壓縮進度": "压缩进度",
                "壓縮完成": "压缩完成",
                "壓縮失敗": "压缩失败",
                "下載完成": "下载完成",
                "清理警告": "清理警告",
                "任務配置": "任务配置",
                "取得結果": "取得结果",
                "重新取得數據": "重新取得数据",
                "確認設置範圍": "确认设置范围",
                "剩餘重載次數": "剩余重载次数",
                "下載失敗數據": "下载失败数据",
                "內頁跳轉數據": "内页跳转数据",
                "圖片連結數據": "图片链接数据",
                "等待失敗重試...": "等待失败重试...",
                "請求錯誤重新加載頁面": "请求错误重新加载页面",
                "檢測到圖片集 !!\n\n是否反轉排序後下載 ?": "检测到图片集 !!\n\n是否反转排序后下载？",
                "下載數據不完整將清除緩存, 建議刷新頁面後重載": "下载数据不完整将清除缓存, 建议刷新页面后重载",
                "找不到圖片元素, 你的 IP 可能被禁止了, 請刷新頁面重試": "找不到图片元素, 你的 IP 可能被禁止了, 请刷新页面重试",
                "範圍設置": "下载完成后自动重置\n\n单项设置: 1. 2, 3\n范围设置: 1~5, 6-10\n排除设置: !5, -10\n",
            },
            English: {
                "🚮 清除數據緩存": "🚮 Clear data cache",
                "🔁 切換下載模式": "🔁 Switch download mode",
                "⚙️ 下載範圍設置": "⚙️ Download range settings",
                "📥 強制壓縮下載": "📥 Force compressed download",
                "⛔️ 終止下載": "⛔️ Terminate download",
                "壓縮下載": "Compressed download",
                "單圖下載": "Single image download",
                "下載中鎖定": "Locked during download",
                "開始下載": "Start download",
                "獲取頁面": "Fetch page",
                "獲取連結": "Fetch link",
                "下載進度": "Download progress",
                "壓縮進度": "Compression progress",
                "壓縮完成": "Compression complete",
                "壓縮失敗": "Compression failed",
                "下載完成": "Download complete",
                "清理警告": "Clean up warning",
                "任務配置": "Task Configuration",
                "取得結果": "Fetch Results",
                "重新取得數據": "Refetch Data",
                "確認設置範圍": "Confirm range settings",
                "剩餘重載次數": "Remaining reload attempts",
                "下載失敗數據": "Failed download data",
                "內頁跳轉數據": "Inner page redirection data",
                "圖片連結數據": "Image link data",
                "等待失敗重試...": "Waiting for failed retry...",
                "請求錯誤重新加載頁面": "Request error, reload the page",
                "檢測到圖片集 !!\n\n是否反轉排序後下載 ?": "Image collection detected !!\n\nWould you like to reverse the order and download?",
                "下載數據不完整將清除緩存, 建議刷新頁面後重載": "Download data is incomplete, cache will be cleared, it's recommended to refresh the page and reload",
                "找不到圖片元素, 你的 IP 可能被禁止了, 請刷新頁面重試": "Image element not found, your IP might be blocked, please refresh the page and try again",
                "範圍設置": "Automatically reset after download completion\n\nSingle item settings: 1. 2, 3\nRange settings: 1~5, 6-10\nExclusion settings: !5, -10\n",
            },
            Korea: {
                "🚮 清除數據緩存": "🚮 데이터 캐시 삭제",
                "🔁 切換下載模式": "🔁 다운로드 모드 전환",
                "⚙️ 下載範圍設置": "⚙️ 다운로드 범위 설정",
                "📥 強制壓縮下載": "📥 강제 압축 다운로드",
                "⛔️ 終止下載": "⛔️ 다운로드 중단",
                "壓縮下載": "압축 다운로드",
                "單圖下載": "단일 이미지 다운로드",
                "下載中鎖定": "다운로드 중 잠금",
                "開始下載": "다운로드 시작",
                "獲取頁面": "페이지 가져오기",
                "獲取連結": "링크 가져오기",
                "下載進度": "다운로드 진행",
                "壓縮進度": "압축 진행",
                "壓縮完成": "압축 완료",
                "壓縮失敗": "압축 실패",
                "下載完成": "다운로드 완료",
                "清理警告": "경고 정리",
                "任務配置": "작업 설정",
                "取得結果": "결과 가져오기",
                "重新取得數據": "데이터 다시 가져오기",
                "確認設置範圍": "설정 범위 확인",
                "剩餘重載次數": "남은 재시도 횟수",
                "下載失敗數據": "다운로드 실패 데이터",
                "內頁跳轉數據": "내부 페이지 리디렉션 데이터",
                "圖片連結數據": "이미지 링크 데이터",
                "等待失敗重試...": "실패 재시도를 기다리는 중...",
                "請求錯誤重新加載頁面": "요청 오류, 페이지를 다시 로드하십시오",
                "檢測到圖片集 !!\n\n是否反轉排序後下載 ?": "이미지 모음이 감지되었습니다 !!\n\n역순으로 정렬하여 다운로드하시겠습니까?",
                "下載數據不完整將清除緩存, 建議刷新頁面後重載": "다운로드 데이터가 불완전합니다. 캐시가 지워집니다. 페이지를 새로고침하고 다시 로드하는 것이 좋습니다",
                "找不到圖片元素, 你的 IP 可能被禁止了, 請刷新頁面重試": "이미지 요소를 찾을 수 없습니다. 귀하의 IP가 차단되었을 수 있습니다. 페이지를 새로고침하고 다시 시도하십시오",
                "範圍設置": "다운로드 완료 후 자동 재설정\n\n단항 설정: 1. 2, 3\n범위 설정: 1~5, 6-10\n제외 설정: !5, -10\n",
            },
            Japan: {
                "🚮 清除數據緩存": "🚮 データキャッシュを削除",
                "🔁 切換下載模式": "🔁 ダウンロードモードの切り替え",
                "⚙️ 下載範圍設置": "⚙️ ダウンロード範囲設定",
                "📥 強制壓縮下載": "📥 強制圧縮ダウンロード",
                "⛔️ 終止下載": "⛔️ ダウンロードを中止",
                "壓縮下載": "圧縮ダウンロード",
                "單圖下載": "単一画像のダウンロード",
                "下載中鎖定": "ダウンロード中にロック",
                "開始下載": "ダウンロードを開始",
                "獲取頁面": "ページを取得",
                "獲取連結": "リンクを取得",
                "下載進度": "ダウンロード進行",
                "壓縮進度": "圧縮進行",
                "壓縮完成": "圧縮完了",
                "壓縮失敗": "圧縮失敗",
                "下載完成": "ダウンロード完了",
                "清理警告": "警告のクリーニング",
                "任務配置": "タスク設定",
                "取得結果": "結果を取得",
                "重新取得數據": "データを再取得",
                "確認設置範圍": "設定範囲の確認",
                "剩餘重載次數": "残りのリロード回数",
                "下載失敗數據": "ダウンロード失敗データ",
                "內頁跳轉數據": "内部ページリダイレクトデータ",
                "圖片連結數據": "画像リンクデータ",
                "等待失敗重試...": "失敗したリトライを待機中...",
                "請求錯誤重新加載頁面": "リクエストエラー、ページを再読み込みしてください",
                "檢測到圖片集 !!\n\n是否反轉排序後下載 ?": "画像集が検出されました !!\n\n逆順に並べ替えてダウンロードしますか？",
                "下載數據不完整將清除緩存, 建議刷新頁面後重載": "ダウンロードデータが不完全です。キャッシュがクリアされます。ページをリフレッシュしてリロードすることをお勧めします",
                "找不到圖片元素, 你的 IP 可能被禁止了, 請刷新頁面重試": "画像要素が見つかりません。あなたのIPがブロックされた可能性があります。ページをリフレッシュして再試行してください",
                "範圍設置": "ダウンロード完了後に自動リセット\n\n単項設定: 1. 2, 3\n範囲設定: 1~5, 6-10\n除外設定: !5, -10\n",
            }
        }, Match = {
            ko: Word.Korea,
            ja: Word.Japan,
            "en-US": Word.English,
            "zh-CN": Word.Simplified,
            "zh-SG": Word.Simplified,
            "zh-TW": Word.Traditional,
            "zh-HK": Word.Traditional,
            "zh-MO": Word.Traditional,
        }, ML = Match[lang] ?? Match["en-US"];
        return {
            Transl: (Str) => ML[Str] ?? Str
        };
    };

    ButtonCore.Init();
})();