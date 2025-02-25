from tkinter import filedialog , messagebox , ttk
from tkinterdnd2 import DND_FILES, TkinterDnD
from multiprocessing import cpu_count
import tkinter as tk
import threading
import win32api
import time
import os

""" Versions 1.0.3 (測試版)

運行環境 =>

Windows 11
Python 3.12.9 64-bit

相同目錄下需要有:

7z.exe
Rar.exe
upx.exe

功能概述 =>

[+] UPX壓縮
[+] UPX還原
[+] RAR壓縮
[+] ZIP壓縮

未來修正 =>

[+] 添加滾動條
[+] 修正 UI, 真的是醜爆了
[+] 修改實現邏輯, 以前寫的真的垃圾

https://github.com/israel-dryer/ttkbootstrap
https://github.com/rdbende/Sun-Valley-ttk-theme
"""

class Compression:
    def __init__(self):
        self.State = None
        self.SeparateList = []
        self.IntegrationList = []

        # 是否是隱藏文件 (只適用於 windows)
        self.Is_hidden = lambda path: win32api.GetFileAttributes(path) & 2 != 0

        # 清理顯示狀態
        self.Clear_display = lambda: (
            gui.RightText.delete("1.0", "end"), gui.LeftText.delete("1.0", "end")
        )

        # 以下為壓縮相關參數
        self.UpxCC = "upx -9 --best --ultra-brute --force"
        self.UpxRC = "upx -d --force"

        self.RarCC = f"rar a -ri15:0.00001 -m5 -mt{cpu_count()-1} -md1g"
        self.ZipCC = f"-t7z -m0=lzma2 -mx=9 -mfb=128 -md=2048m -ms=1g -mmt={cpu_count()} -mqs=on"

        self.UpxError = f"\n\n\n\n\tUPX不支援整合壓縮"
        self.UpxSupport = {"exe","dll","ocx","bpl","cpl","sys","ax","acm","drv","tlb"}

    """---------- 檔案導入 ----------"""

    # 是否是最上層 (資料夾, 只有磁碟機號不算)
    def Is_topmost(self, path):
        path = path.split(":\\")[1]
        return False if path == "" else path.find("\\") == -1

    # 拖曳添加文件
    def DragAdd(self, event, mode):
        {
            "Integrated": self.ImportAsIntegratedFile,
            "Separate": self.ImportAsSeparateFiles
        }.get(mode)(event.data.strip("{}"))

    # 導入所有文件作為集成壓縮
    def ImportAsIntegratedFile(self, filePath=None):
        try:
            self.State = False
            self.IntegrationList.clear()
            self.Clear_display()

            filePath = filePath or filedialog.askdirectory()

            # 當只有最上層 路徑 + 資料夾
            if self.Is_topmost(os.path.abspath(filePath)):
                gui.LeftText.insert("end", f"{os.path.basename(filePath)}")
                self.IntegrationList.append(filePath)
            else: # 當有子資料夾
                entries = os.listdir(filePath)
                fileExists = any(os.path.isfile(os.path.join(filePath, entry)) for entry in entries)

                if fileExists: # 第一層含有檔案
                    gui.LeftText.insert("end", f"{os.path.basename(filePath)}")
                    self.IntegrationList.append(filePath)
                else: # 第一層無檔案 (不處理多層的情況)
                    for entry in entries:
                        if os.path.isdir(os.path.join(filePath, entry)):
                            gui.LeftText.insert("end", f"{entry}\n\n")
                            self.IntegrationList.append(os.path.join(filePath, entry))
        except:pass

    # 單獨導入所有文件,將每個文件丟至List
    def ImportAsSeparateFiles(self, filePath=None):
        self.State = True
        self.SeparateList.clear()
        self.Clear_display()

        filePath = filePath or filedialog.askdirectory()

        if os.path.isfile(filePath): # 單個檔案添加 (針對拖放功能)
            gui.RightText.insert("end", filePath)
            self.SeparateList.append(filePath)
        else:
            for path, dirname, filename in os.walk(filePath): # 路徑, 空資料夾, 文檔
                for name in filename + dirname:
                    gui.RightText.insert("end", f"{name}\n\n") # 這行是在每行的最後插入字串並且換行
                    Complete = os.path.join(path, name) # 取得路徑位置 + 檔名
                    if os.path.isdir(Complete) and os.path.getsize(Complete) == 0 and self.Is_hidden(Complete):continue # 空白目錄 或 隱藏資料夾過濾
                    self.SeparateList.append(Complete)

    """---------- 命令與操作 ----------"""

    # 命令運行
    def CommandRun(self, order, show):
        output = os.popen(order).read()
        show.insert("end", f"{output}\n\n")

    # 恢復按鈕的 UI
    def Ui_Recovery(self, object):
        object.config(fg=gui.Compressbuttonnormal, bg=gui.Compressbuttonbackgroundcolor)

    """---------- UPX壓縮運行 ----------"""

    # UPX壓縮觸發
    def UPXCompression(self):
        try:
            gui.UPXCompression.config(fg=gui.Compressbuttontorun, bg=gui.Compressbuttonbackgroundcolor)

            if len(self.SeparateList) > 0:
                self.UPXRun(self.SeparateList,"Compression")
            else:
                raise Exception()

        except:
            self.UPX_Error_Trigger(gui.UPXCompression)

    # UPX壓縮還原觸發
    def UPXRestore(self):
        try:
            gui.UPXRestore.config(fg=gui.Compressbuttontorun, bg=gui.Compressbuttonbackgroundcolor)

            if len(self.SeparateList) > 0:
                self.UPXRun(self.SeparateList, "Restore")
            else:
                raise Exception()

        except:
            self.UPX_Error_Trigger(gui.UPXRestore)

    # UPX壓縮運行
    def UPXRun(self, Text, Work):
        Finally = []
        if len(Text) != 0: # 非必要判斷
            self.Clear_display()
            
            for text in Text: 
                FileExtension = text.split(".") # 將檔案副檔名與前面切片
                if FileExtension[-1] in map(str.lower, self.UpxSupport) and FileExtension[-2] != "upx": # 判斷附檔名是否在支援格式中, 後面是一開始寫的架構, 避免壓縮到upx.exe自己
                    Finally.append(f'"{text}"')
                else:continue

            if len(Finally) > 0:

                for fina in Finally: # 開始輸出列表
                    time.sleep(0.1)
                    if Work == "Compression": # 判斷是要還原還是壓縮
                        self.Ui_Recovery(gui.UPXCompression)
                        threading.Thread(
                            target=self.CommandRun,
                            args=(f"{self.UpxCC} {fina}", gui.RightText)
                        ).start()
                    elif Work == "Restore":
                        self.Ui_Recovery(gui.UPXRestore)
                        threading.Thread(
                            target=self.CommandRun,
                            args=(f"{self.UpxRC} {fina}", gui.RightText)
                        ).start()

                messagebox.showinfo("運行完成", f"全部以操作完畢")

            else:
                self.Ui_Recovery(gui.UPXRestore)
                self.Ui_Recovery(gui.UPXCompression)
                messagebox.showerror("格式錯誤", "沒有可進行UPX操作的檔案格式")
    
    # UPX 點擊後錯誤的觸發
    def UPX_Error_Trigger(self, object):
        self.Clear_display()
        gui.LeftText.insert("end", f"{self.UpxError}")
        messagebox.showerror("設置錯誤", "未檢測到文件")
        object.config(fg=gui.Compressbuttonnormal, bg=gui.Compressbuttonbackgroundcolor)

    """---------- RAR壓縮運行 ----------"""

    # self.State True 為各別輸出 反之 整合輸出(RAR壓縮觸發)
    def RARCopression(self):
        try:
            gui.RARCompression.config(fg=gui.Compressbuttontorun, bg=gui.Compressbuttonbackgroundcolor) # 按下按鈕時變色
            if len(self.SeparateList) > 0 or len(self.IntegrationList) > 0:
                if self.State: # 判斷是單獨壓縮還是集成壓縮
                    self.RARRespective(self.SeparateList) # True是單獨,呼叫單獨壓縮方式,傳遞單獨壓縮的列表
                else:
                    self.RARFusion(self.IntegrationList) # 反之集成壓縮,給予完整所有路徑
            else:
                raise Exception()
        except:
            messagebox.showerror("設置錯誤", "未檢測到文件")
            self.Ui_Recovery(gui.RARCompression)

    # RAR集成壓縮運行
    def RARFusion(self, Text):
        try:
            self.Clear_display()
            self.Ui_Recovery(gui.RARCompression)

            for text in Text:
                threading.Thread( # 傳遞壓縮指令, 與顯示對象
                    target=self.CommandRun,
                    args=(f'{self.RarCC} "{text}.rar" "{text}"', gui.LeftText)
                ).start()

            messagebox.showinfo("開始壓縮", f"請稍後...\n檔案將保存於 : {Text[0].split("\\", 1)[0]}") # 輸出開始壓縮,並將檔案壓縮位置輸出
        except:pass

    # RAR個別壓縮運行
    def RARRespective(self, Text):
        try:
            self.Clear_display()
            self.Ui_Recovery(gui.RARCompression)
            for text in Text:
                Path = f"{text.split(':/')[0]}:/{text.rsplit("\\", 1)[1]}" # 取得最上層路徑 + 個別壓縮檔名, 合併後的字串

                threading.Thread(
                    target=self.CommandRun,
                    args=(f'{self.RarCC} "{Path}.rar" "{text}"', gui.RightText)
                ).start()

            messagebox.showinfo("壓縮完成", f"\n檔案將保存於 : {Text[0].split("\\", 1)[0]}") # 取得最上層路徑
        except:pass

    """---------- ZIP壓縮運行 ----------"""

    # ZIP壓縮觸發
    def ZIPCompression(self):
        try:
            gui.ZipCompression.config(fg=gui.Compressbuttontorun, bg=gui.Compressbuttonbackgroundcolor)
            if len(self.SeparateList) > 0 or len(self.IntegrationList) > 0:
                if self.State:self.ZIPRespective(self.SeparateList)
                else:self.ZIPFusion(self.IntegrationList)
            else:
                raise Exception()
        except:
            messagebox.showerror("設置錯誤", "未檢測到文件")
            self.Ui_Recovery(gui.ZipCompression) 

    # ZIP集成壓縮
    def ZIPFusion(self, Text):
        try:
            self.Clear_display()
            self.Ui_Recovery(gui.ZipCompression)

            for text in Text:
                threading.Thread(
                    target=self.CommandRun,
                    args=(f'7z a "{text}.7z" "{text}" {self.ZipCC}', gui.LeftText)
                ).start()

            messagebox.showinfo("開始壓縮",f"請稍後...\n檔案將保存於 : {Text[0].split("\\", 1)[0]}")
        except:pass

    # ZIP個別壓縮
    def ZIPRespective(self, Text):
        try:
            self.Clear_display()
            self.Ui_Recovery(gui.ZipCompression)
            for text in Text:
                Path = f"{text.split(':/')[0]}:/{text.rsplit("\\", 1)[1]}"

                threading.Thread(
                    target=self.CommandRun,
                    args=(f'7z a "{Path}.7z" "{text}" {self.ZipCC}', gui.RightText)
                ).start()

            messagebox.showinfo("壓縮完成",f"\n檔案將保存於 : {Text[0].split("\\", 1)[0]}")
        except:pass

