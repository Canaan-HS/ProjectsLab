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
        self.url_template = re.compile(r"^(?:http|ftp)s?://")

        self.match_url = None
        self.intercept_delay = None

        self.count = 0
        self.save_type = None

        self.clip_set = set()
        self.queue = queue.Queue()

        self.on_clip = True
        self.off_token = False
        self.clip_cache = None

    def __verifica(self):
        if self.match_url is not None:
            return True
        else:
            print("請先使用 settings(domainName) 設置域名")

    def __hotkey_trigger(self):
        print("監聽剪貼簿 (Alt + S 觸發):")

        self.save_type = "set"
        clip_task = threading.Thread(target=self.__read_clipboard)
        monitor_hotkey = threading.Thread(target=self.__hotkey)

        clip_task.start()
        monitor_hotkey.start()

        monitor_hotkey.join()
        clip_task.join()

    def __now_trigger(self):
        print("複製網址後立即觸發:")

        self.save_type = "queue"
        self.off_token = True
        threading.Thread(target=self.__read_clipboard).start()

    def __lasting_trigger(self):
        print("持續監聽剪貼簿並自動觸發 (手動停止程式):")

        self.save_type = "queue"
        threading.Thread(target=self.__read_clipboard).start()

    def __read_clipboard(self):
        pyperclip.copy("")

        while self.on_clip:
            clip = pyperclip.paste()

            if clip != self.clip_cache and self.match_url.match(clip):
                self.count += 1
                print(f"擷取網址 [{self.count}] : {clip}")
                self.clip_cache = clip

                if self.save_type == "set":
                    self.clip_set.add(clip)
                elif self.save_type == "queue":
                    self.queue.put(clip)

                    if self.off_token:
                        break

            time.sleep(self.intercept_delay)

    def __hotkey(self):
        keyboard.wait("alt+s")
        self.on_clip = False

    def settings(self, domainName: str, delay=0.3):
        try:
            if self.url_template.match(domainName):
                self.match_url = re.compile(rf"{domainName}.*")
                self.intercept_delay = delay
            else:
                raise Exception()
        except:
            print("錯誤的網址格式")

    # 以list回傳所有擷取的網址
    def get_list(self):
        if self.__verifica():
            self.__hotkey_trigger()

            if len(self.clip_set) > 0:
                os.system("cls")
                return list(self.clip_set)
            else:
                return None

    # 只會回傳一條網址 , 擷取多條就只回傳第一條
    def get_link(self):
        if self.__verifica():
            self.__now_trigger()

            while True:
                if not self.queue.empty():
                    return self.queue.get()
                time.sleep(0.1)

    # 以生成器的方式回傳
    def get_builder(self):
        if self.__verifica():
            self.__hotkey_trigger()

            if len(self.clip_set) > 0:
                os.system("cls")
                for link in list(self.clip_set):
                    yield link
            else:
                yield None

    # 特別的擷取方法
    def unlimited(self):
        """
        這是一個無限擷取的函數 , 沒有快捷停止 , 只能手動中止程式
        * 使用方法 :
        * 使用一個迴圈接受此方法的回傳參數 , 並進行後續的處理
        """
        if self.__verifica():
            self.__lasting_trigger()

            while True:
                if not self.queue.empty():
                    url = self.queue.get()
                    yield url


capture = AutomaticCapture()
