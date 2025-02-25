// ==UserScript==
// @name         Hanime1 簡單優化
// @version      0.0.1-Bate
// @author       Canaan HS
// @description  Hanime1 電腦版觀影體驗優化, 移除礙眼的中心圖示, 媒體暫停時也可自動隱藏控製器和遊標, 手動觸發建立快照預覽圖, 懸浮於進度條上方顯示畫面預覽

// @noframes
// @match        *://hanime1.me/watch?v=*

// @license      MPL-2.0
// @namespace    https://greasyfork.org/users/989635
// @icon         data:image/png;base64,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

// @run-at       document-start
// @grant        GM_registerMenuCommand
// @grant        GM_unregisterMenuCommand
// ==/UserScript==

(async () => {

    const Syn = (() => {
        const
            Mark = {},
            Type = (object) => Object.prototype.toString.call(object).slice(8, -1),
            Query = {
                Match: (Str) => /[ .#=:]/.test(Str),
                "#": (source, select) => source.getElementById(select.slice(1)),
                ".": (source, select, all) => {
                    const query = source.getElementsByClassName(select.slice(1));
                    return all ? [...query] : query[0];
                },
                "tag": (source, select, all) => {
                    const query = source.getElementsByTagName(select);
                    return all ? [...query] : query[0];
                },
                "default": (source, select, all) => {
                    return all ? source.querySelectorAll(select) : source.querySelector(select);
                }
            },
            WaitCore = {
                Options: {
                    raf: false,
                    all: false,
                    timeout: 8,
                    throttle: 50,
                    subtree: true,
                    childList: true,
                    attributes: false,
                    characterData: false,
                    timeoutResult: false,
                    root: document,
                },
                queryMap: (selector) => {
                    const result = selector.map(select => document.querySelector(select));
                    return result.every(Boolean) && result;
                },
                queryElement: (selector, all) => {
                    const result = all ? document.querySelectorAll(selector) : document.querySelector(selector);
                    return (all ? result.length > 0 : result) && result;
                }
            };

        return {
            Type,
            Device: {
                sX: () => window.scrollX,
                sY: () => window.scrollY,
                iW: () => window.innerWidth,
                iH: () => window.innerHeight,
                _Type: undefined,
                Url: location.href,
                Orig: location.origin,
                Host: location.hostname,
                Path: location.pathname,
                Lang: navigator.language,
                Agen: navigator.userAgent,
                Type: function () {
                    return this._Type = this._Type ? this._Type
                        : (this._Type = /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(this.Agen) || this.iW < 768
                            ? "Mobile" : "Desktop");
                }
            },
            $$: (selector, {
                all = false,
                root = document
            } = {}) => {
                const type = !Query.Match(selector)
                    ? "tag" : Query.Match(selector.slice(1))
                        ? "default" : selector[0];
                return Query[type](root, selector, all);
            },
            AddStyle: async (Rule, ID = "New-Style", RepeatAdd = true) => {
                let style = document.getElementById(ID);
                if (!style) {
                    style = document.createElement("style");
                    style.id = ID;
                    document.head.appendChild(style);
                } else if (!RepeatAdd) return;
                style.textContent += Rule;
            },
            Listen: async (
                element,
                type,
                listener,
                add = {},
                resolve = null
            ) => {
                try {
                    element.addEventListener(type, listener, add);
                    resolve && resolve(true);
                } catch { resolve && resolve(false) }
            },
            Observer: async function (object, trigger, {
                mark = true,
                throttle = 100,
                subtree = false,
                childList = false,
                attributes = true,
                characterData = true,
            } = {},
                callback = null
            ) {
                if (mark) {
                    if (Mark[mark]) { return }
                    else { Mark[mark] = true }
                }
                const op = {
                    subtree: subtree,
                    childList: childList,
                    attributes: attributes,
                    characterData: characterData
                }, ob = new MutationObserver(this.Throttle(() => { trigger() }, throttle));
                ob.observe(object, op);
                callback && callback({ ob, op });
            },
            WaitElem: async function (selector, found = null, options = {}) {
                const self = this;
                const Query = typeof selector === "object" ? WaitCore.queryMap : WaitCore.queryElement; //! 為了性能不做精確檢查 (傳遞錯誤類型就會壞掉)
                const {
                    raf, all, root, timeout, throttle,
                    subtree, childList, attributes, characterData, timeoutResult
                } = Object.assign({}, WaitCore.Options, options);

                return new Promise((resolve, reject) => {

                    const Core = async function () {
                        let timer, result;

                        if (raf) {
                            let AnimationFrame;

                            const query = () => {
                                result = Query(selector, all);

                                if (result) {
                                    cancelAnimationFrame(AnimationFrame);
                                    clearTimeout(timer);

                                    found && found(result);
                                    resolve(result);
                                } else {
                                    AnimationFrame = requestAnimationFrame(query);
                                }
                            };

                            AnimationFrame = requestAnimationFrame(query);

                            timer = setTimeout(() => {
                                cancelAnimationFrame(AnimationFrame);

                                if (timeoutResult) {
                                    found && found(result);
                                    resolve(result);
                                }
                            }, (1000 * timeout));

                        } else {
                            const observer = new MutationObserver(self.Throttle(() => {
                                result = Query(selector, all);

                                if (result) {
                                    observer.disconnect();
                                    clearTimeout(timer);

                                    found && found(result);
                                    resolve(result);
                                }
                            }, throttle));

                            observer.observe(root, {
                                subtree: subtree,
                                childList: childList,
                                attributes: attributes,
                                characterData: characterData
                            });

                            timer = setTimeout(() => {
                                observer.disconnect();
                                if (timeoutResult) {
                                    found && found(result);
                                    resolve(result);
                                }
                            }, (1000 * timeout));
                        }
                    };

                    if (document.visibilityState === "hidden") {
                        document.addEventListener("visibilitychange", () => Core(), { once: true });
                    } else Core();
                });
            },
            Throttle: (func, delay) => {
                let lastTime = 0;
                return (...args) => {
                    const now = Date.now();
                    if ((now - lastTime) >= delay) {
                        lastTime = now;
                        func(...args);
                    }
                }
            }
        }
    })();

    if (Syn.Device.Type() === "Mobile") return;

    Syn.WaitElem([
        "#player", // 影片元素
        ".plyr--video", // 影片區塊
        ".plyr__tooltip", // 進度提示器
        "input[data-plyr='seek']" // 進度條
    ], null, { raf: true }).then(found => {
        const [video, container, tip, progress] = found;

        // 隱藏暫停時圖示
        Syn.AddStyle(`
            body {
                cursor: default;
            }
            .Snapshot {
                top: -170px;
                left: 0;
                width: 256px;
                height: 144px;
                position: absolute;
            }
            .plyr--full-ui.plyr--video .plyr__control--overlaid {
                display: none !important;
            }
        `, "Hanime1-Optimize");

        let onTarget, mouseHide;
        const containerClass = container.classList;
        const styalRule = Syn.$$("#Hanime1-Optimize").sheet.cssRules;

        async function Optimize_Video_Control() {
            const Switch = async (params) => {
                styalRule[0].style.setProperty("cursor", params, "important");
            };

            async function Trigger() {
                /* 移動時 */
                Switch("default"); // 恢復滑鼠
                clearTimeout(mouseHide); // 清除計時器
                containerClass.remove("plyr--hide-controls"); // 清除隱藏樣式

                /* 停止一段時間後 */
                mouseHide = setTimeout(() => {
                    if (!onTarget) return;

                    Switch("none"); // 隱藏滑鼠
                    containerClass.add("plyr--hide-controls"); // 恢復隱藏樣式
                }, 2e3);
            };

            // 開始播放時才觸發
            Syn.Listen(video, "play", () => {

                //! 第一個 pointermove 監聽器
                // 目標上移動
                Syn.Listen(container, "pointermove", Syn.Throttle(() => {
                    onTarget = true;
                    Trigger();
                }, 200), { passive: true });

                // 目標上點擊
                Syn.Listen(container, "pointerdown", () => {
                    onTarget && Trigger();
                }, { passive: true });

                // 鍵盤按下
                Syn.Listen(document, "keydown", Syn.Throttle(() => {
                    onTarget && Trigger();
                }, 1e3), { capture: true, passive: true });

                // 離開目標
                Syn.Listen(container, "pointerleave", () => {
                    onTarget = false;
                    clearTimeout(mouseHide);
                }, { passive: true});

            }, { once: true });
        };

        async function Get_Preview_Snapshot() {
            const Menu = GM_registerMenuCommand("⏳ 加載預覽圖", () => {
                GM_unregisterMenuCommand(Menu); // 觸發後刪除菜單

                function timeStringToSeconds(timeString) {
                    const parts = timeString.split(':');

                    if (parts.length === 3) {
                        const hours = parseInt(parts[0], 10);
                        const minutes = parseInt(parts[1], 10);
                        const seconds = parseInt(parts[2], 10);
                        return hours * 3600 + minutes * 60 + seconds;
                    } else if (parts.length === 2) {
                        const minutes = parseInt(parts[0], 10);
                        const seconds = parseInt(parts[1], 10);
                        return minutes * 60 + seconds;
                    } else if (parts.length === 1) {
                        return parseInt(parts[0], 10);
                    }

                    return 0; // 如果格式不符合，則返回 0
                };

                // 保存所有的快照
                const snapshotObject = {};

                // 設定快照的尺寸
                const snapshotHeight = 144;
                const snapshotWidth = 256;

                // 創建畫布並獲取上下文
                const canvas = document.createElement("canvas");
                const ctx = canvas.getContext("2d");

                // 取得影片的總長度
                const totalTime = parseFloat(progress.getAttribute("aria-valuemax"));

                // 抓取處理
                const captureSnapshot = () => {
                    const currentTime = video.currentTime;

                    if (currentTime >= totalTime) {
                        video.currentTime = 0;
                        return;
                    };

                    canvas.width = snapshotWidth;
                    canvas.height = snapshotHeight;
                    ctx.drawImage(video, 0, 0, canvas.width, canvas.height);

                    canvas.toBlob(blob => {
                        if (blob) {
                            const webpURL = URL.createObjectURL(blob);
                            if (webpURL) {
                                snapshotObject[currentTime] = webpURL;
                                video.currentTime = currentTime + 1; // 時間跳轉

                                Syn.Listen(video, "seeked", () => {
                                    requestAnimationFrame(captureSnapshot); // 繼續擷取
                                }, { once: true });

                                return;
                            }
                        }

                        requestAnimationFrame(captureSnapshot);
                    }, "image/webp");
                };

                // 開始擷取
                requestAnimationFrame(captureSnapshot);

                //! 第二個 pointermove 監聽器
                // 動態修正, 根據進度條位置顯示快照
                Syn.Listen(progress, "pointermove", (event) => {
                    const mouseX = event.offsetX;
                    const left = mouseX - 128; // 減圖片一半寬度, 使其居中
                    styalRule[1].style.left = `${left}px`;
                }, { passive: true });

                // 滑鼠離開時移除圖片
                Syn.Listen(progress, "mouseleave", () => {
                    Syn.$$(".Snapshot")?.remove();  // 移除舊圖片
                }, { capture: true, passive: true });

                // 快照顯示
                const parent = tip.parentNode;
                Syn.Observer(tip, () => {
                    Syn.$$(".Snapshot")?.remove();  // 移除舊圖片

                    // 獲取指示器的時間, 並獲取對應的快照
                    const index = timeStringToSeconds(tip.textContent);
                    const selectedSnapshot = snapshotObject[index];

                    if (!selectedSnapshot) return;

                    const img = document.createElement("img");
                    img.className = "Snapshot";
                    img.src = selectedSnapshot;  // 設置圖片源

                    parent.insertBefore( // 插入圖片
                        img,
                        progress
                    );
                });
            });
        };

        Optimize_Video_Control();
        Get_Preview_Snapshot();

    });

})();