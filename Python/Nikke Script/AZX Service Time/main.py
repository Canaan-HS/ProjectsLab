import re
import math
import time

import cv2
import mss
import numpy as np
import keyboard
import pyautogui

from init import config, match_threshold, base_delay, min_duration


# ==========================================
#  1. 核心演算法
# ==========================================
class FastSolver:
    def __init__(self, grid):
        self.rows = len(grid)
        self.cols = len(grid[0])
        self.grid = [row[:] for row in grid]
        self.moves = []

    def _build_prefix(self):
        ps = [[0] * (self.cols + 1) for _ in range(self.rows + 1)]
        pc = [[0] * (self.cols + 1) for _ in range(self.rows + 1)]
        for r in range(self.rows):
            row_sum = 0
            row_cnt = 0
            for c in range(self.cols):
                v = self.grid[r][c]
                row_sum += v
                row_cnt += 1 if v > 0 else 0
                ps[r + 1][c + 1] = ps[r][c + 1] + row_sum
                pc[r + 1][c + 1] = pc[r][c + 1] + row_cnt
        return ps, pc

    @staticmethod
    def _rect_sum(prefix, r1, c1, r2, c2):
        return (
            prefix[r2 + 1][c2 + 1]
            - prefix[r1][c2 + 1]
            - prefix[r2 + 1][c1]
            + prefix[r1][c1]
        )

    def solve(self):
        while True:
            ps, pc = self._build_prefix()
            best_move = None
            best_key = None
            for r1 in range(self.rows):
                for c1 in range(self.cols):
                    for r2 in range(r1, self.rows):
                        for c2 in range(c1, self.cols):
                            total = self._rect_sum(ps, r1, c1, r2, c2)
                            if total == 10:
                                count = self._rect_sum(pc, r1, c1, r2, c2)
                                if count <= 0:
                                    continue
                                area = (r2 - r1 + 1) * (c2 - c1 + 1)
                                is_straight = (r1 == r2) or (c1 == c2)
                                type_priority = 0 if is_straight else 1
                                key = (count, type_priority, area)
                                if best_key is None or key < best_key:
                                    best_key = key
                                    best_move = (r1, c1, r2, c2)
                            if total > 10:
                                break

            if best_move is None:
                break

            move = best_move
            self.moves.append(move)

            r1, c1, r2, c2 = move
            for r in range(r1, r2 + 1):
                for c in range(c1, c2 + 1):
                    self.grid[r][c] = 0
        return self.moves


# ==========================================
#  2. 輔助功能
# ==========================================
def print_grid_state(grid):
    print("\n[辨識結果矩陣]")
    print("   " + "-" * (len(grid[0]) * 3 + 2))
    for row in grid:
        row_str = "".join(" . " if val == 0 else f" {val} " for val in row)
        print(f"   |{row_str}|")
    print("   " + "-" * (len(grid[0]) * 3 + 2))


def get_cell_center(r, c):
    """根據 config 計算螢幕座標"""
    x = int(config.start_x + (c * config.step_x) + (config.roi_w / 2))
    y = int(config.start_y + (r * config.step_y) + (config.roi_h / 2))
    return x, y


def human_drag(start_x, start_y, end_x, end_y):
    """擬人化滑鼠拖曳 (使用 init 配置的 min_duration)"""
    distance = math.sqrt((end_x - start_x) ** 2 + (end_y - start_y) ** 2)
    # 動態調整時間：距離越長，時間越久
    duration = min_duration + (distance / 2000)

    pyautogui.moveTo(start_x, start_y)
    pyautogui.mouseDown()
    pyautogui.moveTo(end_x, end_y, duration=duration, tween=pyautogui.easeOutQuad)
    time.sleep(0.02)  # 短暫停留確保判定
    pyautogui.mouseUp()


