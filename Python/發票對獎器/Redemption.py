import os
import json

# import time
import msvcrt

# import threading

from lxml import html
from curl_cffi import requests

from rich.table import Table
from rich.console import Console
from rich.progress import Progress, SpinnerColumn, TextColumn

# 複寫原生打印方式
console = Console()


def print(*args, **kwargs):
    console.print(*args, **kwargs)


class WinningInstructions:
    def __init__(self) -> None:
        self.reward_level = ["特別獎", "特獎", "頭獎", "二獎", "三獎", "四獎", "五獎", "六獎"]
        self.reward_conditions = [
            "8 碼相同獲得 1000 萬",
            "8 碼相同獲得 200 萬",
            "8 碼相同獲得 20 萬",
            "頭獎末 7 碼相同 4 萬",
            "頭獎末 6 碼相同 1 萬",
            "頭獎末 5 碼相同 4 千",
            "頭獎末 4 碼相同 1 千",
            "頭獎末 3 碼相同 200 元",
        ]
        self.prize_claim_period = {
            "1-2": "1-2 月份領獎期限為 4/6 ~ 7/5",
            "3-4": "3-4 月份領獎期限為 6/6 ~ 9/5",
            "5-6": "5-6 月份領獎期限為 8/6 ~ 11/5",
            "7-8": "7-8 月份領獎期限為 10/6 ~ 次年 1/5",
            "9-10": "9-10 月份領獎期限為 12/6 ~ 次年 3/5",
            "11-12": "11-12 月份領獎期限為次年 2/6 ~ 5/5",
        }


class DataProcessing:
    def __init__(self) -> None:
        self.redemption_data = None
        self.headers = {"Cache-Control": "no-cache"}
        self.session = requests.Session(
            impersonate="chrome120", raise_for_status=True, headers=self.headers
        )

    def __get_data(self, uri) -> html:
        try:
            data = self.session.get(uri)
            return html.fromstring(data.text)
        except Exception as e:
            os.system("cls")
            print("數據請求失敗\n")
            print(e, style="bold red")
            os._exit(1)

    def __get_number(self, element) -> list:
        numbers = element.cssselect(".etw-tbig tbody p.etw-tbiggest")[:5]
        return [el.text_content().strip() for el in numbers]

    def data_analysis(self, uri) -> None:
        link_Data = {}
        Url = uri.rsplit("/", 1)[0]
        element = self.__get_data(uri)

        for a in element.cssselect(".etw-submenu.etw-submenu01 li a[href$='.html']"):
            title = a.get("title")
            href = a.get("href")

            if href == "index.html":  # 最近期
                link_Data[1] = {"month": title, "number": self.__get_number(element)}

            elif href == "lastNumber.html":  # 上一期
                link_Data[2] = {
                    "month": title,
                    "number": self.__get_number(self.__get_data(f"{Url}/{href}")),
                }

        self.session.close()
        self.redemption_data = link_Data


class Comparison(DataProcessing, WinningInstructions):
    def __init__(self, uri) -> None:
        DataProcessing.__init__(self)
        WinningInstructions.__init__(self)

        self.uri = uri
        self.input = ""
        self.winning = {}

        # ? 原生實現變數
        # self.bar = "░" * 10
        # self.wait = "兌獎號碼獲取中 "
        # self.space = " " * (len(self.bar) * len(self.wait))

    def __Comparison_Date(self) -> None:
        print("\n")

        while True:
            if self.input == "":
                print("輸入發票末三碼 [Esc 停止]: ", end="", style="yellow")

            Input = msvcrt.getch().decode()
            if Input == "\x1b":
                print("停止", end="")
                break
            else:
                print(Input, end="")

            try:
                self.input += Input
                if len(self.input) >= 3:
                    print("\n")

                    if self.input.lower() == "dev":
                        print(
                            f"{json.dumps(self.winning, indent=4, ensure_ascii=False)}\n",
                            style="bold bright_cyan",
                        )

                    elif not self.input.isnumeric():
                        self.input = ""
                        raise ValueError()

                    else:
                        winning = self.winning.get(self.input)
                        if winning is not None:
                            if winning["level"] == "頭獎":
                                print(
                                    f"中獎了!! 自行確認中獎等級 ({winning['level']}): {winning['number']}\n",
                                    style="bold green",
                                )
                            else:
                                print(
                                    f"自行確認是否中獎 ({winning['level']}): {winning['number']}\n",
                                    style="bold green",
                                )

                    self.input = ""

            except ValueError:
                print("錯誤輸入類型 !!\n")
            except Exception:
                print(f"幹啥呢 !!\n")
                break

    def __Select_Date(self) -> None:
        """(原生進度條實現)
        threading.Thread(target=self.data_analysis, args=(self.uri,)).start()
        while self.redemption_data is None:
            print(self.wait, end="")

            for bar in self.bar:
                if self.redemption_data is not None: break
                print(bar, end="", flush=True)
                time.sleep(0.1)

            print(f"\r{self.space}\r", end="")
        """

        with Progress(
            SpinnerColumn(), TextColumn("[progress.description]{task.description}")
        ) as progress:
            task = progress.add_task("取得數據中...", start=False)
            self.data_analysis(self.uri)
            progress.stop_task(task)

        os.system("cls")

        select_table = Table()
        select_table.add_column("代號", justify="center", style="bold bright_red")
        select_table.add_column("日期", justify="center", style="bold bright_yellow")

        for index, data in self.redemption_data.items():
            select_table.add_row(str(index), data["month"])
        print(select_table)

        display_table = Table()
        while True:
            try:
                print("\n輸入[代號]選擇日期: ", end="", style="bold green")
                select = self.redemption_data.get(  # 取得對應 Key 值
                    int(msvcrt.getch().decode())  # 讀取數字輸入
                )

                if select is None:
                    print("\n錯誤的代號, 請重新選擇", style="bold red")
                else:
                    os.system("cls")

                    # ! 如需要根據選取月份, 顯示兌換日期, 需要解析此處選擇的 month
                    display_table.add_column(select["month"], justify="center", style="bold")
                    data = select["number"]

                    # 將數據列表解析為字典 (測試以下寫法 比列導式快一些, 雖然列導式更簡潔) [Key 值為末三碼]
                    for index, number in enumerate(data[:2]):  # 這個為, 特別獎, 特獎
                        self.winning[number[-3:]] = {
                            "level": self.reward_level[index],
                            "number": number,
                        }
                    for number in data[2:]:  # 這個都是 頭獎
                        self.winning[number[-3:]] = {
                            "level": self.reward_level[2],
                            "number": number,
                        }

                    break

            except ValueError:
                print("\n代號為數字, 請重新選擇", style="bold red")

        for i in range(0, 8):  # 顯示 獎勵等級, 獎勵條件
            display_table.add_row(self.reward_level[i], self.reward_conditions[i])
        print(display_table)

        self.__Comparison_Date()

    def __call__(self):
        self.__Select_Date()


if __name__ == "__main__":
    Comparison("https://invoice.etax.nat.gov.tw/")()
