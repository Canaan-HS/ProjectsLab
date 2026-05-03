import os
from enum import Enum, auto


class RestoreStatus(Enum):
    """定義還原操作的返回狀態"""

    SUCCESS = auto()  # 操作成功
    FILE_EXCLUDE = auto()  # 排除文件
    INVALID_EXTENSION = auto()  # 無效的文件擴展名
    FILE_NOT_FOUND = auto()  # 輸入文件未找到
    FILE_TOO_SMALL = auto()  # 文件太小，不可能是有效的加密文件
    READ_ERROR = auto()  # 讀取文件時發生IO錯誤
    WRITE_ERROR = auto()  # 寫入文件時發生IO錯誤
    DELETE_ERROR = auto()  # 刪除原始文件時發生錯誤 (但還原本身是成功的)
    UNKNOWN_ERROR = auto()  # 發生未知錯誤


# PNG 文件頭 (前 16 字節)
STANDARD_PNG_HEADER = bytes(
    [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52]
)

# RPG Maker 加密文件需要跳過的頭部字節數 (16字節偽造頭 + 16字節加密頭)
HEADER_OFFSET = 32
# RPG Maker 常見預設資源 (非 CG 不需要)
EXCLUDE_HEADER = ("$", "!", "#", "@")
# 允許的文件擴展名
VALID_EXTENSIONS = {".rpgmvp", ".png_"}


def Restore_RPG(
    input_path: str, output_path: str = None, delete_original: bool = False
) -> RestoreStatus:
    """
    還原 RPG Maker MV/MZ 加密的圖片為標準的 PNG 格式。

    本函數會安靜地執行，僅通過返回一個 RestoreStatus 枚舉來表明操作結果。

    Args:
        input_path (str): 輸入的加密圖片文件的路徑 (e.g., 'C:/path/to/image.png_')。
        output_path (str, optional): 輸出的標準 PNG 圖片文件的路徑。
                                     如果為 None，則默認在原始文件位置生成同名 .png 文件。
                                     (e.g., 'img.rpgmvp' -> 'img.png')。
        delete_original (bool, optional): 如果為 True，則在成功還原後刪除原始加密文件。
                                          默認為 False。

    Returns:
        RestoreStatus: 一個表示操作結果的枚舉成員。
    """

    # 快速檢測文件名與擴展名
    base, extension = os.path.splitext(input_path)

    if extension.lower() not in VALID_EXTENSIONS:
        return RestoreStatus.INVALID_EXTENSION

    if os.path.basename(base).startswith(EXCLUDE_HEADER):
        return RestoreStatus.FILE_EXCLUDE

    # 處理輸出路徑 (如果未提供)
    if output_path is None:
        output_path = base + ".png"

    # 讀取文件
    try:
        with open(input_path, "rb") as f:
            encrypted_data = f.read()
    except FileNotFoundError:
        return RestoreStatus.FILE_NOT_FOUND
    except IOError:
        return RestoreStatus.READ_ERROR
    except Exception:
        return RestoreStatus.UNKNOWN_ERROR

    # 驗證文件大小
    if len(encrypted_data) < HEADER_OFFSET:
        return RestoreStatus.FILE_TOO_SMALL

    # 核心還原邏輯
    rest_of_file = encrypted_data[HEADER_OFFSET:]
    restored_data = STANDARD_PNG_HEADER + rest_of_file

    # 寫入還原後的文件
    try:
        with open(output_path, "wb") as f:
            f.write(restored_data)
    except (IOError, PermissionError):
        return RestoreStatus.WRITE_ERROR
    except Exception:
        return RestoreStatus.UNKNOWN_ERROR

    # 刪除原始文件 (可選)
    if delete_original:
        try:
            os.remove(input_path)
        except (IOError, PermissionError):
            # 還原成功，但刪除失敗 (可選)
            return RestoreStatus.DELETE_ERROR
        except Exception:
            return RestoreStatus.UNKNOWN_ERROR

    return RestoreStatus.SUCCESS
