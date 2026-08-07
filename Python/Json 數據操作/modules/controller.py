from __future__ import annotations

import os
import json
import asyncio
from typing import Any, Dict, List, Optional

from .json_core import DiffEntry, JsonService, RawJsonPatcher
from .signal_bus import Signal


class Controller:
    def __init__(self) -> None:
        # ---- 狀態 ----
        self.source1_path: Optional[str] = None
        self.source2_path: Optional[str] = None
        self._source1_text: Optional[str] = None
        self._source1_encoding: str = "utf-8"
        self._source1_bom: bool = False
        self._obj1: Any = None
        self._obj2: Any = None
        self.entries: List[DiffEntry] = []
        self._unresolved_count = 0
        self._chosen_source2_count = 0

        # ---- 對外信號 ----
        self.sig_source1_changed = Signal()  # (path: Optional[str])
        self.sig_source2_changed = Signal()  # (path: Optional[str])
        self.sig_diff_ready = Signal()  # (entries: List[DiffEntry])
        self.sig_choice_changed = Signal()  # (index: int, choice: int)
        self.sig_busy = Signal()  # (is_busy: bool, message: str)
        self.sig_notify = Signal()  # (message: str, is_error: bool)
        self.sig_output_done = Signal()  # (path: str)

    async def load_source1(self, path: str) -> None:
        self.sig_busy.emit(None, True, "正在讀取來源1...")
        try:
            text, encoding, bom = await asyncio.to_thread(JsonService.load_file, path)
            obj = await asyncio.to_thread(JsonService.parse, text)
        except Exception as ex:
            self.sig_busy.emit(None, False, "")
            self.sig_notify.emit(None, f"來源1 解析失敗：{ex}", True)
            return
        self.source1_path = path
        self._source1_text, self._source1_encoding, self._source1_bom = text, encoding, bom
        self._obj1 = obj
        self.sig_busy.emit(None, False, "")
        self.sig_source1_changed.emit(None, path)
        await self._try_compare()

    async def load_source2(self, path: str) -> None:
        self.sig_busy.emit(None, True, "正在讀取來源2...")
        try:
            text, _, _ = await asyncio.to_thread(JsonService.load_file, path)
            obj = await asyncio.to_thread(JsonService.parse, text)
        except Exception as ex:
            self.sig_busy.emit(None, False, "")
            self.sig_notify.emit(None, f"來源2 解析失敗：{ex}", True)
            return
        self.source2_path = path
        self._obj2 = obj
        self.sig_busy.emit(None, False, "")
        self.sig_source2_changed.emit(None, path)
        if JsonService.is_progress_snapshot(obj):
            self.sig_notify.emit(
                None, "偵測到先前保存的暫存進度檔，將以保存時的狀態繼續比對", False
            )
        await self._try_compare()

    async def _try_compare(self) -> None:
        if self._obj1 is None or self._obj2 is None:
            self.entries = []
            self._unresolved_count = 0
            self._chosen_source2_count = 0
            self.sig_diff_ready.emit(None, self.entries)
            return
        self.sig_busy.emit(None, True, "正在比對差異...")
        try:
            entries = await asyncio.to_thread(JsonService.compare, self._obj1, self._obj2)
        except Exception as ex:
            self.sig_busy.emit(None, False, "")
            self.sig_notify.emit(None, f"比對失敗：{ex}", True)
            return
        self.entries = entries
        self._recount()
        self.sig_busy.emit(None, False, "")
        self.sig_diff_ready.emit(None, self.entries)

    def _recount(self) -> None:
        unresolved = 0
        chosen2 = 0
        for e in self.entries:
            if e.choice == 0:
                unresolved += 1
            elif e.choice == 2:
                chosen2 += 1
        self._unresolved_count = unresolved
        self._chosen_source2_count = chosen2

    def set_choice(self, index: int, choice: int) -> None:
        if not (0 <= index < len(self.entries)):
            return
        entry = self.entries[index]
        old = entry.choice
        if old == choice:
            return  # 選同一邊不做事，避免多餘的訊號 / UI 更新
        if old == 0:
            self._unresolved_count -= 1
        elif old == 2:
            self._chosen_source2_count -= 1
        if choice == 0:
            self._unresolved_count += 1
        elif choice == 2:
            self._chosen_source2_count += 1
        entry.choice = choice
        self.sig_choice_changed.emit(None, index, choice)

    def set_custom_value(self, index: int, text: str) -> None:
        """設定條目的自訂文字，並自動將該條目切換為「自訂」狀態（choice=3"""
        if not (0 <= index < len(self.entries)):
            return
        entry = self.entries[index]
        entry.custom_value = text

        self.set_choice(index, 3)

    @property
    def unresolved_count(self) -> int:
        return self._unresolved_count

    @property
    def chosen_source2_count(self) -> int:
        return self._chosen_source2_count

    async def write_output(self, target_path: str) -> None:
        if self._source1_text is None:
            self.sig_notify.emit(None, "尚未載入來源1", True)
            return
        self.sig_busy.emit(None, True, "正在輸出...")
        try:
            replacements: Dict[str, Any] = {}
            for e in self.entries:
                if e.choice == 2:
                    replacements[e.key_path] = e.value2
                elif e.choice == 3 and e.custom_value is not None:
                    replacements[e.key_path] = e.custom_value

            def _do_write() -> None:
                result = RawJsonPatcher(self._source1_text).patch(replacements)
                if self._source1_encoding == "utf-8" and self._source1_bom:
                    result = "\ufeff" + result
                with open(target_path, "w", encoding=self._source1_encoding, newline="") as f:
                    f.write(result)

            await asyncio.to_thread(_do_write)
        except Exception as ex:
            self.sig_busy.emit(None, False, "")
            self.sig_notify.emit(None, f"輸出失敗：{ex}", True)
            return
        self.sig_busy.emit(None, False, "")
        self.sig_output_done.emit(None, target_path)
        self.sig_notify.emit(None, f"已輸出至：{target_path}", False)

    def default_save_name(self) -> str:
        if not self.source1_path:
            return "merged.json"
        base, _ = os.path.splitext(os.path.basename(self.source1_path))
        return f"{base}_merged.json"

    def default_save_dir(self) -> Optional[str]:
        return os.path.dirname(self.source1_path) if self.source1_path else None

    def default_progress_path(self) -> Optional[str]:
        """暫存進度檔固定存在「主要來源」同一個資料夾，檔名固定規則。"""
        if not self.source1_path:
            return None
        base, _ = os.path.splitext(os.path.basename(self.source1_path))
        return os.path.join(os.path.dirname(self.source1_path), f"{base}.diff_progress.json")

    async def save_progress(self) -> None:
        """保存目前的選取進度為暫存檔，方便下次用主要來源繼續比對剩餘差異

        內容只包含目前這批「有差異」的條目：
        - 已選擇的條目（主要 / 比較 / 自訂）-> 輸出對應已選的值
        - 尚未選擇的條目 -> 輸出比較來源的值（維持「仍然不同」的狀態）
        下次把這個檔案當作比較來源匯入時，已經選主要來源的條目因為值已與
        主要來源一致，會自然被排除；尚未選擇（或選了比較來源）的條目則會
        繼續被判定為有差異，維持顯示
        """
        if self._obj1 is None:
            self.sig_notify.emit(None, "尚未載入主要來源", True)
            return
        if not self.entries:
            self.sig_notify.emit(None, "目前沒有差異條目可以保存", True)
            return
        target = self.default_progress_path()
        if not target:
            self.sig_notify.emit(None, "尚未載入主要來源，無法決定保存位置", True)
            return

        self.sig_busy.emit(None, True, "正在保存進度...")
        try:

            def _do_save() -> None:
                entries_map: Dict[str, Any] = {}
                for e in self.entries:
                    if e.choice == 1:
                        entries_map[e.key_path] = e.value1
                    elif e.choice == 3 and e.custom_value is not None:
                        entries_map[e.key_path] = e.custom_value
                    else:
                        # 0=未選擇 或 2=選比較來源，都以比較來源的值為主
                        entries_map[e.key_path] = e.value2
                payload = {
                    JsonService.PROGRESS_MARKER_KEY: True,
                    "source1": self.source1_path,
                    "source2": self.source2_path,
                    "saved_entry_count": len(entries_map),
                    "entries": entries_map,
                }
                with open(target, "w", encoding="utf-8") as f:
                    json.dump(payload, f, ensure_ascii=False, indent=2)

            await asyncio.to_thread(_do_save)
        except Exception as ex:
            self.sig_busy.emit(None, False, "")
            self.sig_notify.emit(None, f"保存進度失敗：{ex}", True)
            return
        self.sig_busy.emit(None, False, "")
        self.sig_notify.emit(None, f"已保存進度至：{target}", False)
