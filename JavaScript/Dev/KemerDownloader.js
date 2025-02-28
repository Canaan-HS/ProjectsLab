// ==UserScript==
// @name         Kemer 下載器
// @name:zh-TW   Kemer 下載器
// @name:zh-CN   Kemer 下载器
// @name:ja      Kemer ダウンローダー
// @name:en      Kemer Downloader
// @version      0.0.21-Beta5
// @author       Canaan HS
// @description         一鍵下載圖片 (壓縮下載/單圖下載) , 頁面數據創建 json 下載 , 一鍵開啟當前所有帖子
// @description:zh-TW   一鍵下載圖片 (壓縮下載/單圖下載) , 頁面數據創建 json 下載 , 一鍵開啟當前所有帖子
// @description:zh-CN   一键下载图片 (压缩下载/单图下载) , 页面数据创建 json 下载 , 一键开启当前所有帖子
// @description:ja      画像をワンクリックでダウンロード（圧縮ダウンロード/単一画像ダウンロード）、ページデータを作成してjsonでダウンロード、現在のすべての投稿をワンクリックで開く
// @description:en      One-click download of images (compressed download/single image download), create page data for json download, one-click open all current posts

// @connect      *
// @match        *://kemono.su/*
// @match        *://coomer.su/*
// @match        *://nekohouse.su/*
// @match        *://*.kemono.su/*
// @match        *://*.coomer.su/*
// @match        *://*.nekohouse.su/*

// @license      MPL-2.0
// @namespace    https://greasyfork.org/users/989635
// @icon         https://cdn-icons-png.flaticon.com/512/2381/2381981.png

// @run-at       document-start
// @grant        window.close
// @grant        GM_info
// @grant        GM_setValue
// @grant        GM_getValue
// @grant        GM_download
// @grant        GM_openInTab
// @grant        GM_addElement
// @grant        GM_getResourceURL
// @grant        GM_xmlhttpRequest
// @grant        GM_getResourceText
// @grant        GM_registerMenuCommand
// @grant        GM_unregisterMenuCommand

// @require      https://update.greasyfork.org/scripts/495339/1532088/ObjectSyntax_min.js
// @require      https://cdnjs.cloudflare.com/ajax/libs/FileSaver.js/2.0.5/FileSaver.min.js
// @require      https://raw.githubusercontent.com/Canaan-HS/Practical-Exercises/refs/heads/Main/JavaScript/API/JSZip.min.js

// @resource     json-processing https://cdn-icons-png.flaticon.com/512/2582/2582087.png
// @resource     font-awesome https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.2/css/svg-with-js.min.css
// ==/UserScript==

/**
* 修改思路 (什麼時候有空不知道)
*
* 功能設置: 操作系統通知(開關按鈕)/ 下載完成後自動關閉(開關按鈕)/ 實驗功能(開關按鈕)
* 一鍵開帖延遲(輸入框/毫秒)/ 實驗下載延遲(輸入框/毫秒)
*
* 功能選擇:
* 下載模式選擇(按鈕)
* Json 實驗下載功能(按鈕)
* 開啟當前所有頁面(按鈕)
* 進階 Json 輸出格式設置
*
* 添加功能:
* 下載時檔名格式選擇
* 壓縮下載時選擇是否需多一個資料夾
* 上傳導出的 Json 一鍵下載所有內容 (圖片/影片|雲端應該無法)
*/

