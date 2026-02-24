import os
import time
import json
import queue
import threading
import tkinter as tk
from concurrent.futures import ThreadPoolExecutor
from tkinter import scrolledtext, filedialog, messagebox

from tkinterdnd2 import DND_FILES, TkinterDnD

import opencc
import chardet
import pyperclip

"""
>   Versions 1.0.3 - v2 (待重構)

        ~ (開發/運行環境):
        $ Windows 11 25H2
        $ Python 3.12.10 64-bit

        ~ 第三方庫:
        $ opencc
        $ chardet
        $ pyperclip
        $ tkinterdnd2

        ~ 使用說明:
        > 文本轉換:
        & 將需轉換文字貼上至, 文本輸入框 (用快捷 Ctrl + v) 貼上才會觸發轉換
        & 一貼上後就會立即轉換結果, 並將結果顯示於文本框中, 同時會自動添加結果到剪貼簿當中
        & 代表可立即貼上到所需地方, 不用再次手動複製轉換結果, 點選其他窗口後, 再次回到轉換器, 會自動清除先前內容

        > 批量轉換:
        & 選擇一個資料夾, 會根據 support_file 參數中, 允許的類型將導入結果, 顯示在文本框中
        & 接著就可以選擇, 要使用覆蓋原檔案輸出, 還是創建新檔案輸出, 新檔案會創建在導入的目錄中
        & 轉換時會顯示轉換結果, 告知轉換成功狀態, 與轉換消耗時間, 失敗通常會顯示原因

        > 單獨轉換:
        & 功能基本同上, 只是變成選擇單個檔案, 但也會受到 support_file 的允許類型影響

        > JSON轉換:
        & 只能單獨轉換, 適用於翻譯文件, 會只針對 value 轉換

        ~ 開發說明:
        * 改到目前的版本, 多線程與 與 一些設計 其實已經沒啥意義, 現在只作為臨時用工具刪刪改改
"""


class DataProcessing:
    def __init__(self):
        self.output_name = None  # 保存輸出名
        self.output_rename = None  # 保存更改後名
        self.save_queue = queue.Queue()  # 保存轉換後要輸出的數據
        self.work_queue = queue.Queue()  # 保存要進行轉換的工作路徑
        self.lock = threading.Lock()

        self.converter = opencc.OpenCC("s2twp.json")  # 調用 簡體 轉 繁體

        # 計算完成結束時間
        self.ET = lambda start_time: round(time.time() - start_time, 3)

        # 文本轉換
        self.text_conversion = lambda text: self.converter.convert(text)

        # 支援的檔案類型
        self.support_file = {
            "po",
            "py",
            "js",
            "ts",
            "txt",
            "srt",
            "ass",
            "ssa",
            "lng",
            "lua",
            "lang",
            "conf",
            "json",
            "yaml",
            "xml",
            "ini",
            "md",
        }
        # 支持類型字串
        self.support_str = ";".join([f"*.{ext}" for ext in self.support_file])

        # 支援的編碼
        self.decode = lambda Btext, Encoding: Btext.decode(Encoding).splitlines()
        self.support_encod = {  # ! 等待後續修正
            "utf-8": lambda Btext: self.decode(Btext, "utf-8"),
            "ascii": lambda Btext: self.decode(Btext, "utf-8"),
            "utf-8-sig": lambda Btext: self.decode(Btext, "utf-8-sig"),
            "utf-16": lambda Btext: self.decode(Btext, "utf-16"),  # 只能處理 LE 類型
            "big5": lambda Btext: self.decode(Btext.decode("big5").encode("utf-8"), "utf-8"),
            "gbk": lambda Btext: self.decode(Btext, "gb18030"),
            "gb2312": lambda Btext: self.decode(Btext, "gb18030"),
            "gb18030": lambda Btext: self.decode(Btext, "gb18030"),
        }

    # 過濾文件類型
    def filter_type(self, path, data):
        if data.rsplit(".", 1)[-1] in self.support_file:
            self.work_queue.put(os.path.join(path, data).replace("\\", "/"))


