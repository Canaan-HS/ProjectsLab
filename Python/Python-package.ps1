function IsAdmin {
    return ([bool](New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
}

if (-not(IsAdmin)) {
    $scriptPath = $MyInvocation.MyCommand.Path
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
    exit
}

<# 額外工具安裝

pip install --user pipx
pipx ensurepath

#>

# 安裝包
$Package = @(
    <# 封裝與分發 - 將 Python 程式轉為可執行檔或分發包裝 #>
    "pyinstaller" # 最常用的可執行檔打包工具，跨平台，但輸出為「含直譯器的封裝」並非真正編譯
    #! "cython" # 將 Python 代碼轉 C/CPP 擴展，適合性能瓶頸與保護部分模組的源碼
    #! "nuitka" # 以 C++ 編譯方式將 Python 轉成真正的 native binary，效能提升且難以反編譯
    #! "pyarmor" # 代碼混淆與最基本的保護，延緩逆向，但無法真正阻止反編譯

    <# 測試與程式碼品質 - 測試框架與程式碼規範工具 #>
    "pytest" # 主流測試框架，支援 fixture、插件系統與高可讀性寫法
    "faker" # 假數據生成器，用於測試資料填充
    "ruff" # 高性能統一風格工具，整合 lint + 格式化，比 flake8/black 輕量快速
    "flake8" # 傳統 Linter，生態大但逐漸被 ruff 取代
    "black" # 嚴格的自動格式化工具，統一代碼風格
    "mypy" # 靜態類型檢查器，驗證 type hints 是否正確

    <# 日誌與版本管理 #>
    "loguru" # 易用且強大的日誌框架，支援結構化日誌
    "schedule" # 簡易排程器，適合小型任務週期呼叫
    "APScheduler" # 企業級排程器，支援 cron/interval/date 多模式
    "packaging" # 版本解析與比較工具，常用於依賴管理

    <# GUI 開發 - 圖形使用者介面開發工具 #>
    "tkinterdnd2" # tkinter 的拖放增強
    "customtkinter" # 現代化 Tkinter UI 套件，風格一致
    "PyQt6" # Qt6 綁定，功能完整、元件多
    "PySide6" # Qt 官方 Python 綁定，授權更寬鬆
    "pystray" # 建立系統托盤（右下角）常駐圖示
    "pywebview" # 使用 WebView 建立桌面 GUI，介面由 HTML/CSS/JS 控制，Python 與前端可雙向溝通，極適合輕量工具與混合式應用

    <# Web 請求與 HTTP - HTTP 通訊與基礎請求處理 #>
    "requests" # 傳統同步 HTTP，易用但不支援 HTTP/2/3，不適合大量請求
    "requests_toolbelt" # requests 的擴充套件，提供 multipart、流式上傳等
    "httpx[http2]" # 現代 HTTP 客戶端，支援 async / HTTP/2 / proxy / 連接池
    "curl_cffi" # 基於 libcurl，支援 HTTP/3 與指紋模擬（impersonate）
    "niquests" # 支援 HTTP/3 的 Python 原生實作，適合長連線或持久連接

    <# Web 爬蟲與解析 - 網頁數據提取與處理框架 #>
    "lxml" # 高速解析器，支援 XPath / CSS（透過 cssselect）/ XSLT
    "beautifulsoup4" # 容錯能力強但速度慢，適合結構混亂的頁面
    "selectolax" # 超高速解析器，適合大規模爬蟲，並支援 Lexbor 引擎

    <# 網路與協定分析 - 網路封包與協議操作工具 #>
    "scapy" # 封包構建/發送/解析工具，可進行協定測試與模糊測試
    "mitmproxy" # 交互式 MITM，支援攔截/修改 HTTPS/WS 流量（現代主流工具）
    "paramiko" # SSH-2 協定客戶端，用於自動化遠端命令與檔案操作

    <# 異步程式設計 - 高併發與非同步處理工具 #>
    "aiohttp" # 異步 HTTP 客戶端/伺服器，適用於 WebSocket 與大量連線場景
    "aiofiles" # 非同步檔案 I/O，搭配 aiohttp 保存內容

    <# 瀏覽器自動化 - 模擬瀏覽器行為與動態網頁處理 #>
    "selenium" # 傳統瀏覽器自動化，但容易被現代網站檢測
    "playwright" # 具備指紋較自然的自動化框架，Chrome/Firefox/WebKit 全支援
    "DrissionPage" # 結合 requests + 瀏覽器的混合式自動化，對反爬相對友好
    "webdriver_manager" # 自動下載與管理瀏覽器驅動（多用於 Selenium）

    <# 反爬蟲對抗與代理管理 - 繞過限制與匿名化工具 #>
    "selenium-wire" # Selenium 增強版，可攔截/修改 HTTP 請求與響應
    "undetected_chromedriver" # 對新版 Chrome 成功率不穩，但仍能避開部分 WebDriver 特徵
    "browserforge[all]" # 指紋仿真套件，支援 UA、Canvas、WebGL 等瀏覽器層特徵偽裝

    <# 驗證碼處理 - 自動化驗證突破 #>
    "twocaptcha-python" # 與 2Captcha API 整合，代填驗證碼

    <# 代理與 IP 管理 - 防止 IP 封鎖 #>
    #! "stem" # Tor 控制器，用於調整電路、更新出口 IP、控制 Tor 行為
    #! "mitmproxy" # 代理與攔截工具，可用於自製代理或 Debug 流量

    <# 安全與加密 - 數據保護與安全分析工具 #>
    "pycryptodome" # 基礎加密原語完整（AES/RSA/SHA 等），偏底層，適合自訂密碼機制
    "cryptography" # 現代加密庫，API 更安全且符合業界最佳實踐（高層封裝完善）
    "argon2-cffi" # Argon2 密碼雜湊算法的 Python 實作，建議用於密碼儲存
    "bandit" # 靜態安全掃描，檢查常見安全問題（弱隨機數、硬編碼密鑰等）

    <# 程式分析與符號執行 #>
    #! "angr" # 靜態 + 動態 + 符號執行的綜合分析框架，重但威力強
    #! "z3-solver" # 微軟 SMT Solver，符號執行與約束求解核心組件
    #! "triton" # 以動態符號執行為主，可與 Pin/JIT 合作對指令層進行分析
    #! "manticore" # 通用符號執行工具，支援二進制與智能合約

    <# 惡意軟體分析 #>
    #! "yara-python" # YARA 引擎 Python 版，用於惡意樣本規則匹配與特徵掃描
    #! "pyvex" # angr 的 IR 引擎，用於將二進制轉換成中間表示（VEX）
    #! "volatility3" # 主流記憶體取證框架，用於分析 RAM Dump
    #! "capa" # 自動識別樣本行為的靜態分析工具（FireEye/Mandiant）

    <# 反編譯與代碼分析 - Python 字節碼與二進制分析工具 #>
    "uncompyle6" # Python 字節碼反編譯，支援多版本（Py2 ～ Py3.7）
    "radon" # 維度分析（圈複雜度、可維護性分數、代碼品質統計）

    <# 逆向工程與利用 - 二進制分析與漏洞利用工具 #>
    "pwntools" # 漏洞利用與 CTF 工具箱，支援 ROP/格式化字串/遠端互動等
    "frida" # 動態注入框架，可 Hook API、修改記憶體與監控行為（ Windows / Linux / Android / iOS）
    "capstone" # 多架構反彙編引擎，速度快且 API 易用
    "LIEF" # 解析與修改 PE/ELF/Mach-O 的二進制結構（header/section/符號表等）
    "yara-python" # 惡意軟體特徵匹配與規則執行
    "volatility3" # 記憶體取證分析框架
    "capa" # 靜態行為分析，用於快速推斷功能（反沙箱/加密/注入等）

    <# Web 開發 - Web 應用與模板工具 #>
    "Jinja2" # 常用模板引擎，用於動態產生 HTML
    "flask" # 輕量 Web Framework，簡單易擴展
    "fastapi" # 高性能 API 框架，支援 async 與自動文件生成

    <# 系統監控 - 監控與管理系統資源 #>
    "psutil" # 系統資源監控（CPU/記憶體/磁碟/行程）
    "GPUtil" # 取得 NVIDIA GPU 使用率與記憶體資訊
    #! "glances" # 集成式系統監控工具，提供 CLI/Web 界面
    #! "memory_profiler" # 行程級記憶體量測工具，適用於 Debug 記憶體洩漏

    <# 系統操作工具 #>
    "pynput" # 控制與監聽鍵盤滑鼠，可用於桌面自動化
    "keyboard" # 全域鍵盤 Hook，適合熱鍵與鍵盤模擬（Windows 友好）
    "pyautogui" # 跨平台 GUI 自動化（滑鼠、鍵盤、截圖）
    "pyperclip" # 操作剪貼簿
    "pymem" # 讀寫程序記憶體，用於遊戲與逆向相關自動化
    "pywin32" # Windows API 封裝，支援 COM/WMI/系統呼叫

    <# 終端工具 - 終端介面美化與進度顯示 #>
    "rich" # 終端美化，支援語法高亮、表格、Live Console
    "tqdm" # 輕量進度條，支援串流與多層迭代
    "alive-progress" # 更動態與視覺化的進度條
    "tabulate" # 格式化表格輸出
    #! "art" # 輸出 ASCII 文字藝術，用於 CLI 裝飾
    #! "asciichartpy" # ASCII 圖表，用於純文字終端繪圖

    <# 影像處理 - 圖像與視覺處理工具 #>
    "mss" # 螢幕截圖與錄影工具，速度快、跨平台
    "pillow" # 主流影像處理庫，涵蓋編輯/轉換/縮圖等
    #! "opencv-python" # OpenCV 官方預建 CPU 版，用於影像辨識/視覺處理

    <# 影音處理 - 音頻與視頻處理工具 #>
    "ffmpeg-python" # FFmpeg 的 Python wrapper，用來進行影音轉檔與濾鏡處理
    "moviepy" # 影片剪輯工具，支援合成、轉場與基礎動畫
    "faster-whisper" # 高速 Whisper 推理（CTranslate2 後端），支援 GPU/CPU
    "openai-whisper" # 官方 Whisper，適合 CPU 推理或簡易場景
    "pyav" # Python 的 FFmpeg 介面，操作音頻/視頻資料的低階 API

    <# 文字與自然語言處理 - 文本分析與語言處理工具 #>
    "spaCy" # 工業級 NLP 工具，支援 POS/NER/句法分析
    "transformers" # HuggingFace 模型庫，支援 BERT/GPT/各類 LLM
    "thefuzz" # 字符串相似度比較，用於搜尋/比對/模糊查詢
    "jieba" # 中文斷詞工具，支援自訂詞典
    "dateparser" # 多語言日期解析（自然語言日期/相對時間）

    <# AI 與機器學習 - 人工智慧與模型應用 #>
    "ultralytics" # YOLOv8 系列，簡單易用的物件偵測/分割
    "easyocr" # 多語 OCR，安裝簡單、使用直覺
    "langchain" # 用於構建 LLM 應用，提供 Chain/Memory/Agent 等高階組件
    "openai" # OpenAI API 官方套件，用於 GPT/Whisper 等模型
    #! "onnxruntime-gpu" # ONNX Runtime GPU 版，用於高性能推理

    <# 資料科學 - 數據分析與機器學習工具 #>
    "numpy" # 數值陣列運算核心
    "pandas" # 表格資料處理，用於資料清洗與分析
    "polars" # 高性能 DataFrame，基於 Rust，比 pandas 快許多
    "scipy" # 科學運算套件，提供向量/訊號/統計等模組
    "matplotlib" # 傳統繪圖工具，生態完整但較老
    "scikit-learn" # 機器學習算法庫，分類/回歸/聚類皆包含
    "pyyaml" # YAML 讀寫（設定檔常用格式）
    #! "vaex" # 大規模 DataFrame，支援 out-of-core 操作
    #! "numba" # JIT 加速 NumPy，適合運算密集場景
    #! "torch" # PyTorch 深度學習框架（CPU/GPU）
    # (GPU版) https://pytorch.org/get-started/locally/

    <# 編譯 opencv - gpu版本 =>
        顯卡算力 https://developer.nvidia.com/cuda-gpus#compute
        GPU版本載點 https://pytorch.org/get-started/locally/
        GPU開發工具下載 https://developer.nvidia.com/cuda-downloads
        Cudnn https://developer.nvidia.com/rdp/cudnn-download
        Cmake編譯器 https://cmake.org/files/

        原始碼文件 https://github.com/opencv/opencv/tree/4.10.0
        原始碼文件(額外模組) https://github.com/opencv/opencv_contrib/tree/4.10.0

        編譯設置 =>
            WITH_CUDA -> 開
            OPENCV_DNN_CUDA -> 開
            ENABLE_FAST_MATH -> 開
            BUILD_CUDA_STUBS -> 開
            PYTHON -> 看到能開的都開(除了有test的)
            OPENCV_EXTRA_MODULES_PATH -> 指定opencv_contrib的modules
            BUILD_opencv_world -> 開
            OPENCV_ENABLE_NONFREE -> 開
            conf 把debug和release改為只有release
            CUDA_ARCH_BIN -> 根據顯卡算力設置
            CUDA_FAST_MATH -> 開
            test -> 可以都關掉
            java -> 可以都關掉
            OPENCV_GENERATE_SETUPVARS -> 關
            最後開啟 OpenCV.sln -> 用 vs 並且編譯 INSTALL
    #>
)

$hasUv = Get-Command uv -ErrorAction SilentlyContinue
if ($hasUv) {
    $cmd = @{
        exe       = "uv"
        install   = @("pip", "install", "--system")
        uninstall = @("pip", "uninstall", "--system")
        updatepip = @("pip", "install", "--upgrade", "pip", "--system")
        updatepkg = @("pip", "install", "--upgrade", "--system")
        freeze    = @("pip", "freeze", "--system")
    }
}
else {
    $cmd = @{
        exe       = "pip"
        install   = @("install")
        uninstall = @("uninstall")
        updatepip = @("install", "--upgrade", "pip")
        updatepkg = @("install", "--upgrade")
        freeze    = @("freeze")
    }
}

function Print {
    param (
        [string]$text,
        [string]$foreColor = 'White',
        [string]$backColor = 'Black'
    )

    # 打印粗體
    Write-Host "[1m$text" -ForegroundColor $foreColor -BackgroundColor $backColor
}

<#
掃描所有安裝包並建立 requirements.txt
pip freeze > requirements.txt

直接在 powershell 中使用 freeze 掃描後 使用 uv 更新
pip freeze | ForEach-Object { uv pip install --upgrade $_ --index-url https://mirrors.aliyun.com/pypi/simple/ }
#>
# ! 僅安裝|更新, 腳本的 $Package
function Install {
    Print "===================="
    Print "UV|PIP Update =>" Yellow
    Print "====================`n"

    & $cmd.exe @($cmd.updatepip)
    & $cmd.exe @($cmd.updatepkg + "wheel")
    & $cmd.exe @($cmd.updatepkg + "setuptools")

    Print "`n===================="
    Print "Install Package" Yellow
    Print "====================`n"

    # 為了穩定性採用迴圈安裝
    foreach ($package in $Package) {
        & $cmd.exe @($cmd.install + @("--upgrade", $package))
    }

    Print "`n===================="
    Print "Install Is Complete" Yellow
    Print "====================`n"
    Read-Host "輸入任意按鍵退出..."
    Exit
}

# ! 更新全域所有安裝包
function Upgrade {
    Print "===================="
    Print "UV|PIP Update =>" Yellow
    Print "====================`n"

    & $cmd.exe @($cmd.updatepip)
    & $cmd.exe @($cmd.updatepkg + "wheel")
    & $cmd.exe @($cmd.updatepkg + "setuptools")

    Print "`n===================="
    Print "Upgrade Package" Yellow
    Print "====================`n"

    & $cmd.exe @($cmd.freeze) | ForEach-Object {
        & $cmd.exe @($cmd.install + @("--upgrade", $_))
    }

    Print "`n===================="
    Print "Upgrade Is Complete" Yellow
    Print "====================`n"
    Read-Host "輸入任意按鍵退出..."
    Exit
}

<#
批量卸載所有包
pip freeze | ForEach-Object { pip uninstall -y $_ }
#>
function Uninstall {
    Print "`n===================="
    Print "Uninstall Package" Red
    Print "====================`n"

    & $cmd.exe @($cmd.freeze) | ForEach-Object {
        if ($hasUv) {
            & $cmd.exe @($cmd.uninstall + $_) # uv 不需要 -y
        }
        else {
            & $cmd.exe @($cmd.uninstall + @("-y", $_))
        }
    }

    Print "`n===================="
    Print "Uninstall Is Complete" Red
    Print "====================`n"
    Read-Host "輸入任意按鍵退出..."
    Exit
}

while ($true) {
    $choice = Read-Host "[1] Install`n[2] Upgrade`n[3] Uninstall`nChoice"
    switch ($choice) {
        1 {
            Clear-Host
            Install
            break
        }
        2 {
            Clear-Host
            Upgrade
            break
        }
        3 {
            Clear-Host
            Uninstall
            break
        }
        default { Print "無效的代號`n" Red }
    }
}