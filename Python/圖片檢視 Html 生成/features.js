class Additional_Features {
    constructor() {
        this.seeImg = null;
        this.setWidth = null;
        this.title = document.title;
        this.rules = document.querySelector("style").sheet.cssRules[1];
        this.currentWidth = () => parseInt(this.rules.style.maxWidth);
    }

    initView() {
        const record = localStorage.getItem(`${this.title}-View`);

        if (record) {
            const recordObj = JSON.parse(record);

            this.rules.style.maxWidth = recordObj.width;
            this.setWidth = recordObj.width;

            const id = recordObj.id;
            let img = document.getElementById(id);

            if (!img) {
                const idObj = id.match(/\\d+/);
                const images = new Map([...document.querySelectorAll("img")].map(img => [img.id, img]));

                let count = 1;
                while (count <= images.size) {
                    img = images.get(`Img_${+idObj[0] + count}`);
                    if (img) break;
                    count++;
                }
            }

            img && img.scrollIntoView({
                block: "start",
                behavior: "smooth"
            })
        }

        this.widthModify();
    }

    focusImg() {
        const observer = new IntersectionObserver(observed => {
            observed.forEach(entry => {
                if (entry.isIntersecting) {
                    this.seeImg = entry.target;

                    localStorage.setItem(`${this.title}-View`, JSON.stringify({
                        id: this.seeImg.id,
                        width: this.setWidth
                    }));
                };
            });
        }, { threshold: 0.4 });

        document.querySelectorAll("img").forEach(img => observer.observe(img));
    }

    widthModify() {
        this.setWidth = `${this.currentWidth()}%`;

        document.addEventListener("keydown", event => {
            const key = event.key;
            if (key == "+" || key == "-") {

                requestAnimationFrame(() => {
                    this.setWidth = key == "+"
                        ? `${Math.min(this.currentWidth() + 3, 100)}%`
                        : `${Math.max(this.currentWidth() - 3, 1)}%`;

                    this.rules.style.maxWidth = this.setWidth;

                    if (this.seeImg) {
                        this.seeImg.scrollIntoView({
                            block: "nearest"
                        });
                    }
                })
            }
        })

        this.focusImg();
    }
}

async function errorRemove(img) {
    img.remove();
}

window.addEventListener("load", () => {
    const features = new Additional_Features();
    features.initView();
});