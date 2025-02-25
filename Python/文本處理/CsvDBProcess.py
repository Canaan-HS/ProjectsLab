import os
import csv
import time
import psutil
import opencc
from tqdm import tqdm
from sortedcontainers import SortedDict

"""
? 讀取 BT 分享種子轉換的 CSV 文件, 並處理其重複數據, 與文本轉換

* 1. 輸入 讀取 CSV 路徑, 與 輸出 CSV 路徑
"""

def ReadCsv(path):
    with open(path, 'r', encoding='utf-8') as csvfile:
        reader = csv.reader(csvfile)
        for row in reader:
            yield row

def WriteCsv(path, data):
    with open(path, 'w', encoding='utf-8') as csvfile:
        # writer = csv.writer(csvfile)
        value = data.values()
        size = len(value) - 1
        # 為了避免最後一行, 不使用正常 csv 的方式寫入 (但進度條會壞掉)
        for index, row in tqdm(enumerate(value), total=size, desc="輸出中"):
            if index == size:
                csvfile.write(row)
            else:
                csvfile.write(row + "\n")

def Throttle(wait):
    def decorator(fn):
        last_call_time = [0]
        last_result = [None]
        def throttled(*args, **kwargs):
            current_time = time.time()
            if current_time - last_call_time[0] >= wait:
                last_call_time[0] = current_time
                last_result[0] = fn(*args, **kwargs)
            return last_result[0]
        return throttled
    return decorator

@Throttle(5.0)  # 5 秒取得一次
def GetMemory():
    return psutil.virtual_memory().percent

def Process(Read_Path, Write_Path):
    
    if (not os.path.exists(Read_Path)):
        print(f"檔案不存在: {Read_Path}")
        return
    
    count = 0
    local_dict = SortedDict()
    converter = opencc.OpenCC("s2twp.json")
    list_to_string = lambda lst: ','.join([str(item).strip() for item in lst])

    for row in ReadCsv(Read_Path):
        name = row[1]

        if name.isdigit(): # 排除都是數字的
            continue

        Name = name.replace(",", " ") # 名稱中不能有 ,
        row[1] = Name # 修改原數據
        
        Item = local_dict.get(Name) # 舊的紀錄
        Data = converter.convert(list_to_string(row)) # 列表轉成字串, 並轉成繁體

        if Item is None:
            local_dict[Name] = Data
        else: # 重複時, 比較大小, 大的覆蓋
            count -= 1 # 當有重複對象時, 重複數據不納入計算
            try:
                rowSize = int(row[2])
                itemSize = int(Item.split(',')[2]) # 將保存數據轉回列表

                if rowSize > itemSize:
                    local_dict[Name] = Data
            except:
                print(f"\n新數據: {row}\n舊數據: {Item}\n")

        count += 1
        print(f"\r記憶體佔用: {GetMemory()}% | 已處理: {count} 筆數據", end="", flush=True)

    # 輸出數據
    WriteCsv(Write_Path, local_dict)
    local_dict.clear()

if __name__ == "__main__":
    Process(
        "R:\\db.csv",
        "R:\\Clean.csv"
    )