from ..測試版本.Script import AutoCapture, Get
from collections import OrderedDict
from concurrent.futures import *
from multiprocessing import *
import multiprocessing
from lxml import etree
from tqdm import tqdm
import requests
import aiohttp
import asyncio
import math
import time
import json
import re
import os

""" Versions 1.0.4 ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    Todo - EHentai/ExHentai 漫畫下載

        * 功能概述 :
        ? 可下載 EHentai 和 ExHentai , 下載 Ex 需要設置 cookie
        ? cookie 有代碼中設置 Set() 和 json 讀取 Read()
        ? 目前只支援漫畫頁面的下載 , 搜尋頁面的不支援
        ? 呼叫下載有兩種方式 , google() , edge() , 用於模擬不同瀏覽器請求

        * 需求配置 :
        ? Python 版本 3.11.3 - 64 位元
        ? 需求模塊 去下載 Python包安裝.bat 運行
        ? 還有 AutomaticCapture , GetCookiesAutomatically
        ? 這兩個是在此目錄的 Script 資料夾中的如沒有 , 某些功能會失效
        ? 最好 Cookie , Exclude , Script 這三個資料夾都要有
        
    ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    Todo - 使用說明

        * 此版本以廢置, 無依賴項目下, 無法正常運行
"""

#Todo [手動獲取Cookie , 並回傳結果]
def cookie_get():
    return Get.MGCookie("https://e-hentai.org/" , f"{os.path.dirname(os.path.abspath(__file__))}\\Cookie\\EHCookies")

class Set:
    """
    Set 類別 (手動設置)
    * [使用方式]
    * 在需要使用該數據的部份呼叫 Set()
    * 然後輸入 "cookie" 或 "filter" -> Set("cookie")
    * 就可以取得設置的字典數據
    """
    def __init__(self):
        #Todo [ 基本上只有請求 Ex 時需要設置 ]
        self.Cookies = {
            "igneous":"",
            "ipb_member_id":"",
            "ipb_pass_hash":""
        }
        #Todo [手動設置排除標籤 , 並可於 download_settings() 套用回傳結果 , 設置詳情於 download_settings() 說明]
        self.TagExclude = {
            "Tags": [""]
        }

    def __call__(self, Type: str):
        if Type.lower() == "cookie":
            return self.Cookies
        elif Type.lower() == "filter":
            return self.TagExclude
Set = Set()

class Read:
    """
    Read 類別 (自動讀取Json)
    * [使用方式]
    * 在需要使用該數據的部份呼叫 Read()
    * 然後輸入 "cookie" 或 "filter" -> Read("cookie")
    * 就可以取得設置的字典數據
    * 如沒有該數據 , 就會進行創建
    """
    def __init__(self):
        self.Cookies_Path = "./Cookie/EHCookies.json"
        self.Exclude_Path = "./Exclude/EHFilter.json"
        self.Open_Path = None
        self.Create_Format = {}
        self.Create_Path = None

    def Create(self, Type: str):
        if Type.lower() == "cookie":
            self.Create_Format = {
                "cf_clearance":"Please fill in the cookie"
            }
        elif Type.lower() == "filter":
            #Todo [用於排除Tag類型字典]
            self.Create_Format = {
                "Tags": ["Please enter Tag","Please enter Tag"],
            }

        with open(self.Open_Path , "w") as file:
            file.write(json.dumps(self.Create_Format, indent=4, separators=(',',':')))

    def __call__(self,Type: str):
        if Type.lower() == "cookie":
            self.Open_Path = self.Cookies_Path
        elif Type.lower() == "filter":
            self.Open_Path = self.Exclude_Path
            
        try:
            with open(self.Open_Path , "r") as file:
                return json.loads(file.read())
        except:
            self.Create(Type)
Read = Read()

