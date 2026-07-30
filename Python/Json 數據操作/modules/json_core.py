from __future__ import annotations

import json
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple


@dataclass
class DiffEntry:
    key_path: str
    value1: Any
    value2: Any
    index: int = 0
    # 0=未選擇, 1=保留來源1, 2=保留來源2
    choice: int = field(default=0)


class JsonService:
    """讀檔 / 展開 / 比對的純邏輯層。"""

    @staticmethod
    def load_file(path: str) -> Tuple[str, str, bool]:
        """回傳 (檔案文字內容, 編碼, 是否含 BOM)。"""
        raw = open(path, "rb").read()
        if raw.startswith(b"\xef\xbb\xbf"):
            return raw.decode("utf-8-sig"), "utf-8", True
        if raw.startswith((b"\xff\xfe", b"\xfe\xff")):
            return raw.decode("utf-16"), "utf-16", True
        try:
            return raw.decode("utf-8"), "utf-8", False
        except UnicodeDecodeError:
            return raw.decode("gbk"), "gbk", False

    @staticmethod
    def parse(text: str) -> Any:
        return json.loads(text)

    @staticmethod
    def flatten(
        obj: Any, prefix: str = "", out: Optional[Dict[str, Tuple[Any, bool]]] = None
    ) -> Dict[str, Tuple[Any, bool]]:
        """展開巢狀結構為 {key_path: (value, is_leaf)}。"""
        if out is None:
            out = {}
        if isinstance(obj, dict):
            for k, v in obj.items():
                p = f"{prefix}.{k}" if prefix else str(k)
                if isinstance(v, (dict, list)):
                    JsonService.flatten(v, p, out)
                    out[p] = (v, False)
                else:
                    out[p] = (v, True)
        elif isinstance(obj, list):
            for i, v in enumerate(obj):
                p = f"{prefix}[{i}]"
                if isinstance(v, (dict, list)):
                    JsonService.flatten(v, p, out)
                    out[p] = (v, False)
                else:
                    out[p] = (v, True)
        else:
            out[prefix] = (obj, True)
        return out

    @staticmethod
    def _serialize(v: Any) -> str:
        return json.dumps(v, ensure_ascii=False, sort_keys=True, separators=(",", ":"))

    @classmethod
    def compare(cls, obj1: Any, obj2: Any) -> List[DiffEntry]:
        """比對兩個物件，回傳「相同 key 路徑但 value 不同」的條目清單。"""
        flat1 = cls.flatten(obj1)
        flat2 = cls.flatten(obj2)
        entries: List[DiffEntry] = []
        for p in sorted(set(flat1) & set(flat2)):
            v1, leaf1 = flat1[p]
            v2, leaf2 = flat2[p]
            if leaf1 and leaf2:
                if v1 != v2:
                    entries.append(DiffEntry(p, v1, v2))
            elif leaf1 != leaf2:
                s1 = v1 if leaf1 else cls._serialize(v1)
                s2 = v2 if leaf2 else cls._serialize(v2)
                if s1 != s2:
                    entries.append(DiffEntry(p, v1, v2))
        for i, e in enumerate(entries):
            e.index = i
        return entries


class _PathTrie:
    """以字元為單位的 trie，判斷某路徑底下是否還有要替換的目標。"""

    def __init__(self, paths):
        self.root = {"end": False, "ch": {}}
        for p in paths:
            node = self.root
            for c in p:
                nxt = node["ch"].get(c)
                if nxt is None:
                    nxt = {"end": False, "ch": {}}
                    node["ch"][c] = nxt
                node = nxt
            node["end"] = True

    def wants(self, path: str) -> bool:
        node = self.root
        for c in path:
            node = node["ch"].get(c)
            if node is None:
                return False
        if node["end"]:
            return True
        return "." in node["ch"] or "[" in node["ch"]

    def is_target(self, path: str) -> bool:
        node = self.root
        for c in path:
            node = node["ch"].get(c)
            if node is None:
                return False
        return node["end"]


