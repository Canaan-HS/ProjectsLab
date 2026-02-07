import os
import json

from pathlib import Path
from tkinter import filedialog

from jinja2 import Template


class DataImport:
    def __init__(self):
        os.chdir(Path(__file__).parent.resolve())
        self.support_image = {".jpg", ".jpeg", ".png", ".gif", ".webp", ".svg"}

    def read_folder(self, path=None):
        folder_path = filedialog.askdirectory(title="選取文件夾") if path is None else path

        if not folder_path:
            return None

        folder = Path(folder_path)
        create_name = folder.name
        create_path = folder.parent

        data = {}
        for file in folder.rglob("*"):
            if file.is_file() and file.suffix.lower() in self.support_image:
                key = "" if file.parent == folder else file.parent.relative_to(folder).as_posix()
                data.setdefault(f"{key}/", []).append(file.name)

        return create_path, create_name, {folder.as_posix(): data}


class TemplateGeneration(DataImport):
    def __init__(self):
        super().__init__()

    def __create_template(self):
        return Template(
            """
            <html>
                <head>
                    <title>{{ title }}</title>
                    <style>
                        {{ style }}
                    </style>
                    <script>{{ img_data }}</script>
                </head>
                <body>
                    <div id="picture_indicator"></div>
                    <div id="picture_container"></div>
                    <script>
                        {{ loader_script }}
                    </script>
                </body>
            </html>
        """
        )

    def generate_html(self):
        # 讀取資料 (錯誤直接結束)
        try:
            self.create_path, self.create_name, self.data = self.read_folder()
        except:
            return

        if self.create_path is not None:

            # 渲染模板
            html = self.__create_template().render(
                {
                    "title": self.create_name,
                    "style": Path("style.css").read_text(encoding="utf-8"),
                    "img_data": f"const img_data = {self.data}",
                    "loader_script": Path("loader.js").read_text(encoding="utf-8"),
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
