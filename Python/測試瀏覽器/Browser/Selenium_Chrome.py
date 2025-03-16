import os
import time
import random
import shutil
import importlib
import threading
import subprocess


# 檢查使用庫
def Library_installation_detection(lib):
    try:
        importlib.import_module(lib)
    except:
        subprocess.check_call(["pip", "install", lib])


for check in ["selenium"]:
    Library_installation_detection(check)

from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.support.ui import WebDriverWait


class Settings:
    def __init__(self) -> None:
        self.CachePath = "R:/SeleniumCache"  # 緩存路徑
        self.Chrome = Options()
        self.Generate_Port = []
        self.Port = 1024

    def RandomPort(self) -> int:
        port = random.randint(self.Port, 65535)
        if port not in self.Generate_Port:
            self.Generate_Port.append(port)
            return port
        else:
            return self.RandomPort()

    def Option(self) -> object:
        self.Chrome.add_argument("--log-level=3")
        self.Chrome.add_argument("--start-maximized")
        self.Chrome.add_argument("--disable-geolocation")
        self.Chrome.add_argument("--disable-file-system")
        self.Chrome.add_argument("--disable-notifications")
        self.Chrome.add_argument("--disable-popup-blocking")
        self.Chrome.add_argument("--password-store=disabled")
        self.Chrome.add_argument("--no-default-browser-check")
        self.Chrome.add_argument(f"--user-data-dir={self.CachePath}")
        self.Chrome.add_argument("--safebrowsing-disable-download-protection")
        self.Chrome.add_argument(f"--remote-debugging-port={self.RandomPort()}")
        self.Chrome.add_argument(
            "user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36"
        )

        self.Chrome.add_experimental_option("useAutomationExtension", False)
        self.Chrome.add_experimental_option("excludeSwitches", ["enable-logging"])
        self.Chrome.add_experimental_option("excludeSwitches", ["enable-automation"])
        return self.Chrome


class Browser(Settings):
    __version__ = "1.0.3"

    def __init__(self) -> None:
        super().__init__()
        self.Driver = None

    def LoadWait(self):
        WebDriverWait(self.Driver, 10).until(
            lambda driver: driver.execute_script("return document.readyState")
            == "complete"
        )

    def Enable_Browsing(
        self, Url: str = "https://www.google.com.tw/", UserDat: str = None
    ):
        if (
            UserDat
        ):  # 自訂緩存路徑 (可指定預設瀏覽器路徑: C:\Users\...\AppData\Local\Google\Chrome\User Data)
            self.CachePath = UserDat

        self.Driver = webdriver.Chrome(self.Option())

        self.Driver.delete_all_cookies()
        self.Driver.get(Url)
        self.LoadWait()
        self.Driver.execute_script(
            'Object.defineProperty(navigator, "webdriver", {get: () => undefined})'
        )

        os.system("cls")
        print(f"{self.__version__} Selenium 瀏覽器啟動完成...")
        threading.Thread(target=self.Detection).start()

        return self.Driver

    def Detection(self):
        try:
            while self.Driver.window_handles:
                time.sleep(3)
        except:
            self.Driver.quit()

            # 避免錯誤清除 (路徑中包含 cache 字樣的路徑)
            if "cache" in self.CachePath.lower():
                shutil.rmtree(self.CachePath)
                print("緩存數據已清除")
        finally:
            os._exit(0)