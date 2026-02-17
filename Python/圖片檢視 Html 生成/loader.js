class Loader {
    constructor() {
        this.indicator = document.getElementById("picture_indicator");
        this.container = document.getElementById("picture_container");
    }

    compileImgData() {
        const imagesPath = [];
        for (const [key, value] of Object.entries(img_data)) {
            for (const [item_key, item_data] of Object.entries(value)) {
                for (const img of item_data) {
                    imagesPath.push(`${key}${item_key}${img}`);
                }
            }
        }
        return imagesPath;
    };

    loadImage(dataBox) {
        const fragment = document.createDocumentFragment();

        let count = 0;
        for (const [index, path] of dataBox.entries()) {
            const img = document.createElement("img");

            img.src = path;
            img.setAttribute("data-index", index);
            img.onerror = () => { img.remove() };

            fragment.appendChild(img);
            count++;

            if (count >= 50) {
                this.container.appendChild(fragment);
                count = 0;
            }
        }
    };
};

const loader = new Loader();
const imagesData = loader.compileImgData();
loader.loadImage(imagesData);