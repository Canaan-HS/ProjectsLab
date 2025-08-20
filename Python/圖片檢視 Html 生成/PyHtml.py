import os

from pathlib import Path
from tkinter import filedialog

from jinja2 import Template


class DataImport:
    def __init__(self):
        os.chdir(Path(__file__).parent.resolve())

    def read_folder(self):
        folder_path = filedialog.askdirectory(title="選取文件夾")

        if folder_path:
            data_box = []
            folder = Path(folder_path)

            create_name = folder.name
            create_path = folder.parent

            for file in folder.iterdir():
                # ! 無特別判斷是否是圖片
                data_box.append(file.relative_to(create_path).as_posix())

            return create_path, create_name, data_box


class TemplateGeneration(DataImport):
    def __init__(self):
        super().__init__()

    def __create_template(self):
        return Template(
            """
            <html>
                <head>
                    <title>{{ title }}</title>
                    <script>{{ script }}</script>
                    <style>
                        body {
                            margin: 0;
                            padding: 0;
                            background: rgb(110, 110, 110);
                        }
                        img {
                            width: 100%;
                            max-width: 55%;
                            margin: 0 auto;
                        }
                        html {
                            overflow: auto;
                            scrollbar-width: none;
                            -ms-overflow-style: none;
                        }
                        html::-webkit-scrollbar {
                            display: none;
                        }
                        #picture_container img:hover {
                            cursor: none;
                        }
                        #picture_indicator {
                            position: fixed;
                            top: 10px;
                            right: 10px;
                            background: rgba(0,0,0,0.3);
                            color: #fff;
                            padding: 4px 8px;
                            border-radius: 6px;
                            font-size: 14px;
                            font-family: sans-serif;
                            z-index: 9999;
                            cursor: pointer;
                        }
                    </style>
                </head>
                <body>
                    <div id="picture_indicator">1 / {{ total }}</div>
                    <div id="picture_container">
                        {% for src in data %}
                        <img id="img-{{ loop.index }}" data-index="{{ loop.index }}" src="{{ src|safe }}" loading="lazy" style="display: none;" onerror="this.remove()">
                        {% endfor %}
                    </div>
                </body>
            </html>
        """
        )

    def generate_html(self):
        # 讀取資料 (錯誤直接結束)
        try:
            self.create_path, self.create_name, self.data_box = self.read_folder()
        except:
            return

        if self.create_path is not None:

            # 渲染模板
            html = self.__create_template().render(
                {
                    "title": self.create_name,
                    "script": Path("features.js").read_text(encoding="utf-8"),
                    "data": self.data_box,
                    "total": len(self.data_box),
                }
            )

            # 文件名稱
            name = Path(self.create_path) / f"{self.create_name}.html"
            # 輸出文件
            name.write_text(html, encoding="utf-8")

            print("輸出完成")
            os.startfile(name)


if __name__ == "__main__":
    TG = TemplateGeneration()
    TG.generate_html()
