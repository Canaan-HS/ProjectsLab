# Original Author : https://github.com/arcxingye/SlasherSense-VRC/

from __future__ import annotations

import re
import sys
from datetime import datetime
from pathlib import Path
from typing import Optional, Any, TYPE_CHECKING

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
from PySide6.QtCore import Qt, QTimer, Signal, QSize, QUrl
from PySide6.QtGui import QFont, QIcon, QCursor, QPixmap, QPainter, QPixmapCache, QPainterPath
from PySide6.QtNetwork import QNetworkAccessManager, QNetworkRequest, QNetworkReply

try:
    from pythonosc import udp_client

    UDP_CLIENT_AVAILABLE = True
except ImportError:
    udp_client = None
    UDP_CLIENT_AVAILABLE = False

if TYPE_CHECKING:
    from pythonosc.udp_client import SimpleUDPClient

# 地圖映射
GAME_MAPS = {
    "0": "舊 SlashCo 總部",
    "SlashCoHQ": "舊 SlashCo 總部",
    "1": "馬龍斯農場",
    "MalonesFarmyard": "馬龍斯農場",
    "2": "菲利普斯•書斯特伍德高中",
    "PhilipsWestwoodHighSchool": "菲利普斯•書斯特伍德高中",
    "3": "伊斯特伍德綜合醫院",
    "EastwoodGeneralHospital": "伊斯特伍德綜合醫院",
    "4": "德爾塔科研機構",
    "ResearchFacilityDelta": "德爾塔科研機構",
}

# 殺手映射
SLASHERS = {
    0: {  # BABABOOEY
        "name": "巴巴布伊 【肌肉男 / 隱形怪】",
        "icon": "https://images.steamusercontent.com/ugc/2477635226930588606/2CAE95D776EFCD7F635B7CA497C43079BB9BD71C/",
    },
    1: {  # SID
        "name": "席德 【手槍怪 / 餅乾怪】",
        "icon": "https://images.steamusercontent.com/ugc/2477635226930588312/14B6C7D2AC9E6FC21936F1F2D46CCB1F040F6764/",
    },
    2: {  # TROLLAG
        "name": "特羅勒格巨魔【笑臉男 / 火柴人】",
        "icon": "https://images.steamusercontent.com/ugc/2477635226930589045/28AD304EBFA4C6BD7636269FE86B9CCFC4146B35/",
    },
    3: {  # BORGMIRE
        "name": "博格梅爾【機器人】",
        "icon": "https://images.steamusercontent.com/ugc/2477635226930588057/1C8DCDC50F43E8D61E4CE530DF626AA518F0E3CC/",
    },
    4: {  # ABOMIGNAT
        "name": "阿博米納特【憎惡者 / 外星人】",
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
        "name": "觀察者 【高個子】",
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
        "name": "伊戈爾【DJ / 創造者 / 毀滅者】",
        "icon": "https://images.steamusercontent.com/ugc/7417357814949731/8E94E82D4DB07D7153192F36B98075B19A6ADAE5/",
    },
    11: {  # THE GROUCH
        "name": "牢騷者【乞丐】",
        "icon": "https://images.steamusercontent.com/ugc/7417357814868973/3AA5C51CA2AD30A62BC5F03375197ADA60BE155D/",
    },
    12: {  # PRINCESS
        "name": "公主【狗】",
        "icon": "https://images.steamusercontent.com/ugc/7421615891170424/8C80D5AC4FBC1827B4FB7EAB032303ADC334E4A4/",
    },
    13: {  # SPEEDRUNNER
        "name": "極速奔跑者【Dream】",
        "icon": "https://images.steamusercontent.com/ugc/7421615891170364/29FAAF0C483A0BC133A15EAECB18C1BE19392873/",
    },
}

