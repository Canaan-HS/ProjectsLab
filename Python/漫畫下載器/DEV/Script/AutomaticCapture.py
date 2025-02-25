from playsound import playsound
import pyperclip
import threading
import keyboard
import queue
import time
import os
import re

class AutomaticCapture:
    def __init__(self):
        self.sound = f"{os.path.dirname(os.path.abspath(__file__))}\\Effects\\notify.wav"
        self.UrlFormat = re.compile(r'^(?:http|ftp)s?://')

        self.match_url = None
        self.intercept_delay = None

        self.clipboard_cache = None
        self.download_list = set()
        self.queue = queue.Queue()

        self.generate_type = False
        self.return_type = False
        self.detection = True
        self.count = 0
        
    def __verifica(self):
        if self.match_url != None:
            return True
        else:
            print("請先使用 settings(domainName) 設置域名")

    def __trigger(self):
        print("複製網址後自動擷取(Alt+S 開始下載):")
        clipboard = threading.Thread(target=self.__Read_clipboard)
        command = threading.Thread(target=self.__Download_command)

        clipboard.start()
        command.start()

        command.join()
        clipboard.join()
        
    def __return_trigger(self):
        print("複製網址後立即下載:")
        self.return_type = True
        threading.Thread(target=self.__Read_clipboard).start()

    def __generate_trigger(self):
        print("自動監聽剪貼簿觸發下載(只能手動停止程式):")
        self.generate_type = True
        threading.Thread(target=self.__Read_clipboard).start()

    def __Read_clipboard(self):
        pyperclip.copy('')

        while self.detection:
            clipboard = pyperclip.paste()

            if clipboard != self.clipboard_cache and self.match_url.match(clipboard):
                self.count += 1
                print(f"擷取網址 [{self.count}] : {clipboard}")
                self.download_list.add(clipboard)
                self.clipboard_cache = clipboard

                if self.generate_type:
                    self.queue.put(clipboard)
                elif self.return_type:
                    self.queue.put(clipboard)
                    break

                # try:playsound(self.sound)
                # except:pass

            time.sleep(self.intercept_delay)

    def __Download_command(self):
        keyboard.wait("alt+s")
        self.detection = False

    def settings(self, domainName:str, delay=0.05):
        try:
            if self.UrlFormat.match(domainName):
                self.match_url = re.compile(rf"{domainName}.*")
                self.intercept_delay = delay
            else:
                raise Exception()
        except:
            print("錯誤的網址格式")

    # 以list回傳所有擷取的網址
    def GetList(self):
        if self.__verifica():
            self.__trigger()

            if len(self.download_list) > 0:
                os.system("cls")
                return list(self.download_list)
            else:
                return None

    # 只會回傳一條網址 , 擷取多條就只回傳第一條
    def GetLink(self):
        if self.__verifica():
            self.__return_trigger()
            while True:
                if not self.queue.empty():
                    return self.queue.get()
                time.sleep(0.1)

    # 以生成器的方式回傳
    def GetBuilder(self):
        if self.__verifica():
            self.__trigger()

            if len(self.download_list) > 0:
                os.system("cls")
                for link in list(self.download_list):
                    yield link
            else:
                return None

    # 特別的擷取方法
    def Unlimited(self):
        """
        這是一個無限擷取的函數 , 沒有快捷停止 , 只能手動中止程式
        * 使用方法 :
        * 使用一個迴圈接受此方法的回傳參數 , 並進行後續的處理
        """
        if self.__verifica():
            self.__generate_trigger()
            while True:
                if not self.queue.empty():
                    url = self.queue.get()
                    yield url
                time.sleep(0.1)

AutoCapture = AutomaticCapture()