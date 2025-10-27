import os
import time
import shutil
import random
import threading
import importlib
import subprocess


# 檢查使用庫
def Library_installation_detection(lib):
    try:
        importlib.import_module(lib)
    except:
        subprocess.check_call(["pip", "install", lib])


for check in ["selenium", "undetected_chromedriver"]:
    Library_installation_detection(check)

import undetected_chromedriver as uc
from selenium.webdriver.support.ui import WebDriverWait


class Chrome(uc.Chrome):
    def __del__(self):
        try:
            self.service.process.kill()
        except:
            pass


class TestBrowser:
    __version__ = "1.0.1"

    def __init__(self):
        self.Driver = None
        self.DriverPath = rf"{os.path.dirname(os.path.abspath(__file__))}\driver\chromedriver.exe"
        self.CachePath = "R:/UndetectedCache"
        self.Chrome = uc.ChromeOptions()

    def LoadWait(self):
        WebDriverWait(self.Driver, 10).until(
            lambda driver: driver.execute_script("return document.readyState") == "complete"
        )

    def Options(self):
        self.Chrome.add_argument("--lang=en-US")
        self.Chrome.add_argument("--log-level=3")
        self.Chrome.add_argument("--no-first-run")
        self.Chrome.add_argument("--start-maximized")
        self.Chrome.add_argument("--disable-infobars")
        self.Chrome.add_argument("--no-service-autorun")
        self.Chrome.add_argument("--disable-file-system")
        self.Chrome.add_argument("--disable-geolocation")
        self.Chrome.add_argument("--disable-web-security")
        self.Chrome.add_argument("--disable-notifications")
        self.Chrome.add_argument("--disable-popup-blocking")
        self.Chrome.add_argument("--password-store=disabled")
        self.Chrome.add_argument("--no-default-browser-check")
        self.Chrome.add_argument("--profile-directory=Default")
        self.Chrome.add_argument("--disable-site-isolation-trials")
        self.Chrome.add_argument("--allow-running-insecure-content")
        self.Chrome.add_argument(f"--user-data-dir={self.CachePath}")
        self.Chrome.add_argument("--disable-blink-features=AutomationControlled")
        self.Chrome.add_argument(f"--remote-debugging-port={random.randint(1024, 65535)}")

        self.Chrome.headless = False
        return self.Chrome

    def Enable_browsing(self, url: str = "https://www.google.com.tw/", UserDate: str = None):
        if UserDate:
            self.CachePath = UserDate

        self.Driver = Chrome(
            version_main=142,
            advanced_elements=True,
            options=self.Options(),
            driver_executable_path=self.DriverPath,
        )

        self.Driver.delete_all_cookies()
        self.Driver.get(url)
        self.LoadWait()
        self.Driver.execute_script(
            'Object.defineProperty(navigator, "webdriver", {get: () => undefined})'
        )

        os.system("cls")
        print(f"{self.__version__} Undetected 瀏覽器啟動完成...")
        threading.Thread(target=self.Detection).start()

        return self.Driver

    def Detection(self):
        try:
            while self.Driver.window_handles:
                time.sleep(3)
        except:
            self.Driver.quit()

            if "cache" in self.CachePath.lower():
                shutil.rmtree(self.CachePath)
                print("緩存數據已清除")
        finally:
            os._exit(0)
