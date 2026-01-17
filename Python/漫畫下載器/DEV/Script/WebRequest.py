import time

from types import SimpleNamespace

import httpx
import requests

from lxml import html, etree
from bs4 import BeautifulSoup

"""
Todo    適用於 Python 3.10+

?   只寫個人常用的幾種 API 調用
"""


class Headers:
    # 使用 navigator.userAgent 直接獲取
    browser_head = {
        "Google": {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36"
        },
        "Edge": {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36 Edg/144.0.0.0"
        },
    }


class Fetch(Headers):
    def __init__(self, headers: dict | str = "Google", cookies: dict = None):
        """
        * headers: 自定字典或是, "Google" or "Edge"
        * cookies: 傳入字典 cookie
        """
        self.client = httpx.Client(http2=True, timeout=5)
        self.session = requests.Session()
        self.headers = (
            self.browser_head[headers.capitalize()]
            if isinstance(headers, str)
            else headers if isinstance(headers, dict) else None
        )
        self.cookies = cookies

    # 解析要回傳的類型
    def __parse(self, respon, type):
        parse = {
            "none": lambda: respon,
            "text": lambda: respon.text,
            "content": lambda: respon.content,
            "status": lambda: respon.status_code,
            "tree": lambda: etree.HTML(respon.text),
            "html": lambda: html.fromstring(respon.text),
            "bf": lambda: BeautifulSoup(respon.text, "html.parser"),
        }

        try:
            return parse.get(type)()
        except:
            return parse.get("none")()

    def Elapsed_Time(func):
        """
        加上裝飾器 @Elapsed_Time 測試請求運行耗時
        """

        def wrapper(self, url):
            start_time = time.time()
            result = func(self, url)
            end_time = time.time()
            print(f"調用: {func.__name__}, 耗時: {end_time - start_time} 秒")
            return result

        return wrapper

    def head(self, url: str) -> int:
        try:
            return self.__parse(
                self.session.head(url, headers=self.headers, cookies=self.cookies, timeout=3),
                "status",
            )
        except requests.exceptions.Timeout:
            return SimpleNamespace(text="Request Timeout", status_code=408)

    def get(self, url: str, type: str = "text") -> any:
        """
        *   基本 Get 請求
        >>> [ url ]
        要請求的連結

        >>> [ type ]
        要獲取的結果類型
        ("none" | "text" | "content" | "status" | "tree" | "html" | "bf")

        "none" => 無處理
        "tree" => lxml 進行解析, 適用 xml 使用 xpath
        "html" => lxml 進行解析, 適用 html 使用 cssselect
        "bf" => bs4 進行解析
        """
        try:
            return self.__parse(
                self.session.get(
                    url, headers=self.headers, cookies=self.cookies, stream=True, timeout=5
                ),
                type,
            )
        except requests.exceptions.Timeout:
            return SimpleNamespace(text="Request Timeout", status_code=408)

    def http2_head(self, url: str) -> int:
        try:
            return self.__parse(
                self.client.head(url, headers=self.headers, cookies=self.cookies), "status"
            )
        except httpx.ConnectTimeout:
            return SimpleNamespace(text="Request Timeout", status_code=408)

    def http2_get(self, url: str, type: str = "text") -> any:
        """
        *   支援 http2 的 Get 請求
        >>> [ url ]
        要請求的連結

        >>> [ type ]
        要獲取的結果類型
        ("none" | "text" | "content" | "status" | "tree" | "html" | "bf")

        "none" => 無處理
        "tree" => lxml 進行解析, 適用 xml 使用 xpath
        "html" => lxml 進行解析, 適用 html 使用 cssselect
        "bf" => bs4 進行解析
        """
        try:
            return self.__parse(
                self.client.get(url, headers=self.headers, cookies=self.cookies), type
            )
        except httpx.ConnectTimeout:
            return SimpleNamespace(text="Request Timeout", status_code=408)

    async def async_http_get(self, url: str, type: str = "text") -> object:
        """
        *   異步 Get 請求

        >>> [ url ]
        要請求的連結

        >>> [ 使用方式 ]
        import asyncio
        async def main():
            work = [async_http_get(url) for url in date]
            results = await asyncio.gather(*work)
        asyncio.run(main())
        """
        async with httpx.AsyncClient(http2=True) as client:
            response = await client.get(url, headers=self.headers, cookies=self.cookies)
            return self.__parse(response.text, type)

    async def async_get(self, url: str, session, type: str = "text") -> object:
        """
        *   異步 Get 請求

        >>> [ url ]
        要請求的連結

        >>> [ session ]
        請求的 session 值

        >>> [ 使用方式 ]
        import aiohttp
        async def main():
            async with aiohttp.ClientSession() as session:
                work = [async_get(url, session) for url in date]
                results = await asyncio.gather(*work)
        asyncio.run(main())
        """
        async with session.get(url, headers=self.headers, cookies=self.cookies) as response:
            content = await response.text()
            return self.__parse(content, type)


fetch = Fetch()
