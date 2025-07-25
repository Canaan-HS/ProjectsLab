import os
import shutil
import threading
import tkinter as tk

from tkinter import filedialog
from operator import itemgetter
from collections import Counter
from concurrent.futures import ThreadPoolExecutor

from tqdm import tqdm
from rich.console import Console

from utils import Restore_RPG, MAX_WORKERS, VALID_EXTENSIONS

""" Versions 1.0.3 - V2

    Todo - 精簡版檔案類型分類

        ? (開發/運行環境):
        * Windows 11 24H2
        * Python 3.13.5 64-bit

        * 第三方庫:
        * rich
        * progressbar

        ? 使用說明:
        * 運行前可調整 Select() 的參數, 參數說明於下方函數
        * 運行後選擇需分類檔案的 資料夾
        * 接著根據顯示的代號, 輸入代號選擇檔案類型 (如果只有一個類型會自動選擇)
        * 最後會以 (複製 or 移動) [可選的] 方式輸出, 輸出路徑在選擇的資料夾內部
        * 輸出的速度取決於硬碟讀寫速度
"""

console = Console()


def print(*args, **kwargs):
    console.print(*args, **kwargs)


class Read(tk.Tk):
    def __init__(self):
        super().__init__()
        self.Folder_Path = None
        self.Complete_Data = None

        self.withdraw()  # 隱藏主視窗
        self.attributes("-topmost", True)  # 置頂主視窗

    # 選擇開啟資料夾
    def __Open_Folder(self):
        self.Folder_Path = filedialog.askdirectory(title="選擇資料夾", parent=self)

        if self.Folder_Path:
            return self.__Read_All_Files()
        else:
            print("選擇取消", style="bold red")
            os._exit(0)

    def __Read_All_Files(self):
        # 保存選擇資料夾後讀取的所有數據
        Read_Data = {}

        for Root, _, Files in os.walk(self.Folder_Path):  # 路徑 , 資料夾 , 檔名
            Read_Data[Root] = Files

        return Read_Data

    # 解析開啟的路徑數據
    def Analysis(self, Path=None):

        self.Folder_Path = Path  # 可直接給予測試用路徑
        Data = self.__Read_All_Files() if Path else self.__Open_Folder()

        # 緩存處理擴展名
        File_Extension = None
        # 保存所有檔案類型 用於顯示選擇
        File_Type = set()
        # 保存所有檔案類型 用於計算數量
        Type_Quantity = []
        # 保存所有檔案數據
        Complete_Data = []

        for Path, FileBox in Data.items():
            if len(FileBox) != 0:  # 當他是 0 帶表示空資料夾
                for name in FileBox:
                    try:
                        File_Extension = name.rsplit(".", 1)[1].strip()
                    except Exception:  # 可能有例外
                        pass

                    try:
                        LowExtension = File_Extension.lower()

                        File_Type.add(LowExtension)
                        Type_Quantity.append(LowExtension)
                        Complete_Data.append(f"{Path}/{name}".replace("\\", "/"))
                    except Exception:
                        print("無可分類檔案", style="bold red")
                        os._exit(0)

        self.Complete_Data = Complete_Data
        return File_Type, Counter(Type_Quantity)


# 自訂例外
class DataEmptyError(Exception):
    pass


# 輸出
class Output:
    def __init__(self):
        # 將變數都用這種方式初始化, 雖然不是很好 (難以單獨測試), 但是可以讓代碼看起來更整潔
        self.Auto_Open = None
        self.Task_Work = None
        self.Attach_Source = None

        self.Save_Path = None
        self.Output_Data = None
        self.Move_Output = lambda Source_Path, Output_Path: shutil.move(Source_Path, Output_Path)
        self.Copy_Output = lambda Source_Path, Output_Path: shutil.copyfile(
            Source_Path, Output_Path
        )

    # 複製處理
    def __Process_Task(self):
        Record_Output = set()  # 用於紀錄已輸出的文件, 避免重複輸出
        Lock = threading.Lock()  # 線程鎖
        Task_Size = len(self.Output_Data)

        def Process_Start(Copy_Path):
            Base_Name = os.path.basename(Copy_Path)
            # 取得上一層資料夾名稱
            Parent_Path = os.path.basename(os.path.dirname(Copy_Path))

            if self.Attach_Source:
                Output_Path = os.path.join(self.Save_Path, f"[{Parent_Path}] {Base_Name}")
            else:
                Output_Path = os.path.join(self.Save_Path, Base_Name)

                # 使用鎖來保護共享的 Record_Output
                with Lock:
                    if Output_Path in Record_Output:
                        # 當沒有設置來源時, 進行重複檢查, 重複的自動添加來源
                        Output_Path = os.path.join(self.Save_Path, f"{Parent_Path}_{Base_Name}")
                    else:
                        # 如果路徑不重複，使用它並記錄下來
                        Record_Output.add(Output_Path)

                # 執行實際任務
                self.Task_Work(Copy_Path, Output_Path)

        with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
            list(tqdm(executor.map(Process_Start, self.Output_Data), total=Task_Size))

        # 開啟存檔位置
        self.Auto_Open and os.startfile(self.Save_Path)

    # 創建數據
    def CreateTask(self):
        try:
            if len(self.Output_Data) == 0 or self.Output_Data is None:
                raise DataEmptyError()

            os.mkdir(self.Save_Path)  # 創建輸出資料夾
            self.__Process_Task()

        except DataEmptyError:
            print("該路徑下, 無可操作的文件", style="bold red")
        except Exception:
            self.__Process_Task()


