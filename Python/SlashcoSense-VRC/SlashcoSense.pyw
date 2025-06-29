# Original Author : https://github.com/arcxingye/SlasherSense-VRC/

from __future__ import annotations

import re
import sys
from datetime import datetime
from pathlib import Path
from typing import Dict, Optional, Any, TYPE_CHECKING

from PySide6.QtWidgets import (
    QApplication,
    QMainWindow,
    QWidget,
    QVBoxLayout,
    QHBoxLayout,
    QLabel,
    QProgressBar,
    QTextEdit,
    QCheckBox,
    QLineEdit,
    QGroupBox,
)
from PySide6.QtCore import QTimer, Signal, Qt, QSize
from PySide6.QtGui import QFont

try:
    from pythonosc import udp_client

    UDP_CLIENT_AVAILABLE = True
except ImportError:
    udp_client = None
    UDP_CLIENT_AVAILABLE = False

if TYPE_CHECKING:
    from pythonosc.udp_client import SimpleUDPClient

DEFAULT_OSC_PORT = 9000  # 默認埠號
LOG_UPDATE_INTERVAL = 500  # 日誌更新間隔 (毫秒)

# 遊戲資料映射
GAME_MAPS = {
    "SlashCoHQ": "舊 SlashCo 總部",
    "MalonesFarmyard": "馬龍斯農場",
    "PhilipsWestwoodHighSchool": "飛利浦韋斯特伍德高中",
    "EastwoodGeneralHospital": "伊斯特伍德綜合醫院",
    "ResearchFacilityDelta": "三角洲研究設施",
}

SLASHER_CHARACTERS = {
    0: "巴巴布伊",
    1: "席德",
    2: "特羅勒格巨魔",
    3: "博格梅爾",
    4: "阿博米納特",
    5: "口渴",
    6: "埃爾默神父",
    7: "觀察者",
    8: "野獸",
    9: "海豚人",
    10: "伊戈爾",
    11: "牢騷者",
    12: "公主",
    13: "極速奔跑者",
}

# 預編譯正則表達式
LOG_PATTERNS = (
    (re.compile(r"(\d{4}\.\d{2}\.\d{2} \d{2}:\d{2}:\d{2}).*?Played Map:\s*([^,]+)"), "map"),
    (re.compile(r"(\d{4}\.\d{2}\.\d{2} \d{2}:\d{2}:\d{2}).*?Slasher:\s*(\d+)"), "slasher"),
    (
        re.compile(
            r"(\d{4}\.\d{2}\.\d{2} \d{2}:\d{2}:\d{2}).*?Selected Items:\s*(.+?)(?=,\s*\w+:|$)"
        ),
        "items",
    ),
    (
        re.compile(
            r"(\d{4}\.\d{2}\.\d{2} \d{2}:\d{2}:\d{2}).*?SC_(generator\d+) Progress check\. Last (\w+) value: (.*?), updated (\w+) value: (.*)"
        ),
        "generator",
    ),
)

# 進度條顏色映射 - 避免重複計算
PROGRESS_COLORS = {
    (0, 25): "#555555",  # 灰色
    (25, 50): "#e74c3c",  # 紅色
    (50, 75): "#f39c12",  # 黃色
    (75, 100): "#27ae60",  # 綠色
}


def get_progress_color(value: int) -> str:
    """快速獲取進度條顏色"""
    for (min_val, max_val), color in PROGRESS_COLORS.items():
        if min_val <= value <= max_val:
            return color
    return "#27ae60"  # 默認綠色


