from pathlib import Path
from types import SimpleNamespace

base_dir = Path(__file__).parent

# 擷取配置
base_config = {
    "Small": {
        "rows": 14,
        "cols": 8,
        "start_x": 734,
        "start_y": 230,
        "step_x": 59,
        "step_y": 59.2,
        "roi_w": 38,
        "roi_h": 38,
        "padding": 6,
        "templates_path": base_dir / "small_templates",
    },
    "Normal": {
        "rows": 15,
        "cols": 9,
        "start_x": 720,
        "start_y": 225,
        "step_x": 55.2,
        "step_y": 55.2,
        "roi_w": 38,
        "roi_h": 38,
        "padding": 6,
        "templates_path": base_dir / "normal_templates",
    },
    "Large": {
        "rows": 16,
        "cols": 10,
        "start_x": 710,
        "start_y": 230,
        "step_x": 51.8,
        "step_y": 51.8,
        "roi_w": 32,
        "roi_h": 32,
        "padding": 6,
        "templates_path": base_dir / "large_templates",
    },
}

# 使用配置
config = SimpleNamespace(**base_config["Large"])

# 判斷配置
match_threshold = 0.8
safe_confidence = 0.9  # 高信心門檻 (低於此但高於 match_threshold 顯示黃框)

# 操作配置
base_delay = 0.01  # 操作間隔
min_duration = 0.12  # 最短移動時間
