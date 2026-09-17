import time
import asyncio

from typing import Any
from types import SimpleNamespace

import httpx
import niquests
import requests

from lxml import html, etree
from bs4 import BeautifulSoup
from curl_cffi import requests as curl
from selectolax.lexbor import LexborHTMLParser
from niquests.exceptions import Timeout as niqTimeout
from curl_cffi.requests import exceptions, AsyncSession as CurlAsyncSession

"""
適用於 Python 3.10+
"""

BROWSER_HEAD = {
    "Google": {
        "user-agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36"
    },
    "Edge": {
        "user-agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36 Edg/151.0.0.0"
    },
}


class Fetch:
    def __init__(self, headers: dict | str = "Google", cookies: dict = {}):
        """
        * headers: 自定字典或是 "Google" / "Edge"
        * cookies: 傳入字典 cookie
        """

        # 處理 Headers
        if isinstance(headers, str):
            key = headers.capitalize()
            self.headers = BROWSER_HEAD.get(key, BROWSER_HEAD["Google"])
        elif isinstance(headers, dict):
            self.headers = headers
        else:
            self.headers = BROWSER_HEAD["Google"]

        self.cookies = cookies

        # Requests Session
        self.req_session = requests.Session()

        # Niquests Session
        self.niq_session = niquests.Session(multiplexed=True, happy_eyeballs=True)

        # HTTPX Client (HTTP/2)
        self.client = httpx.Client(http2=True, follow_redirects=True)

        # Curl Session (HTTP/3)
        # impersonate 會自動設定 UA，為了避免指紋衝突，這裡不建議手動 update headers 中的 UA
        # 但如果 cookies 需要帶入，可以在這裡設定
        self.curl_session = curl.Session(impersonate="chrome150")

    def __merge_headers(self, headers: dict = None) -> dict:
        """
        合併 headers：基礎 headers + 請求時傳入的 headers）
        """
        merged = self.headers.copy()
        if headers:
            merged.update(headers)
        return merged if merged else None

    def __merge_cookies(self, cookies: dict = None) -> dict:
        """
        合併 cookies：基礎 cookies + 請求時傳入的 cookies
        """
        merged = self.cookies.copy()
        if cookies:
            merged.update(cookies)
        return merged if merged else None

    def __get_text(self, respon: Any) -> str:
        if isinstance(respon, str):
            return respon
        if isinstance(respon, bytes):
            return respon.decode("utf-8", errors="ignore")
        return getattr(respon, "text", "")

    def __get_content(self, respon: Any) -> bytes:
        if isinstance(respon, bytes):
            return respon
        if isinstance(respon, str):
            return respon.encode("utf-8")
        return getattr(respon, "content", b"")

    def __get_status(self, respon: Any) -> int:
        if isinstance(respon, int):
            return respon
        return getattr(respon, "status_code", 0)

    def __parse(self, respon: Any, type: str) -> Any:
        """
        統一解析回傳類型
        """

        # 映射表
        parse_map = {
            "none": lambda: respon,
            "text": lambda: self.__get_text(respon),
            "content": lambda: self.__get_content(respon),
            "status": lambda: self.__get_status(respon),
            "tree": lambda: etree.HTML(self.__get_text(respon)),  # 適用 XPath
            "html": lambda: html.fromstring(self.__get_text(respon)),  # 適用 CSSSelect
            "lex": lambda: LexborHTMLParser(self.__get_text(respon)),
            "bf": lambda: BeautifulSoup(self.__get_text(respon), "html.parser"),
        }

        try:
            return parse_map.get(type, parse_map["none"])()
        except Exception as e:
            print(f"[Parse Error] {e}")
            return respon

    @staticmethod
    def ElapsedTime(func):
        """
        裝飾器: 測試請求運行耗時
        """

        def wrapper(self, *args, **kwargs):
            start_time = time.time()
            result = func(self, *args, **kwargs)
            end_time = time.time()
            url = args[0] if args else kwargs.get("url", "Unknown URL")
            print(f"[{func.__name__}] 耗時: {end_time - start_time:.4f} 秒 | URL: {url}")
            return result

        return wrapper if __name__ == "__main__" else func

    # ================= 同步請求 =================

    @ElapsedTime
    def req_head(self, url: str, headers: dict = None, cookies: dict = None) -> int:
        """
        HEAD 請求，回傳狀態碼
        """
        try:
            return self.__parse(
                self.req_session.head(
                    url,
                    headers=self.__merge_headers(headers),
                    cookies=self.__merge_cookies(cookies),
                    timeout=3,
                ),
                "status",
            )
        except requests.exceptions.Timeout:
            return 408
        except Exception as e:
            # print(f"Request Error: {e}")
            return -1

    @ElapsedTime
    def req_get(
        self,
        url: str,
        headers: dict = None,
        cookies: dict = None,
        type: str = "text",
    ) -> Any:
        """
        >>> type: "none" | "text" | "content" | "status" | "tree" | "html" | "lex" | "bf"
        """
        try:
            return self.__parse(
                self.req_session.get(
                    url,
                    headers=self.__merge_headers(headers),
                    cookies=self.__merge_cookies(cookies),
                    stream=True,
                    timeout=5,
                ),
                type,
            )
        except requests.exceptions.Timeout:
            return SimpleNamespace(text="Request Timeout", status_code=408)
        except Exception as e:
            return SimpleNamespace(text=f"Request Error: {e}", status_code=-1)

    @ElapsedTime
    def niq_head(self, url: str, headers: dict = None, cookies: dict = None) -> int:
        """
        HEAD 請求，回傳狀態碼
        """
        try:
            return self.__parse(
                self.niq_session.head(
                    url,
                    headers=self.__merge_headers(headers),
                    cookies=self.__merge_cookies(cookies),
                    timeout=3,
                ),
                "status",
            )
        except niqTimeout:
            return 408
        except Exception as e:
            # print(f"Request Error: {e}")
            return -1

    @ElapsedTime
    def niq_get(
        self,
        url: str,
        headers: dict = None,
        cookies: dict = None,
        type: str = "text",
    ) -> Any:
        """
        >>> type: "none" | "text" | "content" | "status" | "tree" | "html" | "lex" | "bf"
        """
        try:
            return self.__parse(
                self.niq_session.get(
                    url,
                    headers=self.__merge_headers(headers),
                    cookies=self.__merge_cookies(cookies),
                    stream=True,
                    timeout=5,
                ),
                type,
            )
        except niqTimeout:
            return SimpleNamespace(text="Request Timeout", status_code=408)
        except Exception as e:
            return SimpleNamespace(text=f"Request Error: {e}", status_code=-1)

    @ElapsedTime
    def httpx_head(self, url: str, headers: dict = None, cookies: dict = None) -> int:
        """
        HTTP/2 HEAD 請求，回傳狀態碼
        """
        try:
            return self.__parse(
                self.client.head(
                    url,
                    headers=self.__merge_headers(headers),
                    cookies=self.__merge_cookies(cookies),
                    timeout=3,
                ),
                "status",
            )
        except httpx.TimeoutException:
            return 408
        except Exception as e:
            # print(f"Request Error: {e}")
            return -1

    @ElapsedTime
    def httpx_get(
        self,
        url: str,
        headers: dict = None,
        cookies: dict = None,
        type: str = "text",
    ) -> Any:
        """
        >>> type: "none" | "text" | "content" | "status" | "tree" | "html" | "lex" | "bf"
        """
        try:
            return self.__parse(
                self.client.get(
                    url,
                    headers=self.__merge_headers(headers),
                    cookies=self.__merge_cookies(cookies),
                    timeout=5,
                ),
                type,
            )
        except httpx.TimeoutException:
            return SimpleNamespace(text="Request Timeout", status_code=408)
        except Exception as e:
            return SimpleNamespace(text=f"Request Error: {e}", status_code=-1)

    @ElapsedTime
    def curl_head(self, url: str, headers: dict = None, cookies: dict = None) -> int:
        """
        HTTP/3 HEAD 請求，回傳狀態碼
        """
        try:
            return self.__parse(
                self.curl_session.head(
                    url,
                    headers=self.__merge_headers(headers),
                    cookies=self.__merge_cookies(cookies),
                    timeout=3,
                ),
                "status",
            )
        except exceptions.Timeout:
            return 408
        except Exception as e:
            # print(f"Request Error: {e}")
            return -1

    @ElapsedTime
    def curl_get(
        self,
        url: str,
        headers: dict = None,
        cookies: dict = None,
        type: str = "text",
    ) -> Any:
        """
        >>> type: "none" | "text" | "content" | "status" | "tree" | "html" | "lex" | "bf"
        """
        try:
            return self.__parse(
                self.curl_session.get(
                    url,
                    headers=self.__merge_headers(headers),
                    cookies=self.__merge_cookies(cookies),
                    timeout=5,
                ),
                type,
            )
        except exceptions.Timeout:
            return SimpleNamespace(text="Request Timeout", status_code=408)
        except Exception as e:
            return SimpleNamespace(text=f"Request Error: {e}", status_code=-1)

    # ================= 異步請求區域 =================

    async def async_req_get(
        self,
        url: str,
        session,
        headers: dict = None,
        cookies: dict = None,
        type: str = "text",
    ) -> Any:
        """
        >>> type: "none" | "text" | "content" | "status" | "tree" | "html" | "lex" | "bf"

        >>> Example:
        import aiohttp

        async def main():
            async with aiohttp.ClientSession() as session:
                result = await fetch.async_get("https://example.com", session, type="text")
        """
        try:
            headers = self.__merge_headers(headers)
            cookies = self.__merge_cookies(cookies)

            async with session.get(
                url,
                headers=headers,
                cookies=cookies,
                timeout=5,
            ) as response:
                if type in ["content", "text", "tree", "html", "bf"]:
                    if type == "content":
                        content = await response.read()
                    else:
                        content = await response.text()
                    return self.__parse(content, type)
                else:
                    return self.__parse(response, type)
        except asyncio.TimeoutError:
            return SimpleNamespace(text="Async Timeout", status_code=408)
        except Exception as e:
            return SimpleNamespace(text=f"Async Error: {e}", status_code=-1)

    async def async_niq_get(
        self,
        url: str,
        session: niquests.AsyncSession = None,
        headers: dict = None,
        cookies: dict = None,
        type: str = "text",
    ) -> Any:
        """
        >>> type: "none" | "text" | "content" | "status" | "tree" | "html" | "lex" | "bf"

        >>> Example:
        import asyncio
        import niquests

        async def main():
            async with niquests.AsyncSession(multiplexed=True, happy_eyeballs=True) as session:
                result = await fetch.async_niq_get("https://example.com", session)

        """

        headers = self.__merge_headers(headers)
        cookies = self.__merge_cookies(cookies)

        async def _do_request(s):
            resp = await s.get(
                url,
                headers=headers,
                cookies=cookies,
                timeout=5,
            )
            return self.__parse(resp, type)

        try:
            if session:
                return await _do_request(session)
            else:
                # 若沒提供 session → 自動建立臨時 AsyncSession
                async with niquests.AsyncSession(multiplexed=True, happy_eyeballs=True) as s:
                    return await _do_request(s)

        except niqTimeout:
            return SimpleNamespace(text="Async NIQ Timeout", status_code=408)

        except Exception as e:
            return SimpleNamespace(text=f"Async NIQ Error: {e}", status_code=-1)

    async def async_httpx_get(
        self,
        url: str,
        client: httpx.AsyncClient = None,
        headers: dict = None,
        cookies: dict = None,
        type: str = "text",
    ) -> Any:
        """
        >>> type: "none" | "text" | "content" | "status" | "tree" | "html" | "lex" | "bf"

        >>> Example:
        import httpx

        async def main():
            async with httpx.AsyncClient(http2=True) as client:
                result = await fetch.async_http2_get("https://example.com", client=client)
        """

        headers = self.__merge_headers(headers)
        cookies = self.__merge_cookies(cookies)

        async def _do_request(ac):
            resp = await ac.get(
                url,
                headers=headers,
                cookies=cookies,
                timeout=5,
            )
            return self.__parse(resp, type)

        try:
            if client:
                return await _do_request(client)
            else:
                # 沒傳 client 會導致無法複用連接，大量請求時速度會慢
                async with httpx.AsyncClient(http2=True) as ac:
                    return await _do_request(ac)
        except httpx.TimeoutException:
            return SimpleNamespace(text="Async H2 Timeout", status_code=408)
        except Exception as e:
            return SimpleNamespace(text=f"Async H2 Error: {e}", status_code=-1)

    async def async_curl_get(
        self,
        url: str,
        session: CurlAsyncSession = None,
        headers: dict = None,
        cookies: dict = None,
        type: str = "text",
    ) -> Any:
        """
        >>> type: "none" | "text" | "content" | "status" | "tree" | "html" | "lex" | "bf"

        >>> Example:
        from curl_cffi.requests import AsyncSession

        async def main():
            async with AsyncSession(impersonate="chrome120") as session:
                result = await fetch.async_http3_get("https://example.com", session=session)
        """

        headers = self.__merge_headers(headers)
        cookies = self.__merge_cookies(cookies)

        async def _do_request(s):
            response = await s.get(
                url,
                headers=headers,
                cookies=cookies,
                timeout=5,
            )
            return self.__parse(response, type)

        try:
            if session:
                return await _do_request(session)
            else:
                # 如果沒傳 session，就臨時開一個，使用 async with 自動管理生命週期
                async with CurlAsyncSession(impersonate="chrome120") as s:
                    return await _do_request(s)
        except exceptions.Timeout:
            return SimpleNamespace(text="Async H3 Timeout", status_code=408)
        except Exception as e:
            return SimpleNamespace(text=f"Async H3 Error: {e}", status_code=-1)


fetch = Fetch()

if __name__ == "__main__":
    response = fetch.curl_get("https://example.com")
    print(response)
