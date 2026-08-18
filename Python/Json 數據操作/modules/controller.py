from __future__ import annotations

import os
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
        self.sig_source1_changed = Signal()   # (path: Optional[str])
        self.sig_source2_changed = Signal()   # (path: Optional[str])
        self.sig_diff_ready = Signal()        # (entries: List[DiffEntry])
        self.sig_choice_changed = Signal()    # (index: int, choice: int)
        self.sig_busy = Signal()              # (is_busy: bool, message: str)
        self.sig_notify = Signal()            # (message: str, is_error: bool)
        self.sig_output_done = Signal()       # (path: str)

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
            replacements: Dict[str, Any] = {
                e.key_path: e.value2 for e in self.entries if e.choice == 2
            }

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