#Todo [數據請求回傳]
class DataRequest:
    Session = requests.Session()
    Google_Headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Safari/537.36"}
    Edge_Headers = {"user-agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Safari/537.36 Edg/116.0.1938.54"}
    Cookies = None
    Headers = None

    def get_data(self, url):
        request = self.Session.get(url, headers=self.Headers, cookies=self.Cookies, timeout=3)
        return etree.HTML(request.text)
    
    async def async_get_data(self, url, session):
        async with session.get(url, headers=self.Headers, cookies=self.Cookies) as response:
            content = await response.text()
            return etree.HTML(content)

#Todo [連結驗證與分類]
class Validation(DataRequest):
    Ex_HManga = r"https://exhentai.org/g/\d+/[a-zA-Z0-9]+/"
    E_HManga = r"https://e-hentai.org/g/\d+/[a-zA-Z0-9]+/"
    GetCookie = None
    category = []
    save_box = []

    # 驗證是否請求到網站數據
    def Request_Status(self, domain: str):
        url = None
        if domain == "E":
            url = "https://e-hentai.org/"
        elif domain == "Ex":
            url = "https://exhentai.org/"

        try:
            teee = self.get_data(url)
            teee.xpath("//div[@class='searchtext']/p/text()")
            return True
        except:
            if self.GetCookie:
                print(f"驗證錯誤請稍後...")
                if cookie_get():
                    print("\n獲取成功!\n")
                    self.Cookies = Read("cookie")
                    return True
                else:
                    print("\n獲取失敗!\n")
                    return False
            else:
                return False
            
    def ReSet(self):
        pass

    # 網址的分類
    def URL_Classification(self, link):
        try:
            # 格式判斷
            if isinstance(link,str):
                self.category.append(link)
            elif isinstance(link,list):
                self.category = link
            else:
                raise ValueError()

            # 支援類型匹配
            request_type = "E" # 預設的請求類型是 E
            for url in self.category:

                if re.match(self.E_HManga, url):
                    self.save_box.append(url)

                elif re.match(self.Ex_HManga, url):
                    self.save_box.append(url)

                    if request_type == "E":
                        request_type = "Ex"

                else:
                    print(f"不支援的網址格式 : {url}")

            if len(self.save_box) > 0: # 驗證請求狀態
                if self.Request_Status(request_type):
                    return self.save_box
                else:
                    raise TypeError()
                
        except TypeError:
            print("請更換 Cookie , 或檢查使用的請求瀏覽器")
            os._exit(1)
        except ValueError as e:
            print(f"錯誤的輸入格式\n錯誤碼 : {e}")
            os._exit(1)

