from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.chrome.options import Options
from selenium import webdriver
import threading
import shutil
import random
import time
import os

class Settings:
    def __init__(self) -> None:
        self.CachePath = "R:/TestCache" #個人設置
        self.Options = Options()
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
        self.Options.add_argument("--log-level=3")
        self.Options.add_argument("--start-maximized")
        self.Options.add_argument("--disable-geolocation")
        self.Options.add_argument("--disable-file-system")
        self.Options.add_argument("--disable-notifications")
        self.Options.add_argument("--disable-popup-blocking")
        self.Options.add_argument("--password-store=disabled")
        self.Options.add_argument("--no-default-browser-check")
        self.Options.add_argument(f"--user-data-dir={self.CachePath}")
        self.Options.add_argument("--safebrowsing-disable-download-protection")
        self.Options.add_argument(f"--remote-debugging-port={self.RandomPort()}")
        self.Options.add_argument("user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36")

        self.Options.add_experimental_option("useAutomationExtension", False)
        self.Options.add_experimental_option("excludeSwitches", ["enable-logging"])
        self.Options.add_experimental_option("excludeSwitches", ["enable-automation"])
        return self.Options

class Browser(Settings):
    def __init__(self) -> None:
        super().__init__()
        self.Driver = None
        self.Version = lambda: "1.0.2"

    def LoadWait(self):
        WebDriverWait(self.Driver, 10).until(
            lambda driver: driver.execute_script("return document.readyState") == "complete"
        )

    def Enable_Browsing(self, Url:str ="https://www.google.com.tw/"):
        self.Driver = webdriver.Chrome(self.Option())
        self.Driver.get(Url)

        self.LoadWait()
        self.Driver.delete_all_cookies()
        self.Driver.execute_script('Object.defineProperty(navigator, "webdriver", {get: () => undefined})')
        
        os.system("cls")
        print(f"{self.Version()} 實驗瀏覽器啟動完成...")

        threading.Thread(target=self.Detection).start()
        return self.Driver

    def Detection(self):
        try:
            while self.Driver.window_handles:
                time.sleep(3)
        except:
            self.Driver.quit()
            shutil.rmtree(self.CachePath)
            print("實驗數據已清除")