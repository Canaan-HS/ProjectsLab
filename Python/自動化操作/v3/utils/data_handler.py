import json
import os
from typing import Any, Dict, List


def load_json(file_path: str) -> Dict | List | None:
    """
    從指定的路徑加載 JSON 檔案。

    :param file_path: JSON 檔案的完整路徑。
    :return: 加載後的字典或列表，如果檔案不存在或為空則返回 None。
    """
    if not os.path.exists(file_path):
        print(f"錯誤: 找不到檔案 -> {file_path}")
        return None
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, IOError) as e:
        print(f"錯誤: 讀取或解析 JSON 檔案失敗 -> {file_path}\n{e}")
        return None


def save_json(file_path: str, data: Any) -> bool:
    """
    將數據保存為 JSON 檔案。

    :param file_path: 要保存的檔案完整路徑。
    :param data: 要保存的數據 (例如 dict 或 list)。
    :return: 如果成功保存則返回 True，否則返回 False。
    """
    try:
        # 確保目錄存在
        os.makedirs(os.path.dirname(file_path), exist_ok=True)
        with open(file_path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=4)
        return True
    except IOError as e:
        print(f"錯誤: 寫入 JSON 檔案失敗 -> {file_path}\n{e}")
        return False