# 物品映射
ITEMS = {
    "Proxy-Locator": "定位器",
    "Royal Burger": "皇家漢堡",
    "Cookie": "曲奇",
    "Beer Keg": "啤酒桶",
    "Mayonnaise": "蛋黃醬",
    "Orange Jello": "橙色果凍",
    "Costco Frozen Pizza": "COSTCO速凍披薩",
    "Airport Jungle Juice": "機場的烈性酒",
    "Rhino Pill": "犀牛丸",
    "The Rock": "岩石",
    "Lab-Grown Meat": "人造肉",
    "Pocket Sand": "沙袋",
    "The Baby": "巫毒娃娃",
    "Newport Menthols": "紐波特薄荷",
    "B-GONE Soda": "B-GONE蘇打水",
    "Red40": "40號紅色染劑",
    "Red40 Vial": "40號紅色染劑",
    "Milk Jug": "桶裝牛奶",
    "Pot of Greed": "貪婪之壺",
    "Deathward": "不死圖騰",
    "Evil Jonkler Cart": "邪惡的瓊克爾•卡特",
    "25 Gram Benadryl": "25克苯海拉明",
    "Balkan Boost": "巴爾幹激素",
}

DEFAULT_OSC_PORT = 9000  # 默認埠號
LOG_UPDATE_INTERVAL = 500  # 日誌更新間隔 (毫秒)
VRC_LOG_DIR = Path.home() / "AppData/LocalLow/VRChat/VRChat"  # VRChat 日誌目錄
WINDOWS_ICON_URL = "https://images.steamusercontent.com/ugc/2477635226930601215/D3708CAF453353764ADE800A779730BFCEF83408/"

# 編譯物品解析正則
ITEMS_PATTERN = re.compile(
    "|".join(re.escape(key) for key in sorted(ITEMS.keys(), key=len, reverse=True)), re.IGNORECASE
)

# 編譯類型解析正則
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
    """獲取進度條顏色"""
    for (min_val, max_val), color in PROGRESS_COLORS.items():
        if min_val <= value <= max_val:
            return color
    return "#2c2c2c"  # 默認


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


def parse_items(items: str) -> str:
    """解析物品列表"""
    if not items:
        return ""

    matches = list(ITEMS_PATTERN.finditer(items))
    if not matches:
        return items

    result = []
    last_end = 0

    for match in matches:
        start, end = match.span()

        if start > last_end:
            unmatched = items[last_end:start].strip()
            if unmatched:
                result.append(unmatched)

        result.append(ITEMS[match.group()])
        last_end = end

    if last_end < len(items):
        unmatched = items[last_end:].strip()
        if unmatched:
            result.append(unmatched)

    return " / ".join(result)


