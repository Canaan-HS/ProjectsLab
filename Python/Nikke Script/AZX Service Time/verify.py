import cv2
import numpy as np
import tkinter as tk  # 用來獲取螢幕解析度以置中視窗
from init import config, match_threshold, safe_confidence


# ==========================================
#  1. 極速演算法 (純計算)
# ==========================================
class FastSolver:
    def __init__(self, grid):
        self.rows = len(grid)
        self.cols = len(grid[0])
        self.grid = [row[:] for row in grid]
        self.moves = []

    def get_rect_info(self, r1, c1, r2, c2):
        total = 0
        count = 0
        for r in range(r1, r2 + 1):
            for c in range(c1, c2 + 1):
                val = self.grid[r][c]
                total += val
                if val > 0:
                    count += 1
        return total, count

    def solve(self):
        while True:
            candidates = []
            for r1 in range(self.rows):
                for c1 in range(self.cols):
                    for r2 in range(r1, self.rows):
                        for c2 in range(c1, self.cols):
                            total, count = self.get_rect_info(r1, c1, r2, c2)
                            if total == 10 and count > 0:
                                area = (r2 - r1 + 1) * (c2 - c1 + 1)
                                is_straight = (r1 == r2) or (c1 == c2)
                                type_priority = 0 if is_straight else 1
                                candidates.append(
                                    {
                                        "move": (r1, c1, r2, c2),
                                        "count": count,
                                        "type": type_priority,
                                        "area": area,
                                    }
                                )
                            if total > 10:
                                break

            if not candidates:
                break
            candidates.sort(key=lambda x: (x["count"], x["type"], x["area"]))

            best = candidates[0]
            move = best["move"]
            self.moves.append(move)

            r1, c1, r2, c2 = move
            for r in range(r1, r2 + 1):
                for c in range(c1, c2 + 1):
                    self.grid[r][c] = 0
        return self.moves


# ==========================================
#  2. 圖像處理與視窗功能
# ==========================================
def load_templates():
    templates = {}
    if not config.templates_path.exists():
        print(f"❌ 錯誤：找不到 templates 資料夾: {config.templates_path}")
        return {}

    for i in range(1, 10):
        img_path = config.templates_path / f"{i}.png"
        if img_path.exists():
            img = cv2.imdecode(np.fromfile(str(img_path), dtype=np.uint8), cv2.IMREAD_COLOR)
            gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
            norm = cv2.normalize(gray, None, 0, 255, cv2.NORM_MINMAX)
            templates[i] = norm

    print(f"✅ 已載入 {len(templates)} 個樣板")
    return templates


def match_number(cell_img, templates):
    gray = cv2.cvtColor(cell_img, cv2.COLOR_BGR2GRAY)
    norm = cv2.normalize(gray, None, 0, 255, cv2.NORM_MINMAX)

    h_cell, w_cell = norm.shape[:2]
    best_score = -1
    best_num = None

    for num, tmpl in templates.items():
        h_tmpl, w_tmpl = tmpl.shape[:2]
        if h_tmpl > h_cell or w_tmpl > w_cell:
            continue

        res = cv2.matchTemplate(norm, tmpl, cv2.TM_CCOEFF_NORMED)
        _, max_val, _, _ = cv2.minMaxLoc(res)

        if max_val > best_score:
            best_score = max_val
            best_num = num

    return (best_num, best_score) if best_score > match_threshold else (None, best_score)


def print_grid_state(grid):
    print("   " + "-" * (len(grid[0]) * 3 + 2))
    for row in grid:
        row_str = "".join(" . " if val == 0 else f" {val} " for val in row)
        print(f"   |{row_str}|")
    print("   " + "-" * (len(grid[0]) * 3 + 2))


def center_window(win_name, width, height):
    """將 OpenCV 視窗移動到螢幕正中央"""
    try:
        root = tk.Tk()
        screen_w = root.winfo_screenwidth()
        screen_h = root.winfo_screenheight()
        root.destroy()

        x = (screen_w - width) // 2
        y = (screen_h - height) // 2

        cv2.namedWindow(win_name, cv2.WINDOW_AUTOSIZE)
        cv2.moveWindow(win_name, x, y)
    except Exception as e:
        print(f"視窗置中失敗 (可能無 tkinter): {e}")


