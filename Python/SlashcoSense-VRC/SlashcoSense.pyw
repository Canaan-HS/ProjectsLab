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
from PySide6.QtCore import QTimer, Signal, Qt, QSize, QUrl
from PySide6.QtGui import QFont, QPixmap
from PySide6.QtNetwork import QNetworkAccessManager, QNetworkRequest, QNetworkReply

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
    "0": "舊 SlashCo 總部",
    "SlashCoHQ": "舊 SlashCo 總部",
    "1": "馬龍斯農場",
    "MalonesFarmyard": "馬龍斯農場",
    "2": "飛利浦韋斯特伍德高中",
    "PhilipsWestwoodHighSchool": "飛利浦韋斯特伍德高中",
    "3": "伊斯特伍德綜合醫院",
    "EastwoodGeneralHospital": "伊斯特伍德綜合醫院",
    "4": "三角洲研究設施",
    "ResearchFacilityDelta": "三角洲研究設施",
}

SLASHER_CHARACTERS = {
    0: {  # BABABOOEY
        "name": "巴巴布伊 【肌肉男】",
        "icon": "https://images.steamusercontent.com/ugc/2477635226930588606/2CAE95D776EFCD7F635B7CA497C43079BB9BD71C/",
    },
    1: {  # SID
        "name": "席德 【手槍怪 / 餅乾怪】",
        "icon": "https://images.steamusercontent.com/ugc/2477635226930588312/14B6C7D2AC9E6FC21936F1F2D46CCB1F040F6764/",
    },
    2: {  # TROLLAG
        "name": "特羅勒格巨魔【笑臉男】",
        "icon": "https://images.steamusercontent.com/ugc/2477635226930589045/28AD304EBFA4C6BD7636269FE86B9CCFC4146B35/",
    },
    3: {  # BORGMIRE
        "name": "博格梅爾【機器人】",
        "icon": "https://images.steamusercontent.com/ugc/2477635226930588057/1C8DCDC50F43E8D61E4CE530DF626AA518F0E3CC/",
    },
    4: {  # ABOMIGNAT
        "name": "阿博米納特【憎惡者】",
        "icon": "https://images.steamusercontent.com/ugc/2477635226930588840/1B1FF6A54E92C5CF5A928A2F4A78A79FB8ADADB0/",
    },
    5: {  # THIRSTY
        "name": "口渴 【爬行者 / 牛奶怪】",
        "icon": "https://images.steamusercontent.com/ugc/2477635226930588405/E7E2F6CB2AC3FB6F6F9DEBE0A7ADA4AF0C8DF232/",
    },
    6: {  # FATHER ELMER
        "name": "埃爾默神父 【霰彈槍 / 神父】",
        "icon": "https://images.steamusercontent.com/ugc/2477635226930588961/75CEA25777A1E5DE316CE2B424574D14F73461B9/",
    },
    7: {  # THE WATCHER
        "name": "觀察者 【高個子 / 火柴人】",
        "icon": "https://images.steamusercontent.com/ugc/2477635226930589113/62339E95829B59B81F89C8B910B481C890D9ADEF/",
    },
    8: {  # THE BEAST
        "name": "野獸 【貓貓 / 貓老太】",
        "icon": "https://images.steamusercontent.com/ugc/2477635226930589274/ED63301BDAE54DBF266EEE88A64BF471C2E78337/",
    },
    9: {  # DOLPHINMAN
        "name": "海豚人",
        "icon": "https://images.steamusercontent.com/ugc/7412825351520453/B2177B52B026AC287C4DEF5D59CC5A41669751C0/",
    },
    10: {  # IGOR
        "name": "伊戈爾",
        "icon": "https://images.steamusercontent.com/ugc/7417357814949731/8E94E82D4DB07D7153192F36B98075B19A6ADAE5/",
    },
    11: {  # THE GROUCH
        "name": "牢騷者",
        "icon": "https://images.steamusercontent.com/ugc/7417357814868973/3AA5C51CA2AD30A62BC5F03375197ADA60BE155D/",
    },
    12: {  # PRINCESS
        "name": "公主",
        "icon": "https://images.steamusercontent.com/ugc/7421615891170424/8C80D5AC4FBC1827B4FB7EAB032303ADC334E4A4/",
    },
    13: {  # SPEEDRUNNER
        "name": "極速奔跑者",
        "icon": "https://images.steamusercontent.com/ugc/7421615891170364/29FAAF0C483A0BC133A15EAECB18C1BE19392873/",
    },
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

# 進度條顏色映射
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
        # self.vrchat_log_dir = Path(__file__).parent / "test"
        self.vrchat_log_dir = Path.home() / "AppData/LocalLow/VRChat/VRChat"
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
        self.record_timestamp = {}  # 紀錄每種類型的最新時間戳

        self.image_cache = {}  # 圖片緩存，避免重複下載

        # 定時器設置
        self.log_timer = QTimer()
        self.log_timer.timeout.connect(self._monitor_logs)
        self.log_timer.start(LOG_UPDATE_INTERVAL)
        self.log_message.connect(self._append_log_message)

    def _setup_ui(self):
        """設置使用者介面"""
        self.setWindowTitle("SlashcoSense By:CanaanHS")
        self.setMinimumSize(QSize(500, 700))
        self.resize(QSize(800, 800))

        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        main_layout = QVBoxLayout(central_widget)
        main_layout.setSpacing(15)
        main_layout.setContentsMargins(15, 15, 15, 15)

        # 初始化網路管理器（用於載入圖片）
        self.network_manager = QNetworkAccessManager()
        self.network_manager.finished.connect(self._on_image_loaded)

        # 遊戲狀態群組
        game_group = QGroupBox("遊戲狀態")
        game_group.setFont(QFont("Microsoft YaHei", 12, QFont.Weight.Bold))

        # 修改為水平布局，左邊是遊戲資訊，右邊是圖片
        game_main_layout = QHBoxLayout(game_group)
        game_main_layout.setSpacing(15)

        # 左側：遊戲資訊
        game_info_widget = QWidget()
        game_layout = QVBoxLayout(game_info_widget)
        game_layout.setContentsMargins(0, 0, 0, 0)

        # 上方彈性空間 - 把內容推到中間
        game_layout.addStretch()

        self.map_label = QLabel("地圖: 未知")
        self.slasher_label = QLabel("殺手: 未知")
        self.items_label = QLabel("生成物品: 無")

        font = QFont("Microsoft YaHei", 11)
        for label in [self.map_label, self.slasher_label, self.items_label]:
            label.setFont(font)

        # 手動添加文字和間距
        game_layout.addWidget(self.map_label)
        game_layout.addSpacing(20)  # 手動設置間距
        game_layout.addWidget(self.slasher_label)
        game_layout.addSpacing(20)  # 手動設置間距
        game_layout.addWidget(self.items_label)

        # 下方彈性空間 - 平衡上方空間
        game_layout.addStretch()

        # 右側：圖像框
        image_widget = QWidget()
        image_layout = QVBoxLayout(image_widget)
        image_layout.setContentsMargins(0, 0, 10, 0)

        # 圖片顯示標籤
        self.image_label = QLabel()
        self.image_label.setObjectName("imageDisplay")
        self.image_label.setFixedSize(200, 200)
        self.image_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.image_label.setText("未知")
        self.image_label.setScaledContents(True)

        image_layout.addWidget(self.image_label)

        # 將左右兩側添加到主布局
        game_main_layout.addWidget(game_info_widget, 1)  # 權重1，可以伸縮
        game_main_layout.addWidget(image_widget, 0)  # 權重0，固定大小

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

        gen_widget1 = QWidget()
        gen_widget1.setLayout(gen1_layout)
        gen_widget2 = QWidget()
        gen_widget2.setLayout(gen2_layout)

        gen_layout.addWidget(gen_widget1)
        gen_layout.addWidget(gen_widget2)

        warning = QLabel("發電機監控僅限非房主有效")
        warning.setObjectName("warningText")
        warning.setAlignment(Qt.AlignmentFlag.AlignCenter)
        gen_layout.addWidget(warning)

        # OSC 設置群組
        osc_group = QGroupBox("OSC 設置")
        osc_group.setFont(QFont("Microsoft YaHei", 12, QFont.Weight.Bold))
        osc_layout = QHBoxLayout(osc_group)
        osc_layout.setSpacing(15)

        self.osc_enabled_checkbox = QCheckBox("啟用 OSC")
        self.osc_enabled_checkbox.toggled.connect(self._toggle_osc)
        self.osc_log_enabled_checkbox = QCheckBox("顯示 OSC 日誌")
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
            QLabel#imageDisplay {
                border: 2px solid #555555;
                background-color: #404040;
                border-radius: 8px;
                color: #888888;
                font-size: 12px;
            }
            QLabel#warningText {
                color: #888888;
                font-size: 10px;
            }
        """
        )

    def _set_image_url(self, url: str):
        """設置圖片URL（程式接口）"""
        if url:
            # 先檢查緩存
            if url in self.image_cache:
                # 從緩存中直接取得圖片
                cached_pixmap = self.image_cache[url]
                scaled_pixmap = cached_pixmap.scaled(
                    self.image_label.size(),
                    Qt.AspectRatioMode.KeepAspectRatio,
                    Qt.TransformationMode.SmoothTransformation,
                )
                self.image_label.setPixmap(scaled_pixmap)
                return

            # 如果緩存中沒有，才進行網路請求
            request = QNetworkRequest(QUrl(url))
            # 將URL存儲到請求中，方便回調時使用
            request.setAttribute(QNetworkRequest.Attribute.User, url)
            self.network_manager.get(request)
            self.image_label.setText("載入中...")
        else:
            self.image_label.clear()
            self.image_label.setText("未知")

    def _on_image_loaded(self, reply: QNetworkReply):
        """圖片載入完成的回調"""
        url = reply.request().attribute(QNetworkRequest.Attribute.User)

        if reply.error() == QNetworkReply.NetworkError.NoError:
            # 成功載入圖片
            image_data = reply.readAll()
            pixmap = QPixmap()
            if pixmap.loadFromData(image_data):
                # 將原始圖片存儲到緩存中
                if url:
                    self.image_cache[url] = pixmap

                    # 可選：限制緩存大小，避免內存過度使用
                    if len(self.image_cache) > 50:  # 最多緩存50張圖片
                        # 移除最舊的緩存項目（簡單的FIFO策略）
                        oldest_url = next(iter(self.image_cache))
                        del self.image_cache[oldest_url]

                # 縮放圖片以適應標籤大小
                scaled_pixmap = pixmap.scaled(
                    self.image_label.size(),
                    Qt.AspectRatioMode.KeepAspectRatio,
                    Qt.TransformationMode.SmoothTransformation,
                )
                self.image_label.setPixmap(scaled_pixmap)
            else:
                self.image_label.setText("格式錯誤")
        else:
            # 載入失敗
            self.image_label.setText("載入失敗")

        reply.deleteLater()

    def _toggle_osc(self, enabled: bool):
        """切換 OSC 狀態"""
        if enabled:
            try:
                port = int(self.port_input.text())
                if 1 <= port <= 65535 and UDP_CLIENT_AVAILABLE:
                    self.osc_client = udp_client.SimpleUDPClient("127.0.0.1", port)
                    self.osc_enabled = True
                    self.log_message.emit(f"OSC 已啟用（埠：{port}）")
                else:
                    self.log_message.emit("錯誤：埠號無效或OSC不可用")
                    self.osc_enabled_checkbox.setChecked(False)
            except (ValueError, Exception):
                self.log_message.emit("錯誤：OSC 啟用失敗")
                self.osc_enabled_checkbox.setChecked(False)
        else:
            self.osc_client = None
            self.osc_enabled = False
            self.log_message.emit("OSC 已停用")

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
                search_key = match.group(2) if data_type == "generator" else data_type

                log_timestamp = match.group(1)
                record_timestamp = self.record_timestamp.get(search_key, log_timestamp)

                if log_timestamp < record_timestamp:
                    continue

                self.record_timestamp[search_key] = log_timestamp

            except (ValueError, IndexError):
                pass

            if data_type == "map":
                map_val = match.group(2).strip()
                map_name = GAME_MAPS.get(map_val, map_val)
                self.map_label.setText(f"地圖: \n{map_name}")
                log_parts.append(f"地圖: {map_name}")

                reset_needed = True

            elif data_type == "slasher":
                slasher_id = int(match.group(2))

                # 獲取殺手映射
                slasher_data = SLASHER_CHARACTERS.get(
                    slasher_id, {"name": f"未知殺手({slasher_id})", "icon": None}
                )

                name = slasher_data["name"]
                icon = slasher_data["icon"]

                # 更新UI
                self.slasher_label.setText(f"殺手: \n{name}")

                # 更新圖片
                if icon:
                    self._set_image_url(icon)
                else:
                    self._set_image_url("")  # 顯示預設的"未知"

                reset_needed = True

                # 直接發送OSC
                if (
                    self._send_osc("SlasherID", slasher_id)
                    and self.osc_log_enabled_checkbox.isChecked()
                ):
                    self.log_message.emit(f"[OSC] 發送 SlasherID: {slasher_id}")

            elif data_type == "items":
                items = match.group(2).strip()
                self.items_label.setText(f"生成物品: \n{items}")
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
