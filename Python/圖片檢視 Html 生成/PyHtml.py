import os

from pathlib import Path
from tkinter import filedialog

from jinja2 import Template

class ImageDataImport:
    def __init__(self):
        os.chdir(Path(__file__).parent.resolve())

    def Read_folder(self):
        folder_path = filedialog.askdirectory(title="選取文件夾")

        if folder_path:
            data_box = []
            folder = Path(folder_path)

            create_name = folder.name
            create_path = folder.parent

            for file in folder.iterdir():
                data_box.append(file.relative_to(create_path).as_posix())
            return create_path, create_name, data_box

class TemplateGeneration(ImageDataImport):
    def __init__(self):
        super().__init__()
        self.create_path = None
        self.create_name = None
        self.data_box = None
        self.template = None

    def Get_data(self):
        try:self.create_path, self.create_name, self.data_box = self.Read_folder()
        except:pass

    def Create_Template(self):
        template = """
        <!DOCTYPE html>
        <html>
            <head>
                <title>{{ title }}</title>
                <style>
                    body {
                        margin: 0;
                        padding: 0;
                        background: {{ bg }};
                    }
                    img {
                        width: 100%;
                        height: 100%;
                        max-width: 55%;
                        display: block;
                        margin: 0 auto;
                    }
                    #picture_container img:hover {
                        cursor: none;
                    }
                </style>
                <script>
                    async function ErrorRemove(Img) {
                        Img.remove();
                    }

                    class Additional_Features {
                        constructor() {
                            this.SeeImg = null;
                            this.SetWidth = null;
                            this.Title = document.title;

                            this.Rules = document.querySelector("style").sheet.cssRules[1];
                            this.currentWidth = () => parseInt(this.Rules.style.maxWidth);
                        }

                        async InitView() {
                            const Storage = localStorage.getItem(`${this.Title}-View`);

                            if (Storage) {
                                const Set = JSON.parse(Storage);

                                this.Rules.style.maxWidth = Set.Width;
                                this.SetWidth = Set.Width;

                                const Id = Set.Id;
                                let Img = document.getElementById(Id);

                                if (!Img) {
                                    const IdObj = Id.match(/\\d+/);
                                    const Images = new Map([...document.querySelectorAll("img")].map(img => [img.id, img]));

                                    let count = 1;
                                    while (count <= Images.size) {
                                        Img = Images.get(`Img_${+IdObj[0] + count}`);
                                        if (Img) break;
                                        count++;
                                    }
                                }

                                Img && Img.scrollIntoView({
                                    block: "start",
                                    behavior: "smooth"
                                })
                            }

                            this.WidthModify();
                        }

                        async FocusImg() {
                            const observer = new IntersectionObserver(observed => {
                                observed.forEach(entry => {
                                    if (entry.isIntersecting) {
                                        const img = entry.target;

                                        this.SeeImg = img;
                                        localStorage.setItem(`${this.Title}-View`, JSON.stringify({
                                            Id: img.id,
                                            Width: this.SetWidth
                                        }));
                                    };
                                });
                            }, { threshold: 0.4 });

                            document.querySelectorAll("img").forEach(img => observer.observe(img));
                        }

                        async WidthModify() {
                            this.SetWidth = `${this.currentWidth()}%`;

                            document.addEventListener("keydown", event=> {
                                const key = event.key;
                                if (key == "+" || key == "-") {
                                    const current = parseInt(this.Rules.style.maxWidth);

                                    requestAnimationFrame(()=> {
                                        this.SetWidth = key == "+"
                                            ? `${Math.min(this.currentWidth() + 3, 100)}%`
                                            : `${Math.max(this.currentWidth() - 3, 1)}%`;

                                        this.Rules.style.maxWidth = this.SetWidth;

                                        if (this.SeeImg) {
                                            this.SeeImg.scrollIntoView({
                                                block: "nearest"
                                            });
                                        }
                                    })
                                }
                            })

                            this.FocusImg();
                        }
                    }

                    window.addEventListener("load", () => {
                        const Features = new Additional_Features();
                        Features.InitView();
                    });
                </script>
            </head>
            <body>
                <div id = "picture_container">
                    {% for src in data %}
                    <img id="Img_{{ loop.index }}" src="{{ src|safe }}" onerror="ErrorRemove(this)">
                    {% endfor %}
                </div>
            </body>
        </html>
        """
        self.template = Template(template)

    def Generate_Save_HTML(self):
        self.Get_data()

        if self.create_path != None:
            # 創建模板
            self.Create_Template()

            # 傳遞創建模板參數
            html = self.template.render({
                "title": self.create_name,
                "bg": "rgb(110, 110, 110)",
                "data": self.data_box,
            })

            # 文件名稱
            name = Path(self.create_path) / f"{self.create_name}.html"
            # 輸出文件
            name.write_text(html, encoding="utf-8")
            print("輸出完成")

            os.startfile(name)

if __name__ == "__main__":
    TG = TemplateGeneration()
    TG.Generate_Save_HTML()