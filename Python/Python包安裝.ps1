function IsAdmin {
    return ([bool](New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
}

if (-not(IsAdmin)) {
    $scriptPath = $MyInvocation.MyCommand.Path
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
    exit
}

# 安裝包
$Package = @(
    <# Py 封裝 exe - 將 Python 程式封裝為可執行檔案 #>
    "pyinstaller" # 支援多平臺的 Python 程式打包工具
    "cx_Freeze" # 另一個將 Python 程式打包成獨立可執行檔案的工具

    "pytest" # Python 的單元測試框架

    <# 加密 - 資料加密和解密 #>
    "tinyaes" # 輕量級 AES 加密庫，適用於簡單的加密需求
    "pycryptodome" # Python 中強大的加密庫，提供 AES、DES 等加密演算法

    <# 解密反編譯 - 反編譯工具，用於解碼編譯後的 Python 程式碼 #>
    "uncompyle6" # 將編譯後的 Python 位元組碼反編譯為原始碼

    <# 逆向調式 #>
    #! "winappdbg" # 適用較舊的 Windows，支持進程控制、內存操作、設置斷點等
    #! "pydbg" # Windows 平台的動態分析和逆向工程，可以進行進程控制、內存讀寫、設置斷點等
    "pwntools" # 漏洞利用、逆向工程、滲透測試等高級攻擊模擬，支持動態內存操作和注入代碼
    "frida" # 動態分析，進程注入，內存操作、API hook、記錄系統調用等

    <# 請求/爬蟲 - 處理 HTTP 請求和網路爬蟲的工具 #>
    "httpx[http2]" # 非同步 HTTP 客戶端，支援 HTTP/1.1 和 HTTP/2
    "requests" # 最流行的同步 HTTP 客戶端，易於使用
    "grequests" # 基於 requests 的非同步請求庫
    "Scrapy" # 功能強大的爬蟲框架，適合大規模資料抓取
    "urllib3" # 低階 HTTP 客戶端庫，requests 的依賴之一

    <# 爬蟲資料解析 #>
    "lxml" # XML 和 HTML 解析庫，支援 XPath
    "beautifulsoup4" # 解析和處理 HTML 和 XML 文件的工具

    <# 處理反爬蟲 - 繞過反爬蟲機制的工具 #>
    "scrapy-crawlera" # 為 Scrapy 提供智慧代理輪換的中介軟體
    "cloudscraper" # 繞過 Cloudflare 的反爬蟲檢測(免費版)
    "undetected-chromedriver2" # 用於 Selenium 的反檢測 Chrome 驅動
    "requests-html" # 提供 HTML 渲染和處理動態網站內容的工具

    <# 非同步操作 - 非同步 I/O 操作的庫 #>
    "aiohttp" # 非同步 HTTP 客戶端，適合大規模併發請求
    "aiofiles" # 非同步檔案操作庫

    <# 自動化操作 - 瀏覽器自動化和測試的工具 #>
    "selenium" # 自動化瀏覽器操作的工具
    "chromedriver_autoinstaller" # 自動下載和安裝 Chrome 驅動

    <# 影音處理 - 處理和處理影音檔案的工具 #>
    "ffmpeg-python" # 處理和處理影音檔案的工具

    <# 文字處理 - 處理和分析文字資料的工具 #>
    "feedparser" # 解析 RSS 和 Atom feeds
    "chardet" # 字元編碼檢測工具，支援多種編碼
    "opencc" # 簡繁體中文轉換
    "fuzzywuzzy" # 模糊字串匹配工具
    "python-Levenshtein" # 提供高效的 Levenshtein 編輯距離演算法

    <# 系統資訊與操作 #>
    "psutil" # 進程監控，支持 CPU、內存、磁碟、網絡等信息的讀取，並能夠操作進程
    "GPUtil" # 獲取 GPU 資訊和監控 GPU 資源

    <# 日程安排和版本管理 #>
    "schedule" # 簡單的任務排程庫
    "packaging" # 版本比較和語義化版本號解析
    "wget" # 用於下載檔案的簡單工具
    "pyperclip" # 操作剪貼簿內容
    "playsound" # 播放音訊檔案的簡易庫

    <# 進度條 - 終端顯示進度條的工具 #>
    "rich" # 豐富的終端輸出工具，支援彩色文字、進度條、表格等
    "tqdm" # 進度條庫，支援命令列和 Jupyter Notebook
    "progress" # 簡單的進度條顯示工具
    "progressbar" # 進度條顯示工具
    "progressbar2" # progressbar 的升級版，增加了更多功能
    "alive-progress" # 動態進度條庫，支援複雜的進度顯示

    <# 資料操作 - 資料分析和科學計算工具 #>
    "numpy" # 數值分析庫，支援多維陣列和矩陣運算
    "pandas" # 強大的資料操作和分析工具，支援 DataFrame 資料結構
    "scipy" # 科學計算庫，提供高等數學、統計、訊號處理等功能
    "matplotlib" # 資料視覺化工具，生成靜態、動畫和互動式圖形
    "scikit-learn" # 機器學習和資料探勘庫，支援多種演算法
    "pyyaml" # 處理 YAML 檔案的庫，適用於配置檔案解析
    #! "torch" # 深度學習框架，支援 CPU 和 GPU 計算
    # (GPU版) https://pytorch.org/get-started/locally/

    <# 系統操作與自動化 #>
    "pynput" # 控制和監控輸入裝置(鍵盤和滑鼠)
    "keyboard" # 處理鍵盤操作的庫，支援全域性熱鍵
    "pymem" # 讀寫程序記憶體的工具，常用於遊戲修改
    "pywin32" # 訪問 Windows API 的工具集
    "mss" # 截圖和螢幕錄製工具
    "SpeechRecognition" # 語音識別庫，將語音轉換為文字
    "pyaudio" # 處理音訊流，支援錄音和播放

    <# GUI 開發 - 圖形使用者介面工具 #>
    "PyQt5" # 強大的 GUI 開發工具包
    "PyQt6" # PyQt5 的升級版，支援更多特性和更新的 Qt 版本
    "PySide6" # PyQt 的開源替代品，由 Qt 官方維護
    "pystray" # 建立系統托盤圖示和選單
    "PyAutoGUI" # 自動化 GUI 操作的工具，支援滑鼠鍵盤控制
    "Pillow" # 影像處理庫，支援影像的開啟、操作和儲存
    "tkinterdnd2" # 增強 tkinter 的拖曳功能

    <# 網頁開發 #>
    "Jinja2" # 模板引擎，常用於生成 HTML 內容
    #! "flask" # 輕量級 Web 應用框架
    #! "fastapi" # 高效能 Web 框架，適合構建 API

    <# discord 開發 - 開發 Discord 相關工具 #>
    #! "discord_webhook" # 簡化向 Discord 傳送訊息的操作

    <# 視覺與影像處理 - 影像和影片處理工具 #>
    #! "opencv-python" # 開源計算機視覺庫，支援影像和影片處理(CPU 版本)

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
        [string]$foregroundColor = 'White',
        [string]$backgroundColor = 'Black'
    )

    # 設置颜色
    $Host.UI.RawUI.ForegroundColor = [ConsoleColor]::$foregroundColor
    $Host.UI.RawUI.BackgroundColor = [ConsoleColor]::$backgroundColor
    
    # 打印粗體
    Write-Host "[1m$text"
}

function Main {
    Print "===================="
    Print "PIP Update =>" 'Yellow'
    Print "====================`n"
    python.exe -m pip install --upgrade pip

    Print "`n===================="
    Print "Install Package" 'Yellow'
    Print "====================`n"
    foreach ($package in $Package) {
        pip install --upgrade $package
    }

    Print "`n===================="
    Print "Package Update" 'Yellow'
    Print "====================`n"
    pip install --upgrade setuptools
    pip install --upgrade wheel

    Print "`n===================="
    Print "Install Is Complete" 'Yellow'
    Print "====================`n"
    Read-Host "輸入任意按鍵退出..."
}

Main