# ==========================================
#  3. 圖像辨識
# ==========================================
def load_templates():
    templates = {}
    if not config.templates_path.exists():
        print(f"❌ 錯誤：找不到 templates 資料夾: {config.templates_path}")
        return {}

    template_paths = sorted(config.templates_path.glob("*.png"))
    loaded = 0
    for img_path in template_paths:
        if img_path.name.lower() == "screenshot.png":
            continue

        m = re.match(r"^(\d+)", img_path.stem)
        if not m:
            continue

        num = int(m.group(1))
        img = cv2.imdecode(np.fromfile(str(img_path), dtype=np.uint8), cv2.IMREAD_COLOR)
        if img is None:
            continue
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        norm = cv2.normalize(gray, None, 0, 255, cv2.NORM_MINMAX)
        templates.setdefault(num, []).append(norm)
        loaded += 1

    print(f"✅ 已載入 {loaded} 個數字樣板 (分類數: {len(templates)})")
    return templates


def capture_screen_to_cv2():
    with mss.mss() as sct:
        monitor = sct.monitors[1]
        sct_img = sct.grab(monitor)
        img = np.array(sct_img)
        img = cv2.cvtColor(img, cv2.COLOR_BGRA2BGR)
        return img


def recognize_grid(img, templates):
    grid_data = [[0] * config.cols for _ in range(config.rows)]

    # 1. 轉灰階
    gray_img = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

    # 2. 【HDR 對抗】正規化 (Normalize)
    # 這是提升準確率的關鍵，確保畫面亮度分布與樣板一致
    gray_img = cv2.normalize(gray_img, None, 0, 255, cv2.NORM_MINMAX)

    for r in range(config.rows):
        for c in range(config.cols):
            # 使用 config 計算座標
            cx = int(config.start_x + (c * config.step_x))
            cy = int(config.start_y + (r * config.step_y))

            pad_x = max(0, cx - config.padding)
            pad_y = max(0, cy - config.padding)
            pad_w = config.roi_w + (config.padding * 2)
            pad_h = config.roi_h + (config.padding * 2)

            if pad_y + pad_h > img.shape[0] or pad_x + pad_w > img.shape[1]:
                continue

            search_area = gray_img[pad_y : pad_y + pad_h, pad_x : pad_x + pad_w]
            h_search, w_search = search_area.shape[:2]

            best_score = -1
            best_num = None

            for num, tmpls in templates.items():
                for tmpl in tmpls:
                    h_tmpl, w_tmpl = tmpl.shape[:2]
                    if h_tmpl > h_search or w_tmpl > w_search:
                        continue

                    res = cv2.matchTemplate(search_area, tmpl, cv2.TM_CCOEFF_NORMED)
                    _, max_val, _, _ = cv2.minMaxLoc(res)

                    if max_val > best_score:
                        best_score = max_val
                        best_num = num

            if best_score > match_threshold:
                grid_data[r][c] = best_num
            else:
                grid_data[r][c] = 0

    return grid_data


def execute_moves(moves):
    for idx, (r1, c1, r2, c2) in enumerate(moves):
        start_x, start_y = get_cell_center(r1, c1)
        end_x, end_y = get_cell_center(r2, c2)

        human_drag(start_x, start_y, end_x, end_y)

        time.sleep(base_delay)
    print("✨ 操作完成！")


# ==========================================
#  Main Job
# ==========================================
TEMPLATES = None


def main_job():
    global TEMPLATES
    print("\n[F9] 觸發：開始截圖計算...")

    img = capture_screen_to_cv2()
    grid = recognize_grid(img, TEMPLATES)

    print_grid_state(grid)

    solver = FastSolver(grid)
    moves = solver.solve()

    if not moves:
        print("⚠️ 無法找到可消除路徑 (或辨識結果為空)。")
        return

    execute_moves(moves)


if __name__ == "__main__":
    print("========================================")
    print("  自動消除助手")
    print("  按 [F9]  -> 開始執行")
    print("  按 [ESC] -> 結束程式")
    print("========================================")

    TEMPLATES = load_templates()

    if TEMPLATES:
        keyboard.add_hotkey("f9", main_job)
        keyboard.wait("esc")