# ==========================================
#  3. 主流程
# ==========================================
def recognize_and_solve():
    img = cv2.imdecode(
        np.fromfile(config.templates_path / "screenshot.png", dtype=np.uint8), cv2.IMREAD_COLOR
    )
    if img is None:
        print("無法讀取 screenshot.png")
        return

    templates = load_templates()
    if not templates:
        return

    grid_data = [[0] * config.cols for _ in range(config.rows)]

    # 畫布
    recog_debug_img = img.copy()
    solve_debug_img = img.copy()

    print("\n=== 1. 執行辨識 ===")

    for r in range(config.rows):
        for c in range(config.cols):
            cx = int(config.start_x + (c * config.step_x))
            cy = int(config.start_y + (r * config.step_y))

            pad_x = max(0, cx - config.padding)
            pad_y = max(0, cy - config.padding)
            pad_w = config.roi_w + (config.padding * 2)
            pad_h = config.roi_h + (config.padding * 2)

            if pad_y + pad_h > img.shape[0] or pad_x + pad_w > img.shape[1]:
                continue

            search_area = img[pad_y : pad_y + pad_h, pad_x : pad_x + pad_w]
            num, score = match_number(search_area, templates)

            # 繪圖座標
            rect_x, rect_y = cx, cy

            if num is not None:
                grid_data[r][c] = num

                # 顏色區分信心度 (框框顏色)
                if score >= safe_confidence:
                    box_color = (0, 255, 0)  # 綠色
                else:
                    box_color = (0, 255, 255)  # 黃色

                # 1. 畫框
                cv2.rectangle(
                    recog_debug_img,
                    (rect_x, rect_y),
                    (rect_x + config.roi_w, rect_y + config.roi_h),
                    box_color,
                    2,
                )

                # 2. 畫信心度 (紅色字體，置中顯示在框框上方)
                text = f"{score:.2f}({num})"
                font = cv2.FONT_HERSHEY_SIMPLEX
                font_scale = 0.35
                thickness = 1
                text_color = (0, 0, 255)  # 紅色 BGR

                # 計算文字大小以便置中
                (text_w, text_h), _ = cv2.getTextSize(text, font, font_scale, thickness)

                # 計算置中座標
                text_x = rect_x + (config.roi_w - text_w) // 2
                text_y = rect_y - 3  # 方框上方

                cv2.putText(
                    recog_debug_img, text, (text_x, text_y), font, font_scale, text_color, thickness
                )

            else:
                grid_data[r][c] = 0
                # 紅色框 (失敗)
                cv2.rectangle(
                    recog_debug_img,
                    (rect_x, rect_y),
                    (rect_x + config.roi_w, rect_y + config.roi_h),
                    (0, 0, 255),
                    2,
                )

                # 失敗也顯示分數 (如果夠高)
                if score > 0.1:
                    text = f"{score:.2f}"
                    font = cv2.FONT_HERSHEY_SIMPLEX
                    font_scale = 0.35
                    thickness = 1
                    (text_w, text_h), _ = cv2.getTextSize(text, font, font_scale, thickness)
                    text_x = rect_x + (config.roi_w - text_w) // 2
                    text_y = rect_y - 3
                    cv2.putText(
                        recog_debug_img,
                        text,
                        (text_x, text_y),
                        font,
                        font_scale,
                        (0, 0, 255),
                        thickness,
                    )

    print("\n=== 辨識結果矩陣 ===")
    print_grid_state(grid_data)

    # --- 快速運算 ---
    print("\n=== 2. 計算路徑 ===")
    solver = FastSolver(grid_data)
    moves = solver.solve()
    print(f"共規劃出 {len(moves)} 步消除步驟。")

    # 繪製路徑
    colors = [(255, 0, 0), (0, 255, 0), (0, 0, 255), (0, 255, 255), (255, 0, 255), (255, 128, 0)]

    for idx, (r1, c1, r2, c2) in enumerate(moves):
        pt1_x = int(config.start_x + c1 * config.step_x)
        pt1_y = int(config.start_y + r1 * config.step_y)
        pt2_x = int(config.start_x + c2 * config.step_x + config.roi_w)
        pt2_y = int(config.start_y + r2 * config.step_y + config.roi_h)

        color = colors[idx % len(colors)]
        cv2.rectangle(solve_debug_img, (pt1_x, pt1_y), (pt2_x, pt2_y), color, 2)
        cv2.circle(solve_debug_img, (pt1_x, pt1_y), 3, color, -1)

    # --- 顯示結果視窗 ---
    scale = 0.8
    # 計算縮放後視窗大小
    win_w = int(recog_debug_img.shape[1] * scale)
    win_h = int(recog_debug_img.shape[0] * scale)
    dim = (win_w, win_h)

    # 視窗 1: 信心度 (置中)
    win_name1 = "1. Recognition Confidence"
    center_window(win_name1, win_w, win_h)
    cv2.imshow(win_name1, cv2.resize(recog_debug_img, dim))

    # 視窗 2: 解法 (不強制置中，避免重疊，或可視需求調整)
    win_name2 = "2. Solution Path"
    # center_window(win_name2, win_w, win_h) # 如果想要兩個都置中(會疊在一起)可以打開
    cv2.imshow(win_name2, cv2.resize(solve_debug_img, dim))

    cv2.waitKey(0)
    cv2.destroyAllWindows()


if __name__ == "__main__":
    recognize_and_solve()
