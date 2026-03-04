from enum import Enum, auto
from pathlib import Path


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


def restore_RPG(
    input_path: str, output_path: str = None, delete_original: bool = False
) -> RestoreStatus:
    """
    對 RPG Maker 加密文件進行還原
    """
    path = Path(input_path)
    extension = path.suffix.lower()

    if extension not in VALID_EXTENSIONS:
        return RestoreStatus.INVALID_EXTENSION

    if path.stem.startswith(EXCLUDE_HEADER):
        return RestoreStatus.FILE_EXCLUDE

    if output_path is None:
        output_path = str(path.with_suffix(".png"))

    try:
        encrypted_data = path.read_bytes()
    except FileNotFoundError:
        return RestoreStatus.FILE_NOT_FOUND
    except IOError:
        return RestoreStatus.READ_ERROR
    except Exception:
        return RestoreStatus.UNKNOWN_ERROR

    if len(encrypted_data) < HEADER_OFFSET:
        return RestoreStatus.FILE_TOO_SMALL

    restored_data = STANDARD_PNG_HEADER + encrypted_data[HEADER_OFFSET:]

    try:
        Path(output_path).write_bytes(restored_data)
    except (IOError, PermissionError):
        return RestoreStatus.WRITE_ERROR
    except Exception:
        return RestoreStatus.UNKNOWN_ERROR

    if delete_original:
        try:
            path.unlink()
        except (IOError, PermissionError):
            return RestoreStatus.DELETE_ERROR
        except Exception:
            return RestoreStatus.UNKNOWN_ERROR

    return RestoreStatus.SUCCESS


if __name__ == "__main__":
    restore_RPG("")
