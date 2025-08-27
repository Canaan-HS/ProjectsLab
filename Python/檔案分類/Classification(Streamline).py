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

""" Versions 1.0.5 - V2

    Todo - 精簡版檔案類型分類

        ? (開發/運行環境):
        * Windows 11 24H2
        * Python 3.13.5 64-bit

        * 第三方庫:
        * tqdm
        * progressbar

        * 個人模塊:
        * utils

        ? 使用說明:
        * 運行前可調整 select() 的參數, 參數說明於下方函數
        * 運行後選擇需分類檔案的 資料夾
        * 接著根據顯示的代號, 輸入代號選擇檔案類型 (如果只有一個類型會自動選擇)
        * 最後會以 (複製 or 移動) [可選的] 方式輸出, 輸出路徑在選擇的資料夾內部
        * 輸出的速度取決於硬碟讀寫速度
"""

console = Console()


def print(*args, **kwargs):
    console.print(*args, **kwargs)


class ReadFolder(tk.Tk):
    def __init__(self):
        super().__init__()
        self.folder_path = None
        self.complete_data = None

        self.withdraw()  # 隱藏主視窗
        self.attributes("-topmost", True)  # 置頂主視窗

    # 選擇開啟資料夾
    def __open_folder(self):
        self.folder_path = filedialog.askdirectory(title="選擇資料夾", parent=self)

        if self.folder_path:
            return self.__read_all_files()
        else:
            print("選擇取消", style="bold red")
            os._exit(0)

    def __read_all_files(self):
        # 保存選擇資料夾後讀取的所有數據
        Read_Data = {}

        for Root, _, Files in os.walk(self.folder_path):  # 路徑 , 資料夾 , 檔名
            Read_Data[Root] = Files

        return Read_Data

    # 獲取資料夾分類數據
    def get_folder_groups(self, path=None):

        self.folder_path = path  # 可直接給予測試用路徑
        data = self.__read_all_files() if path else self.__open_folder()

        # 緩存處理擴展名
        file_extension = None
        # 保存所有檔案類型 用於顯示選擇
        file_type = set()
        # 保存所有檔案類型 用於計算數量
        type_quantity = []
        # 保存所有檔案數據
        complete_data = []

        for path, filebox in data.items():
            if len(filebox) != 0:  # 當他是 0 帶表示空資料夾
                for name in filebox:
                    try:
                        file_extension = name.rsplit(".", 1)[1].strip()
                    except Exception:  # 可能有例外
                        pass

                    try:
                        LowExtension = file_extension.lower()

                        file_type.add(LowExtension)
                        type_quantity.append(LowExtension)
                        complete_data.append(f"{path}/{name}".replace("\\", "/"))
                    except Exception:
                        print("無可分類檔案", style="bold red")
                        os._exit(0)

        self.complete_data = complete_data
        return file_type, Counter(type_quantity)


# 自訂例外
class DataEmptyError(Exception):
    pass


# 輸出
class OutputFile:
    def __init__(self):
        # 將變數都用這種方式初始化, 雖然不是很好 (難以單獨測試), 但是可以讓代碼看起來更整潔
        self.auto_open = None
        self.task_work = None
        self.attach_source = None

        self.save_path = None
        self.output_data = None
        self.move_output = lambda Source_Path, output_path: shutil.move(Source_Path, output_path)
        self.copy_output = lambda Source_Path, output_path: shutil.copyfile(
            Source_Path, output_path
        )

    # 複製處理
    def __Process_Task(self):
        record_output = set()  # 用於紀錄已輸出的文件, 避免重複輸出
        lock = threading.Lock()  # 線程鎖
        task_size = len(self.output_data)

        def process_start(copy_path):
            base_name = os.path.basename(copy_path)
            # 取得上一層資料夾名稱
            parent_path = os.path.basename(os.path.dirname(copy_path))

            if self.attach_source:
                output_path = os.path.join(self.save_path, f"[{parent_path}] {base_name}")
            else:
                output_path = os.path.join(self.save_path, base_name)

                # 使用鎖來保護共享的 record_output
                with lock:
                    if output_path in record_output:
                        # 當沒有設置來源時, 進行重複檢查, 重複的自動添加來源
                        output_path = os.path.join(self.save_path, f"{parent_path}_{base_name}")
                    else:
                        # 如果路徑不重複，使用它並記錄下來
                        record_output.add(output_path)

                # 執行實際任務
                self.task_work(copy_path, output_path)

        with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
            list(tqdm(executor.map(process_start, self.output_data), total=task_size))

        # 開啟存檔位置
        self.auto_open and os.startfile(self.save_path)

    # 創建數據
    def create_task(self):
        try:
            if len(self.output_data) == 0 or self.output_data is None:
                raise DataEmptyError()

            os.mkdir(self.save_path)  # 創建輸出資料夾
            self.__Process_Task()

        except DataEmptyError:
            print("該路徑下, 無可操作的文件", style="bold red")
        except Exception:
            self.__Process_Task()


