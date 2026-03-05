import json
from pathlib import Path
from typing import Optional

SYSTEM_JSON_PATHS = {"data/System.json", "www/data/System.json"}


def get_encryption_key(project_path: str) -> Optional[str]:
    for sub_path in SYSTEM_JSON_PATHS:
        full_path = Path(project_path) / sub_path
        if full_path.is_file():
            try:
                data = json.loads(full_path.read_text(encoding="utf-8"))
                key = data.get("encryptionKey")
                if key:
                    return key
            except (json.JSONDecodeError, IOError, UnicodeDecodeError):
                continue
    return None


if __name__ == "__main__":
    print(get_encryption_key(""))
