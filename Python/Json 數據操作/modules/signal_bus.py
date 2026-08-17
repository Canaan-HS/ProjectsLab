from __future__ import annotations

import inspect
from typing import Any, Callable, Dict


class SignalTargetNotFoundError(Exception):
    """當 emit()/request() 指定的 target 不存在時拋出。"""


class Signal:
    def __init__(self) -> None:
        self._slots: Dict[str, dict] = {}

    def _can_call(self, slot_info: dict, arg_count: int) -> bool:
        return slot_info["min_args"] <= arg_count <= slot_info["max_args"]

    def connect(self, func: Callable, label: str = "", once: bool = False) -> str:
        if not callable(func):
            raise TypeError("func 必須是可呼叫的物件")

        sig = inspect.signature(func)
        params = list(sig.parameters.values())

        positional_kinds = (
            inspect.Parameter.POSITIONAL_ONLY,
            inspect.Parameter.POSITIONAL_OR_KEYWORD,
        )
        required_params = [
            p for p in params if p.default is inspect.Parameter.empty and p.kind in positional_kinds
        ]
        min_args = len(required_params)

        if any(p.kind == inspect.Parameter.VAR_POSITIONAL for p in params):
            max_args = float("inf")
        else:
            max_args = len([p for p in params if p.kind in positional_kinds])

        key = label.strip() or getattr(func, "__name__", repr(func))
        self._slots[key] = {
            "func": func,
            "min_args": min_args,
            "max_args": max_args,
            "once": once,
        }
        return key

    def disconnect(self, label: str) -> None:
        self._slots.pop(label, None)

    def disconnect_all(self) -> None:
        self._slots.clear()

    def emit(self, target: str = None, *args, **kwargs) -> None:
        if target is None:
            to_remove = []
            for name, slot_info in list(self._slots.items()):
                if self._can_call(slot_info, len(args)):
                    slot_info["func"](*args, **kwargs)
                    if slot_info.get("once", False):
                        to_remove.append(name)
            for name in to_remove:
                self._slots.pop(name, None)
        else:
            slot_info = self._slots.get(target)
            if slot_info:
                slot_info["func"](*args, **kwargs)
                if slot_info.get("once", False):
                    del self._slots[target]
            else:
                raise SignalTargetNotFoundError(f"Signal target not found: '{target}'")

    def request(self, target: str = None, *args, **kwargs) -> Any:
        if target is None:
            self.emit(target, *args, **kwargs)
            return None
        slot_info = self._slots.get(target)
        if slot_info:
            result = slot_info["func"](*args, **kwargs)
            if slot_info.get("once", False):
                del self._slots[target]
            return result
        return None
