import asyncio
import uuid
from crawl4ai import AsyncWebCrawler, BrowserConfig, CrawlerRunConfig, CrawlResult


def get_browser_config() -> BrowserConfig:
    """
    獲取瀏覽器設定參數
    """
    return BrowserConfig(
        browser_type="chromium",
        headless=False,  # 關閉 headless，才能看到視窗
        extra_args={
            "--lang": "en-US",
            "--start-maximized": "",
            "--disable-extensions": "",
            "--disable-notifications": "",
            "--disable-popup-blocking": "",
            "--disable-blink-features": "AutomationControlled",
        },
    )


class AutomationSession:
    """
    一個自動化會話管理器，使用 `async with` 語句來確保瀏覽器被正確開啟和關閉。
    所有操作都在同一個會話（瀏覽器實例）中進行。
    """

    def __init__(self, config: BrowserConfig):
        """
        初始化時傳入瀏覽器設定，並生成一個唯一的會話 ID。
        """
        self._config = config
        self._session_id = str(uuid.uuid4())
        self._crawler: AsyncWebCrawler | None = None

    async def __aenter__(self):
        """
        進入上下文時，創建並啟動 AsyncWebCrawler 實例。
        """
        self._crawler = AsyncWebCrawler(config=self._config)
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """
        退出上下文時，關閉 crawler 來釋放瀏覽器資源。
        """
        if self._crawler:
            await self._crawler.close()

    async def run(
        self, url: str, js_code: list[str] | None = None, wait_for: str | None = None
    ) -> CrawlResult:
        """
        在當前會話中執行一個自動化步驟。

        :param url: 要操作的目標網址
        :param js_code: 一個包含多個 JavaScript 命令的列表，將在頁面載入後執行
        :param wait_for: 一個 CSS 選擇器。程式會等到此選擇器對應的元素出現在頁面上再結束。
        :return: 包含執行結果的 CrawlResult 物件
        """
        if not self._crawler:
            raise RuntimeError("Crawler is not running. Use 'async with AutomationSession(...)'.")

        run_config = CrawlerRunConfig(
            session_id=self._session_id, js_code=js_code or [], wait_for=wait_for
        )
        return await self._crawler.arun(url=url, config=run_config)


async def main():
    """
    主程式進入點：演示如何使用 AutomationSession 進行多步操作。
    """
    # 1. 獲取瀏覽器啟動參數
    config = get_browser_config()

    # 2. 使用 'async with' 啟動一個自動化會話
    print("正在啟動自動化會話...")
    try:
        async with AutomationSession(config) as session:
            # --- 從這裡開始，主程式只需要關注自動化實現 ---
            google_url = "https://www.google.com"

            # 步驟 1: 打開 Google 首頁
            print(f"步驟 1: 導航至 {google_url}")
            result = await session.run(url=google_url)
            if not result.success:
                raise RuntimeError(f"無法打開 {google_url}: {result.error}")
            print("Google 首頁已載入。")
            await asyncio.sleep(1)  # 暫停以便觀察

            # 步驟 2: 在搜尋框中輸入文字
            # JavaScript 中，單引號需要轉義為 \'
            search_term = "Crawl4ai"
            js_fill_input = [
                f"document.querySelector('textarea[name=\"q\"').value = '{search_term}';"
            ]
            print(f"步驟 2: 在搜尋框中輸入 '{search_term}'")
            await session.run(url=google_url, js_code=js_fill_input)
            await asyncio.sleep(1)  # 暫停以便觀察

            # 步驟 3: 提交表單 (模擬按下 Enter)，並等待搜尋結果頁的特定元素出現
            js_press_enter = ["document.querySelector('textarea[name=\"q\"').form.submit();"]
            print("步驟 3: 提交搜尋表單並等待結果...")
            result = await session.run(url=google_url, js_code=js_press_enter, wait_for="#search")
            if not result.success:
                raise RuntimeError(f"搜尋失敗: {result.error}")

            print("搜尋結果頁面已載入。")
            print(f"頁面標題: {result.metadata.get('title')}")

            print("\n自動化操作演示完畢，5 秒後將自動關閉瀏覽器...")
            await asyncio.sleep(5)

    except Exception as e:
        print(f"\n發生未預期的錯誤: {e}")

    print("自動化會話已結束。")


if __name__ == "__main__":
    asyncio.run(main())
