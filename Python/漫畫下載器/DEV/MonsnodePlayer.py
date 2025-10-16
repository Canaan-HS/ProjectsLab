import os
from Script import Request, AutoCapture

# 臨時撰寫 個人用途的工具


def open_href(url: str):
    if not url:
        return
    url = url.replace("redirect", "twjn")
    tree = Request.http2_get(url, "tree")

    try:
        href = tree.xpath("//strong/a/@href")[0]
        if href:
            os.system(f"fp {href}")  # 調用個人環境 cli 播放器
    except:
        pass


if __name__ == "__main__":
    AutoCapture.settings("https://monsnode.com/")

    for capture in AutoCapture.Unlimited():
        open_href(capture)
