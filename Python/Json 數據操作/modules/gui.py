from __future__ import annotations

import flet as ft

from .controller import Controller
from .json_core import DiffEntry

PRIMARY = "#4F6BFF"
BG = "#F4F6FB"
SURFACE = "#FFFFFF"
BORDER = "#E4E7F0"
TEXT_MUTED = "#6B7280"
SUCCESS = "#22A06B"
DANGER = "#E5484D"

CHUNK = 300


class View:
    def __init__(self, page: ft.Page):
        self.page = page
        self.controller = Controller()
        self._rendered = 0
        self._filter_text = ""
        self._entry_cards: dict[int, ft.Control] = {}

        self._setup_page()
        self._build_widgets()
        self._wire_controller_signals()
        self.page.add(self._layout())

    def _setup_page(self) -> None:
        page = self.page
        page.title = "JSON 差異比對選擇器"
        page.theme_mode = ft.ThemeMode.LIGHT
        page.theme = ft.Theme(color_scheme_seed=PRIMARY, use_material3=True)
        page.bgcolor = BG
        page.padding = 0
        page.window.width = 1180
        page.window.height = 840
        page.window.min_width = 860
        page.window.min_height = 600

        # FilePicker 是 Service，必須註冊在 page.services（不是 page.overlay），
        # 放在 overlay 是 flet 1.x 之後互動失效最常見的原因。
        self.pick1 = ft.FilePicker()
        self.pick2 = ft.FilePicker()
        self.saver = ft.FilePicker()
        page.services.extend([self.pick1, self.pick2, self.saver])

    def _build_widgets(self) -> None:
        self.source1_name = ft.Text("尚未選擇檔案", size=13, color=TEXT_MUTED, no_wrap=True)
        self.source2_name = ft.Text("尚未選擇檔案", size=13, color=TEXT_MUTED, no_wrap=True)
        self.source1_chip = self._status_chip(False)
        self.source2_chip = self._status_chip(False)

        self.summary_text = ft.Text("請先選擇來源1與來源2", size=14, weight=ft.FontWeight.W_600)
        self.progress_text = ft.Text("", size=12, color=TEXT_MUTED)
        self.busy_ring = ft.ProgressRing(width=16, height=16, stroke_width=2, visible=False)

        self.search_box = ft.TextField(
            hint_text="搜尋 key path...",
            prefix_icon=ft.Icons.SEARCH,
            dense=True,
            border_radius=10,
            filled=True,
            bgcolor=SURFACE,
            border_color=BORDER,
            height=42,
            on_change=self._on_search_change,
            expand=True,
        )
        self.filter_unresolved = ft.Checkbox(
            label="只顯示未選擇", value=False, on_change=lambda e: self._render_list(reset=True)
        )

        self.list_view = ft.ListView(
            expand=True, spacing=10, padding=ft.Padding(4, 4, 12, 4), on_scroll=self._on_scroll
        )
        self.empty_hint = ft.Container(
            content=ft.Column(
                [
                    ft.Icon(ft.Icons.FIND_IN_PAGE_OUTLINED, size=40, color=BORDER),
                    ft.Text("尚無差異條目", color=TEXT_MUTED, size=13),
                ],
                horizontal_alignment=ft.CrossAxisAlignment.CENTER,
                spacing=6,
            ),
            alignment=ft.Alignment.CENTER,
            expand=True,
            visible=False,
        )

        self.btn_overwrite = ft.FilledButton(
            "覆蓋輸出來源1",
            icon=ft.Icons.SAVE_ALT,
            on_click=self._on_overwrite_click,
            disabled=True,
        )
        self.btn_save_as = ft.OutlinedButton(
            "另存新檔",
            icon=ft.Icons.SAVE_AS_OUTLINED,
            on_click=self._on_save_as_click,
            disabled=True,
        )

    def _status_chip(self, ok: bool) -> ft.Container:
        return ft.Container(
            content=ft.Row(
                [
                    ft.Icon(
                        ft.Icons.CHECK_CIRCLE if ok else ft.Icons.RADIO_BUTTON_UNCHECKED,
                        size=14,
                        color=SUCCESS if ok else TEXT_MUTED,
                    ),
                    ft.Text("已載入" if ok else "未載入", size=12, color=SUCCESS if ok else TEXT_MUTED),
                ],
                spacing=4,
                tight=True,
            ),
            bgcolor="#E9F9F1" if ok else "#F1F2F6",
            border_radius=20,
            padding=ft.Padding(10, 4, 10, 4),
        )

    def _source_card(self, title: str, icon, name_text, chip, on_pick) -> ft.Container:
        return ft.Container(
            content=ft.Column(
                [
                    ft.Row(
                        [
                            ft.Row([ft.Icon(icon, size=18, color=PRIMARY), ft.Text(title, weight=ft.FontWeight.W_600, size=14)], spacing=6),
                            chip,
                        ],
                        alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                    ),
                    name_text,
                    ft.OutlinedButton("選擇檔案...", icon=ft.Icons.UPLOAD_FILE_OUTLINED, on_click=on_pick),
                ],
                spacing=10,
            ),
            bgcolor=SURFACE,
            border=ft.Border.all(1, BORDER),
            border_radius=14,
            padding=16,
            expand=True,
        )

    def _layout(self) -> ft.Control:
        header = ft.Container(
            content=ft.Row(
                [
                    ft.Column(
                        [
                            ft.Text("JSON 差異比對選擇器", size=20, weight=ft.FontWeight.BOLD),
                            ft.Text(
                                "比對兩份 JSON 中 key 相同但 value 不同的條目，逐條選擇要保留哪一方",
                                size=12,
                                color=TEXT_MUTED,
                            ),
                        ],
                        spacing=2,
                    ),
                ],
            ),
            bgcolor=SURFACE,
            padding=ft.Padding(24, 18, 24, 18),
            border=ft.Border(bottom=ft.BorderSide(1, BORDER)),
        )

        sources_row = ft.Row(
            [
                self._source_card("來源1（主要）", ft.Icons.DESCRIPTION_OUTLINED, self.source1_name, self.source1_chip, self._on_pick_source1),
                self._source_card("來源2（比較）", ft.Icons.DIFFERENCE_OUTLINED, self.source2_name, self.source2_chip, self._on_pick_source2),
            ],
            spacing=16,
        )

        toolbar = ft.Row(
            [
                self.search_box,
                self.filter_unresolved,
                self.busy_ring,
                self.progress_text,
            ],
            spacing=14,
        )

        list_area = ft.Stack([self.list_view, self.empty_hint], expand=True)

        content = ft.Container(
            content=ft.Column(
                [
                    sources_row,
                    ft.Divider(height=1, color=BORDER),
                    ft.Row([self.summary_text], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
                    toolbar,
                    ft.Container(
                        content=list_area,
                        bgcolor=SURFACE,
                        border=ft.Border.all(1, BORDER),
                        border_radius=14,
                        padding=12,
                        expand=True,
                    ),
                ],
                spacing=16,
                expand=True,
            ),
            padding=24,
            expand=True,
        )

        footer = ft.Container(
            content=ft.Row(
                [
                    ft.Text(
                        "提示：未選擇的條目輸出時保留來源1原始值；其餘排版不受影響。",
                        size=12,
                        color=TEXT_MUTED,
                        expand=True,
                    ),
                    self.btn_save_as,
                    self.btn_overwrite,
                ],
                alignment=ft.MainAxisAlignment.END,
                spacing=12,
            ),
            bgcolor=SURFACE,
            padding=ft.Padding(24, 14, 24, 14),
            border=ft.Border(top=ft.BorderSide(1, BORDER)),
        )

        return ft.Column([header, content, footer], spacing=0, expand=True)

    def _wire_controller_signals(self) -> None:
        c = self.controller
        c.sig_source1_changed.connect(self._on_source1_changed)
        c.sig_source2_changed.connect(self._on_source2_changed)
        c.sig_diff_ready.connect(self._on_diff_ready)
        c.sig_choice_changed.connect(self._on_choice_changed)
        c.sig_busy.connect(self._on_busy)
        c.sig_notify.connect(self._on_notify)
        c.sig_output_done.connect(self._on_output_done)

    def _on_source1_changed(self, path: str) -> None:
        self.source1_name.value = path
        self.source1_name.color = None
        self.source1_chip.content = self._status_chip(True).content
        self.source1_chip.bgcolor = "#E9F9F1"
        self.page.update()

    def _on_source2_changed(self, path: str) -> None:
        self.source2_name.value = path
        self.source2_name.color = None
        self.source2_chip.content = self._status_chip(True).content
        self.source2_chip.bgcolor = "#E9F9F1"
        self.page.update()

    def _on_diff_ready(self, entries) -> None:
        self._render_list(reset=True)
        has_both = self.controller.source1_path and self.controller.source2_path
        self.btn_overwrite.disabled = not (has_both and entries)
        self.btn_save_as.disabled = not (has_both and entries)
        if has_both:
            self.summary_text.value = (
                f"找到 {len(entries)} 個差異條目" if entries else "兩份文件沒有差異條目（相同 key 且 value 不同）"
            )
        else:
            self.summary_text.value = "請先選擇來源1與來源2"
        self.page.update()

    def _on_choice_changed(self, index: int, choice: int) -> None:
        self._update_progress_text()
        self.page.update()

    def _on_busy(self, is_busy: bool, message: str) -> None:
        self.busy_ring.visible = is_busy
        self.progress_text.value = message if is_busy else self._progress_summary()
        self.page.update()

    def _on_notify(self, message: str, is_error: bool) -> None:
        snack = ft.SnackBar(
            content=ft.Text(message, color="#FFFFFF"),
            bgcolor=DANGER if is_error else SUCCESS,
            duration=ft.Duration(seconds=6 if is_error else 3),
        )
        self.page.show_dialog(snack)

    def _on_output_done(self, path: str) -> None:
        pass  # 通知已由 sig_notify 處理

    async def _on_pick_source1(self, e) -> None:
        files = await self.pick1.pick_files(
            dialog_title="選擇來源1 JSON 檔",
            allow_multiple=False,
            file_type=ft.FilePickerFileType.CUSTOM,
            allowed_extensions=["json"],
        )
        if not files:
            return
        await self.controller.load_source1(files[0].path)

    async def _on_pick_source2(self, e) -> None:
        files = await self.pick2.pick_files(
            dialog_title="選擇來源2 JSON 檔",
            allow_multiple=False,
            file_type=ft.FilePickerFileType.CUSTOM,
            allowed_extensions=["json"],
        )
        if not files:
            return
        await self.controller.load_source2(files[0].path)

    async def _on_overwrite_click(self, e) -> None:
        if self.controller.source1_path:
            await self._confirm_and_run(self.controller.source1_path)

    async def _on_save_as_click(self, e) -> None:
        if not self.controller.source1_path:
            return
        path = await self.saver.save_file(
            dialog_title="另存新檔",
            file_name=self.controller.default_save_name(),
            initial_directory=self.controller.default_save_dir(),
            file_type=ft.FilePickerFileType.CUSTOM,
            allowed_extensions=["json"],
        )
        if path:
            await self._confirm_and_run(path)

    async def _confirm_and_run(self, target_path: str) -> None:
        unresolved = self.controller.unresolved_count
        if unresolved > 0:
            dlg = ft.AlertDialog(
                modal=True,
                title=ft.Text("未選擇提醒"),
                content=ft.Text(f"有 {unresolved} 個條目未選擇。未選擇的條目將保留來源1的原始值，是否繼續？"),
                actions=[
                    ft.TextButton("取消", on_click=lambda _: self.page.pop_dialog()),
                    ft.FilledButton(
                        "繼續",
                        on_click=lambda _: self.page.run_task(self._run_output, target_path),
                    ),
                ],
                actions_alignment=ft.MainAxisAlignment.END,
            )
            self.page.show_dialog(dlg)
        else:
            await self._run_output(target_path)

    async def _run_output(self, target_path: str) -> None:
        self.page.pop_dialog()
        await self.controller.write_output(target_path)

    def _on_search_change(self, e) -> None:
        self._filter_text = (self.search_box.value or "").strip().lower()
        self._render_list(reset=True)

    def _filtered_entries(self):
        entries = self.controller.entries
        if self._filter_text:
            entries = [e for e in entries if self._filter_text in e.key_path.lower()]
        if self.filter_unresolved.value:
            entries = [e for e in entries if e.choice == 0]
        return entries

    def _render_list(self, reset: bool = False) -> None:
        if reset:
            self.list_view.controls.clear()
            self._entry_cards.clear()
            self._rendered = 0
        self._visible_entries = self._filtered_entries()
        self.empty_hint.visible = len(self._visible_entries) == 0
        self._load_more()
        self._update_progress_text()
        self.page.update()

    def _load_more(self) -> None:
        end = min(self._rendered + CHUNK, len(self._visible_entries))
        for i in range(self._rendered, end):
            entry = self._visible_entries[i]
            card = self._build_card(entry)
            self._entry_cards[entry.index] = card
            self.list_view.controls.append(card)
        self._rendered = end

    def _on_scroll(self, e: ft.OnScrollEvent) -> None:
        # event_type 是列舉：START/UPDATE/END/USER/OVERSCROLL，並非布林式的「到底了」。
        # 用捲動位置(pixels)接近底部(max_scroll_extent)來判斷是否該載入下一批。
        if e.event_type not in (ft.ScrollType.UPDATE, ft.ScrollType.END):
            return
        if e.max_scroll_extent - e.pixels < 400 and self._rendered < len(self._visible_entries):
            self._load_more()
            self.page.update()

    @staticmethod
    def _disp(v) -> str:
        import json as _json

        s = v if isinstance(v, str) else _json.dumps(v, ensure_ascii=False)
        s = " ".join(s.split())
        return s if len(s) <= 150 else s[:150] + "…"

    def _value_tile(self, entry: DiffEntry, side: int, value) -> ft.Container:
        selected = entry.choice == side
        label = "來源1" if side == 1 else "來源2"
        return ft.Container(
            content=ft.Row(
                [
                    ft.Radio(value=str(side), label=label),
                    ft.Text(self._disp(value), expand=True, selectable=True, size=13),
                ],
                spacing=6,
            ),
            bgcolor="#EEF1FF" if selected else "#FAFBFD",
            border=ft.Border.all(1, PRIMARY if selected else BORDER),
            border_radius=10,
            padding=ft.Padding(10, 8, 10, 8),
        )

    def _build_card(self, entry: DiffEntry) -> ft.Container:
        v1_tile = self._value_tile(entry, 1, entry.value1)
        v2_tile = self._value_tile(entry, 2, entry.value2)

        def on_change(e, idx=entry.index, v1=v1_tile, v2=v2_tile):
            choice = int(e.control.value)
            self.controller.set_choice(idx, choice)
            v1.bgcolor = "#EEF1FF" if choice == 1 else "#FAFBFD"
            v1.border = ft.Border.all(1, PRIMARY if choice == 1 else BORDER)
            v2.bgcolor = "#EEF1FF" if choice == 2 else "#FAFBFD"
            v2.border = ft.Border.all(1, PRIMARY if choice == 2 else BORDER)
            self.page.update()

        group = ft.RadioGroup(
            value=str(entry.choice) if entry.choice else None,
            content=ft.Column([v1_tile, v2_tile], spacing=6),
            on_change=on_change,
        )

        return ft.Container(
            content=ft.Column(
                [
                    ft.Text(entry.key_path, weight=ft.FontWeight.W_600, selectable=True, size=13, font_family="monospace"),
                    group,
                ],
                spacing=8,
            ),
            bgcolor=SURFACE,
            border=ft.Border.all(1, BORDER),
            border_radius=12,
            padding=14,
        )

    def _progress_summary(self) -> str:
        total = len(self.controller.entries)
        if total == 0:
            return ""
        unresolved = self.controller.unresolved_count
        return f"已顯示 {self._rendered}/{len(self._visible_entries)} 筆 · 尚有 {unresolved} 筆未選擇"

    def _update_progress_text(self) -> None:
        self.progress_text.value = self._progress_summary()
