class Features {
    constructor() {
        this.title = document.title;

        this.container = document.getElementById("picture_container");
        this.images = [...this.container.querySelectorAll("img")];
        this.indicator = document.getElementById("picture_indicator");
        this.rules = document.getElementsByTagName("style")[0].sheet.cssRules[3].style;

        this.record = localStorage.getItem(`${this.title}-view`);

        this.setWidth = null;
        this.imageObserver = null;

        this.loadRange = 5;
        this.currentIndex = -1;
        this.totalImages = this.images.length;

        this._currentWidth = () => parseInt(this.rules.maxWidth);
    }

    _debounce(func, delay) {
        let timer = null;
        return (...args) => {
            clearTimeout(timer);
            timer = setTimeout(() => {
                func.apply(this, args);
            }, delay);
        };
    }

    _loadImage(index) {
        if (index >= 0 && index < this.images.length) {
            const img = this.images[index];
            if (img && !img.src) {
                img.src = img.dataset.src;
            }
        }
    }

    _unloadImage(index) {
        if (index >= 0 && index < this.images.length) {
            const img = this.images[index];
            if (img && img.src) {
                img.removeAttribute("src");
            }
        }
    }

    _updateIndicator() {
        this.indicator.textContent = `${this.currentIndex + 1} / ${this.totalImages}`;
    }

    _updateVisibleImages(newIndex, isJumping = false) {
        if (newIndex < 0 || newIndex >= this.images.length || newIndex === this.currentIndex) {
            return;
        }

        const oldIndex = this.currentIndex;
        const lowerBound = newIndex - this.loadRange;
        const upperBound = newIndex + this.loadRange;

        // 這種模式下，我們只加載目標範圍的圖片，絕不卸載任何圖片，以防止佈局變動。
        if (isJumping) {
            for (let i = lowerBound; i <= upperBound; i++) {
                this._loadImage(i);
            }
        }
        // 這是由 IntersectionObserver 觸發的正常模式，執行滑動窗口邏輯。
        else {
            // 首次加載也走這個邏輯
            if (oldIndex === -1) {
                for (let i = lowerBound; i <= upperBound; i++) {
                    this._loadImage(i);
                }
            } else {
                const oldLowerBound = oldIndex - this.loadRange;
                const oldUpperBound = oldIndex + this.loadRange;

                // 卸載離開窗口的舊圖片
                for (let i = oldLowerBound; i <= oldUpperBound; i++) {
                    if (i < lowerBound || i > upperBound) this._unloadImage(i);
                }
                // 加載進入窗口的新圖片
                for (let i = lowerBound; i <= upperBound; i++) {
                    if (i < oldLowerBound || i > oldUpperBound) this._loadImage(i);
                }
            }
        }

        this.currentIndex = newIndex;
        this._updateIndicator();

        // 只有在自然滾動時才頻繁保存，避免跳轉時不必要的寫入
        if (!isJumping) {
            localStorage.setItem(`${this.title}-view`, JSON.stringify({
                index: this.currentIndex + 1,
                width: this.setWidth || this.rules.maxWidth,
            }));
        }
    }

    _reconnectObserver() {
        this.imageObserver.disconnect();
        this.images.forEach(img => {
            if (img) this.imageObserver.observe(img);
        });
    }

    _setupObserver() {
        this.imageObserver = new IntersectionObserver(this._debounce(entries => {
            const intersectingEntry = entries.find(entry => entry.isIntersecting);
            if (intersectingEntry) {
                const newIndex = +intersectingEntry.target.dataset.index;
                this._updateVisibleImages(newIndex, false);
            }
        }, 150), {
            threshold: 0.35
        });
    }

    _scrollToIndex(index, behavior = 'auto') {
        const targetImage = this.images[index];
        if (!targetImage) return;

        // 1. [可選但推薦] 依然先斷開觀察者，作為雙重保險。
        if (this.imageObserver) {
            this.imageObserver.disconnect();
        }

        // 2. [關鍵] 以 "跳轉模式" 呼叫更新函式，只加載不卸載。
        this._updateVisibleImages(index, true);

        // 3. 執行滾動。因為沒有圖片被卸載，佈局是穩定的，滾動不會出錯。
        targetImage.scrollIntoView({
            block: "start",
            behavior: behavior
        });

        // 4. 等待滾動動畫結束後，重新連接觀察者，恢復正常偵測。
        setTimeout(() => {
            this._reconnectObserver();

            localStorage.setItem(`${this.title}-view`, JSON.stringify({
                index: this.currentIndex + 1,
                width: this.setWidth || this.rules.maxWidth,
            }));
        }, behavior === 'smooth' ? 800 : 100);
    }

    _widthModify() {
        this.setWidth = `${this._currentWidth()}%`;

        document.addEventListener("keydown", event => {
            const key = event.key;
            if (key == "+" || key == "-") {

                requestAnimationFrame(() => {
                    this.setWidth = key == "+"
                        ? `${Math.min(this._currentWidth() + 3, 100)}%`
                        : `${Math.max(this._currentWidth() - 3, 1)}%`;

                    this.rules.maxWidth = this.setWidth;

                    if (this.seeImg) {
                        this.seeImg.scrollIntoView({
                            block: "nearest"
                        });
                    }
                })
            }
        })
    };

    initOnerror() {
        this.container.addEventListener("error", (e) => {
            const brokenImg = e.target;
            if (brokenImg.tagName !== "IMG" || !brokenImg.src) return;

            const errorIndex = this.images.indexOf(brokenImg);
            if (errorIndex !== -1 && this.images[errorIndex] !== null) {
                console.error(`圖片加載失敗，已移除: ${brokenImg.dataset.src}`);

                this.imageObserver.unobserve(brokenImg);
                brokenImg.style.display = "none";

                this.images[errorIndex] = null;
                this.totalImages--;

                this._updateIndicator();
            }
        }, { capture: true });
    }

    initView() {
        let startIndex = 0;
        if (this.record) {
            try {
                const recordObj = JSON.parse(this.record);
                if (recordObj.width) {
                    this.rules.maxWidth = recordObj.width;
                    this.setWidth = recordObj.width;
                }
                if (recordObj.index) {
                    startIndex = Math.max(0, Math.min(parseInt(recordObj.index, 10), this.images.length - 1));
                }
            } catch (e) { console.error("解析 localStorage 紀錄失敗:", e); }
        }

        // 呼叫我們全新的、穩定的跳轉函式來進行初始化
        this._scrollToIndex(startIndex, 'auto');
        this._setupObserver();

        this.indicator.addEventListener("click", () => {
            const numberStr = prompt(`輸入要跳轉的圖片編號 (1 - ${this.images.length}):`);
            if (!numberStr) return;

            const targetIndex = Math.round(Number(numberStr)) - 1;
            if (targetIndex >= 0 && targetIndex < this.images.length && this.images[targetIndex]) {
                this._scrollToIndex(targetIndex, 'smooth');
            } else {
                alert("錯誤的範圍或該圖片已失效");
            }
        });

        this._widthModify();
    }
}

window.addEventListener("load", () => {
    const features = new Features();
    features.initOnerror();
    features.initView();
});