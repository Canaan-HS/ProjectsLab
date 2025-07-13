# -*- mode: python ; coding: utf-8 -*-

excludes = [
    # 1. 測試與偵錯 (Testing & Debugging)
    # 這些是開發時才用到的工具，發布時完全不需要。
    'unittest', 'test', 'doctest', 'pytest', '_pytest', 'nose', 'mock', 'tox', 'hypothesis',
    'pdb', 'bdb', 'cProfile', 'profile', 'pstats', 'tracemalloc',

    # 2. 開發與外帶工具 (Development & Packaging Tools)
    # 應用程式執行時不需要外帶工具本身。
    'distutils', '_distutils_hack', 'setuptools', 'pip', 'venv', 'zipapp',
    'lib2to3', 'pyclbr', 'pydoc', 'pydoc_data', 'idlelib',

    # 3. GUI / TUI (若您的專案未使用)
    # 如果您使用 PySide6/PyQt5，就不需要 Tkinter。
    'tkinter', 'turtle', 'turtledemo', 'curses', 

    # 4. 大型科學與網頁框架 (若您的專案未使用)
    # 這些函式庫體積龐大，只在確定需要時才外帶。
    'numpy', 'pandas', 'scipy', 'matplotlib',
    'requests', 'flask', 'jinja2', 'werkzeug', 'sqlalchemy',
    'PIL', 'Pillow', 'pygame',

    # 5. 過時或罕用的網路協定
    'email', 'ftplib', 'telnetlib', 'nntplib', 'poplib', 'smtpd', 'smtplib', 'mailbox',

    # 6. 其他罕用標準庫
    'argparse', # 如果您的 GUI 應用不處理命令列參數
    'getopt',
    'calendar',
]


# --- 排除二進位包 (Excluded Binary Packages) ---
# 再次確認外帶和建構工具不會被包含進來。
excluded_packages = [
    'PyInstaller', '_pyinstaller_hooks_contrib', 'pyinstaller_hooks_contrib',
    'pip', 'setuptools', 'pkg_resources', 'altgraph', 'win32ctypes', 'packaging', 'pefile'
]


# --- 排除檔案類型 (Excluded File Types) ---
# 排除掉編譯過程中的中間檔案和偵錯檔。
excluded_file_types = ['.pdb', '.lib', '.a', '.ilk', '.exp', '.map']


# =============================================================================
#  Analysis Block: 告訴 PyInstaller 如何分析您的專案
# =============================================================================
a = Analysis(
    # 主程式檔案
    ['your_script.py'],

    pathex=[],
    binaries=[],

    # 專案需要的額外檔案 (圖示、圖片、設定檔等)
    # 格式：[('來源路徑', '外帶後在根目錄下的相對路徑')]
    datas=[('assets/icon.ico', '.'), ('assets/config.json', '.')],

    # 如果出現 ModuleNotFoundError，在此處添加缺少的模組名
    hiddenimports=[],

    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=excludes,
    noarchive=False,
    optimize=2,
)

# 根據上面的列表過濾掉不需要的二進位檔案
a.binaries = [
    binary for binary in a.binaries
    if not any(binary[0].startswith(prefix) for prefix in excluded_packages)
    and not any(binary[1].lower().endswith(ext) for ext in excluded_file_types)
]


# =============================================================================
#  PYZ, EXE, COLLECT Blocks: 定義如何建構最終的執行檔
# =============================================================================
pyz = PYZ(a.pure, a.zipped_data, compress=True)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],

    # 輸出的執行檔名稱
    name='YourAppName',

    # 執行檔的圖示
    icon='assets/icon.ico',

    # 【可選】執行檔版本資訊，需要一個 version_info.txt 檔案
    # version='version_info.txt',

    # 【可選】使用 UPX 壓縮，可以顯著減小 exe 體積。需自行下載 upx.exe 並放到專案目錄。
    upx=True,
    upx_exclude=[],

    # --- 視窗與偵錯設定 ---
    debug=False,
    strip=True,  # 移除符號表，減小體積
    runtime_tmpdir=None,

    # True = 顯示黑色命令提示字元視窗 (適合偵錯)
    # False = 不顯示視窗 (適合發布 GUI 應用)
    console=False,
    disable_windowed_traceback=False,
)