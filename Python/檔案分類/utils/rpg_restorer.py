from pathlib import Path
from enum import Enum, auto

# PNG 文件頭 (前 16 字節)
STANDARD_PNG_HEADER = bytes(
    [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52]
)

# RPG Maker 加密文件需要跳過的頭部字節數 (16字節偽造頭 + 16字節加密頭)
HEADER_OFFSET = 32
# RPG Maker 常見預設資源開頭 (非 CG 不需要)
EXCLUDE_HEADER = ("$", "!", "#", "@")

# 通常沒加密的格式
UNENCRYPTED_IMAGE = {".rpgmvp", ".png_"}
# 通常加密的格式
ENCRYPTED_AUDIO = {".rpgmvo", ".ogg_", ".m4a_"}

VALID_RPG_SUFFIXS = UNENCRYPTED_IMAGE | ENCRYPTED_AUDIO


class RestoreStatus(Enum):
    """定義還原操作的返回狀態"""

    SUCCESS = auto()  # 操作成功
    FILE_EXCLUDE = auto()  # 排除文件
    INVALID_SUFFIX = auto()  # 無效的文件擴展名
    FILE_NOT_FOUND = auto()  # 輸入文件未找到
    FILE_TOO_SMALL = auto()  # 文件太小，不可能是有效的加密文件
    DECRYPT_ERROR = auto()  # 解密文件時發生錯誤
    READ_ERROR = auto()  # 讀取文件時發生IO錯誤
    WRITE_ERROR = auto()  # 寫入文件時發生IO錯誤
    DELETE_ERROR = auto()  # 刪除原始文件時發生錯誤 (但還原本身是成功的)
    UNKNOWN_ERROR = auto()  # 發生未知錯誤


def restore_suffix(path: str, suffix: str) -> str:
    ext = ".unknown"

    if suffix in UNENCRYPTED_IMAGE:
        ext = ".png"
    elif suffix in ENCRYPTED_AUDIO:
        ext = ".m4a" if suffix == ".m4a_" else ".ogg"

    return str(Path(path).with_suffix(ext))


def restore_rpg(
    input_path: str, output_path: str = None, decrypt_key: str = None, delete_original: bool = False
) -> RestoreStatus:
    """
    對 RPG Maker 加密文件進行還原
    """
    path = Path(input_path)
    suffix = path.suffix.lower()

    # 檢查擴展名是否合法
    if suffix not in VALID_RPG_SUFFIXS:
        return RestoreStatus.INVALID_SUFFIX

    # 排除預設圖片
    if suffix in UNENCRYPTED_IMAGE and path.stem.startswith(EXCLUDE_HEADER):
        return RestoreStatus.FILE_EXCLUDE

    # 檢查輸出路徑
    if output_path is None:
        output_path = restore_suffix(str(path), suffix)

    # 讀取加密文件
    try:
        encrypted_data = path.read_bytes()
    except FileNotFoundError:
        return RestoreStatus.FILE_NOT_FOUND
    except IOError:
        return RestoreStatus.READ_ERROR
    except Exception:
        return RestoreStatus.UNKNOWN_ERROR

    # 檢查文件是否太小
    if len(encrypted_data) < HEADER_OFFSET:
        return RestoreStatus.FILE_TOO_SMALL

    # 進行解密
    if encrypted_data[:5] in (b"RPGMV", b"RPGMZ"):
        if decrypt_key is None:
            return RestoreStatus.DECRYPT_ERROR

        key_bytes = bytes.fromhex(decrypt_key)
        xor_header = bytes(a ^ b for a, b in zip(encrypted_data[16:32], key_bytes))
        restored_data = xor_header + encrypted_data[32:]
    else:
        restored_data = STANDARD_PNG_HEADER + encrypted_data[HEADER_OFFSET:]

    # 寫入文件
    try:
        Path(output_path).write_bytes(restored_data)
    except (IOError, PermissionError):
        return RestoreStatus.WRITE_ERROR
    except Exception:
        return RestoreStatus.UNKNOWN_ERROR

    # 刪除原始文件
    if delete_original:
        try:
            path.unlink()
        except (IOError, PermissionError):
            return RestoreStatus.DELETE_ERROR
        except Exception:
            return RestoreStatus.UNKNOWN_ERROR

    return RestoreStatus.SUCCESS


if __name__ == "__main__":
    restore_rpg("")
