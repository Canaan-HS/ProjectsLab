from __future__ import annotations

import flet as ft

from .controller import Controller
from .json_core import DiffEntry

# 分批渲染的筆數
CHUNK = 120

LIGHT_PALETTE = {
    "bg": "#F4F6FB",
    "surface": "#FFFFFF",
    "surface_alt": "#FAFBFD",
    "border": "#E4E7F0",
    "text": "#1A1D29",
    "text_muted": "#6B7280",
    "primary": "#4F6BFF",
    "primary_soft": "#EEF1FF",
    "success": "#1F9D63",
    "success_soft": "#E9F9F1",
    "danger": "#E5484D",
    "chip_off_bg": "#F1F2F6",
    "chip_off_text": "#6B7280",
}

DARK_PALETTE = {
    "bg": "#14161F",
    "surface": "#1C1F2B",
    "surface_alt": "#242737",
    "border": "#333748",
    "text": "#F1F2F8",
    "text_muted": "#9CA3AF",
    "primary": "#7C90FF",
    "primary_soft": "#2A2F55",
    "success": "#34C889",
    "success_soft": "#1B3A2D",
    "danger": "#FF6B70",
    "chip_off_bg": "#2A2D3D",
    "chip_off_text": "#9CA3AF",
}

FILTER_LABELS = {
    "all": "全部",
    "unresolved": "未選",
    "primary": "選主要",
    "compare": "選比較",
}