class RawJsonPatcher:
    """掃描 JSON 原文，只替換指定 key 路徑的值，保留其餘排版（縮排/換行/順序/註解外其餘字元皆不動）。"""

    _WS = " \t\r\n"

    def __init__(self, text: str):
        self.text = text
        self._n = len(text)
        self._spans: Dict[str, Tuple[int, int]] = {}

    def _skip_ws(self, i: int) -> int:
        while i < self._n and self.text[i] in self._WS:
            i += 1
        return i

    def _read_string_end(self, i: int) -> int:
        i += 1
        while i < self._n:
            c = self.text[i]
            if c == "\\":
                i += 2
                continue
            if c == '"':
                return i + 1
            i += 1
        raise ValueError("JSON 字串未閉合")

    def _skip_container(self, i: int) -> int:
        depth = 1
        while i < self._n:
            c = self.text[i]
            if c == '"':
                i = self._read_string_end(i)
                continue
            if c in "{[":
                depth += 1
            elif c in "}]":
                depth -= 1
                if depth == 0:
                    return i + 1
            i += 1
        raise ValueError("JSON 容器未閉合")

    def _scan_value(self, i: int, path: Optional[str], trie: _PathTrie) -> int:
        c = self.text[i]
        if c == '"':
            return self._read_string_end(i)
        if c == "{":
            if path is not None and trie.wants(path):
                return self._scan_object(i, path, trie)
            return self._skip_container(i + 1)
        if c == "[":
            if path is not None and trie.wants(path):
                return self._scan_array(i, path, trie)
            return self._skip_container(i + 1)
        j = i
        while j < self._n and self.text[j] not in self._WS + ",}]":
            j += 1
        return j

    def _scan_object(self, i: int, path: str, trie: _PathTrie) -> int:
        i = self._skip_ws(i + 1)
        while True:
            if i >= self._n:
                raise ValueError("JSON 物件未閉合")
            if self.text[i] == "}":
                return i + 1
            key_end = self._read_string_end(i)
            key = json.loads(self.text[i:key_end])
            i = self._skip_ws(key_end)
            if i >= self._n or self.text[i] != ":":
                raise ValueError("JSON 格式錯誤: 預期 ':'")
            val_start = self._skip_ws(i + 1)
            child = f"{path}.{key}" if path else str(key)
            val_end = self._scan_value(val_start, child, trie)
            if trie.is_target(child):
                self._spans[child] = (val_start, val_end)
            i = self._skip_ws(val_end)
            if i < self._n and self.text[i] == ",":
                i = self._skip_ws(i + 1)
                continue
            if i < self._n and self.text[i] == "}":
                return i + 1
            raise ValueError("JSON 格式錯誤: 預期 ',' 或 '}'")

    def _scan_array(self, i: int, path: str, trie: _PathTrie) -> int:
        i = self._skip_ws(i + 1)
        idx = 0
        while True:
            if i >= self._n:
                raise ValueError("JSON 陣列未閉合")
            if self.text[i] == "]":
                return i + 1
            child = f"{path}[{idx}]"
            val_start = i
            val_end = self._scan_value(val_start, child, trie)
            if trie.is_target(child):
                self._spans[child] = (val_start, val_end)
            i = self._skip_ws(val_end)
            if i < self._n and self.text[i] == ",":
                idx += 1
                i = self._skip_ws(i + 1)
                continue
            if i < self._n and self.text[i] == "]":
                return i + 1
            raise ValueError("JSON 格式錯誤: 預期 ',' 或 ']'")

    def patch(self, replacements: Dict[str, Any]) -> str:
        if not replacements:
            return self.text
        trie = _PathTrie(replacements.keys())
        self._spans = {}
        i = self._skip_ws(0)
        if i >= self._n:
            raise ValueError("空檔案")
        c = self.text[i]
        if c == "{":
            end = self._scan_object(i, "", trie)
        elif c == "[":
            end = self._scan_array(i, "", trie)
        else:
            raise ValueError("JSON 根節點必須是物件或陣列")
        tail = self._skip_ws(end)
        if tail != self._n:
            raise ValueError("JSON 根節點之後還有內容")
        edits = []
        for path, new_val in replacements.items():
            if path not in self._spans:
                continue
            start, end = self._spans[path]
            repl = json.dumps(new_val, ensure_ascii=False, separators=(",", ":"))
            edits.append((start, end, repl))
        edits.sort(key=lambda e: e[0], reverse=True)
        out = self.text
        for start, end, repl in edits:
            out = out[:start] + repl + out[end:]
        return out