class ProgressBar(QProgressBar):
    """進度條 - 減少樣式更新開銷"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setMinimumHeight(25)
        self.setTextVisible(True)
        self.setRange(0, 100)
        self._current_color = "#555555"
        self._apply_style(self._current_color)

    def setValue(self, value: int):
        super().setValue(value)
        # 只在顏色改變時更新樣式
        new_color = get_progress_color(value)
        if new_color != self._current_color:
            self._current_color = new_color
            self._apply_style(new_color)

    def _apply_style(self, color: str):
        self.setStyleSheet(
            f"""
            QProgressBar {{
                border: 2px solid #3c3c3c; border-radius: 8px; background-color: #2c2c2c;
                text-align: center; font-weight: bold; font-size: 12px; color: white;
            }}
            QProgressBar::chunk {{ background-color: {color}; border-radius: 6px; margin: 1px; }}
        """
        )


class SlashcoSenseMainWindow(QMainWindow):
    """主視窗類"""

    log_message = Signal(str)

    def __init__(self):
        super().__init__()
        # 直接初始化所有屬性，避免額外的對象創建
        self.osc_client: Optional[SimpleUDPClient] = None
        self.osc_enabled = False
        self.vrchat_log_dir = Path(__file__).parent / "test"
        # self.vrchat_log_dir = Path.home() / "AppData/LocalLow/VRChat/VRChat"
        self.current_log_file: Optional[Path] = None
        self.file_position = 0

        # 預分配生成器引用 - 避免字典查找
        self.gen1_progress: Optional[ProgressBar] = None
        self.gen1_label: Optional[QLabel] = None
        self.gen1_battery: Optional[QLabel] = None
        self.gen2_progress: Optional[ProgressBar] = None
        self.gen2_label: Optional[QLabel] = None
        self.gen2_battery: Optional[QLabel] = None

        self._setup_ui()
        self._apply_dark_theme()

        self.initial = True  # 初始狀態標誌
        self.type_timestamp = {}  # 紀錄每種類型的最新時間戳

        # 定時器設置
        self.log_timer = QTimer()
        self.log_timer.timeout.connect(self._monitor_logs)
        self.log_timer.start(LOG_UPDATE_INTERVAL)
        self.log_message.connect(self._append_log_message)

    def _setup_ui(self):
        """設置使用者介面"""
        self.setWindowTitle("SlashcoSense By:CanaanHS")
        self.setMinimumSize(QSize(500, 700))
        self.resize(QSize(600, 800))

        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        main_layout = QVBoxLayout(central_widget)
        main_layout.setSpacing(15)
        main_layout.setContentsMargins(15, 15, 15, 15)

        # 遊戲狀態群組
        game_group = QGroupBox("遊戲狀態")
        game_group.setFont(QFont("Microsoft YaHei", 12, QFont.Weight.Bold))
        game_layout = QVBoxLayout(game_group)
        game_layout.setSpacing(8)

        self.map_label = QLabel("地圖: 未知")
        self.slasher_label = QLabel("殺手: 未知")
        self.items_label = QLabel("生成物品: 無")

        font = QFont("Microsoft YaHei", 11)
        for label in [self.map_label, self.slasher_label, self.items_label]:
            label.setFont(font)
            game_layout.addWidget(label)

        # 發電機狀態群組 - 直接創建，避免循環開銷
        gen_group = QGroupBox("發電機狀態")
        gen_group.setFont(QFont("Microsoft YaHei", 12, QFont.Weight.Bold))
        gen_layout = QVBoxLayout(gen_group)
        gen_layout.setSpacing(10)

        # 發電機1
        gen1_layout = QHBoxLayout()
        gen1_layout.setSpacing(10)
        self.gen1_label = QLabel("發電機1")
        self.gen1_label.setMinimumWidth(20)
        self.gen1_label.setFont(QFont("Microsoft YaHei", 11, QFont.Weight.Bold))
        self.gen1_progress = ProgressBar()
        self.gen1_progress.setMinimumWidth(250)
        self.gen1_battery = QLabel("電池: ❌")
        self.gen1_battery.setMinimumWidth(70)
        self.gen1_battery.setFont(QFont("Microsoft YaHei", 10))

        gen1_layout.addWidget(self.gen1_label)
        gen1_layout.addWidget(self.gen1_progress)
        gen1_layout.addWidget(self.gen1_battery)
        gen1_layout.addStretch()

        # 發電機2
        gen2_layout = QHBoxLayout()
        gen2_layout.setSpacing(10)
        self.gen2_label = QLabel("發電機2")
        self.gen2_label.setMinimumWidth(20)
        self.gen2_label.setFont(QFont("Microsoft YaHei", 11, QFont.Weight.Bold))
        self.gen2_progress = ProgressBar()
        self.gen2_progress.setMinimumWidth(250)
        self.gen2_battery = QLabel("電池: ❌")
        self.gen2_battery.setMinimumWidth(70)
        self.gen2_battery.setFont(QFont("Microsoft YaHei", 10))

        gen2_layout.addWidget(self.gen2_label)
        gen2_layout.addWidget(self.gen2_progress)
        gen2_layout.addWidget(self.gen2_battery)
        gen2_layout.addStretch()

        gen_widget1 = QWidget()
        gen_widget1.setLayout(gen1_layout)
        gen_widget2 = QWidget()
        gen_widget2.setLayout(gen2_layout)

        gen_layout.addWidget(gen_widget1)
        gen_layout.addWidget(gen_widget2)

        warning = QLabel("發電機監控僅限非房主有效")
        warning.setStyleSheet("color: #888888; font-size: 10px;")
        warning.setAlignment(Qt.AlignmentFlag.AlignCenter)
        gen_layout.addWidget(warning)

        # OSC 設置群組
        osc_group = QGroupBox("OSC 設置")
        osc_group.setFont(QFont("Microsoft YaHei", 12, QFont.Weight.Bold))
        osc_layout = QHBoxLayout(osc_group)
        osc_layout.setSpacing(15)

        self.osc_enabled_checkbox = QCheckBox("啟用OSC")
        self.osc_enabled_checkbox.toggled.connect(self._toggle_osc)
        self.osc_log_enabled_checkbox = QCheckBox("顯示OSC日誌")
        self.osc_log_enabled_checkbox.setChecked(True)

        self.port_input = QLineEdit(str(DEFAULT_OSC_PORT))
        self.port_input.setMaximumWidth(80)

        osc_layout.addWidget(self.osc_enabled_checkbox)
        osc_layout.addWidget(self.osc_log_enabled_checkbox)
        osc_layout.addStretch()
        osc_layout.addWidget(QLabel("埠號:"))
        osc_layout.addWidget(self.port_input)

        # 日誌顯示群組
        log_group = QGroupBox("即時日誌")
        log_group.setFont(QFont("Microsoft YaHei", 12, QFont.Weight.Bold))
        log_layout = QVBoxLayout(log_group)

        self.log_display = QTextEdit()
        self.log_display.setReadOnly(True)
        self.log_display.setFont(QFont("Consolas", 10))
        log_layout.addWidget(self.log_display)

        # 添加所有群組到主布局
        main_layout.addWidget(game_group)
        main_layout.addWidget(gen_group)
        main_layout.addWidget(osc_group)
        main_layout.addWidget(log_group)

    def _apply_dark_theme(self):
        """應用暗黑主題"""
        self.setStyleSheet(
            """
            QMainWindow { background-color: #2b2b2b; color: #ffffff; }
            QGroupBox {
                font-weight: bold; border: 2px solid #3c3c3c; border-radius: 8px;
                margin-top: 1ex; padding-top: 10px; background-color: #333333;
            }
            QGroupBox::title {
                subcontrol-origin: margin; left: 10px; padding: 0 5px 0 5px; color: #ffffff;
            }
            QLabel { color: #ffffff; background-color: transparent; }
            QCheckBox { color: #ffffff; spacing: 5px; }
            QCheckBox::indicator { width: 18px; height: 18px; }
            QCheckBox::indicator:unchecked {
                border: 2px solid #555555; background-color: #2b2b2b; border-radius: 3px;
            }
            QCheckBox::indicator:checked {
                border: 2px solid #3498db; background-color: #3498db; border-radius: 3px;
            }
            QLineEdit {
                background-color: #404040; border: 2px solid #555555; border-radius: 4px;
                padding: 5px; color: #ffffff;
            }
            QLineEdit:focus { border-color: #3498db; }
            QTextEdit {
                background-color: #1e1e1e; border: 2px solid #3c3c3c; border-radius: 8px;
                color: #ffffff; selection-background-color: #3498db;
            }
        """
        )

    def _toggle_osc(self, enabled: bool):
        """切換 OSC 狀態"""
        if enabled:
            try:
                port = int(self.port_input.text())
                if 1 <= port <= 65535 and UDP_CLIENT_AVAILABLE:
                    self.osc_client = udp_client.SimpleUDPClient("127.0.0.1", port)
                    self.osc_enabled = True
                    self.log_message.emit(f"OSC已啟用（埠：{port}）")
                else:
                    self.log_message.emit("錯誤：埠號無效或OSC不可用")
                    self.osc_enabled_checkbox.setChecked(False)
            except (ValueError, Exception):
                self.log_message.emit("錯誤：OSC啟用失敗")
                self.osc_enabled_checkbox.setChecked(False)
        else:
            self.osc_client = None
            self.osc_enabled = False
            self.log_message.emit("OSC已停用")

    def _send_osc(self, param: str, value: Any) -> bool:
        """快速發送OSC參數"""
        if self.osc_enabled and self.osc_client:
            try:
                self.osc_client.send_message(f"/avatar/parameters/{param}", value)
                return True
            except Exception:
                pass
        return False

    def _monitor_logs(self):
        """日誌監控"""
        try:
            # 檢查新文件
            if not self.vrchat_log_dir.exists():
                return

            log_files = list(self.vrchat_log_dir.glob("output_log_*.txt"))

            if not log_files:
                return

            latest_file = max(log_files, key=lambda f: f.stat().st_mtime)
            if latest_file != self.current_log_file:
                self.current_log_file = latest_file
                self.file_position = 0
                self.log_message.emit(f"開始監控日誌文件: {latest_file.name}")

            # 讀取新行
            if self.current_log_file.exists():
                with open(self.current_log_file, "r", encoding="utf-8", errors="ignore") as file:
                    file.seek(self.file_position)
                    new_content = file.read()
                    self.file_position = file.tell()

                if new_content:
                    # 按行處理，但只進行一次文件讀取
                    for line in reversed(new_content.splitlines()):
                        if line.strip():
                            self._process_log_line(line.strip())
        except Exception:
            pass

    def _process_log_line(self, line: str):
        """日誌處理"""
        log_parts = []
        reset_needed = False

        # 單次遍歷所有模式，避免重複搜索
        for pattern, data_type in LOG_PATTERNS:
            match = pattern.search(line)

            if not match:
                continue

            try:
                log_timestamp = match.group(1)
                type_timestamp = self.type_timestamp.get(data_type, log_timestamp)

                if log_timestamp < type_timestamp:
                    continue

                self.type_timestamp[data_type] = log_timestamp

            except (ValueError, IndexError):
                # 如果時間戳解析失敗，仍然處理該日誌
                pass

            if data_type == "map":
                map_val = match.group(2).strip()
                map_name = GAME_MAPS.get(map_val, map_val)
                self.map_label.setText(f"地圖: {map_name}")
                log_parts.append(f"地圖: {map_name}")

                reset_needed = True

            elif data_type == "slasher":
                slasher_id = int(match.group(2))
                slasher_name = SLASHER_CHARACTERS.get(slasher_id, f"未知殺手({slasher_id})")
                self.slasher_label.setText(f"殺手: {slasher_name}")
                log_parts.append(f"殺手: {slasher_name}")

                reset_needed = True

                # 直接發送OSC
                if (
                    self._send_osc("SlasherID", slasher_id)
                    and self.osc_log_enabled_checkbox.isChecked()
                ):
                    self.log_message.emit(f"[OSC] 發送 SlasherID: {slasher_id}")

            elif data_type == "items":
                items = match.group(2).strip()
                self.items_label.setText(f"生成物品: {items}")
                log_parts.append(f"物品: {items}")

            elif data_type == "generator":
                _, gen_name, var_type, _, _, new_value = match.groups()
                self._update_generator(gen_name, var_type, new_value)
                log_parts.append(f"{gen_name} {var_type}: {new_value}")

        if log_parts:
            self.log_message.emit(" | ".join(log_parts))

        if reset_needed and not self.initial:
            self._reset_generators()
        elif reset_needed and self.initial:
            self.initial = False

    def _reset_generators(self):
        """重置所有發電機狀態 (不透過 _update_generator 更新, 減少性能開銷)"""

        # 重置發電機1
        self.gen1_progress.setValue(0)
        self.gen1_battery.setText("電池: ❌")

        # 重置發電機2
        self.gen2_progress.setValue(0)
        self.gen2_battery.setText("電池: ❌")

        # 直接發送OSC消息
        if self.osc_enabled:
            self._send_osc("GENERATOR1_FUEL", 0)
            self._send_osc("GENERATOR1_BATTERY", 0)
            self._send_osc("GENERATOR2_FUEL", 0)
            self._send_osc("GENERATOR2_BATTERY", 0)

            if self.osc_log_enabled_checkbox.isChecked():
                self.log_message.emit("[OSC] 重置所有狀態")

    def _update_generator(self, gen_name: str, var_type: str, new_value: str):
        """發電機更新 - 直接訪問UI元素"""
        try:
            if var_type == "REMAINING":
                filled = 4 - int(new_value)
                progress = (filled * 100) // 4  # 使用整數除法

                # 直接更新對應的發電機，避免字典查找
                if gen_name == "generator1":
                    self.gen1_progress.setValue(progress)
                    if (
                        self._send_osc("GENERATOR1_FUEL", filled)
                        and self.osc_log_enabled_checkbox.isChecked()
                    ):
                        self.log_message.emit(f"[OSC] 發送 GENERATOR1_FUEL: {filled}")
                elif gen_name == "generator2":
                    self.gen2_progress.setValue(progress)
                    if (
                        self._send_osc("GENERATOR2_FUEL", filled)
                        and self.osc_log_enabled_checkbox.isChecked()
                    ):
                        self.log_message.emit(f"[OSC] 發送 GENERATOR2_FUEL: {filled}")

            elif var_type == "HAS_BATTERY":
                has_battery = new_value.lower() == "true"
                battery_text = "電池: ✅" if has_battery else "電池: ❌"
                battery_value = 1 if has_battery else 0

                if gen_name == "generator1":
                    self.gen1_battery.setText(battery_text)
                    if (
                        self._send_osc("GENERATOR1_BATTERY", battery_value)
                        and self.osc_log_enabled_checkbox.isChecked()
                    ):
                        self.log_message.emit(f"[OSC] 發送 GENERATOR1_BATTERY: {battery_value}")
                elif gen_name == "generator2":
                    self.gen2_battery.setText(battery_text)
                    if (
                        self._send_osc("GENERATOR2_BATTERY", battery_value)
                        and self.osc_log_enabled_checkbox.isChecked()
                    ):
                        self.log_message.emit(f"[OSC] 發送 GENERATOR2_BATTERY: {battery_value}")
        except ValueError:
            pass

    def _append_log_message(self, message: str):
        """添加日誌訊息"""
        timestamp = datetime.now().strftime("[%H:%M:%S]")
        self.log_display.append(f"{timestamp} {message}")

        # 保持日誌在底部
        scrollbar = self.log_display.verticalScrollBar()
        scrollbar.setValue(scrollbar.maximum())


if __name__ == "__main__":
    app = QApplication(sys.argv)
    window = SlashcoSenseMainWindow()
    window.show()
    sys.exit(app.exec())
