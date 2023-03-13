/*
TODO - 重構 DataToJson 函數

IsNeko 的對象適用於舊邏輯, 其他不適用

*/

const IsNeko = Syn.Device.Host === "nekohouse.su";

class FetchData {
    constructor() {
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
        this.TaskCount = 50; // 預設抓取的任務數
        this.OnlyMode = false; // 判斷獲取數據的模式

        // 內部連結的 API 模板
        this.PostAPI = `${this.FirstURL}/post`.replace(this.Host, `${this.Host}/api/v1`);

        this.PreviewAPI = Url => // 將預覽頁面轉成 API 連結
            /[?&]o=/.test(Url)
              ? Url.replace(this.Host, `${this.Host}/api/v1`).replace(/([?&]o=)/, "/posts-legacy$1")
              : Url.replace(this.Host, `${this.Host}/api/v1`) + "/posts-legacy";

        // 影片類型
        this.Media = new Set([
            ".mp4", ".avi", ".mkv", ".mov", ".flv", ".wmv", ".webm", ".mpg", ".mpeg",
            ".m4v", ".ogv", ".3gp", ".asf", ".ts", ".vob", ".rm", ".rmvb", ".m2ts",
            ".divx", ".xvid", ".wm"
        ]);

        // 預設添加的數據
        this.InfoRules = {
            "PostLink": Lang.Transl("帖子連結"),
            "Timestamp": Lang.Transl("發佈日期"),
            "ImgNumber": Lang.Transl("圖片數量"),
            "TypeTag": Lang.Transl("類型標籤"),
            "VideoLink": Lang.Transl("影片連結"),
            "DownloadLink": Lang.Transl("下載連結")
        };

        /**
         * 生成數據 (傳入以下參數) [不驗證有效性]
         * @param {{
         *      PostLink: string,
         *      Timestamp: string,
         *      ImgNumber: number,
         *      TypeTag: string[],
         *      VideoLink: object,
         *      DownloadLink: object
         * }} Data
         * @returns {object}
         */
        this.FetchGenerate = (Data) => {
            return Object.keys(Data).reduce((acc, key) => {
                if (this.InfoRules.hasOwnProperty(key)) {
                    acc[this.InfoRules[key]] = Data[key] || "";
                }
                return acc;
            }, {});
        };

        // 解析 MEGA 連結
        this.MegaParse = (Data) => {
            const Cache = {};

            try {
                for (const p of Syn.$$("body p", {all: true, root: Syn.DomParse(Data)})) {
                    for (const a of Syn.$$("a", {all: true, root: p})) {
                        const href = a.href;

                        if (href.startsWith("https://mega.nz")) {

                            let name = a.previousElementSibling.textContent.replace(":", "").trim();
                            if (name === "") continue;

                            let pass = [...a.nextElementSibling.childNodes].filter(node => node.nodeType === Node.TEXT_NODE)?.[0].textContent ?? "";
                            if (pass.startsWith("Pass")) {
                                pass = pass.match(/Pass:([^<]*)/)[1].trim();
                            }

                            Cache[name] = {
                                [Lang.Transl("密碼")]: pass,
                                [Lang.Transl("連結")]: href
                            };
                        }
                    }
                }
            } catch {}

            return Cache;
        };

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
                    if (xhr.readyState === 4 && xhr.status === 200) {
                        postMessage({ index, title, url, text: xhr.response, error: false });
                    } else {
                        FetchRequest(index, title, url);
                    }
                }
                xhr.onerror = function() {
                    FetchRequest(index, title, url);
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
    }

    /**
     * 設置抓取規則
     * @param {string} Mode - "FilterMode" | "OnlyMode"
     * @param {Array} UserSet - 要進行的設置
     *
     * @example
     * 可配置項目: ["PostLink", "Timestamp", "ImgNumber", "TypeTag", "VideoLink", "DownloadLink"]
     *
     * 這會將這些項目移除在顯示
     * Config("FilterMode", ["PostLink", "ImgNumber", "DownloadLink"]);
     *
     * 這會只顯示這些項目
     * Config("OnlyMode", ["PostLink", "ImgNumber", "DownloadLink"]);
     */
    async Config(Mode = "FilterMode", UserSet = []) {
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
    }

    /* 入口調用函數 */
    async FetchInit() {
        const Section = Syn.$$("section");

        if (Section) {
            lock = true; // 鎖定菜單的操作, 避免重複抓取

            // 取得當前頁數
            for (const page of Syn.$$(".pagination-button-disabled b", {all: true})) {
                const number = Number(page.textContent);
                if (number) {
                    this.Pages = number;
                    break;
                }
            }

            this.FetchMonitor(); // 啟用監聽
            this.FetchRun(Section, this.SourceURL); // 啟用抓取
        } else {
            alert(Lang.Transl("未取得數據"));
        }
    }

    /* ===== 主要抓取函數 ===== */