class GUI(Compression, TkinterDnD.Tk):
    def __init__(self):
        Compression.__init__(self)
        TkinterDnD.Tk.__init__(self)
        
        Current_Location = os.path.dirname(os.path.abspath(__file__))
        os.chdir(Current_Location)

        """ 窗口初始設置 """
        self.title("懶人壓縮器 - v1.0.3-Beta")
        self.iconbitmap(os.path.join(Current_Location, "Compression.ico")) # 這邊在寫一次定位, 是避免打包成 exe 後找不到圖標
        self.resizable(False, False)

        Win_Width = 850
        Win_Height = 720
        Win_Cur_Width = self.winfo_screenwidth() # 螢幕寬度
        Win_Cur_Height = self.winfo_screenheight() # 螢幕高度

        self.geometry(f"{Win_Width}x{Win_Height}+{int((Win_Cur_Width - Win_Width) / 2)}+{int((Win_Cur_Height - Win_Height) / 2)}")
        
        """ 顏色設置 """
        self.configure(background="#A4EBF3") # 整體背景色

        Space = " "
        OuterFrameColor = "#F4F9F9"
        Displayboxcolor = "#20262E"
        ImportTextColor = "#CD5888"
        self.Compressbuttontorun = "#DF2E38"
        self.Compressbuttonnormal = "#F0EEED"
        self.Compressbuttonbackgroundcolor = "#BFACE2"

        """ 框架宣告 """
        self.OuterFrame = tk.Canvas(self, bd=0, highlightthickness=0, bg=OuterFrameColor) # 最外層的框架
        self.TopFrame = tk.Canvas(self.OuterFrame, bd=0, highlightthickness=0, bg=OuterFrameColor) # 頂層框架
        self.LeftFrame = tk.Canvas(self.OuterFrame, bd=0, highlightthickness=0, bg=OuterFrameColor) # 左側框架
        self.RightFrame = tk.Canvas(self.OuterFrame, bd=0, highlightthickness=0, bg=OuterFrameColor) # 右側框架
        self.MiddleFrame = tk.Canvas(self.OuterFrame, bd=0, highlightthickness=0, bg="#CCF2F4") # 中間框架(本來要做其他功能的)
        self.UnderlyingFramework = tk.Canvas(self.OuterFrame, bd=0, highlightthickness=0, bg=OuterFrameColor) # 底層框架

        """ 元素宣告 """
        
        Element_style = {
            "height": 1, "width": 10, "border": 3,
            "cursor": "hand2", "font": ("Arial", 25, "bold"),
            "relief": "groove", "fg": "#609EA2", "bg": OuterFrameColor
        }

        # 整合壓縮導入按鈕
        self.IntegrateData = tk.Button(self.TopFrame, Element_style, text="整合壓縮", command=self.ImportAsIntegratedFile)
        # 個別壓縮導入按鈕
        self.AloneData = tk.Button(self.TopFrame, Element_style, text="單檔壓縮", command=self.ImportAsSeparateFiles)

        Display_style = {
            "bd": 0,
            "wrap": "word",
            "cursor": "arrow",
            "font": ("Arial", 13),
            "fg": ImportTextColor, "bg": Displayboxcolor
        }

        # 左側文字框
        self.LeftText = tk.Text(self.LeftFrame, Display_style)
        self.LeftText.drop_target_register(DND_FILES)
        self.LeftText.dnd_bind("<<Drop>>", lambda event: self.DragAdd(event, "Integrated"))
        self.LeftText.insert("end", f"\n\tUPX不支援整合壓縮\n\n{Space*8}不要同時進行過多的RAR壓縮\n\n{Space*12}該程式沒有對線程數限制\n\n\t過多可能造成嚴重卡頓")
        
        # 右側文字框
        self.RightText = tk.Text(self.RightFrame, Display_style)
        self.RightText.drop_target_register(DND_FILES)
        self.RightText.dnd_bind("<<Drop>>", lambda event: self.DragAdd(event, "Separate"))
        self.RightText.insert("end", f"\n\t{Space*7}單檔壓縮主要適用於UPX壓縮\n\n\t{Space*9}UPX是針對EXE和Dll的壓縮\n\n\t{Space*15}壓縮前請自行備份\n\n\t{Space*15}壓縮後低機率損毀")

        Element_style.update({
            "border": 2,
            "font": ("Arial", 15, "bold"),
            "fg": self.Compressbuttonnormal,
            "bg": self.Compressbuttonbackgroundcolor
        })

        # 底層UPX壓縮按鈕
        self.UPXCompression = tk.Button(self.UnderlyingFramework, Element_style, text="UPX 壓縮", command=self.UPXCompression)
        # 底層UPX壓縮還原按鈕
        self.UPXRestore = tk.Button(self.UnderlyingFramework, Element_style, text="UPX 還原", command=self.UPXRestore)
        # 底層PAR壓縮按鈕
        self.RARCompression = tk.Button(self.UnderlyingFramework, Element_style, text="RAR 壓縮", command=self.RARCopression)
        # 底層Zip壓縮按鈕
        self.ZipCompression = tk.Button(self.UnderlyingFramework, Element_style, text="ZIP 壓縮", command=self.ZIPCompression)

        self.frame() # 創建框架
        self.Element() # 創建元素

    def frame(self):
        self.OuterFrame.place(width=830, height=665, x=10, y=40)
        self.TopFrame.place(width=790, height=80, x=20, y=0)
        self.LeftFrame.place(width=350, height=450, x=20, y=90)
        self.RightFrame.place(width=440, height=450, x=370, y=90)
        self.MiddleFrame.place(width=20, height=450, x=350, y=90)
        self.UnderlyingFramework.place(width=790, height=105, x=20, y=550)

    def Element(self):
        self.AloneData.place(x=470, y=10)
        self.IntegrateData.place(x=55, y=10)
        self.LeftText.place(x=0, y=0)
        self.RightText.place(x=0, y=0)
        self.UPXCompression.place(x=520, y=5)
        self.UPXRestore.place(x=520, y=55)
        self.RARCompression.place(x=660, y=5)
        self.ZipCompression.place(x=660, y=55)

    def __call__(self):
        self.mainloop()

if __name__ == "__main__":
    gui = GUI()
    gui()