(async () => {
    const Config = {
        Dev: false, // 顯示請求資訊, 與錯誤資訊
        ContainsVideo: false, // 下載時包含影片
        CompleteClose: false, // 下載完成後關閉
        ConcurrentDelay: 3, // 下載線程延遲 (秒) [壓縮下載]
        ConcurrentQuantity: 5, // 下載線程數量 [壓縮下載]
        BatchOpenDelay: 500, // 一鍵開啟帖子的延遲 (ms)
    };

    /** ---------------------
     * 暫時的 檔名修改方案
     *
     * 根據要添加的元素修改字串
     * 中間的間隔可用任意字符
     *
     * ! 不限制大小寫, 但一定要有 {}, 不能用於命名的符號會被移除
     *
     * {Time} 發表時間
     * {Title} 標題
     * {Artist} 作者 | 繪師 ...
     * {Source} 來源 => (Pixiv Fanbox) 之類的標籤
     *
     * {Fill} 填充 => ! 只適用於檔名, 位置隨意 但 必須存在該值, 不然會出錯
     */
    const FileName = {
        FillValue: {
            Filler: "0", // 填充元素 / 填料
            Amount: "Auto", // 填充數量 [輸入 auto 或 任意數字]
        },
        CompressName: "({Artist}) {Title}", // 壓縮檔案名稱
        FolderName: "{Title}", // 資料夾名稱 (用空字串, 就直接沒資料夾)
        FillName: "{Artist} {Fill}", // 檔案名稱 [! 可以移動位置, 但不能沒有 {Fill}]
    };

    /** ---------------------
     * 設置 FetchData 輸出格式
     *
     *! 無論設置什麼, 只要沒有的數據, 就不會顯示 (會被排除掉)
     *
     * ----------------------
     * 舊版 nekohouse.su
     *
     *
     * ----------------------
     * Mode
     * 排除模式: "FilterMode" -> 預設為全部使用, 設置排除的項目
     * 僅有模式: "OnlyMode" -> 預設為全部不使用, 設置使用的項目
     * ----------------------
     * Format
     * 帖子連結: "PostLink"
     * 發佈時間: "Timestamp"
     * 標籤 Tag: "TypeTag"
     * 圖片數量: "ImgLink"
     * 影片連結: "VideoLink"
     * 下載連結: "DownloadLink"
     * 其他連結: "CloudLink"
     */
    const FetchSet = {
        AdvancedFetch: true, // 進階抓取, 可獲取 (雲端 or 第三方) 連結 和 Tag 標籤資訊 (所需時間較久)
        UseFormat: false, // 這裡為 false 下面兩項就不生效
        Mode: "FilterMode",
        Format: ["Timestamp", "ImgLink"],
    };

    /* --------------------- */

    let lock = false;
    const Lang = Language(Syn.Device.Lang);
    const IsNeko = Syn.Device.Host === "nekohouse.su"; // 臨時方案

    class Download {
        constructor(CM, MD, BT) {
            this.Button = BT;
            this.ModeDisplay = MD;
            this.CompressMode = CM;
            this.ForceDownload = false;

            this.Named_Data = null;

            /* 獲取原始標題 */
            this.OriginalTitle = () => {
                const cache = document.title;
                return cache.startsWith("✓ ") ? cache.slice(2) : cache;
            };

            this.videoFormat = new Set(["MP4", "MOV", "AVI", "WMV", "FLV"]);
            this.isVideo = (str) => this.videoFormat.has(str.toUpperCase());

            this.worker = Syn.WorkerCreation(`
                let queue = [], processing=false;
                onmessage = function(e) {
                    queue.push(e.data);
                    !processing && (processing=true, processQueue());
                }
                async function processQueue() {
                    if (queue.length > 0) {
                        const {index, url} = queue.shift();
                        XmlRequest(index, url);
                        processQueue();
                    } else {processing = false}
                }

                async function XmlRequest(index, url) {
                    let xhr = new XMLHttpRequest();
                    xhr.responseType = "blob";
                    xhr.open("GET", url, true);
                    xhr.onload = function() {
                        if (xhr.readyState === 4 && xhr.status === 200) {
                            postMessage({ index, url: url, blob: xhr.response, error: false });
                        } else {
                            FetchRequest(index, url);
                        }
                    }
                    xhr.onerror = function() {
                        FetchRequest(index, url);
                    }
                    xhr.send();
                }

                async function FetchRequest(index, url) {
                    try {
                        const response = await fetch(url);
                        if (response.readyState === 4 && response.status === 200) {
                            const blob = await response.blob();
                            postMessage({ index, url: url, blob, error: false });
                        } else {
                            postMessage({ index, url: url, blob: "", error: true });
                        }
                    } catch {
                        postMessage({ index, url: url, blob: "", error: true });
                    }
                }
            `);
        }

        /* 解析名稱格式 */
        NameAnalysis(format) {
            if (typeof format == "string") {
                return format.split(/{([^}]+)}/g).filter(Boolean).map(data => {
                    const LowerData = data.toLowerCase().trim();
                    const isWord = /^[a-zA-Z]+$/.test(LowerData);
                    return isWord ? this.Named_Data[LowerData]?.() ?? "None" : data;
                }).join("");

            } else if (typeof format == "object") {
                const filler = String(format.Filler) || "0";
                const amount = parseInt(format.Amount) || "auto";
                return [amount, filler];

            } else { }
        }

        /* 下載觸發 [ 查找下載數據, 解析下載資訊, 呼叫下載函數 ] */
        DownloadTrigger() { // 下載數據, 文章標題, 作者名稱
            Syn.WaitElem([
                ".post__title, .scrape__title",
                ".post__files, .scrape__files",
                ".post__user-name, .scrape__user-name, fix_name"
            ], found => {
                const [title, files, artist] = found;
                this.Button.disabled = lock = true;
                const DownloadData = new Map();

                this.Named_Data = { // 建立數據
                    fill: () => "fill",
                    title: () => Syn.$$("span", { root: title }).textContent.trim(),
                    artist: () => artist.textContent.trim(),
                    source: () => new Date(title.querySelector(":nth-child(2)").textContent.trim()).toLocaleString(),
                    time: () => {
                        if (IsNeko) {
                            return Syn.$$(".timestamp")?.textContent.trim() || "";
                        };

                        let published = Syn.$$(".post__published").cloneNode(true);
                        document.querySelector(".post__published");
                        published.firstElementChild.remove();
                        return published.textContent.trim().split(" ")[0];
                    }
                }

                const [ // 獲取名稱
                    compress_name,
                    folder_name,
                    fill_name
                ] = Object.keys(FileName).slice(1).map(key => this.NameAnalysis(FileName[key]));

                const // 這種寫法適應於還未完全載入原圖時
                    data = [...files.children]
                        .map(child => Syn.$$(IsNeko ? "div, rc, img" : "a, rc, img", { root: child }))
                        .filter(Boolean),
                    video = Syn.$$(".post__attachment a, .scrape__attachment a", { all: true }),
                    final_data = Config.ContainsVideo ? [...data, ...video] : data;

                // 使用 foreach, 他的異步特性可能造成一些意外, 因此使用 for
                for (const [index, file] of final_data.entries()) {
                    const Uri = file.src || file.href || file.getAttribute("src") || file.getAttribute("href");
                    if (Uri) {
                        DownloadData.set(index, (
                            Uri.startsWith("http") ? Uri : `${Syn.Device.Orig}${Uri}`
                        ));
                    }
                }

                Syn.Log("Get Data", {
                    FolderName: folder_name,
                    DownloadData: DownloadData
                }, { dev: Config.Dev, collapsed: false });

                this.CompressMode
                    ? this.PackDownload(compress_name, folder_name, fill_name, DownloadData)
                    : this.SeparDownload(fill_name, DownloadData);

            }, { raf: true });
        }

        /* 打包壓縮下載 */
        async PackDownload(CompressName, FolderName, FillName, Data) {
            let
                show,
                extension,
                progress = 0,
                Total = Data.size;
            const
                Self = this,
                Zip = new JSZip(),
                TitleCache = this.OriginalTitle();
            const
                FillValue = this.NameAnalysis(FileName.FillValue),
                Filler = FillValue[1],
                Amount = FillValue[0] == "auto" ? Syn.GetFill(Total) : FillValue[0];

            // 強制下載
            async function ForceDownload() {
                Self.worker.terminate();
                Self.Compression(CompressName, Zip, TitleCache);
            }

            Syn.Menu({
                [Lang.Transl("📥 強制壓縮下載")]: { func: () => ForceDownload(), hotkey: "d" }
            }, "Enforce");

            // 更新請求狀態
            FolderName = FolderName != "" ? `${FolderName}/` : ""; // 處理資料夾名稱格式
            function Request_update(index, url, blob, retry = false) {
                if (Self.ForceDownload) return;
                requestAnimationFrame(() => {
                    Data.delete(index);
                    if (retry) {
                        Data.set(index, url);
                    } else {
                        extension = Syn.ExtensionName(url); // 雖然 Mantissa 函數可直接傳遞 url 為第四個參數, 但因為需要 isVideo 的資訊, 所以分別操作
                        Self.isVideo(extension)
                            ? Zip.file(`${FolderName}${decodeURIComponent(url.split("?f=")[1])}`, blob)
                            : Zip.file(`${FolderName}${FillName.replace("fill", Syn.Mantissa(index, Amount, Filler))}.${extension}`, blob);
                    }

                    show = `[${++progress}/${Total}]`;
                    document.title = show;
                    Self.Button.textContent = `${Lang.Transl("下載進度")} ${show}`;

                    if (progress == Total) {
                        Total = Data.size;
                        if (Total == 0) {
                            Self.worker.terminate();
                            Self.Compression(CompressName, Zip, TitleCache);
                        } else {
                            show = "Wait for failed re download";
                            progress = 0;
                            document.title = show;
                            Self.Button.textContent = show;
                            setTimeout(() => {
                                for (const [index, url] of Data.entries()) {
                                    Self.worker.postMessage({ index: index, url: url });
                                }
                            }, 1500);
                        }
                    }
                });
            }

            // 不使用 worker 的請求, 切換窗口時, 這裡的請求就會變慢
            async function Request(index, url) {
                if (Self.ForceDownload) return;
                GM_xmlhttpRequest({
                    url: url,
                    method: "GET",
                    responseType: "blob",
                    onload: response => {
                        if (response.status == 429) {
                            Request_update(index, url, "", true);
                            return;
                        }

                        const blob = response.response;
                        blob instanceof Blob && blob.size > 0
                            ? Request_update(index, url, blob)
                            : Request_update(index, url, "", true);
                    },
                    onerror: () => {
                        Request_update(index, url, "", true);
                    }
                })
            }

            // 傳遞訊息
            const Batch = Config.ConcurrentQuantity;
            const Delay = Config.ConcurrentDelay * 1e3;

            // 只是顯示給使用者讓其知道 有運作 (無實際作用)
            Self.Button.textContent = `${Lang.Transl("請求進度")} [${Total}/${Total}]`;

            for (let i = 0; i < Total; i += Batch) {
                setTimeout(() => {
                    for (let j = i; j < i + Batch && j < Total; j++) {
                        this.worker.postMessage({ index: j, url: Data.get(j) });
                    }
                }, (i / Batch) * Delay);
            }

            // 接收訊息
            this.worker.onmessage = (e) => {
                const { index, url, blob, error } = e.data;
                error
                    ? (Request(index, url), Syn.Log("Download Failed", url, { dev: Config.Dev, type: "error", collapsed: false }))
                    : (Request_update(index, url, blob), Syn.Log("Download Successful", url, { dev: Config.Dev, collapsed: false }));
            }
        }

        /* 壓縮檔案 */
        async Compression(Name, Data, Title) {
            this.ForceDownload = true;
            GM_unregisterMenuCommand("Enforce-1");
            Data.generateAsync({
                type: "blob",
                compression: "DEFLATE",
                compressionOptions: { level: 5 }
            }, (progress) => {
                document.title = `${progress.percent.toFixed(1)} %`;
                this.Button.textContent = `${Lang.Transl("封裝進度")}: ${progress.percent.toFixed(1)} %`;
            }).then(zip => {
                saveAs(zip, `${Name}.zip`);
                document.title = `✓ ${Title}`;
                this.Button.textContent = Lang.Transl("下載完成");
                setTimeout(() => {
                    this.ResetButton();
                }, 3000);
            }).catch(result => {
                document.title = Title;

                const ErrorShow = Lang.Transl("壓縮封裝失敗");
                this.Button.textContent = ErrorShow;
                Syn.Log(ErrorShow, result, { dev: Config.Dev, type: "error", collapsed: false });

                setTimeout(() => {
                    this.Button.disabled = false;
                    this.Button.textContent = this.ModeDisplay;
                }, 6000);
            })
        }

        /* 單圖下載 */
        async SeparDownload(FillName, Data) {
            let
                show,
                link,
                filename,
                extension,
                stop = false,
                progress = 0;
            const
                Self = this,
                Process = [],
                Promises = [],
                Total = Data.size,
                ShowTracking = {},
                DownloadTracking = {},
                TitleCache = this.OriginalTitle();
            const
                FillValue = this.NameAnalysis(FileName.FillValue),
                Filler = FillValue[1],
                Amount = FillValue[0] == "auto" ? Syn.GetFill(Total) : FillValue[0];

            // 停止下載的線程
            async function Stop() {
                stop = true;
                Process.forEach(process => process.abort())
            }

            Syn.Menu({
                [Lang.Transl("⛔️ 終止下載")]: { func: () => Stop(), hotkey: "s" }
            }, "Abort");

            async function Request(index) {
                if (stop) return;
                link = Data.get(index);
                extension = Syn.ExtensionName(link);
                filename = Self.isVideo(extension)
                    ? decodeURIComponent(link.split("?f=")[1])
                    : `${FillName.replace("fill", Syn.Mantissa(index, Amount, Filler))}.${extension}`;

                return new Promise((resolve, reject) => {

                    const completed = () => {
                        if (!ShowTracking[index]) { // 多一個判斷是因為, 他有可能同樣的重複呼叫多次
                            ShowTracking[index] = true;

                            Syn.Log("Download Successful", link, { dev: Config.Dev, collapsed: false });

                            show = `[${++progress}/${Total}]`;
                            document.title = show;

                            Self.Button.textContent = `${Lang.Transl("下載進度")} ${show}`;
                            resolve();
                        }
                    };

                    const download = GM_download({
                        url: link,
                        name: filename,
                        conflictAction: "overwrite",
                        onload: () => {
                            completed();
                        },
                        onprogress: (progress) => {
                            /* 新版本的油猴插件, 這個回條怪怪的
                            Syn.Log("Download Progress", {
                                Index: index,
                                ImgUrl: link,
                                Progress: `${progress.loaded}/${progress.total}`
                            }, {dev: Config.Dev, collapsed: false});

                            DownloadTracking[index] = (progress.loaded == progress.total);
                            DownloadTracking[index] && completed();
                            */
                        },
                        onerror: () => {
                            Syn.Log("Download Error", link, { dev: Config.Dev, type: "error", collapsed: false });
                            setTimeout(() => {
                                reject();
                                Request(index);
                            }, 1500);
                        }
                    });

                    Process.push(download);
                });
            }

            for (let i = 0; i < Total; i++) {
                Promises.push(Request(i));
                await Syn.Sleep(1e3);
            }

            await Promise.allSettled(Promises);
            GM_unregisterMenuCommand("Abort-1");

            document.title = `✓ ${TitleCache}`;
            this.Button.textContent = Lang.Transl("下載完成");
            setTimeout(() => {
                this.ResetButton();
            }, 3000);
        }

        /* 按鈕重置 */
        async ResetButton() {
            Config.CompleteClose && window.close();
            lock = false;
            const Button = Syn.$$("#ExDB button");
            Button.disabled = false;
            Button.textContent = `✓ ${this.ModeDisplay}`;
        }
    }

    class DataToJson {
        constructor() {
            this.JsonDict = {};
            this.Genmode = true;
            this.SortMap = new Map();
            this.Source = document.URL;
            this.TitleCache = document.title;
            this.Section = Syn.$$("section");
            this.Pages = this.progress = this.filtercache = null;
            this.Author = Syn.$$("span[itemprop='name'], fix_name").textContent;
            this.JsonMode = { "orlink": "set_1", "imgnb": "set_2", "videonb": "set_3", "dllink": "set_4" }

            /* Mega 連結解析 (測試中 有些Bug) */
            this.MegaAnalysis = (data) => {
                let title_box = [], link_box = [], result = {}, pass;
                for (let i = 0; i < data.length; i++) {
                    const str = data[i].textContent.trim();
                    if (str.startsWith("Pass")) { // 解析密碼字串
                        const ps = data[i].innerHTML.match(/Pass:([^<]*)/);
                        try { pass = `Pass : ${ps[1].trim()}` } catch { pass = str }
                    } else if (str.toUpperCase() == "MEGA") {
                        link_box.push(data[i].parentElement.href);
                    } else {
                        title_box.push(str.replace(":", "").trim());
                    }
                }
                // 合併數據
                for (let i = 0; i < title_box.length; i++) {
                    result[title_box[i]] = link_box[i]
                }
                return { pass, result };
            }
        }

        /* 獲取下一頁數據 */
        async GetNextPage(NextPage) {
            GM_xmlhttpRequest({
                method: "GET",
                url: NextPage,
                nocache: false,
                onload: response => {
                    this.GetPageData(Syn.$$("section", { root: response.responseXML }));
                }
            })
        }

        /* 獲取主頁元素 */
        async GetPageData(section) {
            let title, link;
            const item = Syn.$$(".card-list__items article", { all: true, root: section });

            // 遍歷數據
            this.progress = 0;
            for (const [index, card] of item.entries()) {
                link = Syn.$$("a", { root: card }).href;
                title = Syn.$$(".post-card__header", { root: card }).textContent.trim() || `Untitled_${String(this.progress + 1).padStart(2, "0")}`;

                if (Config.ExperimeDownload) {
                    this.worker.postMessage({ index: index, title: title, url: link });
                } else {
                    this.JsonDict[`${link}`] = title;
                }

                await Syn.Sleep(10);
            }

            const menu = Syn.$$("a.pagination-button-after-current", { root: section });
            const ILength = item.length,
                wait = setInterval(() => {
                    if (ILength == this.SortMap.size) {
                        clearInterval(wait);

                        for (let i = 0; i < ILength; i++) { // 按照索引順序取出 SortMap, 並將數據添加到 JsonDict, 接著清除掉 SortMap
                            const data = this.SortMap.get(i);
                            this.JsonDict[data.title] = data.box;
                        }

                        this.Pages++;
                        this.SortMap.clear(); // 清除
                        menu ? this.GetNextPage(menu.href) : this.ToJson();
                    }
                }, 500);
        }

        /* Json 數據請求 並 解析 */
        async DataAnalysis() {
            this.worker.onmessage = async (e) => {
                const data_box = {}, { index, title, url, text, error } = e.data;
                if (!error) {
                    const DOM = Syn.DomParse(text);

                    const original_link = url,
                        pictures_number = Syn.$$("post__thumbnail, .scrape__thumbnail", { all: true, root: DOM }).length,
                        video_number = Syn.$$(".post__body li video, .scrape__files video", { all: true, root: DOM }).length,
                        mega_link = Syn.$$(".post__content strong, .scrape__content strong", { all: true, root: DOM });

                    Syn.$$("a.post__attachment-link, a.scrape__attachment-link", { all: true, root: DOM }).forEach(link => {
                        const analyze = decodeURIComponent(link.href).split("?f="),
                            download_link = analyze[0],
                            download_name = analyze[1];
                        data_box[download_name] = download_link;
                    })

                    if (mega_link.length > 0) {
                        try {
                            const { pass, result } = this.MegaAnalysis(mega_link);
                            pass != unSynined ? data_box[pass] = result : null;
                        } catch { }
                    }

                    const box = this.GenerateBox(original_link, pictures_number, video_number, data_box);
                    if (Object.keys(box).length !== 0) {
                        this.SortMap.set(index, { title: title, box: box });
                    }

                    Syn.Log("Request Successful", this.SortMap, { dev: Config.Dev, collapsed: false });
                    document.title = `（${this.Pages} - ${++this.progress}）`;
                } else {
                    Syn.Log("Request Failed", { title: title, url: url }, { dev: Config.Dev, type: "error", collapsed: false });
                    await Syn.Sleep(1500);
                    this.worker.postMessage({ index: index, title: title, url: url });
                }
            }
        }
    }

    class FetchData {
        constructor(AdvancedFetch) {
            this.MetaDict = {}; // 保存元數據
            this.DataDict = {}; // 保存最終數據

            this.TaskDict = new Map(); // 任務臨時數據

            this.Host = Syn.Device.Host;
            this.SourceURL = document.URL; // 不能從 Device 取得, 會無法適應換頁
            this.TitleCache = document.title;
            this.FirstURL = this.SourceURL.split("?o=")[0]; // 第一頁連結

            this.Pages = 1; // 預設開始抓取的頁數
            this.FinalPages = 10; // 預設最終抓取的頁數
            this.Progress = 0; // 用於顯示當前抓取進度
            this.OnlyMode = false; // 判斷獲取數據的模式
            this.AdvancedFetch = AdvancedFetch; // 判斷是否往內抓數據

            // 內部連結的 API 模板
            this.PostAPI = `${this.FirstURL}/post`.replace(this.Host, `${this.Host}/api/v1`);

            this.PreviewAPI = Url => // 將預覽頁面轉成 API 連結
                /[?&]o=/.test(Url)
                    ? Url.replace(this.Host, `${this.Host}/api/v1`).replace(/([?&]o=)/, "/posts-legacy$1")
                    : Url.replace(this.Host, `${this.Host}/api/v1`) + "/posts-legacy";

            // 預設添加的數據
            this.InfoRules = {
                "PostLink": Lang.Transl("帖子連結"),
                "Timestamp": Lang.Transl("發佈日期"),
                "TypeTag": Lang.Transl("類型標籤"),
                "ImgLink": Lang.Transl("圖片連結"),
                "VideoLink": Lang.Transl("影片連結"),
                "DownloadLink": Lang.Transl("下載連結"),
                "CloudLink": Lang.Transl("雲端連結")
            };

            // 根據類型判斷預設值
            this.Default = (Value) => {
                if (!Value) return null;

                const type = Syn.Type(Value);
                if (type === "Array") return Value.length > 0 && Value.some(item => item !== "") ? Value : null;
                if (type === "Object") {
                    const values = Object.values(Value);
                    return values.length > 0 && values.some(item => item !== "") ? Value : null;
                }

                return Value;
            };

            /**
             * 生成數據
             * @param {{
             *      PostLink: string,
             *      Timestamp: string,
             *      TypeTag: array,
             *      ImgLink: object,
             *      VideoLink: object,
             *      DownloadLink: object
             *      CloudLink: object
             * }} Data
             * @returns {object}
             */
            this.FetchGenerate = (Data) => {
                return Object.keys(Data).reduce((acc, key) => {
                    if (this.InfoRules.hasOwnProperty(key)) {
                        const value = this.Default(Data[key]);
                        value && (acc[this.InfoRules[key]] = value); // 有數據的才被添加
                    }
                    return acc;
                }, {});
            };

            // 影片類型
            this.Video = new Set([
                ".mp4", ".avi", ".mkv", ".mov", ".flv", ".wmv", ".webm", ".mpg", ".mpeg",
                ".m4v", ".ogv", ".3gp", ".asf", ".ts", ".vob", ".rm", ".rmvb", ".m2ts",
                ".f4v", ".mts"
            ]);

            // 圖片類型
            this.Image = new Set([
                ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".webp", ".tiff", ".tif",
                ".svg", ".heic", ".heif", ".raw", ".ico", ".psd"
            ]);

            // 進階抓取檔案分類 (影片與圖片文件 Array) => { video: {}, other: {} }
            this.AdvancedCategorize = (Data) => {
                return Data.reduce((acc, file) => {
                    const url = `${file.server}/data${file.path}?f=${file.name.replace(/\s/g, "+")}`;
                    this.Video.has(file.extension) ? (acc.video[file.name] = url) : (acc.other[file.name] = url);
                    return acc;
                }, { video: {}, other: {} });
            };

            // 一般抓取的檔案分類 (標題字串, 所有類型文件 Array) => { img: [], video: {}, other: {} }
            this.Categorize = (Title, Data) => {
                let imgNumber = 0;
                let serverNumber = 0;

                return Data.reduce((acc, file) => {
                    const name = file.name;
                    const path = file.path;
                    const extension = `.${name.match(/\.([^.]+)$/)[1]}`;

                    serverNumber = (serverNumber % 4) + 1;
                    const server = `https://n${serverNumber}.${this.Host}/data`;

                    if (this.Video.has(extension)) {
                        acc.video[name] = `${server}${path}?f=${name}`;
                    } else if (this.Image.has(extension)) {
                        const name = `${Title}_${String(++imgNumber).padStart(2, "0")}${extension}`;
                        acc.img[name] = `${server}${path}?f=${name}`;
                    } else {
                        acc.other[name] = `${server}${path}?f=${name}`;
                    }

                    return acc;
                }, { img: {}, video: {}, other: {} });
            };

            this.TryAgain_Promise = null; // 緩存等待的 Promise
            this.TooMany_TryAgain = (Uri) => {
                // 如果已經有一個等待中的 Promise，直接返回
                if (this.TryAgain_Promise) {
                    return this.TryAgain_Promise;
                }

                const sleepTime = 5e3; // 每次等待 5 秒
                const timeout = 20e4; // 最多等待 20 秒
                const Url = Uri;

                this.TryAgain_Promise = new Promise(async (resolve) => {
                    const checkRequest = async () => {
                        const controller = new AbortController(); // 創建 AbortController
                        const signal = controller.signal;
                        const timeoutId = setTimeout(() => {
                            controller.abort(); // 超時後中止請求
                        }, timeout);

                        try {
                            const response = await fetch(Url, { // 發起請求
                                method: "HEAD", signal
                            });

                            clearTimeout(timeoutId);
                            if (response.status === 429) {
                                await Syn.Sleep(sleepTime);
                                await checkRequest(); // 繼續檢查
                            } else {
                                resolve(); // 等待完成
                                this.TryAgain_Promise = null;
                            }
                        } catch (err) {
                            clearTimeout(timeoutId);
                            await Syn.Sleep(sleepTime);
                            await checkRequest();
                        }
                    };

                    await checkRequest();
                });

                return this.TryAgain_Promise;
            };

            // 請求工作
            this.Worker = Syn.WorkerCreation(`
                let queue = [], processing=false;
                onmessage = function(e) {
                    queue.push(e.data);
                    !processing && (processing=true, processQueue());
                }
                async function processQueue() {
                    if (queue.length > 0) {
                        const {index, title, url} = queue.shift();
                        XmlRequest(index, title, url);
                        processQueue();
                    } else {processing = false}
                }
                async function XmlRequest(index, title, url) {
                    let xhr = new XMLHttpRequest();
                    xhr.responseType = "text";
                    xhr.open("GET", url, true);
                    xhr.onload = function() {
                        if (xhr.status === 200) {
                            postMessage({ index, title, url, text: xhr.response, error: false });
                        } else if (xhr.status === 429) {
                            postMessage({ index, title, url, text: "", error: true });
                        } else {
                            FetchRequest(index, title, url);
                        }
                    }
                    xhr.onerror = function() {
                        if (xhr.status === 429) {
                            postMessage({ index, title, url, text: "", error: true });
                        } else {
                            FetchRequest(index, title, url);
                        }
                    }
                    xhr.send();
                }
                async function FetchRequest(index, title, url) {
                    fetch(url).then(response => {
                        if (response.ok) {
                            response.text().then(text => {
                                postMessage({ index, title, url, text, error: false });
                            });
                        } else {
                            postMessage({ index, title, url, text: "", error: true });
                        }
                    })
                    .catch(error => {
                        postMessage({ index, title, url, text: "", error: true });
                    });
                }
            `);

            // 解析特別連結
            this.specialLinkParse = (Data) => {
                const Cache = {};

                try {
                    for (const strong of Syn.$$("body strong", { all: true, root: Syn.DomParse(Data) })) {
                        const mayBeLink = strong.nextElementSibling;

                        // 確認是連結
                        if (mayBeLink?.tagName === "A" && mayBeLink.hasAttribute("href")) {
                            const href = mayBeLink.href;

                            if (href.startsWith("https://mega.nz")) {

                                let name = strong.textContent.replace(":", "").trim() || href.textContent.trim();
                                if (name === "") continue;

                                let pass = [...mayBeLink.nextElementSibling.childNodes].filter(node => node.nodeType === Node.TEXT_NODE)?.[0].textContent ?? "";
                                if (pass.startsWith("Pass")) {
                                    pass = pass.match(/Pass:([^<]*)/)[1].trim();
                                }

                                Cache[name] = {
                                    [Lang.Transl("密碼")]: pass,
                                    [Lang.Transl("連結")]: href
                                };
                            } else if (href) { // ! 待測試
                                const name = mayBeLink.textContent.replace(":", "").trim();
                                Cache[name] = href;
                            }
                        };
                    }
                } catch (error) {
                    Syn.Log("Error specialLinkParse", error, { dev: Config.Dev, type: "error", collapsed: false });
                }

                return Cache;
            };
        }

        /**
         * 設置抓取規則
         * @param {string} Mode - "FilterMode" | "OnlyMode"
         * @param {Array} UserSet - 要進行的設置
         *
         * @example
         * 可配置項目: ["PostLink", "Timestamp", "TypeTag", "ImgLink", "VideoLink", "DownloadLink"]
         *
         * 這會將這些項目移除在顯示
         * FetchConfig("FilterMode", ["PostLink", "ImgLink", "DownloadLink"]);
         *
         * 這會只顯示這些項目
         * FetchConfig("OnlyMode", ["PostLink", "ImgLink", "DownloadLink"]);
         */
        async FetchConfig(Mode = "FilterMode", UserSet = []) {
            let Cache;
            switch (Mode) {
                case "FilterMode":
                    this.OnlyMode = false;
                    UserSet.forEach(key => delete this.InfoRules[key]);
                    break;
                case "OnlyMode":
                    this.OnlyMode = true;
                    Cache = Object.keys(this.InfoRules).reduce((acc, key) => {
                        if (UserSet.includes(key)) acc[key] = this.InfoRules[key];
                        return acc;
                    }, {});
                    this.InfoRules = Cache;
                    break;
            }
        };

        /* 入口調用函數 */
        async FetchInit() {
            const Section = Syn.$$("section");

            if (Section) {
                lock = true; // 鎖定菜單的操作, 避免重複抓取

                // 取得當前頁數
                for (const page of Syn.$$(".pagination-button-disabled b", { all: true })) {
                    const number = Number(page.textContent);
                    if (number) {
                        this.Pages = number;
                        break;
                    }
                }

                this.FetchRun(Section, this.SourceURL); // 啟用抓取
            } else {
                alert(Lang.Transl("未取得數據"));
            }
        };

        /* ===== 主要抓取函數 ===== */

        /* 運行抓取數據 */
        async FetchRun(Section, Url) {

            if (IsNeko) {
                const Item = Syn.$$(".card-list__items article", { all: true, root: Section });

                // 下一頁連結
                const Menu = Syn.$$("a.pagination-button-after-current", { root: Section });
                if (Menu) {
                    // Menu.href
                }
            } else {
                this.Worker.postMessage({ index: 0, title: this.TitleCache, url: this.PreviewAPI(Url) });

                // 等待主頁數據
                const HomePage = await new Promise((resolve, reject) => {
                    this.Worker.onmessage = async (e) => {
                        const { index, title, url, text, error } = e.data;
                        if (!error) resolve({ index, title, url, text });
                        else {
                            Syn.Log(error, { title: title, url: url }, { dev: Config.Dev, type: "error", collapsed: false });
                            await this.TooMany_TryAgain(url);
                            this.Worker.postMessage({ index: index, title: title, url: url });
                        };
                    }
                });

                // 等待內容數據
                await this.FetchContent(HomePage);

                this.Pages++;
                this.Pages <= this.FinalPages
                    ? this.FetchRun(null,
                        /\?o=\d+$/.test(Url) // 生成下一頁連結
                            ? Url.replace(/\?o=(\d+)$/, (match, number) => `?o=${+number + 50}`)
                            : `${Url}?o=50`
                    )
                    : this.ToJson();
            }
        };

        /* 獲取帖子內部數據 */
        async FetchContent(Data) {
            this.Progress = 0; // 重置進度
            const { index, title, url, text } = Data; // 解構數據

            // 解析處理的數據
            if (IsNeko) {

            } else {
                /* ----- 這邊是主頁的數據 ----- */
                const Json = JSON.parse(text);

                if (Json) {

                    // 首次生成元數據
                    if (Object.keys(this.MetaDict).length === 0) {
                        const props = Json.props;
                        this.FinalPages = Math.ceil(+props.count / 50); // 計算最終頁數
                        this.MetaDict = {
                            [Lang.Transl("作者")]: props.name,
                            [Lang.Transl("帖子數量")]: props.count,
                            [Lang.Transl("建立時間")]: Syn.GetDate("{year}-{month}-{date} {hour}:{minute}"),
                            [Lang.Transl("獲取頁面")]: this.SourceURL,
                            [Lang.Transl("作者網站")]: props.display_data.href
                        };
                    }


                    const Results = Json.results;

                    /* ----- 進階抓取數據 ----- */
                    if (this.AdvancedFetch) {
                        const Tasks = [];
                        const resolvers = new Map(); // 用於存儲每個 Promise

                        this.Worker.onmessage = async (e) => {
                            const { index, title, url, text, error } = e.data;

                            if (resolvers.has(index)) {
                                const { resolve, reject } = resolvers.get(index);

                                try {
                                    if (!error) {
                                        const Json = JSON.parse(text);

                                        if (Json) {
                                            const Post = Json.post;

                                            // 對下載連結進行分類
                                            const File = this.AdvancedCategorize(Json.attachments);

                                            // 獲取圖片連結
                                            const ImgLink = () => {//! 還需要測試
                                                const ServerList = Json.previews.filter(item => item.server); // 取得圖片伺服器
                                                if ((ServerList?.length ?? 0) === 0) return;

                                                // 為了穩定性這樣寫
                                                const List = [
                                                    ...(Post.file ? (Array.isArray(Post.file) ? Post.file : Object.keys(Post.file).length ? [Post.file] : []) : []),
                                                    ...Post.attachments
                                                ];
                                                const Fill = Syn.GetFill(ServerList.length);

                                                // 依據篩選出有預覽圖伺服器的, 生成圖片連結
                                                return ServerList.reduce((acc, Server, Index) => {
                                                    const name = `${Post.title}_${Syn.Mantissa(Index, Fill, '0', List[Index].name)}`;
                                                    acc[name] = `${Server.server}/data${List[Index].path}?f=${name}`;
                                                    return acc;
                                                }, {});                                                
                                            };

                                            // 生成請求數據 (處理要抓什麼數據)
                                            const Gen = this.FetchGenerate({
                                                PostLink: `${this.FirstURL}/post/${Post.id}`,
                                                Timestamp: new Date(Post.added)?.toLocaleString(),
                                                TypeTag: Post.tags,
                                                ImgLink: ImgLink(),
                                                VideoLink: File.video,
                                                DownloadLink: File.other,
                                                CloudLink: this.specialLinkParse(Post.content)
                                            });

                                            // 儲存數據
                                            if (Object.keys(Gen).length !== 0) {
                                                this.TaskDict.set(index, { title: Post.title, content: Gen });
                                            };

                                            resolve();
                                            document.title = `（${this.Pages} - ${++this.Progress}）`;
                                            Syn.Log("Request Successful", this.TaskDict, { dev: Config.Dev, collapsed: false });
                                        } else throw new Error("Json Parse Failed");
                                    } else {
                                        throw new Error("Request Failed");
                                    }
                                } catch (error) {
                                    Syn.Log(error, { title: title, url: url }, { dev: Config.Dev, type: "error", collapsed: false });
                                    await this.TooMany_TryAgain(url); // 錯誤等待
                                    this.Worker.postMessage({ index: index, title: title, url: url });
                                }

                                await Syn.Sleep(50);
                            }
                        };

                        // 生成任務
                        for (const [Index, Post] of Results.entries()) {
                            Tasks.push(new Promise((resolve, reject) => {
                                resolvers.set(Index, { resolve, reject }); // 存儲解析器
                                this.Worker.postMessage({ index: Index, title: Post.title, url: `${this.PostAPI}/${Post.id}` });
                            }));
                        }

                        // 等待所有任務
                        await Promise.allSettled(Tasks);

                    } else {
                        for (const [Index, Post] of Results.entries()) {
                            const title = Post.title.trim();

                            try {
                                // 分類所有文件
                                const File = this.Categorize(title, [...(Post.file ? (Array.isArray(Post.file) ? Post.file : Object.keys(Post.file).length ? [Post.file] : []) : []), ...Post.attachments]);

                                const Gen = this.FetchGenerate({
                                    PostLink: `${this.FirstURL}/post/${Post.id}`,
                                    Timestamp: new Date(Post.published)?.toLocaleString(),
                                    ImgLink: File.img,
                                    VideoLink: File.video,
                                    DownloadLink: File.other
                                });

                                if (Object.keys(Gen).length !== 0) {
                                    this.TaskDict.set(Index, { title: title, content: Gen });
                                };

                                document.title = `（${this.Pages} - ${++this.Progress}）`;
                                Syn.Log("Parsed Successful", this.TaskDict, { dev: Config.Dev, collapsed: false });
                            } catch (error) {
                                Syn.Log(error, { title: title, url: url }, { dev: Config.Dev, type: "error", collapsed: false });
                                continue;
                            }
                        }
                    }

                    // 將數據依序取出轉存
                    for (const data of this.TaskDict.values()) {
                        this.DataDict[data.title] = data.content;
                    }

                    this.TaskDict.clear(); // 清空任務數據
                    return true; // 回傳完成
                } else { /* 之後在想 */ }
            }
        };

        /* ===== 輸出生成 ===== */

        async ToJson() {
            // 合併數據
            const Json_data = Object.assign(
                {},
                { [Lang.Transl("元數據")]: this.MetaDict },
                { [`${Lang.Transl("帖子內容")} (${Object.keys(this.DataDict).length})`]: this.DataDict }
            );

            Syn.OutputJson(Json_data, this.MetaDict[Lang.Transl("作者")], () => {
                // 狀態恢復
                lock = false;
                this.Worker.terminate();
                document.title = this.TitleCache;
            });
        };

    }

    (new class Main {
        constructor() {
            this.URL = Syn.Device.Url;
            this.Page = {
                Content: /^(https?:\/\/)?(www\.)?.+\/.+\/user\/.+\/post\/.+$/.test(this.URL),
                Preview: /^(https?:\/\/)?(www\.)?.+\/posts\/?(\?.*)?$/.test(this.URL)
                    || /^(https?:\/\/)?(www\.)?.+\/.+\/user\/[^\/]+(\?.*)?$/.test(this.URL)
                    || /^(https?:\/\/)?(www\.)?.+\/dms\/?(\?.*)?$/.test(this.URL)
            }

            this.AddStyle = async () => {
                Syn.AddStyle(`
                    ${GM_getResourceText("font-awesome")}
                    .File_Span {
                        padding: 1rem;
                        font-size: 20% !important;
                    }
                    .Setting_Button {
                        cursor: pointer;
                    }
                    .Download_Button {
                        color: hsl(0, 0%, 45%);
                        padding: 6px;
                        margin: 10px;
                        border-radius: 8px;
                        border: 2px solid rgba(59, 62, 68, 0.7);
                        background-color: rgba(29, 31, 32, 0.8);
                        font-family: Arial, sans-serif;
                    }
                    .Download_Button:hover {
                        color: hsl(0, 0%, 95%);
                        background-color: hsl(0, 0%, 45%);
                        font-family: Arial, sans-serif;
                    }
                    .Download_Button:disabled {
                        color: hsl(0, 0%, 95%);
                        background-color: hsl(0, 0%, 45%);
                        cursor: Synault;
                    }
                `, "Download-button-style", false);
            }

            // 下載模式 native, disabled, browser
            GM_info.downloadMode = "browser";
            GM_info.isIncognito = true;
        }

        /* 按鈕創建 */
        async ButtonCreation() {
            Syn.$$("section").setAttribute("Download-Button-Created", true); this.AddStyle();
            let Button, Files;
            const IntervalFind = setInterval(() => {
                Files = Syn.$$(IsNeko ? "div.scrape__body h2" : "div.post__body h2", { all: true });

                if (Files.length > 0) {
                    clearInterval(IntervalFind);

                    try {
                        const CompressMode = Syn.Storage("Compression", { type: localStorage, error: true });
                        const ModeDisplay = CompressMode ? Lang.Transl("壓縮下載") : Lang.Transl("單圖下載");

                        // 創建 Span (找到含有 Files 文本的對象)
                        Files = Array.from(Files).filter(file => file.textContent.trim() == "Files");
                        if (Files.length == 0) {
                            return;
                        }

                        const spanElement = GM_addElement(Files[0], "span", { class: "File_Span", id: "ExDB" });
                        // 創建 Svg
                        const setting = GM_addElement(spanElement, "svg", { class: "Setting_Button" });
                        setting.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" height="1.3rem" viewBox="0 0 512 512"><style>svg {fill: hsl(0, 0%, 45%);}</style>
                        <path d="M495.9 166.6c3.2 8.7 .5 18.4-6.4 24.6l-43.3 39.4c1.1 8.3 1.7 16.8 1.7 25.4s-.6 17.1-1.7 25.4l43.3 39.4c6.9 6.2 9.6 15.9 6.4 24.6c-4.4 11.9-9.7 23.3-15.8 34.3l-4.7 8.1c-6.6 11-14 21.4-22.1 31.2c-5.9 7.2-15.7 9.6-24.5 6.8l-55.7-17.7c-13.4 10.3-28.2 18.9-44 25.4l-12.5 57.1c-2 9.1-9 16.3-18.2 17.8c-13.8 2.3-28 3.5-42.5 3.5s-28.7-1.2-42.5-3.5c-9.2-1.5-16.2-8.7-18.2-17.8l-12.5-57.1c-15.8-6.5-30.6-15.1-44-25.4L83.1 425.9c-8.8 2.8-18.6 .3-24.5-6.8c-8.1-9.8-15.5-20.2-22.1-31.2l-4.7-8.1c-6.1-11-11.4-22.4-15.8-34.3c-3.2-8.7-.5-18.4 6.4-24.6l43.3-39.4C64.6 273.1 64 264.6 64 256s.6-17.1 1.7-25.4L22.4 191.2c-6.9-6.2-9.6-15.9-6.4-24.6c4.4-11.9 9.7-23.3 15.8-34.3l4.7-8.1c6.6-11 14-21.4 22.1-31.2c5.9-7.2 15.7-9.6 24.5-6.8l55.7 17.7c13.4-10.3 28.2-18.9 44-25.4l12.5-57.1c2-9.1 9-16.3 18.2-17.8C227.3 1.2 241.5 0 256 0s28.7 1.2 42.5 3.5c9.2 1.5 16.2 8.7 18.2 17.8l12.5 57.1c15.8 6.5 30.6 15.1 44 25.4l55.7-17.7c8.8-2.8 18.6-.3 24.5 6.8c8.1 9.8 15.5 20.2 22.1 31.2l4.7 8.1c6.1 11 11.4 22.4 15.8 34.3zM256 336a80 80 0 1 0 0-160 80 80 0 1 0 0 160z"/></svg>`
                        Syn.Listen(setting, "click", () => { alert("Currently Invalid") }, { capture: true, passive: true });
                        // 創建 Button
                        Button = GM_addElement(spanElement, "button", {
                            class: "Download_Button",
                            textContent: lock ? Lang.Transl("下載中鎖定") : ModeDisplay
                        });
                        Button.disabled = lock;
                        Syn.Listen(Button, "click", () => {
                            let Instantiate = null;
                            Instantiate = new Download(CompressMode, ModeDisplay, Button);
                            Instantiate.DownloadTrigger();
                        }, { capture: true, passive: true });
                    } catch {
                        Button.disabled = true;
                        Button.textContent = Lang.Transl("無法下載");
                    }
                }
            });
        }

        /* 一鍵開啟當前所有帖子 */
        async OpenAllPages() {
            const card = Syn.$$("article.post-card a", { all: true });
            if (card.length == 0) { throw new Error("No links found") }

            let scope = prompt(`(${Lang.Transl("當前帖子數")}: ${card.length})${Lang.Transl("開帖說明")}`);

            if (scope != null) {
                scope = scope == "" ? "1-50" : scope;
                for (const link of Syn.ScopeParsing(scope, card)) {
                    GM_openInTab(link.href, {
                        insert: false,
                        setParent: false
                    });
                    await Syn.Sleep(Config.BatchOpenDelay);
                }
            }
        }

        /* 下載模式切換 */
        async DownloadModeSwitch() {
            Syn.Storage("Compression", { type: localStorage, error: true })
                ? Syn.Storage("Compression", { type: localStorage, value: false })
                : Syn.Storage("Compression", { type: localStorage, value: true });
            Syn.$$("#ExDB").remove();
            this.ButtonCreation();
        }

        /* 注入檢測創建 [ 檢測頁面創建按鈕, 創建菜單 ] */
        async Injection() {
            Syn.Observer(document, () => {
                try {
                    (this.Page.Content && !Syn.$$("section").hasAttribute("Download-Button-Created")) && this.ButtonCreation();
                } catch { }
            }, { throttle: 300 });

            if (this.Page.Content) {
                Syn.Menu({
                    [Lang.Transl("🔁 切換下載模式")]: { func: () => this.DownloadModeSwitch(), close: false, hotkey: "c" }
                });

            } else if (this.Page.Preview) {
                Syn.Menu({
                    [Lang.Transl("📑 獲取 Json 數據")]: {
                        func: () => {
                            if (!lock) {
                                let Instantiate = null;
                                Instantiate = new FetchData(FetchSet.AdvancedFetch);
                                FetchSet.UseFormat && Instantiate.FetchConfig(FetchSet.Mode, FetchSet.Format);
                                Instantiate.FetchInit();
                            }
                        }
                    },
                    [Lang.Transl("📃 開啟當前頁面帖子")]: { func: () => this.OpenAllPages() }
                });
            }
        }
    }).Injection();

    function Language(lang) {
        const Word = {
            Traditional: {
                "開帖說明": "\n\n!! 不輸入直接確認, 將會開啟當前頁面所有帖子\n輸入開啟範圍(說明) =>\n單個: 1, 2, 3\n範圍: 1~5, 6-10\n排除: !5, -10"
            },
            Simplified: {
                "🔁 切換下載模式": "🔁 切换下载模式",
                "📑 獲取 Json 數據": "📑 获取 Json 数据",
                "📃 開啟當前頁面帖子": "📃 打开当前页面帖子",
                "📥 強制壓縮下載": "📥 强制压缩下载",
                "⛔️ 終止下載": "⛔️ 终止下载",
                "壓縮下載模式": "压缩下载模式",
                "單圖下載模式": "单图下载模式",
                "壓縮下載": "压缩下载",
                "單圖下載": "单图下载",
                "開始下載": "开始下载",
                "無法下載": "无法下载",
                "下載進度": "下载进度",
                "封裝進度": "打包进度",
                "壓縮封裝失敗": "压缩打包失败",
                "下載完成": "下载完成",
                "請求進度": "请求进度",
                "下載中鎖定": "下载中锁定",
                "原始連結": "原始链接",
                "圖片數量": "图片数量",
                "影片數量": "视频数量",
                "下載連結": "下载链接",
                "作者": "作者",
                "時間": "时间",
                "來源": "来源",
                "未取得數據": "未取得数据",
                "模式切換": "模式切换",
                "數據處理中": "数据处理中",
                "當前處理頁數": "当前处理页数",
                "數據處理完成": "数据处理完成",
                "Json 數據下載": "Json 数据下载",
                "當前帖子數": "当前帖子数",
                "開帖說明": "\n\n!! 不输入直接确认, 将会打开当前页面所有帖子\n输入开启范围(说明) =>\n单个: 1, 2, 3\n范围: 1~5, 6-10\n排除: !5, -10",
            },
            Japan: {
                "🔁 切換下載模式": "🔁 ダウンロードモードの切り替え",
                "📑 獲取 Json 數據": "📑 Json データの取得",
                "📃 開啟當前頁面帖子": "📃 現在のページの投稿を開く",
                "📥 強制壓縮下載": "📥 強制的に圧縮してダウンロード",
                "⛔️ 終止下載": "⛔️ ダウンロードを中止",
                "壓縮下載模式": "圧縮ダウンロードモード",
                "單圖下載模式": "単一画像ダウンロードモード",
                "壓縮下載": "圧縮ダウンロード",
                "單圖下載": "単一画像ダウンロード",
                "開始下載": "ダウンロードを開始",
                "無法下載": "ダウンロードできません",
                "下載進度": "ダウンロードの進行状況",
                "封裝進度": "パッケージングの進行状況",
                "壓縮封裝失敗": "圧縮パッケージングに失敗しました",
                "下載完成": "ダウンロードが完了しました",
                "請求進度": "リクエストの進行状況",
                "下載中鎖定": "ダウンロード中にロック",
                "原始連結": "元のリンク",
                "圖片數量": "画像の数",
                "影片數量": "動画の数",
                "下載連結": "ダウンロードリンク",
                "作者": "著者",
                "時間": "時間",
                "來源": "ソース",
                "未取得數據": "データを取得できませんでした",
                "模式切換": "モードの切り替え",
                "數據處理中": "データ処理中",
                "當前處理頁數": "現在処理中のページ数",
                "數據處理完成": "データ処理が完了しました",
                "Json 數據下載": "Json データのダウンロード",
                "當前帖子數": "現在の投稿数",
                "開帖說明": "\n\n!! 直接確認を入力しないと、現在のページのすべての投稿が開きます\n開始範囲を入力してください (説明) =>\n単一: 1, 2, 3\n範囲: 1~5, 6-10\n除外: !5, -10",
            },
            English: {
                "🔁 切換下載模式": "🔁 Switch Download Mode",
                "📑 獲取 Json 數據": "📑 Get Json Data",
                "📃 開啟當前頁面帖子": "📃 Open Current Page Post",
                "📥 強制壓縮下載": "📥 Force Compress Download",
                "⛔️ 終止下載": "⛔️ Terminate download",
                "壓縮下載模式": "Compress Download Mode",
                "單圖下載模式": "Single Image Download Mode",
                "壓縮下載": "Compress Download",
                "單圖下載": "Single Image Download",
                "開始下載": "Start Download",
                "無法下載": "Unable to Download",
                "下載進度": "Download Progress",
                "封裝進度": "Packaging Progress",
                "壓縮封裝失敗": "Compress Packaging Failed",
                "下載完成": "Download Complete",
                "請求進度": "Request Progress",
                "下載中鎖定": "Download Locked",
                "原始連結": "Original Link",
                "圖片數量": "Image Count",
                "影片數量": "Video Count",
                "下載連結": "Download Link",
                "作者": "Author",
                "時間": "Time",
                "來源": "Source",
                "未取得數據": "No Data",
                "模式切換": "Mode Switch",
                "數據處理中": "Data Processing",
                "當前處理頁數": "Current Processing Page",
                "數據處理完成": "Data Processing Complete",
                "Json 數據下載": "Json Data Download",
                "當前帖子數": "Current Post Count",
                "開帖說明": "\n\n!! If you do not enter a direct confirmation, all posts on the current page will be opened\nEnter the start range (說明) =>\nSingle: 1, 2, 3\nRange: 1~5, 6-10\nExclude: !5, -10",
            }
        }, Match = {
            "zh-TW": Word.Traditional,
            "zh-HK": Word.Traditional,
            "zh-MO": Word.Traditional,
            "zh-CN": Word.Simplified,
            "zh-SG": Word.Simplified,
            "en-US": Word.English,
            ja: Word.Japan
        }, ML = Match[lang] ?? Match["en-US"];

        return {
            Transl: (Str) => ML[Str] ?? Str,
        };
    }
})();