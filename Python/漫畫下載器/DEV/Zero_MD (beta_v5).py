import re
import time
import asyncio

from pathlib import Path
from types import SimpleNamespace
from multiprocessing import cpu_count
from concurrent.futures import ProcessPoolExecutor

import opencc

from rich.console import Console
from curl_cffi.requests import AsyncSession as async_curl

from Script import capture, fetch

""" Versions 1.0.1

    & Zero 漫畫下載器

        ? (開發/運行環境):
        * Python 3.14.7 64-bit
        * 個人依賴庫 -> Script 資料夾內所有文件 (capture, fetch)

        ? 使用說明:
        * 配置 CONFIG
        * 其餘下載設置, 由下方入口點觀看
"""

CONFIG = SimpleNamespace(
    **{
        "DownloadPath": "R:/",  # 路徑結尾必須為斜線
        "RequestDomain": "https://www.zerobyw33.com/",  # 域名修正: https://zerobyw.github.io/
    }
)

# ? 複寫原生打印
console = Console()
print = lambda *args, **kwargs: console.print(*args, **kwargs)


class SupportVerify:
    def __init__(self):
        self.twp = None

        escaped_domain = CONFIG.RequestDomain.replace(".", r"\.")
        self.verify_rules = re.compile(rf"{escaped_domain}pc/(?:details|pc2details)/\?kuid=(.*)")

    def verify(self, url: str) -> bool:
        if re.match(self.verify_rules, url):
            if self.twp is None:
                self.twp = opencc.OpenCC("s2twp.json")
            return True

        print("不符合的網址格式", style="bold red")
        return False


class ProcessingMeta(SupportVerify):
    def __init__(self):
        super().__init__()
        self.name_rules = re.compile(r"^(.*?)【")

    def get_meta(self, url: str) -> dict:

        result = {"RequesState": False}

        if self.verify(url):
            try:
                start_time = time.time()
                html = fetch.curl_get(url, type="lex")

                # 取得漫畫名稱
                name_el = re.match(self.name_rules, html.css_first("title").text().strip())
                manga_name = self.twp.convert(name_el.group(1).strip())

                # 取得漫畫連結 (預覽圖)
                img_src = html.css_first("img[src*='tupa']").attributes.get("src")

                # 取得漫畫章節編號
                manga_chapter = [
                    link.text().strip()
                    for link in html.css(
                        """a[href*='view/index.php'], [onclick="app.showLockTip('login')"]"""
                    )[1:]
                ]

                # 複寫數據
                result = {
                    "RequesState": True,
                    "MangaName": manga_name,
                    "MangaChapters": manga_chapter,  # 漫畫章節 ['1', '2', ...]
                    "ImgData": img_src.rsplit("/", 2),  # 預覽圖連結資訊拆分 [連結, 章節編號, 檔名]
                }

                print(
                    f"[獲取完成] 耗時 %.3f 秒\n[漫畫名稱] {manga_name}\n"
                    % ((time.time() - start_time)),
                    style="bold",
                )
            except Exception as e:
                print(f"域名錯誤 , 或是伺服器問題: {e}", style="bold red")

        return SimpleNamespace(**result)


class DownloadTask:
    # 設置下載任務參數
    def set_task(
        self,
        merge: bool = False,
        mantissa: int = None,
        extension: str = None,
        img_domain: str = None,
    ) -> None:
        self.merge = merge  # 下載完成是否合併
        self.mantissa = mantissa  # 圖片尾數
        self.extension = extension  # 圖片擴展名
        self.img_domain = img_domain  # 圖片請求域名

    # 創建資料夾
    def create_folder(self, name: str) -> None:
        Path(name).mkdir(exist_ok=True)

    # 試錯處理
    async def _task_trial_error(self, page: str, url: str) -> str:
        length_range = range(1, 6)
        extension = ["jpg", "jpeg", "png", "gif", "webp", "avif"]

        async with async_curl(timeout=3, impersonate="chrome150") as client:

            async def check(url, mantissa, ext):
                try:
                    resp = await client.head(url)
                    if resp.status_code == 200:
                        return (url, mantissa, ext)
                except Exception:
                    pass
                return ""

            tasks = []
            for mantissa in length_range:
                padded = page.zfill(mantissa)
                for ext in extension:
                    tasks.append(asyncio.create_task(check(f"{url}/{padded}.{ext}", mantissa, ext)))

            # 回傳最快成功的
            for coro in asyncio.as_completed(tasks):
                result = await coro

                if result:
                    url, mantissa, ext = result

                    # 成功的改變預設的, 尾數 / 擴展名
                    self.mantissa = mantissa
                    self.extension = ext

                    return url

            return ""

    # 下載任務
    def _task_download(self, folder_name: str, save_path: str, url: str) -> int:
        response = fetch.curl_get(url, type="none")
        status = response.status_code

        if status == 200:

            if not self.merge:
                # 創建資料夾 (寫在這的原因, 是避免在開始請求前, 就直接創資料夾, 如果請求失敗就會有一堆空資料夾)
                self.create_folder(folder_name)

            # 保存圖片
            Path(save_path).write_bytes(response.content)

        return status

    # 任務開始
    def task_start(self, folder_name: str, chapter: str, is_special: bool) -> None:
        if is_special:
            print(f"第 {chapter} 特別章節 - 開始下載", style="bold blue")
        else:
            print(f"第 {chapter} 章節 - 開始下載", style="bold blue")

        page_count = 0  # 計算總共頁數

        # 根據是否合併, 決定創建的路徑是資料夾還是檔名
        link_symbol = " - " if self.merge else "/"

        # ? 為了可下載未知章節, 因此使用模糊請求
        for index in range(1, 1001):
            # 生成下載頁數
            page = f"{index}".zfill(self.mantissa)

            # 生成下載連結
            url = (  # ! 特別話 的網址類型可能變更
                f"{self.img_domain}/{chapter}sheng/{page}.{self.extension}"
                if is_special
                else f"{self.img_domain}/{chapter}/{page}.{self.extension}"
            )

            img_save_path = f"{folder_name}{link_symbol}{page}.{self.extension}"

            status = self._task_download(folder_name, img_save_path, url)

            # 自動試錯不提供選擇 (自動使用)
            if status != 200:
                trial_url = asyncio.run(self._task_trial_error(str(index), url.rsplit("/", 1)[0]))

                if trial_url:
                    self._task_download(folder_name, img_save_path, trial_url)
                else:
                    # ! 因為是模糊請求, 當試錯都失敗直接跳出迴圈 (根據試錯的邏輯, 可能會缺頁面)
                    break

            page_count += 1

        print(f"第 {chapter} 章節 [共 {page_count} 頁] - 下載完成", style="bold green")


