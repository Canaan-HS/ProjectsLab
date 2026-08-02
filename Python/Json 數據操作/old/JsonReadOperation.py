import os
import json
import time
import webbrowser

from pathlib import Path


class ReadJson:
    def __init__(self):
        os.chdir(Path(__file__).resolve().parent)
        self.json_name = None
        self.json_data = None

        self.json_operation_a = {}
        self.json_operation_b = {}
        self.json_special = []

        self.operation_pass = True
        self.stop_line = None
        self.calculate = 0

    def __read_json(self):
        try:
            self.json_data = json.loads(Path(self.json_name).read_text(encoding="utf-8"))
            return True
        except:
            print("找不到設置的 Json 文件")
            return False

    def open_url(self, json_name: str, stop_line: int, location: int = 0, output: bool = False):
        """
        讀取 Json 值中的 URL , 並開啟網址的方法
        * json_name 設置要開啟的 Json 檔全名 例 : Test.json
        * stop_line 設置 10 就是開啟 10 個停止一次
        * location 設置 0 使用 Key 值開啟 , 1 使用 Value 值開啟
        * output 設置是否運行完畢 , 將剩下未開啟的網址進行輸出 , 如果沒有未開啟的網址了 , 就會直接刪除該 Json 檔案
        """
        try:

            if location < 0 or location > 1:
                raise ValueError()

            self.json_name = json_name
            self.stop_line = stop_line

            state = self.__read_json()

            if state:
                amount = len(self.json_data)
                print(amount)

                for key, value in self.json_data.items():
                    if self.operation_pass:
                        if self.calculate == self.stop_line:

                            self.calculate = 0
                            amount -= self.stop_line

                            n = input(f"按下Enter繼續測試 [剩餘:{amount}] [輸入 0 結束] : ")
                            if n == "0":
                                self.operation_pass = False
                        else:
                            webbrowser.open(key if location == 0 else value)
                            time.sleep(0.3)

                        self.calculate += 1
                    else:
                        self.json_operation_a[key] = value

                if output:
                    self.__output_delete(self.json_operation_a)

        except ValueError:
            print("location 只有 0 和 1")

    def cookie_parsing(self, json_name: str, show_dict: bool = False, output: bool = False):
        """
        讀取 Json 格式的 Cookie , 並分類出有用的部份
        * json_name 設置要開啟的 Json 檔全名 例 : Test.json
        * show_dict 解析後以字典打印
        * output 將轉換成功的字典輸出
        """
        self.json_name = json_name
        state = self.__read_json()

        if state:

            for cookie in self.json_data:
                name = cookie["name"]
                value = cookie["value"]
                self.json_operation_a[name] = value

            if show_dict:
                print(self.json_operation_a)

            if output:
                self.__output(self.json_operation_a)

    def cookie_parsing_2(self, json_name: str, show_dict: bool = False, output: bool = False):
        """
        讀取 Json 格式的 Cookie , 保留原數據格式解析方法
        * json_name 設置要開啟的 Json 檔全名 例 : Test.json
        * show_dict 解析後以字典打印
        * output 將轉換成功的字典輸出
        """
        self.json_name = json_name
        state = self.__read_json()

        if state:

            for cookie in self.json_data:
                special_dict = {}
                special_dict["name"] = cookie["name"]
                special_dict["value"] = cookie["value"]
                self.json_special.append(special_dict)

            if show_dict:
                print(self.json_special)

            if output:
                self.__output(self.json_special)

    def json_to_txt(self, json_name: str, location: int = 0, delete: bool = False):
        """
        將 Json 檔 Key 或 Value 的值 , 變成 txt 文字輸出
        * json_name 設置要開啟的 Json 檔全名 例 : Test.json
        * location 設置轉換的值 [0 使用 Key , 1 使用 Value , 2 使用全部]
        * delete 是否將原始的 Json 檔案刪除
        """
        try:
            if location < 0 or location > 2:
                raise ValueError()

            self.json_name = json_name
            state = self.__read_json()

            if state:
                output_path = Path(self.json_name.replace(".json", ".txt"))
                output_data = []

                for key, value in self.json_data.items():
                    if location == 0:
                        output_data.append(key)
                    elif location == 1:
                        output_data.append(value)
                    elif location == 2:
                        output_data.append(f"[{key}] : [{value}]")

                output_path.write_text("\n".join(output_data), encoding="utf-8")

                if delete:
                    Path(self.json_name).unlink(missing_ok=True)
                    print(f"已刪除 {self.json_name}")
                print("輸出完成...")

        except ValueError:
            print("location 範圍 0 ~ 2")

    def json_str_split(
        self,
        json_name: str,
        location: int = 0,
        split: list = [],
        filter_mode: bool = False,
        delete: bool = False,
    ):
        """
        [此方法是以含有指定類型的文字進行分割]
        將 Json 檔 Key 或 Value 的值 , 作為判斷的基準 , 根據 split 參數進行分割
        * json_name 設置要開啟的 Json 檔全名 例 : Test.json
        * location 設置轉換的值 [0 使用 Key , 1 使用 Value]
        * split 設置要分割的 list , 會找出含有該 list 內字串的項目進行分割
        * filter_mode 過濾模式 , 啟用後就不是分割 , 而是過濾掉設置的 split 項目
        * delete 是否將原始的 Json 檔案刪除
        """
        try:
            if location < 0 or location > 1:
                raise ValueError()

            if not isinstance(split, list):
                raise TypeError()

            self.json_name = json_name
            state = self.__read_json()

            if state:
                judge_str = None
                for key, value in self.json_data.items():
                    judge_bool = False

                    if location == 0:
                        judge_str = key
                    else:
                        judge_str = value

                    for sp in split:
                        if sp in judge_str:
                            judge_bool = True

                    if judge_bool:
                        self.json_operation_a[key] = value
                    else:
                        self.json_operation_b[key] = value

                if filter_mode:
                    self.__split_output(f"[Filter]_{json_name}", self.json_operation_b, delete)
                else:
                    self.__split_output(f"[ClassA]_{json_name}", self.json_operation_b, delete)
                    self.__split_output(f"[ClassB]_{json_name}", self.json_operation_a, delete)

        except ValueError:
            print("location 只有 0 和 1")
        except TypeError:
            print("split 請輸入 List 格式")

    def __output(self, data):
        if len(data) > 0:
            Path(self.json_name).write_text(
                json.dumps(data, indent=4, separators=(",", ":")),
                encoding="utf-8",
            )
            print("輸出完成...")

    def __output_delete(self, data):
        if len(data) > 0:
            Path(self.json_name).write_text(
                json.dumps(data, indent=4, separators=(",", ":")),
                encoding="utf-8",
            )
            print("輸出完成...")
        else:
            Path(self.json_name).unlink(missing_ok=True)
            print(f"已刪除 {self.json_name}")

    def __split_output(self, name, data, delete):
        Path(name).write_text(
            json.dumps(data, indent=4, separators=(",", ":")),
            encoding="utf-8",
        )
        print(f"{name} => 輸出完成")

        if delete:
            if Path(self.json_name).exists():
                Path(self.json_name).unlink(missing_ok=True)
                print(f"已刪除 {self.json_name}")


if __name__ == "__main__":
    rj = ReadJson()
    # 開啟網頁連結
    # rj.open_url("範圍401-999.json", 10, output=True)

    # 解析 cookie (只保留數值)
    # rj.cookie_parsing("Cookies.json", output=True)

    # 解析 cookie (保留 name 和 value 的值)
    # rj.cookie_parsing_2("Cookies.json", output=True)

    # 將 Json 文件內容轉成 txt
    # rj.json_to_txt("可用網址.json", delete=True)

    # 使用設置的分離文字 , 將原 Json 分離成 , 兩個 json
    # rj.json_str_split("#.json", 1, ["",""])
