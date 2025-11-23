import cv2
import numpy as np
from init import Path, config

shrink_border = 2


def crop_grid_images():
    Path.mkdir(config.templates_path, exist_ok=True)

    img = cv2.imdecode(np.fromfile(config.templates_path / "screenshot.png", dtype=np.uint8), -1)
    if img is None:
        print("無法讀取 screenshot.png")
        return

    count = 0
    for r in range(config.rows):
        for c in range(config.cols):
            x = int(config.start_x + (c * config.step_x))
            y = int(config.start_y + (r * config.step_y))

            w = config.roi_w
            h = config.roi_h

            crop_x = x + shrink_border
            crop_y = y + shrink_border
            crop_w = w - (shrink_border * 2)
            crop_h = h - (shrink_border * 2)

            # 防呆：確保長寬合理
            if crop_w <= 0 or crop_h <= 0:
                print("⚠️ 錯誤：內縮值太大，導致圖片寬高為負，請調小 shrink_border")
                return

            # 執行裁切
            cell_img = img[crop_y : crop_y + crop_h, crop_x : crop_x + crop_w]

            save_name = config.templates_path / f"cell_{r}_{c}.png"
            cv2.imencode(".png", cell_img)[1].tofile(save_name)

            count += 1

    print(f"✅ 完成！已裁切 {count} 張圖片。")
    print("👉 確認沒問題後，請手動挑選 1~9 的圖片，改名為 1.png, 2.png...")


if __name__ == "__main__":
    crop_grid_images()
