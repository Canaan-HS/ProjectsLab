import cv2
import numpy as np

from init import config


def check_grid_overlay():
    img = cv2.imdecode(np.fromfile(config.templates_path / "screenshot.png", dtype=np.uint8), -1)
    if img is None:
        print("無法讀取 screenshot.png")
        return

    debug_img = img.copy()
    for r in range(config.rows):
        for c in range(config.cols):
            # 絕對座標計算
            curr_x = config.start_x + (c * config.step_x)
            curr_y = config.start_y + (r * config.step_y)

            x = int(curr_x)
            y = int(curr_y)

            # 畫出框
            cv2.rectangle(debug_img, (x, y), (x + config.roi_w, y + config.roi_h), (0, 255, 0), 2)

            # 畫出中心點
            cv2.circle(debug_img, (x + config.roi_w // 2, y + config.roi_h // 2), 2, (0, 0, 255), -1)

    # 縮放顯示
    scale = 0.8
    dim = (
        int(debug_img.shape[1] * scale),
        int(debug_img.shape[0] * scale),
    )
    resized_img = cv2.resize(debug_img, dim, interpolation=cv2.INTER_AREA)

    cv2.imshow("check grid", resized_img)
    cv2.waitKey(0)
    cv2.destroyAllWindows()


if __name__ == "__main__":
    check_grid_overlay()
