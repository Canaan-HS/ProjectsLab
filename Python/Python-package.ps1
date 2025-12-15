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
    "pyinstaller" # 多平臺外帶工具，支援豐富的自訂選項與鉤子函數，最廣泛使用
    #! "cython" # 將 Python 代碼轉譯為 C，可與其他外帶工具結合提高性能與保護源碼
    #! "nuitka" # Python 轉 C++ 編譯器，生成真正的二進制執行檔，執行速度更快且難以反編譯
    #! "cx_Freeze" # 跨平臺凍結工具，生成的檔案較小，支援 Python 模組與第三方庫外帶
    #! "pyarmor" # 提供代碼加密與授權保護，防止逆向工程，支援多種外帶工具整合

    <# 測試與程式碼品質 - 測試框架與程式碼規範工具 #>
    "pytest" # 功能豐富的測試框架，支援參數化測試、夾具與插件系統
    "faker" # 測試數據生成器，產生各類假數據
    "ruff" # 高效能 Python Linter 與格式化工具，可取代 flake8、black
    "flake8" # 代碼風格檢查工具，結合多種檢查器
    "black" # 自動代碼格式化工具，統一代碼風格
    "mypy" # 靜態類型檢查器，驗證類型註解

    <# 安全與加密 - 數據保護與安全分析工具 #>
    "pycryptodome" # 全面的加密庫，提供對稱/非對稱加密、雜湊與數字簽名
    "cryptography" # 現代加密庫，提供高層次接口，符合最佳實踐
    "argon2-cffi" # Argon2 密碼雜湊算法實現，最新密碼學推薦
    "bandit" # 安全性導向的 Python 代碼分析工具

    <# 惡意軟體分析 #>
    #! "yara-python" # 惡意軟體模式匹配引擎
    #! "pyvex" # 用於中間表示(IR)轉換的庫
    #! "volatility3" # 內存取證框架
    #! "capa" # 自動識別惡意軟體功能的工具

    <# 反編譯與代碼分析 - Python 字節碼與二進制分析工具 #>
    "uncompyle6" # Python 字節碼反編譯器，支援多種 Python 版本
    "radon" # 代碼複雜度分析工具

    <# 逆向工程與利用 - 二進制分析與漏洞利用工具 #>
    "pwntools" # 漏洞利用、逆向工程、滲透測試等高級攻擊模擬，支持動態內存操作和注入代碼
    "frida" # 動態分析，進程注入，內存操作、API hook、記錄系統調用等
    "capstone" # 多架構反彙編引擎，支持多種CPU架構
    "LIEF" # 二進制格式解析庫，支持PE/ELF/Mach-O
    "yara-python" # 惡意軟體模式匹配引擎
    "volatility3" # 內存取證框架
    "capa" # 自動識別惡意軟體功能的工具

    <# 程式分析與符號執行 #>
    #! "angr" # 強大的二進制分析框架，結合靜態分析和符號執行
    #! "z3-solver" # 微軟的約束求解器，是符號執行的基礎組件
    #! "triton" # 動態二進制分析框架，專注於動態符號執行
    #! "manticore" # 另一個符號執行工具，支持智能合約分析

    <# Web 請求與 HTTP - HTTP 通訊與基礎請求處理 #>
    "requests" # 同步 HTTP 客戶端的標準庫，支援 Cookie、表單、代理等基本功能
    "requests_toolbelt" # requests 增強工具集，提供多部分表單、流式上傳、自訂驗證等
    "httpx[http2]" # 現代化 HTTP 客戶端，支援 HTTP/2、異步請求、連接池優化
    #! "urllib3" # 低階 HTTP 庫，提供連接池管理、SSL/TLS 驗證、重試策略

    <# Web 爬蟲與解析 - 網頁數據提取與處理框架 #>
    "lxml" # 高效能 XML/HTML 解析器，支援 XPath、XSLT，速度最快
    "beautifulsoup4" # 直覺易用的 HTML/XML 解析器，容錯能力強，適合處理不規範網頁
    "selectolax" # 高效能 HTML/XML 解析器，速度比 beautifulsoup4 更快
    "Scrapy" # 完整爬蟲框架，提供請求排程、中介軟體、管道處理、分散式支援
    "requests-html" # 結合 requests 與解析功能，支援 JavaScript 渲染與 CSS 選擇器

    <# 網路與協定分析 - 網路封包與協議操作工具 #>
    "scapy" # 網路封包操作工具，可分析、構建、發送自訂封包
    "paramiko" # SSH 協議實現，用於自動化 SSH 連接與操作

    <# 異步程式設計 - 高併發與非同步處理工具 #>
    "aiohttp" # 異步 HTTP 客戶端/伺服器，支援 WebSockets、大規模併發請求
    "aiofiles" # 異步檔案 I/O 操作，適合與 aiohttp 搭配存儲爬取結果

    <# 瀏覽器自動化 - 模擬瀏覽器行為與動態網頁處理 #>
    "selenium" # 跨瀏覽器自動化工具，支援完整瀏覽器操作與 JavaScript 執行
    "playwright" # 微軟開發的現代瀏覽器自動化庫，更難被檢測 (首次使用需執行 playwright install)
    "webdriver_manager" # 自動管理多種瀏覽器驅動，支援 Chrome、Firefox、Edge 等
    #! "browser-cookie3" # 從已安裝瀏覽器提取 cookies，用於模擬登入狀態

    <# 反爬蟲對抗與代理管理 - 繞過限制與匿名化工具 #>
    "selenium-stealth" # Selenium 隱身套件，消除自動化指紋特徵
    "selenium-wire" # Selenium 增強版，可攔截/修改 HTTP 請求與響應
    "cloudscraper" # 專門繞過 Cloudflare 防護的工具，處理 JavaScript 挑戰
    "fake-useragent" # 隨機產生真實的 User-Agent 標頭
    "undetected_chromedriver" # 防檢測 Chrome 驅動，修改 WebDriver 特徵
    "fingerprint-randomizer" # 瀏覽器指紋隨機化工具，修改 Canvas、WebGL 等特徵

    <# 驗證碼處理 - 自動化驗證突破 #>
    "twocaptcha-python" # 整合 2Captcha 驗證碼服務的 API

    <# 代理與 IP 管理 - 防止 IP 封鎖 #>
    #! "rotating-free-proxies" # 自動搜尋並使用免費代理伺服器
    #! "stem" # Tor 控制器，用於 IP 匿名化與輪換
    #! "browsermob-proxy" # 可編程代理伺服器，允許修改 HTTP 請求/響應
    #! "mitmproxy" # 中間人代理工具，支援 HTTPS 流量檢查與修改

    <# 影音處理 - 音頻與視頻處理工具 #>
    "ffmpeg-python" # FFmpeg 的 Python 封裝，處理影音檔案
    "moviepy" # 影片編輯函式庫，支援剪輯、合成、轉場等
    "pyaudio" # 處理音訊流，支援錄音和播放
    "SpeechRecognition" # 語音識別庫，將語音轉換為文字

    <# 文字與自然語言處理 - 文本分析與語言處理工具 #>
    "nltk" # 自然語言處理工具包，提供分詞、詞性標註、語法分析等功能
    "spaCy" # 工業級自然語言處理庫，速度快且準確
    "transformers" # Hugging Face 的 NLP 模型庫，支援 BERT、GPT 等
    "thefuzz" # 字符串模糊匹配庫，支援相似度比較 (fuzzywuzzy 的後繼者)
    "jieba" # 中文分詞庫，支援自定義詞典
    "dateparser" # 強大的日期解析庫，支援多語言和相對時間

    <# 系統監控 - 監控與管理系統資源 #>
    "psutil" # 跨平台系統監控庫，獲取 CPU、內存、磁盤等信息
    "GPUtil" # NVIDIA GPU 監控工具，獲取使用率和內存信息
    #! "glances" # 系統監控工具，提供 Web 界面和 API
    #! "memory_profiler" # 內存使用分析工具，監控 Python 程式內存

    <# 日誌與版本管理 #>
    "loguru" # 功能強大且簡單易用的日誌記錄庫
    "schedule" # 簡單的任務排程庫
    "APScheduler" # 高級任務調度庫，支援 cron 表達式
    "packaging" # 版本比較和語義化版本號解析

    <# 系統操作工具 #>
    "pynput" # 鍵盤鼠標監控與控制庫，全平台支援
    "keyboard" # 全局鍵盤監聽與模擬庫，特別適合 Windows
    "pyautogui" # 跨平台 GUI 自動化工具，控制鼠標和鍵盤
    "pyperclip" # 操作剪貼簿內容
    "pymem" # 讀寫程序記憶體的工具，常用於遊戲修改
    "pywin32" # 訪問 Windows API 的工具集

    <# 終端工具 - 終端介面美化與進度顯示 #>
    "rich" # 強大的終端格式化庫，支援顏色、表格、語法高亮
    "tqdm" # 快速、可擴展的進度條庫，支援嵌套和並行
    "alive-progress" # 動態進度條庫，支援複雜的進度顯示
    "tabulate" # 表格數據美觀列印工具
    #! "art" # ASCII 藝術文本生成庫
    #! "asciichartpy" # ASCII 字符圖表生成庫

    <# 影像處理 - 圖像與視覺處理工具 #>
    "mss" # 截圖和螢幕錄製工具
    "pillow" # Python 圖像處理庫，支援多種圖像格式
    #! "opencv-python" # 計算機視覺庫，支援圖像處理與分析 (CPU 版本)

    <# GUI 開發 - 圖形使用者介面開發工具 #>
    "tkinterdnd2" # 增強 tkinter 的拖曳功能
    "customtkinter" # 基於 Tkinter 的現代化 UI 庫，提供美觀的元件
    # "wxPython" # 跨平台 GUI 開發工具
    "PyQt6" # PyQt5 的升級版，支援更多特性和更新的 Qt 版本
    "PySide6" # PyQt 的開源替代品，由 Qt 官方維護
    "pystray" # 建立系統托盤圖示和選單

    <# Web 開發 - Web 應用與模板工具 #>
    "Jinja2" # 模板引擎，常用於生成 HTML 內容
    "flask" # 輕量級 Web 應用框架
    "fastapi" # 高效能 Web 框架，適合構建 API

    <# 混合式自動化框架 - 結合請求與瀏覽器操作 #>
    "DrissionPage" # 結合 requests 的便捷與 selenium 的自動化能力，專為反爬蟲設計

    <# AI 與機器學習 - 人工智慧與模型應用 #>
    # 電腦視覺 (Computer Vision)
    "ultralytics" # YOLOv8 物件偵測框架，易於使用且效能強大，適合圖像辨識任務
    "easyocr" # 準確率高的光學字元辨識庫，可從圖片中提取文字
    # 自然語言與大型語言模型 (NLP & LLM)
    "langchain" # 大型語言模型應用開發框架，快速建構聊天機器人、RAG 應用
    "openai" # OpenAI 官方 API 庫，用於存取 GPT 系列模型
    # 模型部署與優化 (Model Deployment & Optimization)
    #! "onnxruntime-gpu" # 高效能 AI 模型推理引擎，支援 ONNX 格式 (GPU 版本)

    <# 資料科學 - 數據分析與機器學習工具 #>
    "numpy" # 數值計算基礎庫，提供高效數組操作
    "pandas" # 數據分析與處理庫，提供 DataFrame 結構
    "polars" # 高性能數據操作庫，類似 pandas 但速度更快
    "scipy" # 科學計算庫，提供高等數學、統計、訊號處理等功能
    "matplotlib" # 經典數據可視化庫，支援多種圖表類型
    "scikit-learn" # 機器學習庫，提供分類、回歸、聚類等算法
    "pyyaml" # 處理 YAML 檔案的庫，適用於配置檔案解析
    #! "vaex" # 處理大數據的 DataFrame 庫，支援內存外計算
    #! "numba" # JIT 編譯器，加速 NumPy 數組操作
    #! "torch" # 深度學習框架，支援 CPU 和 GPU 計算
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

function Print {
    param (
        [string]$text,
        [string]$foreColor = 'White',
        [string]$backColor = 'Black'
    )

    # 打印粗體
    Write-Host "[1m$text" -ForegroundColor $foreColor -BackgroundColor $backColor
}

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

<#
掃描所有安裝包並建立 requirements.txt
pip freeze > requirements.txt

直接在 powershell 中使用 freeze 掃描後 使用 uv 更新
pip freeze | ForEach-Object { uv pip install --upgrade $_ }
#>
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

    foreach ($package in $Package) {
        & $cmd.exe @($cmd.install + @("--upgrade", $package))
    }

    Print "`n===================="
    Print "Install Is Complete" Yellow
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
    $Choice = Read-Host "[1] Install`n[2] Uninstall`nChoice"
    switch ($Choice) {
        1 {
            Clear-Host
            Install
            break
        }
        2 {
            Clear-Host
            Uninstall
            break
        }
        default { Print "無效的代號`n" Red }
    }
}