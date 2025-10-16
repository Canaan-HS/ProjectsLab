import asyncio
import os
from typing import List, Dict, Any

from browser.manager import AutomationManager
from utils import data_handler


class JKFAutomator(AutomationManager):
    """
    繼承自 AutomationManager，專門用於 JKF 論壇的自動化任務。
    """

    def __init__(self, headless: bool = False):
        super().__init__(headless=headless)
        self.base_url = "https://www.jkforum.net/forum.php?mod=forum"
        self.cookie_path = os.path.join(os.path.dirname(__file__), "jkf_cookies.json")

    async def login_and_confirm(self, jump_url: str) -> bool:
        """
        處理 JKF 的登入流程，優先使用 Cookie，若失敗則等待手動登入。

        :param jump_url: 登入成功後要跳轉到的目標頁面。
        :return: 如果成功登入並到達目標頁則返回 True。
        """
        print("步驟 1: 嘗試使用 Cookie 登入 JKF 論壇...")
        cookies = data_handler.load_json(self.cookie_path)

        # 初始載入頁面，使用 Cookie
        login_result = await self.run(url=self.base_url, cookies=cookies)
        if not login_result.success:
            print(f"錯誤: 無法打開 JKF 網站: {login_result.error}")
            return False

        # 檢查登入是否成功 (透過檢查頭像元素是否存在)
        # 注意：這裡的 page_source 是靜態的，所以我們用 js_code 來做動態檢查
        check_js = ["document.querySelector('span.circleHead > img') !== null"]
        check_result = await self.run(url=self.base_url, js_code=check_js)

        is_logged_in = check_result.js_results and check_result.js_results[0]

        if is_logged_in:
            print("提示: Cookie 登入成功！")
        else:
            print("提示: Cookie 登入失敗或 Cookie 已過期。")
            print("提示: 請在開啟的瀏覽器視窗中手動登入。")
            input("提示: 手動登入完成後，請按 Enter 鍵繼續...")

            # 手動登入後，我們需要獲取新的 Cookie 並保存
            print("提示: 正在保存新的 Cookie 以供下次使用...")
            # CrawlResult 的 cookies 屬性包含了當前頁面的 cookies
            new_cookies_result = await self.run(url=self.base_url)
            if new_cookies_result.cookies:
                data_handler.save_json(self.cookie_path, new_cookies_result.cookies)
                print("提示: 新的 Cookie 已保存。")
            else:
                print("警告: 未能獲取新的 Cookie。")

        # 最後，跳轉到最終目標頁面
        print(f"步驟 2: 導航至目標頁面 -> {jump_url}")
        final_page = await self.run(url=jump_url)
        if not final_page.success:
            print(f"錯誤: 無法導航至目標頁面: {final_page.error}")
            return False

        print("提示: 已成功到達目標頁面。")
        return True

    # --- old.py 中的其他方法 (jkf_use_props, jkf_mining) 可以依照上面的模式在此處實現 ---
    # 例如:
    # async def use_props(self):
    #     is_logged_in = await self.login_and_confirm(jump_url="https://www.jkforum.net/material/my_item")
    #     if not is_logged_in:
    #         return
    #
    #     # 接下來使用 self.run() 搭配 js_code 來點擊 "查看"、"確認" 等按鈕
    #     await self.run(url=self.current_url, js_code=["document.querySelector(...).click()"], wait_for="...")
    #     ...


async def main():
    """
    主程式進入點
    """
    jkf_automator = JKFAutomator(headless=False)
    await jkf_automator.start()

    try:
        # --- 任務目標 ---
        # 以 JKF 登入並跳轉到 "我的道具" 頁面為例
        target_url = "https://www.jkforum.net/material/my_item"
        success = await jkf_automator.login_and_confirm(jump_url=target_url)

        if success:
            print("\n任務完成: 已成功登入並跳轉至指定頁面。")
            # --- 模式選擇 ---
            # 模式一：自動化完成後，等待 5 秒自動關閉 (自動化模式)
            # print("\n5 秒後將自動關閉瀏覽器...")
            # await asyncio.sleep(5)
            # await jkf_automator.close()

            # 模式二：將瀏覽器保持開啟，直到用戶手動關閉 (常駐等待模式)
            await jkf_automator.wait_for_manual_close()
        else:
            print("\n任務失敗: 未能完成所有指定步驟。")
            await jkf_automator.close()

    except Exception as e:
        print(f"\n程式執行期間發生未預期的錯誤: {e}")
        await jkf_automator.close()


if __name__ == "__main__":
    asyncio.run(main())
