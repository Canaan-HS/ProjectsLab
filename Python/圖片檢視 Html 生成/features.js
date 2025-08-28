class Features {
    constructor() {
        this.seeImg = null;
        this.setWidth = null;
        this.specifyIndex = null;
        this.title = document.title;

        this.buffer = 1;
        this.lastVisibleIndex = -1;
        this.record = localStorage.getItem(`${this.title}-view`);

        this.images = [...document.querySelectorAll("img")];
        this.indicator = document.getElementById("picture_indicator");
        this.rules = document.getElementsByTagName("style")[0].sheet.cssRules[1].style;

        this._currentWidth = () => parseInt(this.rules.maxWidth);
    }

    _debounce(func, delay) {
        let timer = null;
        return (...args) => {
            clearTimeout(timer);
            timer = setTimeout(function () {
                func(...args);
            }, delay);
        }
    };

    _focusImg() {
        const observer = new IntersectionObserver(this._debounce(observed => {
            observed.forEach(entry => {
                if (entry.isIntersecting) {

                    // ! 目前的寫法，無論是初始跳轉，還是手動跳轉，都無法直接顯示最後一張圖片，只能手動滾動

                    const currentIndex = this.images.indexOf(entry.target);

                    // 如果當前可見的圖片和上次一樣，就不做任何事
                    if (currentIndex === this.lastVisibleIndex) {
                        return;
                    }

                    const oldIndex = this.lastVisibleIndex;
                    this.lastVisibleIndex = currentIndex; // 更新當前索引

                    // 計算新的可見範圍
                    const newStart = Math.max(0, currentIndex - this.buffer);
                    const newEnd = Math.min(this.images.length - 1, currentIndex + this.buffer);

                    // 計算舊的可見範圍
                    const oldStart = Math.max(0, oldIndex - this.buffer);
                    const oldEnd = Math.min(this.images.length - 1, oldIndex + this.buffer);

                    // 顯示進入窗口的圖片
                    for (let i = newStart; i <= newEnd; i++) {
                        if ((i < oldStart || i > oldEnd) && this.images[i]) {
                            this.images[i].style.display = "block";
                        }
                    }

                    // 隱藏離開窗口的圖片
                    for (let i = oldStart; i <= oldEnd; i++) {
                        if ((i < newStart || i > newEnd) && this.images[i]) {
                            this.images[i].style.display = "none";
                        }
                    }

                    this.seeImg = entry.target;
                    let index = this.seeImg.getAttribute("data-index");

                    if (this.record) {
                        this.record = false;
                        // ? 有紀錄時 需要 -1 才是正確的
                        index = Math.max(index - 1, 1);
                    }

                    if (this.specifyIndex) {
                        index = this.specifyIndex;
                        // ? 目前寫法用指定值 - 1 才是正確的 (不修跳轉後 第一次觸發下一張圖片時將無法正常頁數)
                        this.lastVisibleIndex = index - 1;

                        this.specifyIndex = null;
                    }

                    this.indicator.textContent = `${index} / ${this.images.length}`;
                    localStorage.setItem(`${this.title}-view`, JSON.stringify({
                        index,
                        width: this.setWidth
                    }))
                }
            })
        }, 150), { threshold: 0.35 });

        this.images.forEach(img => observer.observe(img));
    };

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

    initView() {
        if (this.record) {
            const recordObj = JSON.parse(this.record);

            this.rules.maxWidth = recordObj.width;
            this.setWidth = recordObj.width;

            const index = Math.max(parseInt(recordObj.index), 1);
            let img = document.getElementById(`img-${index}`);

            if (!img) {
                const images = new Map(this.images.map(img => [img.id, img]));

                let count = 1;

                while (count <= images.size) {
                    if (index - count <= 0) break;

                    // 往回找到可用圖片
                    img = images.get(`img-${index - count}`);
                    if (img) break;

                    count++;
                }
            }

            if (!img) return;

            // ? 適應 _focusImg 的顯示，使用下一張會剛好是紀錄的
            const nextImg = img.nextElementSibling;
            if (index != 1 && nextImg) img = nextImg;

            img.style.display = "block";
            img.scrollIntoView({ block: "start" });
        } else {
            this.images[0].style.display = "block";
        }

        this.indicator.addEventListener("click", () => {
            const numberStr = prompt("輸入要跳轉的圖片編號: ");
            const numberInt = Math.round(Number(numberStr));

            if (!numberStr || !numberInt) return;

            let imgElement = null;
            if (numberInt >= 1 && numberInt < this.images.length) {
                imgElement = this.images[numberInt]; // 實際上獲取的是下一張，但 _focusImg 會剛好顯示原本的
            } else if (numberInt === this.images.length) {
                imgElement = this.images[numberInt - 1]; // 最後一張需要特別處理
            }

            if (!imgElement) {
                alert("錯誤的範圍");
                return;
            }

            // ! 直接跳尾頁會有一點問題
            // ? 臨時暴力解法，直接顯示 imgElement 後跳轉，中間的並沒有顯示，所以實際滾動距離只有一點
            // ? 再加上 _focusImg 就會將他拉回原本頁數 只跳 1~2 張左右，每次要操作 2 次才能正常跳轉，但先隱藏所有就能解決
            document.querySelectorAll("img[style='display: block;']").forEach(img => {
                img.style.display = "none";
            });

            this.specifyIndex = numberInt;
            imgElement.style.display = "block";
            imgElement.scrollIntoView({ block: "start" });
        });

        this._focusImg();
        this._widthModify();
    };
}

window.addEventListener("load", () => {
    const features = new Features();
    features.initView();
});