class SlashcoSenseMainWindow(QMainWindow):
    """主視窗類"""

    log_message = Signal(str)

    def __init__(self):
        super().__init__()

        self.log_dir = VRC_LOG_DIR

        # 開發測試用 (我本人沒玩 Slashco，所以沒有日誌目錄)
        if not self.log_dir.exists():
            self.log_dir = Path(__file__).parent / "TEST"

        # 初始化網路管理器（用於載入圖片）
        self.network_manager = QNetworkAccessManager()
        self.network_manager.finished.connect(self._on_image_loaded)

        self.info_cache = ""  # 資訊緩存
        self.reset_mark = False  # 重置標記
        self.record_timestamp = {}  # 紀錄每種類型的最新時間戳

        self.gen1_progress: Optional[ProgressBar] = None
        self.gen1_label: Optional[QLabel] = None
        self.gen1_battery: Optional[QLabel] = None
        self.gen2_progress: Optional[ProgressBar] = None
        self.gen2_label: Optional[QLabel] = None
        self.gen2_battery: Optional[QLabel] = None

        self.osc_enabled = False
        self.osc_client: Optional[SimpleUDPClient] = None

        self.file_position = 0
        self.current_log_file: Optional[Path] = None

        # 初始化UI
        self._setup_ui()
        self._apply_dark_theme()

        # 定時器 與 連結 設置
        self.log_timer = QTimer()
        self.log_timer.timeout.connect(self._monitor_logs)
        self.log_timer.start(LOG_UPDATE_INTERVAL)
        self.log_message.connect(self._append_log_message)

    def _setup_ui(self):
        """設置使用者介面"""
        self.setWindowTitle("SlashCoSense")
        self.setMinimumSize(QSize(500, 700))
        self.resize(QSize(800, 800))

        icon = QNetworkRequest(QUrl(WINDOWS_ICON_URL))
        icon.setAttribute(QNetworkRequest.Attribute.User, "icon")
        self.network_manager.get(icon)

        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        main_layout = QVBoxLayout(central_widget)
        main_layout.setSpacing(15)
        main_layout.setContentsMargins(15, 15, 15, 15)

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
        image_layout.setContentsMargins(0, 0, 5, 0)

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

        # 發電機 1
        gen1_layout = QHBoxLayout()
        gen1_layout.setSpacing(10)
        self.gen1_label = QLabel("發電機 1")
        self.gen1_label.setMinimumWidth(20)
        self.gen1_label.setFont(QFont("Microsoft YaHei", 11, QFont.Weight.Bold))
        self.gen1_progress = ProgressBar()
        self.gen1_progress.setMinimumWidth(250)
        self.gen1_battery = QLabel("電池: ❌")
        self.gen1_battery.setMinimumWidth(70)
        self.gen1_battery.setFont(QFont("Microsoft YaHei", 12))

        gen1_layout.addWidget(self.gen1_label)
        gen1_layout.addWidget(self.gen1_progress)
        gen1_layout.addWidget(self.gen1_battery)

        # 發電機 2
        gen2_layout = QHBoxLayout()
        gen2_layout.setSpacing(10)
        self.gen2_label = QLabel("發電機 2")
        self.gen2_label.setMinimumWidth(20)
        self.gen2_label.setFont(QFont("Microsoft YaHei", 11, QFont.Weight.Bold))
        self.gen2_progress = ProgressBar()
        self.gen2_progress.setMinimumWidth(250)
        self.gen2_battery = QLabel("電池: ❌")
        self.gen2_battery.setMinimumWidth(70)
        self.gen2_battery.setFont(QFont("Microsoft YaHei", 12))

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
        self.osc_enabled_checkbox.setCursor(QCursor(Qt.CursorShape.PointingHandCursor))

        self.osc_log_enabled_checkbox = QCheckBox("顯示 OSC 日誌")
        self.osc_log_enabled_checkbox.setCursor(QCursor(Qt.CursorShape.PointingHandCursor))
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
                border: 2px solid #27ae60; background-color: #27ae60; border-radius: 3px;
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

    def _rounded_pixmap(self, pixmap: QPixmap, radius: int) -> QPixmap:
        size = pixmap.size()
        mask = QPixmap(size)
        mask.fill(Qt.GlobalColor.transparent)

        painter = QPainter(mask)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        path = QPainterPath()
        path.addRoundedRect(0, 0, size.width(), size.height(), radius, radius)
        painter.setClipPath(path)
        painter.drawPixmap(0, 0, pixmap)
        painter.end()

        return mask

    def _on_image_loaded(self, reply: QNetworkReply):
        """圖片載入完成的回調"""
        url = reply.request().attribute(QNetworkRequest.Attribute.User)

        if reply.error() == QNetworkReply.NetworkError.NoError:
            pixmap = QPixmap()
            image_data = reply.readAll()

            if url == "icon" and pixmap.loadFromData(image_data):  # 載入圖標
                # 裁出圖片中心的正方形區域
                w, h = pixmap.width(), pixmap.height()
                side = min(w, h)
                x = (w - side) // 2
                y = (h - side) // 2
                center_crop = pixmap.copy(x, y, side, side)

                # 圖標大小
                icon_size = 124
                scaled = center_crop.scaled(
                    icon_size, icon_size, Qt.KeepAspectRatio, Qt.SmoothTransformation
                )

                # 製作圓形遮罩
                circular = QPixmap(icon_size, icon_size)
                circular.fill(Qt.transparent)

                painter = QPainter(circular)
                painter.setRenderHint(QPainter.Antialiasing)
                path = QPainterPath()
                path.addEllipse(0, 0, icon_size, icon_size)
                painter.setClipPath(path)
                painter.drawPixmap(0, 0, scaled)
                painter.end()

                # 設定視窗圖標
                self.setWindowIcon(QIcon(circular))
            elif pixmap.loadFromData(image_data):  # 載入殺手圖片
                self.image_label.setStyleSheet("")  # 恢復原本樣式

                if url:
                    QPixmapCache.insert(url, pixmap)  # 存入 QPixmapCache

                # 縮放圖片以適應標籤大小
                scaled_pixmap = pixmap.scaled(
                    self.image_label.size(),
                    Qt.AspectRatioMode.KeepAspectRatio,
                    Qt.TransformationMode.SmoothTransformation,
                )

                # radius 與 QLabel 的 border-radius 相同
                self.image_label.setPixmap(self._rounded_pixmap(scaled_pixmap, radius=8))
            elif url != "icon":
                self.image_label.setText("格式錯誤")
        elif url != "icon":
            # 載入失敗
            self.image_label.setText("載入失敗")

        reply.deleteLater()

    def _set_image_url(self, url: str):
        """設置圖片URL（程式接口）"""
        if url:
            # 先從 QPixmapCache 快取找
            pixmap = QPixmap()
            if QPixmapCache.find(url, pixmap):
                scaled_pixmap = pixmap.scaled(
                    self.image_label.size(),
                    Qt.AspectRatioMode.KeepAspectRatio,
                    Qt.TransformationMode.SmoothTransformation,
                )
                self.image_label.setPixmap(self._rounded_pixmap(scaled_pixmap, radius=8))
                self.image_label.setStyleSheet("")
                return

            # 如果緩存中沒有，才進行網路請求
            request = QNetworkRequest(QUrl(url))
            # 將URL存儲到請求中，方便回調時使用
            request.setAttribute(QNetworkRequest.Attribute.User, url)
            self.network_manager.get(request)

            # 設置載入中的樣式和文字
            self.image_label.clear()  # 清除之前的圖片
            self.image_label.setText("?")
            self.image_label.setStyleSheet(
                """
                    QLabel#imageDisplay {
                        color: red;
                        font-size: 100px;
                        font-weight: bold;
                        border-radius: 8px;
                        border: 5px solid red;
                        background-color: #404040;
                    }
                """
            )
        else:
            self.image_label.clear()
            self.image_label.setText("未知")
            self.image_label.setStyleSheet("")

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

    def _append_log_message(self, message: str):
        """添加日誌訊息"""
        timestamp = datetime.now().strftime("[%H:%M:%S]")
        self.log_display.append(f"{timestamp} {message}")

        # 保持日誌在底部
        scrollbar = self.log_display.verticalScrollBar()
        scrollbar.setValue(scrollbar.maximum())

    def _monitor_logs(self):
        """日誌監控"""
        try:
            # 檢查新文件
            if not self.log_dir.exists():
                return

            log_files = list(self.log_dir.glob("output_log_*.txt"))

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
        new_info = False

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

                new_info = True

            elif data_type == "slasher":
                slasher_id = int(match.group(2))

                # 獲取殺手映射
                slasher_data = SLASHERS.get(
                    slasher_id, {"name": f"未知殺手({slasher_id})", "icon": None}
                )

                name = slasher_data["name"]
                icon = slasher_data["icon"]

                self.slasher_label.setText(f"殺手: \n{name}")
                log_parts.append(f"殺手: {name}")

                new_info = True

                # 更新圖片
                self._set_image_url(icon if icon else "")

                # 直接發送OSC
                if (
                    self._send_osc("SlasherID", slasher_id)
                    and self.osc_log_enabled_checkbox.isChecked()
                ):
                    self.log_message.emit(f"[OSC] 發送 SlasherID: {slasher_id}")

            elif data_type == "items":
                items = parse_items(match.group(2).strip())
                self.items_label.setText(f"生成物品: \n{items}")
                log_parts.append(f"物品: {items}")

                new_info = True

            elif data_type == "generator" and not self.reset_mark:  # 重置標記時禁止更新
                _, gen_name, var_type, _, _, new_value = match.groups()
                self._update_generator(gen_name, var_type, new_value)
                log_parts.append(f"{gen_name} {var_type}: {new_value}")

        if log_parts:
            # 理論上有 new_info 更新時, 不可能跟緩存相同 (除非真的生成完全一樣的資訊)
            message = " | ".join(log_parts)

            if new_info and message != self.info_cache:  # 有新資訊且與緩存不同, 通常是新遊戲開始
                self.reset_mark = False
                self.info_cache = message
            elif (  # 有新資訊但與緩存相同, 通常是結束後再次打印資訊
                new_info and message == self.info_cache
            ):
                self._reset_generators()
                if self.reset_mark:  # 已經標記時, 跳出避免重置後多餘日誌
                    return
                self.reset_mark = True
            elif self.reset_mark:  # 禁止重置狀態的, 後續日誌
                return

            self.log_message.emit(message)

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


if __name__ == "__main__":
    app = QApplication(sys.argv)
    window = SlashcoSenseMainWindow()
    window.show()
    sys.exit(app.exec())
