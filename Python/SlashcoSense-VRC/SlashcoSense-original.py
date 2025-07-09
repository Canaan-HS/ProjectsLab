import os
import time
import re
from datetime import datetime
from tkinter import *
from tkinter import ttk, messagebox
from pythonosc import udp_client

from pathlib import Path

DEFAULT_PORT = 9000

PLAYED_MAP = {
    0: "SlashCoHQ",
    1: "MalonesFarmyard",
    2: "PhilipsWestwoodHighSchool",
    3: "EastwoodGeneralHospital",
    4: "ResearchFacilityDelta",
}
SLASHER_MAP = {
    0: "Bababooey",
    1: "Sid",
    2: "Trollge",
    3: "Borgmire",
    4: "Abomignat",
    5: "Thirsty",
    6: "Elmo",
    7: "Watcher",
    8: "Beast",
    9: "Dolphinman",
    10: "Igor",
    11: "Grouch",
    12: "Princess",
    13: "Speedrunner",
}


def get_latest_log_file(log_dir):
    try:
        if not os.path.isdir(log_dir):
            return None
        log_files = [
            os.path.join(log_dir, f)
            for f in os.listdir(log_dir)
            if f.startswith("output_log_") and f.endswith(".txt")
        ]
        return max(log_files, key=os.path.getmtime) if log_files else None
    except Exception as e:
        print(f"Error finding logs: {e}")
        return None


def parse_log_line(line):
    result = {}

    map_match = re.search(r"Played Map:\s*([^,]+)", line)
    if map_match:
        map_val = map_match.group(1).strip()
        result["map"] = PLAYED_MAP.get(int(map_val), map_val) if map_val.isdigit() else map_val

    slasher_match = re.search(r"Slasher:\s*(\d+)", line)
    if slasher_match:
        slasher_id = int(slasher_match.group(1))
        result["slasher"] = {
            "id": slasher_id,
            "name": SLASHER_MAP.get(slasher_id, f"Unknown({slasher_id})"),
        }

    items_match = re.search(r"Selected Items:\s*(.+?)(?=,\s*\w+:|$)", line)
    if items_match:
        result["items"] = items_match.group(1).strip()

    generator_pattern = (
        r"SC_(generator\d+) Progress check\. Last (\w+) value: (.*?), updated (\w+) value: (.*)"
    )
    if "Progress check" in line:
        gen_match = re.search(generator_pattern, line)
        if gen_match:
            result["generator"] = {
                "name": gen_match.group(1),
                "var_name": gen_match.group(2),
                "old_value": gen_match.group(3),
                "new_value": gen_match.group(5),
            }

    return result