class TypeSelection(Read, Output):
    def __init__(self):
        Read.__init__(self)
        Output.__init__(self)

        self.Task_List = None
        self.Repeat_Task = None
        self.Type_Folder = None
        self.Copy_Mode = True

    # 選擇輸出類型
    def __Choose(self, Select: None):

        # ! 懶得處理細節判斷
        # ! 使用 Repeat_Task 如果不是複製文件, 就不要選擇已經操作過的類型, 因為沒有根據選擇清理 Task_List, 重新選擇可能會導致找不到文件報錯
        while True:
            try:
                SelectCode = Select or int(input("\n選擇輸出類型 (代號) : "))

                if SelectCode == 0:
                    print(f"你選擇了 : 全部\n", style="bold green")
                    Selected = "ALL"

                    self.Output_Data = self.Complete_Data  # 將完整數據賦予給輸出數據
                else:
                    Type = self.Task_List[SelectCode - 1][0]  # 根據索引取出選擇則字串
                    Selected = Type

                    print(f"你選擇了 : {Type}\n", style="bold green")

                    # 檢查是否為 RPG Maker 加密圖片類型
                    if f".{Type.lower()}" in VALID_EXTENSIONS:

                        def Rpg_Restore_Task(source_path, output_path):
                            # 將輸出的副檔名強制變更為 .png
                            output_path_base, _ = os.path.splitext(output_path)
                            png_output_path = output_path_base + ".png"

                            # 執行還原任務
                            Restore_RPG(
                                input_path=source_path,
                                output_path=png_output_path,
                                delete_original=not self.Copy_Mode,  # 如果不是複製模式，就刪除原始檔案
                            )

                        # 將任務切換為 RPG 圖片還原
                        self.Task_Work = Rpg_Restore_Task

                    # 根據選擇類型, 取出完整數據中符合該副檔名的文件
                    self.Output_Data = [
                        Item for Item in self.Complete_Data if Item.endswith(f".{Type}")
                    ]

                # 生成保存路徑
                self.Save_Path = (
                    f"{self.Folder_Path}/{os.path.basename(self.Folder_Path)} ({Selected})"
                    if self.Type_Folder
                    else self.Folder_Path
                )

                # 創建輸出任務
                self.CreateTask()

                # 非重複選擇直接跳出
                if not self.Repeat_Task:
                    break

            except Exception as e:
                print(f"選擇錯誤: {e}", style="bold red")

    def Select(
        self,
        Copy: bool = True,
        Repeat: bool = False,
        ReSelect: bool = False,
        SaveOpen: bool = False,
        AddSource: bool = False,
        CreateTypeFolder: bool = True,
    ):
        """
        選擇輸出類型文件

        1. Copy: 是否使用複製, 否則使用移動
        2. Repeat: 是否重複選擇其他文件類型
        3. ReSelect: 是否在輸出完成後, 重新選擇來源路徑
        3. SaveOpen: 是否自動開啟輸出存檔路徑
        4. AddSource: 輸出檔名是否要含有來源路徑
        5. CreateTypeFolder: 是否創建類型資料夾, 作為輸出路徑
        """

        # 賦予數據
        self.Copy_Mode = Copy
        self.Auto_Open = SaveOpen
        self.Repeat_Task = Repeat
        self.Attach_Source = AddSource
        self.Type_Folder = CreateTypeFolder
        self.Task_Work = self.Copy_Output if self.Copy_Mode else self.Move_Output  # 選擇任務模式

        while True:
            Default_Choose = None  # 預設選擇類型
            File_Type, Type_Quantity = self.Analysis()  # 獲取解析數據

            if len(File_Type) > 1:  # 如果有多檔案類型才建立選擇
                # 展示用數據建立
                Show_Table = []
                Show_Table.append(["[0]", "ALL", f"{len(self.Complete_Data)}"])

                # Key = 類型, Value = 對應數量
                Sort_Cache = {Type: Type_Quantity[Type] for Type in File_Type}

                # 使用數量由大到小排序
                self.Task_List = sorted(Sort_Cache.items(), key=itemgetter(1), reverse=True)
                for Index, (Type, Count) in enumerate(self.Task_List):
                    Show_Table.append([f"[{Index + 1}]", Type, Count])

                # 顯示選擇
                print("{:<6} {:<8} {}".format("代號", "檔案類型", "類型數量"), style="bold magenta")
                for Row in Show_Table:
                    print("{:<10} {:<12} {}".format(Row[0], Row[1], Row[2]), style="bold yellow")
            else:
                Default_Choose = 1
                self.Task_List = [[File_Type.pop()]]

            self.__Choose(Default_Choose)
            if not ReSelect:
                break

        self.destroy()  # 結束後消除視窗


if __name__ == "__main__":
    TypeSelection().Select(True)
