import glob
import os
import threading
import tkinter as tk
import concurrent.futures

from pathlib import Path
from types import SimpleNamespace
from multiprocessing import cpu_count
from tkinter import filedialog, messagebox

import ffmpeg
from alive_progress import alive_bar
from tkinterdnd2 import DND_FILES, TkinterDnD

"""
>   Versions 1.0.0 - 簡易 影片快照截圖

        ~ (開發/運行環境):
        $ Windows 11 23H2
        $ Python 3.12.8 64-bit
        $ ffmpeg 2025-02-09

        ~ 第三方庫:
        $ tkinterdnd2
        $ alive_progress

        ~ 功能說明:
        ^ 添加影片
        ^ 擷取截圖

        ~ 使用說明:
        & 透過拖放 或 點擊, 添加影片
        & 接著會自動開始擷取截圖, 並保存在影片所在位置
        
        ~ 可調參數:
        & Interval: 擷取間隔 (預設 1 秒)
"""
    
class Snapshots():
    def __init__(self):
        self.video_duration = None
        self.command_display = None

        self.task_event = None
        self.duration_event = None

        self.max_workers = cpu_count() // 2 # 限制處理的線程, 太高可能會卡死

        self.Allow_Type = {
            "mp4", "mkv", "avi", "mov", "flv", "wmv", "webm", "mpeg", "mpg", "m4v", "ogv",
            "3gp", "asf", "ts", "vob", "rm", "rmvb", "m2ts", "divx", "xvid"
        }
        self.Allow_Type_Str = ";".join([f"*.{ext}" for ext in self.Allow_Type])

    def capture(self, video_path, img_path, frame_time):
        # 擷取快照 (擷取影片本身的解析度)
        (
            ffmpeg
                .input(video_path, ss=frame_time)  # 設置擷取的時間點
                .output(
                    img_path, # 指定輸出文件名
                    q=1,               # 設定圖片的質量，1為最佳質量
                    vframes=1,         # 只擷取一幀
                    lossless=1,         # 開啟無損壓縮
                    loglevel="quiet",
                    vf="unsharp=5:5:0.8:3:3:0.4"
                )
                .run(overwrite_output=True)
        )

        # 轉換格式
        (
            ffmpeg
                .input(img_path)
                .output(
                    f"{img_path.replace('.png', '.webp')}", # 這邊不能直接覆蓋, 會出錯
                    q=1,
                    lossless=1,
                    loglevel="quiet",
                    vf="unsharp=5:5:0.8:3:3:0.4"
                ).run(overwrite_output=True)
        )

        # 刪除原始圖片
        Path(img_path).unlink()

    def get_video_duration(self, path):
        # 獲取總時長
        self.video_duration = float(ffmpeg.probe(path)["format"]["duration"])

        # 表示線程完成
        self.duration_event.set()

    def create_task(self, path, interval):
        video_path = path
        save_path = Path(path).parent / f"[{Path(path).stem}] Snapshots"

        # 創建路徑
        save_path.mkdir(parents=True, exist_ok=True)

        try:
            self.duration_event = threading.Event()
            # 啟動獲取影片長度的線程
            threading.Thread(target=self.get_video_duration, args=(video_path,)).start()
            # 等待影片時長獲取完成
            self.duration_event.wait()

            # 取得影片時長
            video_duration = self.video_duration
            # 計算截圖總數
            total_frames = int(video_duration // interval)
            # 計算填充長度
            filler_length = len(str(total_frames))

            with concurrent.futures.ThreadPoolExecutor(max_workers=self.max_workers) as executor:
                tasks = []

                # ! 暫時以進度條顯示 處理
                with alive_bar(total=total_frames, title=Path(path).name, length=90, bar='blocks', spinner='dots_waves', elapsed=False) as bar:
                    for frames in range(total_frames):
                        frame_time = frames * interval
                        img_path = f"{save_path}/{str(frames+1).zfill(filler_length)}.png"

                        process = executor.submit(self.capture, video_path, img_path, frame_time)
                        tasks.append(process)

                    for task in tasks:
                        task.result()
                        bar()

            self.task_event.set()
        except Exception as e:
            print(e)

class GUI(Snapshots, TkinterDnD.Tk):
    def __init__(self, Interval=1):
        Snapshots.__init__(self)
        TkinterDnD.Tk.__init__(self, className="影片快照截圖")

        # 設置擷取延遲
        self.interval = Interval

        # 取得使用者螢幕大小
        self.User_Win_Width = self.winfo_screenwidth()
        self.User_Win_Height = self.winfo_screenheight()

        # 設定視窗大小
        self.Win_Width = self.User_Win_Width // 4
        self.Win_Height = self.User_Win_Height // 2

        # 內部框架的大小
        self.Ins_Width = self.Win_Width // 1.2
        self.Ins_Height = self.Win_Height // 4

        # 標籤允許顯示長度
        self.label_show_length = 24

        # 設定視窗不可調整大小，位置中上
        self.resizable(False, False)
        self.geometry(f"{self.Win_Width}x{self.Win_Height}+{int((self.User_Win_Width - self.Win_Width) / 2)}+{int((self.User_Win_Height - self.Win_Height) / 6)}")

        # 設置延遲框架
        self.set_frame = tk.Frame(self, width=self.Win_Width, height=self.Ins_Height // 2)
        # 顯示運行狀態框架
        self.show_frame = tk.Frame(self, width=self.Win_Width, height=self.Win_Height // 1.8)
        # Canvas 拖放框架
        self.add_frame = tk.Canvas(self, width=self.Ins_Width, height=self.Ins_Height, bd=1, highlightthickness=0)

        # 擷取間隔輸入框
        vcmd = (self.register(lambda value: value.replace(".", "", 1).isdigit() or value == ""), "%P")
        self.placeholder = "間隔設置(秒)"
        self.set_entet = tk.Entry(self.set_frame,
            width=28, font=("Arial Bold", 18), justify="center",
            borderwidth=1.3, relief="solid", validate="key",
            validatecommand=vcmd, textvariable=tk.StringVar(value=self.placeholder),
        )

        # 顯示運行狀態
        # Todo - 創建文本框, 用於顯示運行指令狀態

        # 畫實線邊框
        self.border = self.add_frame.create_rectangle(2, 2, self.Ins_Width, self.Ins_Height, outline="black", width=2)
        self.add_frame.drop_target_register(DND_FILES) # 註冊拖放事件
        # 顯示標籤
        self.display_label = tk.Label(self.add_frame, font=("Arial Bold", 18))
        self.add_frame.create_window(self.Ins_Width // 2, self.Ins_Height // 2, window=self.display_label)

        # 開始運行
        self.init_run()

    # 拖放提示
    def drag_tip(self, _, param):
        self.add_frame.itemconfig(self.border, dash=param)

    # 點擊選擇文件
    def open_file(self, _):
        try:
            file_path = filedialog.askopenfilename(title="影片選取", filetypes=[("影片文件", self.Allow_Type_Str)])
            if not file_path: raise
            self.on_add(SimpleNamespace(data=file_path))
        except: pass

    # 添加完成準備運行任務
    def on_add(self, event):
        file_path = event.data.strip("{}") # 解析檔案路徑
        file_type = Path(file_path).suffix[1:]
        file_name = Path(file_path).stem

        if file_type not in self.Allow_Type:
            self.drag_tip(None, ()) # 恢復顯示
            messagebox.showerror("不支援的檔案類型", "請選擇影片文件")
            return

        if self.destroy_setting(file_name): # 啟動銷毀設定
            self.task_event = threading.Event()
            threading.Thread(target=self.create_task, args=(file_path, self.interval)).start()
            self.task_event.wait()

            self.init_setting()

    # 消除設定, 避免重複操作
    def destroy_setting(self, show_path):
        try:
            self.set_entet.config(state="disabled") # 關閉輸入

            self.add_frame.config(cursor="arrow") # 設置鼠標為箭頭
            self.add_frame.itemconfig(self.border, dash=(5, 5))

            # 只允許顯示 24 個字元的檔名
            if len(show_path) > self.label_show_length: show_path = f"...{show_path[-self.label_show_length:]}"
            self.display_label.config(text=show_path)  # 更新標籤顯示
            self.display_label.update_idletasks() # 強制更新 UI

            # 解除綁定的事件 (避免重複操作)
            self.add_frame.unbind("<Button-1>")
            self.add_frame.dnd_bind("<<Drop>>", None)
            self.add_frame.dnd_bind("<<DropEnter>>", None)
            self.add_frame.dnd_bind("<<DropLeave>>", None)

            return True
        except Exception as e:
            print(e)
            return False

    def init_setting(self):
        self.set_entet.config(state="normal") # 啟用輸入
        
        self.add_frame.config(cursor="hand2") # 設置鼠標為手指
        self.add_frame.itemconfig(self.border, dash=())
        self.display_label.config(text="選擇影片")

        self.add_frame.bind("<Button-1>", self.open_file) # 綁定點擊添加事件
        self.add_frame.dnd_bind("<<Drop>>", self.on_add) # 綁定拖放添加事件
        self.add_frame.dnd_bind("<<DropEnter>>", lambda event: self.drag_tip(event, (5, 5))) # 綁定拖放進入事件
        self.add_frame.dnd_bind("<<DropLeave>>", lambda event: self.drag_tip(event, ())) # 綁定拖放離開事件

    def init_run(self):
        def focus_input(_):
            if self.set_entet.get() == self.placeholder:
                self.set_entet.delete(0, tk.END)

        def enter(_):
            value = self.set_entet.get()
            self.interval = float(value if value != "" else 1)

        self.init_setting()
        self.set_frame.place(x=0, y=0)
        self.set_entet.bind("<Button-1>", focus_input)
        self.set_entet.bind("<KeyRelease>", enter)
        self.set_entet.place(relx=0.5, rely=0.5, anchor="center")

        self.show_frame.place(x=0, y=70)
        self.add_frame.place(relx=0.5, rely=0.82, anchor="center")
        
        self.mainloop()

if __name__ == "__main__":
    GUI()