class GUI(DataProcessing, TkinterDnD.Tk):
    def __init__(self):
        DataProcessing.__init__(self)
        TkinterDnD.Tk.__init__(self, className="文本簡繁轉換器 v2")

        self.iconbitmap(os.path.join(os.path.dirname(__file__), "ChineseConversion.ico"))
        self.resizable(0, 0)

        # 窗口大小
        self.win_width = 280
        self.win_height = 305
        # 使用者的螢幕寬高
        self.win_cur_width = lambda: self.winfo_screenwidth()
        self.win_cur_height = lambda: self.winfo_screenheight()

        # 設置窗口大小與位置
        self.geometry(
            f"{self.win_width}x{self.win_height}+{int((self.win_cur_width() - self.win_width) / 2)}+{int((self.win_cur_height() - self.win_height) / 2)}"
        )

        # 設置顏色
        self.buttontext = "#FDF4F5"
        self.buttontrigger = "#C0DBEA"
        self.buttonbackground = "#E8A0BF"
        self.configure(background="#BA90C6")  # 介面背景色

        # 內容顯示框架
        self.console_frame = tk.Frame(self, width=1080, height=605)
        self.console_frame.pack_propagate(False)  # 禁止大小變動

        self.console = scrolledtext.ScrolledText(
            self.console_frame,
            font=("KaiTi", 24),
            fg=self.buttontext,
            bg=self.buttonbackground,
            state="disabled",
            cursor="arrow",
        )

        # 設置標籤 (顯示顏色)
        self.console.tag_configure("Success", foreground="#00A600")
        self.console.tag_configure("Failure", foreground="#FF2D2D")

        button_style = {
            "height": 1,
            "width": 12,
            "border": 2,
            "cursor": "hand2",
            "font": ("Arial Bold", 22),
            "relief": "groove",
            "fg": self.buttontext,
            "bg": self.buttonbackground,
        }

        self.text_button = tk.Button(
            self, button_style, text="文本轉換", command=lambda: self.display_data(True)
        )

        self.json_button = tk.Button(
            self,
            button_style,
            text="JSON轉換",
            command=lambda: self.select_document(self.json_button, "選擇 JSON 檔案", "*.json"),
        )

        self.document_button = tk.Button(
            self,
            button_style,
            text="單獨轉換",
            command=lambda: self.select_document(
                self.document_button, "選擇單獨檔案", self.support_str
            ),
        )

        self.file_button = tk.Button(self, button_style, text="批量轉換", command=self.select_file)

        self.input_clear_box = [  # 用於清除元素
            self.text_button,
            self.json_button,
            self.document_button,
            self.file_button,
        ]

        button_style.update({"width": 10, "font": ("Arial Bold", 20)})  # 更新樣式
        self.reset_button = tk.Button(self, button_style, text="重新選擇", command=self.ui_reset)
        self.create_button = tk.Button(
            self, button_style, text="新建輸出", command=lambda: self.conversion_trigger("create")
        )
        self.override_button = tk.Button(
            self, button_style, text="覆蓋輸出", command=lambda: self.conversion_trigger("override")
        )
        self.output_clear_box = [self.create_button, self.override_button]

        # 用於文本輸入時, 自動清除內容
        self.wait_clear = False

    # 運行創建
    def __call__(self):
        self.json_process = False  # 重置 JSON 標記
        self.text_button.place(x=27, y=15)  # 文本選擇
        self.json_button.place(x=27, y=85)  # JSON選擇
        self.document_button.place(x=27, y=155)  # 單獨選擇
        self.file_button.place(x=27, y=225)  # 批量選擇
        self.mainloop()

    # 取得文本數據
    def get_text(self, _del: bool = True, _end: str = "end-1c"):
        text = self.console.get("1.0", _end)
        exist = bool(text.strip())

        if _del and exist:
            self.console.config(state="normal")
            self.console.delete("1.0", "end")

        return text.splitlines() if exist else []

    # 插入文本數據
    def insert_text(self, text, *args):
        self.console.config(state="normal")
        self.console.insert("end", f"{text}\n", *args)
        self.console.yview("end")
        self.console.config(state="disabled")

    # 開啟資料夾
    def select_file(self):
        try:
            self.file_button.config(fg=self.buttontrigger, bg=self.buttonbackground)
            data = filedialog.askdirectory(title="選擇資料夾")

            if not data:
                raise FileNotFoundError

            analyze = {}  # 遍歷所有數據
            for dirpath, dirnames, filenames in os.walk(data):
                analyze[dirpath] = filenames

            self.data_analysis(self.file_button, analyze)

        except FileNotFoundError:
            self.file_button.config(fg=self.buttontext, bg=self.buttonbackground)
            pass
        except Exception as e:
            print(f"Exception: {e}")

    # 開啟檔案
    def select_document(self, button: tk.Button, title: str, support: str):
        try:
            button.config(fg=self.buttontrigger, bg=self.buttonbackground)
            data = filedialog.askopenfilename(title=title, filetypes=[("支援格式", support)])

            if not data:
                raise FileNotFoundError

            if support == "*.json":
                self.json_process = True

            analyze = {}
            analyze[os.path.dirname(data)] = os.path.basename(data)
            self.data_analysis(button, analyze)

        except FileNotFoundError:
            button.config(fg=self.buttontext, bg=self.buttonbackground)
            pass
        except Exception as e:
            print(f"Exception: {e}")

    # 數據解析
    def data_analysis(self, button, data):
        button.config(fg=self.buttontext, bg=self.buttonbackground)

        # 導入工作並分類
        for path, name in data.items():
            if isinstance(name, list):
                for _name in name:
                    self.filter_type(path, _name.strip())

            elif isinstance(name, str):
                self.filter_type(path, name.strip())

        # 讀取工作
        while not self.work_queue.empty():
            work = self.work_queue.get()
            self.insert_text(work)

        # 判斷讀取的狀態 (只取一個小範圍)
        if self.get_text(False, "2.0"):
            self.display_data(False)
        else:
            messagebox.showerror("格式錯誤", "無可轉換的檔案格式")

    # 顯示數據
    def display_data(self, direct):
        # 變更窗口大小
        win_width = self.win_width * 4
        win_height = int(self.win_height * 2.37)
        self.geometry(
            f"{win_width}x{win_height}+{int((self.win_cur_width() - win_width) / 2)}+{int((self.win_cur_height() - win_height) / 2)}"
        )

        # 刪除選擇按鈕
        for button in self.input_clear_box:
            button.destroy()

        # 顯示框架
        self.console_frame.place(x=20, y=20)
        # 顯示文本
        self.console.pack(fill=tk.BOTH, expand=True)

        if direct:  # 針對文本轉換

            def trigger(event):  # 觸發後先讀取文本
                TexT = self.get_text()
                with ThreadPoolExecutor(max_workers=1000) as executor:
                    scrapbook = ""
                    length = len(TexT) - 1  # 取得結尾得長度
                    for index, text in enumerate(TexT):  # 使用線程池 以多線程進行轉換
                        change = executor.submit(self.text_conversion, text).result() + (
                            "" if index == length else "\n"
                        )
                        scrapbook += change  # 結果合併成一個字串
                        self.console.insert("end", change)  # 結果插入文本框 (獨立調用插入)
                    pyperclip.copy(scrapbook)  # 將結果添加到使用者 剪貼簿

            # 焦點狀態
            def focus_in(event):
                if self.wait_clear:
                    self.wait_clear = False
                    self.get_text()  # 清除內容

            # 離開焦點
            def focus_out(event):
                self.wait_clear = True

            # 修改預設狀態
            self.console.config(font=("Courier", 12), cursor="ibeam", state="normal")

            self.console.bind("<FocusIn>", focus_in)
            self.console.bind("<FocusOut>", focus_out)
            self.bind("<Control-v>", trigger)  # 貼上觸發
        else:
            # 新建輸出按鈕
            self.create_button.place(x=520, y=645)
            # 覆蓋輸出按鈕
            self.override_button.place(x=720, y=645)

        self.reset_button.place(x=920, y=645)

    # 觸發轉換
    def conversion_trigger(self, out_type):
        # 禁用重置按鈕
        self.reset_button.config(state="disabled", cursor="arrow")

        # 刪除輸出按鈕
        for button in self.output_clear_box:
            button.destroy()

        # 為了可以轉換後立即更新UI, 採取此方式, 但運行過多項目會卡
        for index, work in enumerate(self.get_text(), start=1):
            if work != "":
                threading.Thread(
                    target=self.conversion_output, args=(index, work, out_type)
                ).start()

        # 等待全部輸出完成
        def thread_wait():
            while True:
                if threading.active_count() <= 2:
                    self.reset_button.config(state="normal", cursor="hand2")
                    break
                time.sleep(0.5)

        # 等待所有線程完成
        threading.Thread(target=thread_wait).start()

    # 轉換後輸出
    def conversion_output(self, index, work, out_type):

        self.lock.acquire()  # 線程鎖
        Start = time.time()

        directory = os.path.dirname(work)
        fileName = os.path.basename(work)

        if out_type == "create":
            self.output_name = os.path.join(directory, f"(繁體轉換) {fileName}")
            self.output_rename = os.path.join(
                directory, f"(繁體轉換) {self.text_conversion(fileName)}"
            )
        elif out_type == "override":
            self.output_name = work
            self.output_rename = os.path.join(directory, self.text_conversion(fileName))

        try:
            if self.json_process:
                with open(work, "r", encoding="utf-8") as file:
                    data = json.load(file)
                with open(self.output_name, "w", encoding="utf-8") as output:
                    json.dump(
                        {key: self.text_conversion(value) for key, value in data.items()},
                        output,
                        indent=2,
                        ensure_ascii=False,
                    )
            else:
                encode = None
                decode_text = None

                with open(work, "rb") as file:  # 以二進制讀取
                    text = file.read()  # 獲取文本
                    encode = chardet.detect(text)["encoding"].lower()  # 解析編碼類型

                    with ThreadPoolExecutor(max_workers=1000) as executor:
                        supported = self.support_encod.get(encode)

                        if supported:
                            decode_text = supported(text)
                        else:  # @ 是輸出格式化用的分割符號
                            raise UnicodeDecodeError(f"@不支援的編碼: {encode}@", b"", 0, 1, "")

                        # 解碼完成後進行轉換
                        for txt in decode_text:
                            self.save_queue.put(executor.submit(self.text_conversion, txt).result())

                # 輸出
                with open(self.output_name, "w", encoding=encode) as output:
                    while not self.save_queue.empty():
                        output.write(
                            self.save_queue.get() + ("\n" if not self.save_queue.empty() else "")
                        )

            self.insert_text(
                f"({index}) {fileName} => [轉換完成: {self.ET(Start)} 秒]", "Success"
            )
            # 檔名轉換
            os.rename(self.output_name, self.output_rename)

        except UnicodeDecodeError as e:
            self.insert_text(
                f"({index}) {fileName} => [{str(e).split('@')[1]}]", "Failure"
            )
        except Exception as e:
            self.insert_text(f"(Exception) => {e}", "Failure")

        self.lock.release()  # 線程鎖釋放

    # 重置選擇
    def ui_reset(self):
        # 清除子物件
        # [widget.destroy() for widget in self.winfo_children()]

        self.destroy()  # 清除所有物件
        GUI().__call__()  # 重新實例化


if __name__ == "__main__":
    GUI().__call__()