class ZeroDownloader(DownloadTask):
    def __init__(self):
        super().__init__()
        self.chapter_cache: str = None  # 緩存章節數
        self.max_task: int = cpu_count()  # 最大同時處理任務數量

    # 解析章節
    def _parse_chapter(self, chapter: object, default: list) -> object:
        if chapter is None:
            return default
        elif isinstance(chapter, list):
            return chapter
        elif isinstance(chapter, int) or isinstance(chapter, str):
            return [chapter]
        else:
            return default

    # 創建下載任務
    def create_task(self, **kwargs):
        """
        建立下載任務。

        :param str Url:
            下載網址 (必填)

        :param str Ext:
            自訂輸出擴展名，例如 "jpg", "png", "webp" 等 (選填)

        :param bool Merge:
            啟用後將所有章節輸出到同一層，不再依章節建立子資料夾 (選填)

        :param int | str Chapter:
            自訂章節名稱，可為數字或字串 (選填)

        :param int Mantissa:
            自訂頁碼填充長度 (選填)
            例如：
                3 → 003
                2 → 03

        :param bool Special:
            是否下載特別話內容，例如：全彩中文、全彩生肉等 (選填)

        """
        config = SimpleNamespace(
            **{
                "Url": "",
                "Ext": None,
                "Merge": False,
                "Chapter": None,
                "Mantissa": None,
                "Special": False,
            }
            | kwargs
        )

        meta = pm.get_meta(config.Url)
        if meta.RequesState:

            # 生成漫畫保存路徑
            manga_folder_path = rf"{CONFIG.DownloadPath}{meta.MangaName}"
            # 創建資料夾
            self.create_folder(manga_folder_path)

            end = meta.ImgData[2].split(".")  # 使用圖片數據, 進行分割
            self.set_task(
                merge=config.Merge,
                # 取得圖片請求域名
                img_domain=meta.ImgData[0],
                # 取得尾數填充值 [長度命名可能錯誤, 但不影響下載]
                mantissa=config.Mantissa if isinstance(config.Mantissa, int) else len(end[0]),
                # 取得擴展名
                extension=config.Ext if isinstance(config.Ext, str) else end[1],
            )

            with ProcessPoolExecutor(max_workers=self.max_task) as executor:
                for chapter in self._parse_chapter(config.Chapter, meta.MangaChapters):
                    chapter = str(chapter)

                    folder_name, is_special = (
                        (f"{manga_folder_path}/Special-{chapter.replace('-', '~')}", True)
                        if config.Special or chapter == self.chapter_cache
                        else (f"{manga_folder_path}/{chapter.replace('-', '~')}", False)
                    )

                    self.chapter_cache = chapter

                    if is_special:
                        print(f"第 {chapter} 特別章節 - 準備下載", style="bold yellow")
                    else:
                        print(f"第 {chapter} 章節 - 準備下載", style="bold yellow")

                    executor.submit(self.task_start, folder_name, chapter, is_special)


if __name__ == "__main__":
    custom_range = lambda start, end: [chapter for chapter in range(start, end + 1)]
    capture.settings(CONFIG.RequestDomain)

    pm = ProcessingMeta()  # 驗證獲取並處理漫畫元資料
    zd = ZeroDownloader()  # 執行下載任務

    # Todo -> 下方創建方式擇一使用

    # ? 監聽剪貼簿自動創建任務
    zd.create_task(Url=capture.get_link(), Merge=True)

    # ? 自定下載任務 (模板), 範圍設置 -> (1 or [1, 2, 3] or custom_range(1, 3))
    # zd.create_task(Url="Url", Chapter=custom_range(1, 10), Mantissa=2, Ext="jpg", Special=True)