#Todo [主要下載邏輯]
class EHentaidownloader(Validation):
    def __init__(self):
        # super().__init__()
        os.chdir(os.path.dirname(os.path.abspath(__file__)))
        self.illegal_filename = r'[<>:"/\\|?*]'
        #Todo => 判斷是否自訂設置
        self.SetUse = False
        #Todo => 下載設置項目
        self.path = None
        self.MaxProcess = None
        self.ProcessDelay = None
        self.TagFilterBox = None
        self.ProtectionDelay = None
        #Todo => 數據保存
        self.title = None
        self.save_location = None
        self.picture_link_data = {}
        self.TV = 0

    def download_settings(
        self,
        GetCookie: bool=False,
        DownloadPath: str=os.path.dirname(os.path.abspath(__file__)),
        DownloadDelay =0.3,
        ProcessCreationDelay =1,
        MaxConcurrentDownload: int=cpu_count(),
        FilterTags: dict=None,
        CookieSource: dict=Set("cookie"),
    ):
        """
        * 下載設置

        >>> [ GetCookie (預設: False) ]

        * 啟用後當請求失敗時 , 會開啟網頁登入窗口
        * 登入後確認 , 可自動取得 cookie , 保存成 json

        >>> [ DownloadPath (預設: 當前代碼路徑) ]

        * 設置下載位置

        >>> [ DownloadDelay (預設: 0.3) ]

        * 設置下載圖片時的延遲
        * 用於保護伺服器 , 和避免請求過快
        * 短時間請求過快 , 會被 Ban IP

        >>> [ ProcessCreationDelay (預設: 1) ]

        * 開始處理下載數據時的 , 進程創建延遲
        * 同樣也是保護伺服器 , 和避免被 Ban

        >>> [ MaxConcurrentDownload (預設: 自身 cpu 核心數) ]

        * 最大的併發處理數
        * 進程創建總數

        >>> [ FilterTags (預設: None) ]

        * 輸入字典格式 {"key":["排除Tag","排除Tag","排除Tag"]}
        * 手動設置 -> Set("filter")
        * 讀取 Json -> Read("filter")

        >>> [ CookieSource (預設: Set("cookie")) ]

        * 設置 Cookie 的來源
        * 預設是手動設置 , 於上方的 Set() 類中
        * 讀取 Json , Read("cookie")
        """
        self.SetUse = True
        self.path = DownloadPath
        self.GetCookie = GetCookie
        self.Cookies = CookieSource
        self.TagFilterBox = FilterTags
        self.ProtectionDelay = DownloadDelay
        self.MaxProcess = MaxConcurrentDownload
        self.ProcessDelay = ProcessCreationDelay  

    def TestChannel(self, link: str, browse: str="google"):
        """
        [link = 下載 Url , browse = 使用的瀏覽器]
        * 測試通道 !!
        * 不會驗證網址是否正確
        * 不會驗證是否可請求成功
        * 沒有限制創建進程數量 , 與創建速度
        """
        if self.TV == 0:
            if browse.lower() == "google":
                self.Headers = self.Google_Headers
            elif browse.lower() == "edge":
                self.Headers = self.Edge_Headers  
        self.TV += 1
        multiprocessing.Process(target=self.Comic_Page_process, args=(link, self.TV)).start()

    def google(self, link):
        self.Headers = self.Google_Headers

        if not self.SetUse:
            self.download_settings()

        # 驗證格式後 傳回 進行觸發
        self.Process_Trigger(self.URL_Classification(link))

    def edge(self, link):
        self.Headers = self.Edge_Headers

        if not self.SetUse:
            self.download_settings()

        self.Process_Trigger(self.URL_Classification(link))

    # 處理觸發器 (用於開啟線程)
    def Process_Trigger(self,box):
        if box != None:
            if len(box) == 1:
                self.Comic_Page_process(box[0], 1)
            else:
                with ProcessPoolExecutor(max_workers=self.MaxProcess) as executor:
                    for index , url in enumerate(box):
                        executor.submit(self.Comic_Page_process , url, index+1)
                        time.sleep(self.ProcessDelay)

    # 漫畫連結處理
    def Comic_Page_process(self, url, count):
        url = url.split("?p=")[0]
        # 保存主頁數據
        home_page_data = []
        def home_page(tree):
            for data in tree.xpath("//div[@id='gdt']/div/a"):
                href = data.get("href")
                if href != None:
                    home_page_data.append(href)

        # 保存圖片連結
        link_box = OrderedDict()
        def picture_link(tree):
            for data in tree.xpath("//img[@id='img']"):
                # 每本漫畫的取得元素不同
                href = data.get("href")
                sec = data.get("src")

                if href != None:
                    link_box[href] = None
                elif sec != None:
                    link_box[sec] = None

        print(f"[漫畫 {count} 開始處理] => {url}" , flush=True)
        StartTime = time.time()
        tree = self.get_data(url)
        home_page(tree) # 獲取第一頁連結
        
        # 取得漫畫標題 , 並排除非法字元
        try:
            title = tree.xpath("//*[@id='gj']/text()")[0] # 日文標題
        except:
            try:
                title = tree.xpath("//*[@id='gn']/text()")[0] # 英文標題
            except:
                print("\n[無法取得標題元素!]\n可能原因:\n\n[1]需要特別的Cookie\n[2]該頁面元素位置有例外\n[3]你的IP被Ban了")
                return

        self.title = re.sub(self.illegal_filename, '', title).strip()
        # 漫畫頁數
        total_pages = math.ceil(int(tree.xpath("//td[@class='gdt2']/text()")[-2].split(" ")[0]) / 20)
        
        # 當有設置排除標籤時 , 重複時會進行排除
        if self.TagFilterBox != None:
            # 取得漫畫標籤
            labelbox = tree.xpath("//td/div/a/text()")
            for value in self.TagFilterBox.values():
                result = set(value) & set(labelbox)
                if result:
                    print(f"[漫畫 {count} 標籤排除]" , flush=True)
                    return
                
        # 保存路徑
        self.save_location = os.path.join(self.path, self.title)

        #! 核心數據處理邏輯
        async def Trigger():
            count = 0
            async with aiohttp.ClientSession() as session:
                # 處理主頁數據
                work = []
                work1 = []
                for page in range(1, total_pages):
                    work.append(asyncio.create_task(self.async_get_data(f"{url}?p={page}", session)))
                    
                    count+=1
                    if count == 5:
                        print(f"\r以處理 [{page}] 頁", end="", flush=True)
                        await asyncio.sleep(1) # 主要是保護網站
                        count = 0

                results = await asyncio.gather(*work)

                for tree in results:
                    home_page(tree)
                
                Processed_pages = len(home_page_data)
                if (Processed_pages <= 0):
                    os.system("cls")
                    print("數據處理錯誤")
                    os._exit(1)
                    
                # 請求內部圖片連結
                for link in home_page_data:
                    # 異步併發請求
                    work1.append(self.async_get_data(link, session))
                    
                    count+=1
                    if count == 100:
                        Processed_pages -= count
                        print(f"\r剩餘處理 [{Processed_pages}] 張", end="", flush=True)
                        await asyncio.sleep(1)
                        count = 0
                        
                results = await asyncio.gather(*work1)
                
                for tree in results:
                    picture_link(tree)

        asyncio.run(Trigger())
        
        # 數據轉換回列表
        link_list = list(link_box.keys())
        for page , link in enumerate(link_list):
            SaveName = f"{(page+1):04d}"
            self.picture_link_data[SaveName] = link

        print("\r[漫畫 %d 處理完成] => 處理耗時 %.3f 秒" % (count , (time.time() - StartTime)) , flush=True)
        self.download_processing()

    def create_folder(self,Name):
        try:os.mkdir(Name)
        except:pass

    def download_processing(self):
        self.create_folder(self.save_location)

        with ThreadPoolExecutor(max_workers=100) as executor:
            for SaveName , comic_link in tqdm(self.picture_link_data.items() , desc=self.title, colour="#DB005B"):

                save = os.path.join(self.save_location, f"{SaveName}.{comic_link.rsplit('.',1)[1]}")
                executor.submit(self.download, save, comic_link)

                time.sleep(self.ProtectionDelay)

    def download(self, download_path, download_link):
        ImageData = self.Session.get(download_link, headers=self.Headers, cookies=self.Cookies)

        if ImageData.status_code == 200:
            with open(download_path , "wb") as f:
                f.write(ImageData.content)

if __name__ == "__main__":
    eh = EHentaidownloader()
    AutoCapture.settings("https://(exhentai|e-hentai)")

    eh.download_settings(
        DownloadPath = "R:/",
        CookieSource = Read("cookie"),
    )
    
    """ 可由快捷停止的擷取方法 , 一次回傳一個列表 , 並停止擷取狀態
    capture = AutoCapture.GetList()
    if capture != None:
        eh.google(capture)
    else:
        print("無擷取內容")
        os._exit(0)
    """
    
    # 無限擷取 , 擷取到一個網址立即下載[請使用測試通道] , 無法由快捷停止
    for capture in AutoCapture.Unlimited():
        eh.TestChannel(capture)