    /* 運行抓取數據 */
    async FetchRun(Section, Url) {

        if (Config.NotiFication) {
            GM_notification({
                title: Lang.Transl("數據處理中"),
                text: `${Lang.Transl("當前處理頁數")} : ${this.Pages}`,
                image: GM_getResourceURL("json-processing"),
                timeout: 800
            });
        }

        if (IsNeko) {
            const Item = Syn.$$(".card-list__items article", {all: true, root: Section});

            // 下一頁連結
            const Menu = Syn.$$("a.pagination-button-after-current", {root: Section});

            if (Menu) {
                // Menu.href
            }
        } else {
            this.Worker.postMessage({ index: 0, title: this.TitleCache, url: this.PreviewAPI(Url) });

            // 目前只想的到這個爛方法
            const Wait = setInterval(()=> {
                // 等到數量相同, 做下一步操作
                if (this.TaskDict.size === this.TaskCount) {
                    clearInterval(Wait);

                    // 生成下一頁連結
                    Url = /\?o=\d+$/.test(Url)
                        ? Url.replace(/\?o=(\d+)$/, (match, number) => `?o=${+number + 50}`)
                        : `${Url}?o=50`;

                    for (let index = 0; index < this.TaskCount; index++) {
                        const data = this.TaskDict.get(index);
                        this.DataDict[data.title] = data.content;
                    }

                    this.Pages++;
                    this.TaskDict.clear(); // 清空任務數據
                    this.Pages <= this.FinalPages ? this.FetchRun(null, Url) : this.ToJson();
                }
            }, 500);
        }
    }

    /* 獲取帖子內部數據 */
    async FetchContent(Results) {
        this.Progress = 0; // 重置進度
        this.TaskCount = Results.length; // 更新任務數量

        for (const [index, page] of Results.entries()) {
            this.Worker.postMessage({ index: index, title: page.title, url: `${this.PostAPI}/${page.id}` });
            await Syn.Sleep(10);
        }
    }

    /* 監聽請求數據 */
    async FetchMonitor() {
        this.Worker.onmessage = async (e) => {
            const Cache_data = {}, { index, title, url, text, error } = e.data;

            try {
                // 沒有出錯
                if (!error) {
                    if (IsNeko) {
                        const DOM = Syn.DomParse(text);

                    } else {
                        const Json = JSON.parse(text);

                        if (Json) {
                            const Post = Json.post;

                            // 首次生成元數據
                            if (Object.keys(this.MetaDict).length === 0) {
                                const props = Json.props;

                                // 計算最終頁數
                                this.FinalPages = Math.ceil(+props.count / 50);

                                this.MetaDict = {
                                    [Lang.Transl("作者")]: props.name,
                                    [Lang.Transl("帖子數量")]: props.count,
                                    [Lang.Transl("建立時間")]: Syn.GetDate("{year}-{month}-{date} {hour}:{minute}"),
                                    [Lang.Transl("獲取頁面")]: this.SourceURL,
                                    [Lang.Transl("作者網站")]: props.display_data.href
                                };
                            }

                            if (Post) { // 是帖子內數據

                                // 對下載連結進行分類
                                const Categorized = Json.attachments.reduce((acc, file) => {
                                    const url = `${file.server}/data${file.path}?f=${file.name.replace(/\s/g, "+")}`;
                                    this.Media.has(file.extension) ? (acc.video[file.name] = url) : (acc.other[file.name] = url);
                                    return acc;
                                }, { video: {}, other: {} });

                                // 生成請求數據
                                const Gen = this.FetchGenerate({
                                    PostLink: `${this.FirstURL}/post/${Post.id}`,
                                    Timestamp: new Date(Post.added).toLocaleString(),
                                    ImgNumber: Json.previews.length,
                                    TypeTag: Post.tags,
                                    VideoLink: Categorized.video,
                                    DownloadLink: Object.assign({}, Categorized.other, this.MegaParse(Post.content))
                                });

                                // 儲存數據
                                if (Object.keys(Gen).length !== 0) {
                                    this.TaskDict.set(index, {title: Post.title, content: Gen});
                                }

                                document.title = `（${this.Pages} - ${++this.Progress}）`;
                            } else { // 不是的調用抓取
                                this.FetchContent(Json.results); // 獲取帖子內部數據
                            }

                        } else {
                            throw new Error("Json Parse Failed");
                        }
                    }
                } else { throw new Error("Request Failed") }
            } catch (error) {
                Syn.Log(error, {title: title, url: url}, {dev: Config.Dev, collapsed: false});
                await Syn.Sleep(3e3);
                this.Worker.postMessage({ index: index, title: title, url: url });
            }
        }

    }

    /* ===== 輸出生成 ===== */

    async ToJson () {
        // 合併數據
        const Json_data = Object.assign(
            {}, {[Lang.Transl("元數據")]:this.MetaDict}, {[Lang.Transl("帖子內容")]:this.DataDict}
        );

        Syn.OutputJson(Json_data, this.MetaDict[Lang.Transl("作者")], ()=> {
            if (Config.NotiFication) {
                GM_notification({
                    title: Lang.Transl("數據處理完成"),
                    text: Lang.Transl("Json 數據下載"),
                    image: GM_getResourceURL("json-processing"),
                    timeout: 2000
                });
            }

            // 狀態恢復
            lock = false;
            this.Worker.terminate();
            document.title = this.TitleCache;
        });
    }

}