class View:
    def __init__(self, page: ft.Page):
        self.page = page
        self.controller = Controller()
        self._dark = True
        self._rendered = 0
        self._filter_text = ""
        self._filter_mode = "all"  # all / unresolved / primary / compare
        self._visible_entries: list[DiffEntry] = []

        self._setup_page()
        self._wire_controller_signals()
        self._rebuild_ui()

    # ------------------------------------------------------------------ #
    # Page-level 設定
    # ------------------------------------------------------------------ #
    def _setup_page(self) -> None:
        page = self.page
        page.title = "JSON 差異比對選擇器"
        page.padding = 0
        page.window.width = 1180
        page.window.height = 860
        page.window.min_width = 900
        page.window.min_height = 620

        # 開啟時視窗預設置中
        page.run_task(self._center_window)

        self.pick1 = ft.FilePicker()
        self.pick2 = ft.FilePicker()
        self.saver = ft.FilePicker()
        page.services.extend([self.pick1, self.pick2, self.saver])

    async def _center_window(self) -> None:
        await self.page.window.wait_until_ready_to_show()
        await self.page.window.center()

    @property
    def C(self) -> dict:
        return DARK_PALETTE if self._dark else LIGHT_PALETTE

    def _apply_theme_mode(self) -> None:
        page = self.page
        page.theme_mode = ft.ThemeMode.DARK if self._dark else ft.ThemeMode.LIGHT
        seed = self.C["primary"]
        page.theme = ft.Theme(color_scheme_seed=seed, use_material3=True)
        page.dark_theme = ft.Theme(color_scheme_seed=seed, use_material3=True)
        page.bgcolor = self.C["bg"]

    # ------------------------------------------------------------------ #
    # 整棵畫面樹重建（初始化 / 切換深淺色時使用；狀態一律來自 controller）
    # ------------------------------------------------------------------ #
    def _rebuild_ui(self) -> None:
        self._apply_theme_mode()
        self._build_widgets()
        self.page.controls.clear()
        self.page.add(self._layout())

        # 用目前 controller 的既有狀態把畫面補回去（例如切換深淺色時已載入的檔案）
        if self.controller.source1_path:
            self._on_source1_changed(self.controller.source1_path)
        if self.controller.source2_path:
            self._on_source2_changed(self.controller.source2_path)
        self._on_diff_ready(self.controller.entries)
        self.page.update()

    # ------------------------------------------------------------------ #
    # Widgets
    # ------------------------------------------------------------------ #
    def _build_widgets(self) -> None:
        C = self.C

        self.theme_switch = ft.Switch(
            value=self._dark,
            on_change=self._on_theme_toggle,
            active_color=C["primary"],
            scale=0.85,
        )

        self.source1_name = ft.Text("尚未選擇檔案", size=14, color=C["text_muted"], no_wrap=True)
        self.source2_name = ft.Text("尚未選擇檔案", size=14, color=C["text_muted"], no_wrap=True)
        self.source1_chip = self._status_chip(False)
        self.source2_chip = self._status_chip(False)

        self.summary_text = ft.Text(
            "請先選擇主要與比較檔案", size=16, weight=ft.FontWeight.W_700, color=C["text"]
        )
        self.progress_text = ft.Text("", size=13, weight=ft.FontWeight.W_500, color=C["text_muted"])
        self.busy_ring = ft.ProgressRing(width=18, height=18, stroke_width=2, visible=False)

        self.search_box = ft.TextField(
            hint_text="搜尋",
            prefix_icon=ft.Icons.SEARCH,
            dense=True,
            border_radius=12,
            filled=True,
            bgcolor=C["surface"],
            border_color=C["border"],
            color=C["text"],
            text_size=15,
            height=46,
            on_change=self._on_search_change,
            expand=True,
        )

        self.filter_chips_row = ft.Row(spacing=8)
        self._build_filter_chips()

        self.list_view = ft.ListView(
            expand=True, spacing=12, padding=ft.Padding(4, 4, 12, 4), on_scroll=self._on_scroll
        )
        self.empty_hint = ft.Container(
            content=ft.Column(
                [
                    ft.Icon(ft.Icons.FIND_IN_PAGE_OUTLINED, size=44, color=C["border"]),
                    ft.Text("尚無符合條件的差異條目", color=C["text_muted"], size=14, weight=ft.FontWeight.W_500),
                ],
                horizontal_alignment=ft.CrossAxisAlignment.CENTER,
                spacing=8,
            ),
            alignment=ft.Alignment.CENTER,
            expand=True,
            visible=False,
        )

        self.btn_overwrite = ft.FilledButton(
            "覆蓋主要檔案",
            icon=ft.Icons.SAVE_ALT,
            on_click=self._on_overwrite_click,
            disabled=True,
            style=ft.ButtonStyle(text_style=ft.TextStyle(size=15, weight=ft.FontWeight.W_600)),
        )
        self.btn_save_as = ft.OutlinedButton(
            "另存新檔",
            icon=ft.Icons.SAVE_AS_OUTLINED,
            on_click=self._on_save_as_click,
            disabled=True,
            style=ft.ButtonStyle(text_style=ft.TextStyle(size=15, weight=ft.FontWeight.W_600)),
        )

    def _build_filter_chips(self) -> None:
        C = self.C
        self.filter_chips_row.controls.clear()
        for mode, label in FILTER_LABELS.items():
            active = self._filter_mode == mode
            self.filter_chips_row.controls.append(
                ft.Container(
                    content=ft.Text(
                        label,
                        size=14,
                        weight=ft.FontWeight.W_600,
                        color="#FFFFFF" if active else C["text_muted"],
                    ),
                    bgcolor=C["primary"] if active else C["chip_off_bg"],
                    border_radius=20,
                    padding=ft.Padding(16, 8, 16, 8),
                    on_click=lambda e, m=mode: self._on_filter_mode_change(m),
                    ink=True,
                )
            )

    def _status_chip(self, ok: bool) -> ft.Container:
        C = self.C
        return ft.Container(
            content=ft.Row(
                [
                    ft.Icon(
                        ft.Icons.CHECK_CIRCLE if ok else ft.Icons.RADIO_BUTTON_UNCHECKED,
                        size=15,
                        color=C["success"] if ok else C["text_muted"],
                    ),
                    ft.Text(
                        "已載入" if ok else "未載入",
                        size=13,
                        weight=ft.FontWeight.W_600,
                        color=C["success"] if ok else C["text_muted"],
                    ),
                ],
                spacing=4,
                tight=True,
            ),
            bgcolor=C["success_soft"] if ok else C["chip_off_bg"],
            border_radius=20,
            padding=ft.Padding(12, 5, 12, 5),
        )

    def _source_card(self, title: str, icon, name_text, chip, on_pick) -> ft.Container:
        C = self.C
        return ft.Container(
            content=ft.Column(
                [
                    ft.Row(
                        [
                            ft.Row(
                                [ft.Icon(icon, size=20, color=C["primary"]), ft.Text(title, weight=ft.FontWeight.W_700, size=16, color=C["text"])],
                                spacing=8,
                            ),
                            chip,
                        ],
                        alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                    ),
                    name_text,
                    ft.OutlinedButton("選擇檔案...", icon=ft.Icons.UPLOAD_FILE_OUTLINED, on_click=on_pick),
                ],
                spacing=10,
            ),
            bgcolor=C["surface"],
            border=ft.Border.all(1, C["border"]),
            border_radius=18,
            padding=18,
            expand=True,
        )

    def _layout(self) -> ft.Control:
        C = self.C

        header = ft.Container(
            content=ft.Row(
                [
                    ft.Text("JSON 差異比對選擇器", size=26, weight=ft.FontWeight.W_800, color=C["text"]),
                    ft.Row(
                        [
                            ft.Icon(ft.Icons.LIGHT_MODE, size=18, color=C["text_muted"]),
                            self.theme_switch,
                            ft.Icon(ft.Icons.DARK_MODE, size=18, color=C["text_muted"]),
                        ],
                        spacing=4,
                    ),
                ],
                alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
            ),
            bgcolor=C["surface"],
            padding=ft.Padding(24, 20, 24, 20),
            border=ft.Border(bottom=ft.BorderSide(1, C["border"])),
        )

        sources_row = ft.Row(
            [
                self._source_card("主要來源", ft.Icons.DESCRIPTION_OUTLINED, self.source1_name, self.source1_chip, self._on_pick_source1),
                self._source_card("比較來源", ft.Icons.DIFFERENCE_OUTLINED, self.source2_name, self.source2_chip, self._on_pick_source2),
            ],
            spacing=16,
        )

        toolbar = ft.Column(
            [
                ft.Row([self.search_box, self.busy_ring, self.progress_text], spacing=14),
                self.filter_chips_row,
            ],
            spacing=12,
        )

        list_area = ft.Stack([self.list_view, self.empty_hint], expand=True)

        content = ft.Container(
            content=ft.Column(
                [
                    sources_row,
                    ft.Divider(height=1, color=C["border"]),
                    self.summary_text,
                    toolbar,
                    ft.Container(
                        content=list_area,
                        bgcolor=C["surface"],
                        border=ft.Border.all(1, C["border"]),
                        border_radius=18,
                        padding=14,
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
                        "提示：未選擇的條目輸出時保留主要檔案原始值；其餘排版不受影響。",
                        size=13,
                        weight=ft.FontWeight.W_500,
                        color=C["text_muted"],
                        expand=True,
                    ),
                    self.btn_save_as,
                    self.btn_overwrite,
                ],
                alignment=ft.MainAxisAlignment.END,
                spacing=12,
            ),
            bgcolor=C["surface"],
            padding=ft.Padding(24, 16, 24, 16),
            border=ft.Border(top=ft.BorderSide(1, C["border"])),
        )

        return ft.Column([header, content, footer], spacing=0, expand=True)

    # ------------------------------------------------------------------ #
    # 深淺色切換
    # ------------------------------------------------------------------ #
    def _on_theme_toggle(self, e) -> None:
        self._dark = self.theme_switch.value
        self._rebuild_ui()

    # ------------------------------------------------------------------ #
    # Controller signal wiring（只在 __init__ 綁一次，畫面重建不會重複註冊）
    # ------------------------------------------------------------------ #
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
        C = self.C
        self.source1_name.value = path
        self.source1_name.color = C["text"]
        chip = self._status_chip(True)
        self.source1_chip.content = chip.content
        self.source1_chip.bgcolor = chip.bgcolor
        self.source1_name.update()
        self.source1_chip.update()

    def _on_source2_changed(self, path: str) -> None:
        C = self.C
        self.source2_name.value = path
        self.source2_name.color = C["text"]
        chip = self._status_chip(True)
        self.source2_chip.content = chip.content
        self.source2_chip.bgcolor = chip.bgcolor
        self.source2_name.update()
        self.source2_chip.update()

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
            self.summary_text.value = "請先選擇主要與比較檔案"
        self.summary_text.update()
        self.btn_overwrite.update()
        self.btn_save_as.update()

    def _on_choice_changed(self, index: int, choice: int) -> None:
        self._update_progress_text()
        self.progress_text.update()

    def _on_busy(self, is_busy: bool, message: str) -> None:
        self.busy_ring.visible = is_busy
        self.progress_text.value = message if is_busy else self._progress_summary()
        self.busy_ring.update()
        self.progress_text.update()

    def _on_notify(self, message: str, is_error: bool) -> None:
        C = self.C
        snack = ft.SnackBar(
            content=ft.Text(message, color="#FFFFFF", weight=ft.FontWeight.W_600),
            bgcolor=C["danger"] if is_error else C["success"],
            duration=ft.Duration(seconds=6 if is_error else 3),
        )
        self.page.show_dialog(snack)

    def _on_output_done(self, path: str) -> None:
        pass  # 通知已由 sig_notify 處理

    # ------------------------------------------------------------------ #
    # 檔案選擇事件
    # ------------------------------------------------------------------ #
    async def _on_pick_source1(self, e) -> None:
        files = await self.pick1.pick_files(
            dialog_title="選擇主要來源 JSON 檔",
            allow_multiple=False,
            file_type=ft.FilePickerFileType.CUSTOM,
            allowed_extensions=["json"],
        )
        if not files:
            return
        await self.controller.load_source1(files[0].path)

    async def _on_pick_source2(self, e) -> None:
        files = await self.pick2.pick_files(
            dialog_title="選擇比較來源 JSON 檔",
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
                title=ft.Text("未選擇提醒", weight=ft.FontWeight.W_700),
                content=ft.Text(f"有 {unresolved} 個條目未選擇。未選擇的條目將保留主要檔案的原始值，是否繼續？"),
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

    # ------------------------------------------------------------------ #
    # 篩選 / 搜尋
    # ------------------------------------------------------------------ #
    def _on_filter_mode_change(self, mode: str) -> None:
        self._filter_mode = mode
        self._build_filter_chips()
        self.filter_chips_row.update()
        self._render_list(reset=True)

    def _on_search_change(self, e) -> None:
        self._filter_text = (self.search_box.value or "").strip().lower()
        self._render_list(reset=True)

    def _filtered_entries(self) -> list[DiffEntry]:
        entries = self.controller.entries
        if self._filter_text:
            entries = [e for e in entries if self._filter_text in e.search_blob]
        if self._filter_mode == "unresolved":
            entries = [e for e in entries if e.choice == 0]
        elif self._filter_mode == "primary":
            entries = [e for e in entries if e.choice == 1]
        elif self._filter_mode == "compare":
            entries = [e for e in entries if e.choice == 2]
        return entries

    # ------------------------------------------------------------------ #
    # 差異列表渲染（分批載入 / 選擇狀態保留）
    # ------------------------------------------------------------------ #
    def _render_list(self, reset: bool = False) -> None:
        if reset:
            self.list_view.controls.clear()
            self._rendered = 0
        self._visible_entries = self._filtered_entries()
        self.empty_hint.visible = len(self._visible_entries) == 0
        self._load_more()
        self._update_progress_text()

        self.list_view.update()
        self.empty_hint.update()
        self.progress_text.update()

    def _load_more(self) -> None:
        end = min(self._rendered + CHUNK, len(self._visible_entries))
        for i in range(self._rendered, end):
            entry = self._visible_entries[i]
            self.list_view.controls.append(self._build_card(entry, i + 1))
        self._rendered = end

    def _on_scroll(self, e: ft.OnScrollEvent) -> None:
        # event_type 是列舉：START/UPDATE/END/USER/OVERSCROLL，並非「捲到底」的旗標。
        # 用捲動位置(pixels)接近底部(max_scroll_extent)判斷是否該載入下一批。
        if e.event_type not in (ft.ScrollType.UPDATE, ft.ScrollType.END):
            return
        if e.max_scroll_extent - e.pixels < 400 and self._rendered < len(self._visible_entries):
            self._load_more()
            self.list_view.update()

    @staticmethod
    def _disp(v) -> str:
        import json as _json

        s = v if isinstance(v, str) else _json.dumps(v, ensure_ascii=False)
        s = " ".join(s.split())
        return s if len(s) <= 160 else s[:160] + "…"

    def _value_block(self, entry: DiffEntry, side: int, value, on_pick) -> ft.GestureDetector:
        C = self.C
        selected = entry.choice == side
        container = ft.Container(
            content=ft.Column(
                [
                    ft.Row(
                        [ft.Icon(ft.Icons.CHECK_CIRCLE, size=16, color=C["primary"], visible=selected)],
                        alignment=ft.MainAxisAlignment.CENTER,
                    ),
                    ft.Text(
                        self._disp(value),
                        selectable=True,
                        size=15,
                        weight=ft.FontWeight.W_500,
                        color=C["text"],
                        text_align=ft.TextAlign.CENTER,
                    ),
                ],
                spacing=4,
                horizontal_alignment=ft.CrossAxisAlignment.CENTER,
            ),
            bgcolor=C["primary_soft"] if selected else C["surface_alt"],
            border=ft.Border.all(2 if selected else 1, C["primary"] if selected else C["border"]),
            border_radius=14,
            padding=ft.Padding(14, 12, 14, 12),
            expand=True,
            animate=ft.Animation(150),
        )

        # Container 本身沒有 mouse_cursor 屬性，用 GestureDetector 包一層來處理
        return ft.GestureDetector(
            content=container,
            on_tap=on_pick,
            mouse_cursor=ft.MouseCursor.CLICK,
            expand=True,
        )

    def _build_card(self, entry: DiffEntry, display_index: int) -> ft.Container:
        C = self.C

        def choose(side: int, _e=None):
            self.controller.set_choice(entry.index, side)
            fresh1 = self._value_block(entry, 1, entry.value1, lambda e: choose(1, e))
            fresh2 = self._value_block(entry, 2, entry.value2, lambda e: choose(2, e))
            block1.content.bgcolor = fresh1.content.bgcolor
            block1.content.border = fresh1.content.border
            block1.content.content = fresh1.content.content
            block2.content.bgcolor = fresh2.content.bgcolor
            block2.content.border = fresh2.content.border
            block2.content.content = fresh2.content.content

            block1.update()
            block2.update()

        block1 = self._value_block(entry, 1, entry.value1, lambda e: choose(1, e))
        block2 = self._value_block(entry, 2, entry.value2, lambda e: choose(2, e))

        index_badge = ft.Container(
            content=ft.Text(f"{display_index}", size=12, weight=ft.FontWeight.W_700, color=C["text_muted"]),
            bgcolor=C["chip_off_bg"],
            border_radius=10,
            padding=ft.Padding(8, 3, 8, 3),
            width=48,
            alignment=ft.Alignment.CENTER,
        )
        spacer = ft.Container(width=48)

        return ft.Container(
            content=ft.Column(
                [
                    ft.Row(
                        [
                            index_badge,
                            ft.Text(
                                entry.key_path,
                                weight=ft.FontWeight.W_800,
                                selectable=True,
                                size=17,
                                color=C["text"],
                                text_align=ft.TextAlign.CENTER,
                                expand=True,
                            ),
                            spacer,
                        ],
                        alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                    ),
                    ft.Row([block1, block2], spacing=12),
                ],
                spacing=12,
            ),
            bgcolor=C["surface"],
            border=ft.Border.all(1, C["border"]),
            border_radius=18,
            padding=16,
        )

    def _progress_summary(self) -> str:
        total = len(self.controller.entries)
        if total == 0:
            return ""
        unresolved = self.controller.unresolved_count
        return f"顯示 {len(self._visible_entries)} 筆（共 {total} 筆）· 尚有 {unresolved} 筆未選擇"

    def _update_progress_text(self) -> None:
        self.progress_text.value = self._progress_summary()
