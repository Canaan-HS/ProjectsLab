import asyncio
import uuid
from typing import List, Dict, Any

from crawl4ai import AsyncWebCrawler, BrowserConfig, CrawlerRunConfig, CrawlResult


def get_browser_config(headless: bool = False) -> BrowserConfig:
    """
    獲取瀏覽器設定參數。
    """
    return BrowserConfig(
        browser_type="chromium",
        headless=headless,
        extra_args={
            "--lang": "en-US",
            "--start-maximized": "",
            "--disable-extensions": "",
            "--disable-notifications": "",
            "--disable-popup-blocking": "",
            "--disable-blink-features": "AutomationControlled",
        },
    )


class AutomationManager:
    """
    封裝了 crawl4ai 的核心功能，提供一個穩定的自動化會話管理器。
    """

    def __init__(self, headless: bool = False):
        self._config = get_browser_config(headless)
        self._session_id = str(uuid.uuid4())
        self._crawler: AsyncWebCrawler | None = None
        self.current_url: str | None = None

    async def start(self) -> None:
        """
        啟動瀏覽器並初始化 crawler。
        """
        if not self._crawler:
            print("提示: 正在啟動瀏覽器...")
            self._crawler = AsyncWebCrawler(config=self._config)
        else:
            print("提示: 瀏覽器已經在運行中。")

    async def run(
        self,
        url: str,
        js_code: List[str] | None = None,
        wait_for: str | None = None,
        cookies: List[Dict[str, Any]] | None = None,
    ) -> CrawlResult:
        """
        在當前會話中執行一個自動化步驟。
        """
        if not self._crawler:
            raise RuntimeError("錯誤: 管理器尚未啟動，請先調用 start() 方法。")

        self.current_url = url
        run_config = CrawlerRunConfig(
            session_id=self._session_id,
            js_code=js_code or [],
            wait_for=wait_for,
            cookies=cookies or [],
        )
        return await self._crawler.arun(url=url, config=run_config)

    async def wait_for_manual_close(self) -> None:
        """
        將瀏覽器保持開啟狀態，直到用戶手動關閉所有窗口。
        此為常駐模式。
        """
        if not self._crawler or not self._crawler.browser:
            print("提示: 瀏覽器未運行，無需等待。")
            return

        print("\n提示: 瀏覽器將保持開啟狀態，您可以手動操作。")
        print("提示: 當您手動關閉所有瀏覽器窗口後，程式將會自動清理並結束。")
        try:
            while self._crawler.browser.is_connected():
                await asyncio.sleep(1)
        finally:
            print("\n提示: 偵測到瀏覽器已關閉，正在進行清理...")
            await self.close()

    async def close(self) -> None:
        """
        關閉瀏覽器並釋放資源。
        此為自動化模式的結束步驟。
        """
        if self._crawler:
            print("提示: 正在關閉瀏覽器...")
            await self._crawler.close()
            self._crawler = None
            print("提示: 瀏覽器已成功關閉。")