class VRChatMonitorGUI:
    def __init__(self, master):
        self.master = master
        master.title("SlashcoSense By:arcxingye")
        master.geometry("410x600")

        self.status_frame = ttk.LabelFrame(master, text="游戏状态")
        self.status_frame.pack(fill=BOTH, padx=10, pady=5, expand=False)
        self.status_frame.grid_propagate(False)
        self.status_frame.config(width=380, height=175)

        self.map_label = ttk.Label(self.status_frame, text="地图: 未知")
        self.map_label.grid(row=0, column=0, sticky=W, padx=5, pady=2)

        self.slasher_label = ttk.Label(self.status_frame, text="杀手: 未知")
        self.slasher_label.grid(row=1, column=0, sticky=W, padx=5, pady=2)

        self.items_label = ttk.Label(self.status_frame, text="生成物品: 无")
        self.items_label.grid(row=2, column=0, sticky=W, padx=5, pady=2)

        self.generator_frame = ttk.Frame(self.status_frame)
        self.generator_frame.grid(row=3, column=0, columnspan=2, pady=5, sticky=EW)

        self.generators = {
            "generator1": {
                "fuel": ttk.Progressbar(self.generator_frame, length=200),
                "battery": ttk.Label(self.generator_frame, text="电池: ❌"),
                "label": ttk.Label(self.generator_frame, text="发电机1"),
            },
            "generator2": {
                "fuel": ttk.Progressbar(self.generator_frame, length=200),
                "battery": ttk.Label(self.generator_frame, text="电池: ❌"),
                "label": ttk.Label(self.generator_frame, text="发电机2"),
            },
        }

        for i, (gen_id, gen) in enumerate(self.generators.items()):
            gen["label"].grid(row=i, column=0, padx=5, sticky=W)
            gen["fuel"].grid(row=i, column=1, padx=5)
            gen["battery"].grid(row=i, column=2, padx=5)

        self.generator_warning = ttk.Label(
            self.generator_frame,
            text="发电机监控仅限非房主有效",
            foreground="gray60",
            font=("微软雅黑", 8),
        )
        self.generator_warning.grid(row=2, column=0, columnspan=3, padx=5, pady=(0, 5), sticky=W)

        self.log_frame = ttk.LabelFrame(master, text="实时日志")
        self.log_frame.pack(fill=BOTH, expand=True, padx=10, pady=5)

        self.log_text = Text(self.log_frame, wrap=WORD, state=DISABLED)
        self.scrollbar = ttk.Scrollbar(self.log_frame, command=self.log_text.yview)
        self.log_text.configure(yscrollcommand=self.scrollbar.set)

        self.scrollbar.pack(side=RIGHT, fill=Y)
        self.log_text.pack(fill=BOTH, expand=True)

        self.osc_frame = ttk.Frame(master)
        self.osc_frame.pack(fill=X, padx=10, pady=5)

        self.osc_enabled = BooleanVar(value=False)
        self.osc_log_enabled = BooleanVar(value=True)

        ttk.Checkbutton(
            self.osc_frame, text="启用OSC", variable=self.osc_enabled, command=self.toggle_osc
        ).grid(row=0, column=0, padx=5, sticky=W)

        ttk.Checkbutton(self.osc_frame, text="显示OSC日志", variable=self.osc_log_enabled).grid(
            row=0, column=1, padx=3, sticky=W
        )

        ttk.Label(self.osc_frame, text="端口:").grid(row=0, column=2, padx=5)
        self.port_entry = ttk.Entry(self.osc_frame, width=6)
        self.port_entry.insert(0, str(DEFAULT_PORT))
        self.port_entry.grid(row=0, column=3, padx=3)

        self.osc_client = None
        # self.log_dir = os.path.expandvars(r"%USERPROFILE%\AppData\LocalLow\VRChat\VRChat")
        self.log_dir = Path(__file__).parent / "test"
        self.current_file = None
        self.file_pos = 0
        self.master.after(100, self.monitor_logs)

    def toggle_osc(self):
        if self.osc_enabled.get():
            try:
                port = int(self.port_entry.get())
                if 1 <= port <= 65535:
                    self.osc_client = udp_client.SimpleUDPClient("127.0.0.1", port)
                    self.log(f"OSC已启用（端口：{port}）")
                else:
                    messagebox.showerror("错误", "端口号必须在1-65535之间")
                    self.osc_enabled.set(False)
            except ValueError:
                messagebox.showerror("错误", "无效的端口号")
                self.osc_enabled.set(False)
        else:
            self.osc_client = None
            self.log("OSC已禁用")

    def log(self, message):
        self.log_text.configure(state=NORMAL)
        timestamp = datetime.now().strftime("[%H:%M:%S] ")
        self.log_text.insert(END, timestamp + message + "\n")
        self.log_text.see(END)
        self.log_text.configure(state=DISABLED)

    def update_generator(self, gen_data):
        gen = self.generators.get(gen_data["name"].lower())
        if not gen:
            return

        var_type = gen_data["var_name"]
        new_value = gen_data["new_value"]

        try:
            if var_type == "REMAINING":
                total = 4
                current = int(new_value)
                filled = total - current
                progress = filled / total

                gen["fuel"]["value"] = progress * 100
                gen["label"].config(
                    text=f"{gen_data['name'].replace('generator', '发电机')} 燃料: {filled}/{total}"
                )

                if self.osc_client:
                    param_name = f"{gen_data['name'].upper()}_FUEL"
                    self.osc_client.send_message(f"/avatar/parameters/{param_name}", filled)
                    if self.osc_log_enabled.get():
                        self.log(f"[OSC] 发送 {param_name}: {filled}")

            elif var_type == "HAS_BATTERY":
                installed = new_value.lower() == "true"
                gen["battery"].config(text="电池: ✅" if installed else "电池: ❌")

                if self.osc_client:
                    param_name = f"{gen_data['name'].upper()}_BATTERY"
                    self.osc_client.send_message(
                        f"/avatar/parameters/{param_name}", 1 if installed else 0
                    )
                    if self.osc_log_enabled.get():
                        self.log(f"[OSC] 发送 {param_name}: {1 if installed else 0}")

        except Exception as e:
            self.log(f"发电机更新错误: {str(e)}")

    def monitor_logs(self):
        try:
            latest = get_latest_log_file(self.log_dir)
            if latest != self.current_file:
                self.current_file = latest
                self.file_pos = 0
                if latest:
                    self.log(f"开始监控日志文件: {os.path.basename(latest)}")

            if self.current_file:
                with open(self.current_file, "r", encoding="utf-8", errors="ignore") as f:
                    f.seek(self.file_pos)
                    lines = f.readlines()
                    self.file_pos = f.tell()

                    for line in lines:
                        data = parse_log_line(line.strip())

                        if "map" in data:
                            self.map_label.config(text=f"地图: {data['map']}")
                        if "slasher" in data:
                            self.slasher_label.config(text=f"杀手: {data['slasher']['name']}")
                            if self.osc_client:
                                try:
                                    self.osc_client.send_message(
                                        "/avatar/parameters/SlasherID", data["slasher"]["id"]
                                    )
                                    if self.osc_log_enabled.get():
                                        self.log(f"[OSC] 发送 SlasherID: {data['slasher']['id']}")
                                except Exception as e:
                                    self.log(f"[OSC错误] 发送杀手ID失败: {str(e)}")
                        if "items" in data:
                            self.items_label.config(text=f"生成物品: {data['items']}")
                        if "generator" in data:
                            self.update_generator(data["generator"])

                        outputs = []
                        if "map" in data:
                            outputs.append(f"地图: {data['map']}")
                        if "slasher" in data:
                            outputs.append(f"杀手: {data['slasher']['name']}")
                        if "items" in data:
                            outputs.append(f"物品: {data['items']}")
                        if "generator" in data:
                            gen = data["generator"]
                            outputs.append(f"{gen['name']} {gen['var_name']}: {gen['new_value']}")

                        if outputs:
                            self.log(" | ".join(outputs))

        except Exception as e:
            self.log(f"监控错误: {str(e)}")

        self.master.after(500, self.monitor_logs)


if __name__ == "__main__":
    root = Tk()
    style = ttk.Style()
    style.theme_use("clam")
    style.configure("green.Horizontal.TProgressbar", troughcolor="#4a4a4a", background="#2ecc71")

    app = VRChatMonitorGUI(root)
    root.mainloop()