class TypeSelection(ReadFolder, OutputFile):
    def __init__(self):
        ReadFolder.__init__(self)
        OutputFile.__init__(self)

    # 選擇輸出類型
    def __choose(self, select: None):

        # ! 懶得處理細節判斷
        # ! 使用 Repeat_Task 如果不是複製文件, 就不要選擇已經操作過的類型, 因為沒有根據選擇清理 Task_List, 重新選擇可能會導致找不到文件報錯
        while True:
            try:
                select_code = select or int(input("\n選擇輸出類型 (代號) : "))

                if select_code == 0:
                    print(f"你選擇了 : 全部\n", style="bold green")
                    selected = "ALL"

                    self.output_data = self.complete_data  # 將完整數據賦予給輸出數據
                else:
                    selected = self.task_list[select_code - 1][0]  # 根據索引取出選擇則字串

                    print(f"你選擇了 : {selected}\n", style="bold green")

                    # 檢查是否為 RPG Maker 加密圖片類型
                    if f".{selected.lower()}" in VALID_EXTENSIONS:

                        def rpg_restore_task(source_path, output_path):
                            # 將輸出的副檔名強制變更為 .png
                            output_path_base, _ = os.path.splitext(output_path)
                            png_output_path = output_path_base + ".png"

                            # 執行還原任務
                            Restore_RPG(
                                input_path=source_path,
                                output_path=png_output_path,
                                delete_original=not self.use_copy,  # 如果不是複製模式，就刪除原始檔案
                            )

                        # 將任務切換為 RPG 圖片還原
                        self.task_work = rpg_restore_task

                    # 根據選擇類型, 取出完整數據中符合該副檔名的文件
                    self.output_data = [
                        item for item in self.complete_data if item.endswith(f".{selected}")
                    ]

                # 生成保存路徑
                self.save_path = (
                    f"{self.folder_path}/{os.path.basename(self.folder_path)} ({selected})"
                    if self.use_type_folder
                    else self.folder_path
                )

                # 創建輸出任務
                self.create_task()

                # 非重複選擇直接跳出
                if not self.repeat_task:
                    break

            except Exception as e:
                print(f"選擇錯誤: {e}", style="bold red")

    def select(
        self,
        copy: bool = True,
        repeat: bool = False,
        reSelect: bool = False,
        saveOpen: bool = False,
        addSource: bool = False,
        createTypeFolder: bool = True,
    ):
        """
        選擇輸出類型文件

        1. copy: 是否使用複製, 否則使用移動
        2. repeat: 是否重複選擇其他文件類型
        3. reSelect: 是否在輸出完成後, 重新選擇來源路徑
        3. saveOpen: 是否自動開啟輸出存檔路徑
        4. addSource: 輸出檔名是否要含有來源路徑
        5. createTypeFolder: 是否創建類型資料夾, 作為輸出路徑
        """

        # 賦予數據
        self.use_copy = copy
        self.auto_open = saveOpen
        self.repeat_task = repeat
        self.attach_source = addSource
        self.use_type_folder = createTypeFolder
        self.task_work = self.copy_output if self.use_copy else self.move_output  # 選擇任務模式

        while True:
            default_choose = None  # 預設選擇類型
            file_type, type_quantity = self.get_folder_groups()

            type_len = len(file_type)
            print(f"選擇路徑: {self.folder_path}\n", style="bold")

            if type_len > 1:  # 如果有多檔案類型才建立選擇
                # 展示用數據建立
                show_table = []
                show_table.append(["[0]", "ALL", f"{len(self.complete_data)}"])

                # Key = 類型, Value = 對應數量
                sort_cache = {Type: type_quantity[Type] for Type in file_type}

                # 使用數量由大到小排序
                self.task_list = sorted(sort_cache.items(), key=itemgetter(1), reverse=True)
                for Index, (Type, Count) in enumerate(self.task_list):
                    show_table.append([f"[{Index + 1}]", Type, Count])

                # 顯示選擇
                print("{:<6} {:<8} {}".format("代號", "檔案類型", "類型數量"), style="bold magenta")
                for row in show_table:
                    print("{:<10} {:<12} {}".format(row[0], row[1], row[2]), style="bold yellow")
            elif type_len == 1:
                default_choose = 1
                self.task_list = [[file_type.pop()]]
            else:
                print("無可分類檔案", style="bold red")
                continue

            self.__choose(default_choose)
            if not reSelect:
                break

        self.destroy()  # 結束後消除視窗


if __name__ == "__main__":
    TypeSelection().select(True)
