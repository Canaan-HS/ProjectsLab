# -*- mode: python ; coding: utf-8 -*-

excludes = [
    # 客製化 GUI / TUI (若您的專案未使用)
    # 使用 PySide6/PyQt5，就不需要 Tkinter。
    'tkinter', 'turtle', 'turtledemo', 'curses',
    'winsound', 'colorsys', 'chunk', 'imghdr',
    'sndhdr', 'ossaudiodev',

    # 測試與偵錯 (Testing & Debugging)
    # 這些是開發時才用到的工具，發布時完全不需要。
    'unittest', 'test', 'doctest', 'pytest', '_pytest',
    'nose', 'mock', 'tox', 'hypothesis', 'pdb', 
    'bdb', 'cProfile', 'profile', 'pstats', 'tracemalloc', 
    'pydoc', 'tests', 'pydoc_data', 'lib2to3', 'pickletools'

    # 開發與外帶工具 (Development & Packaging Tools)
    # 應用程式執行時不需要外帶工具本身。
    'distutils', '_distutils_hack', 'setuptools', 'pip', 'venv',
    'zipapp', 'lib2to3', 'pyclbr', 'pydoc', 'pydoc_data',
    'idlelib', 'pkg_resources', 'ensurepip', 'wheel'

    # PyInstaller 相關工具和包
    'altgraph', 'pyinstaller_hooks_contrib', '_pyinstaller_hooks_contrib',
    'pefile', 'packaging', 'pywin32_system32',

    # Windows 特定組件 (激進)
    'win32com', 'win32ctypes', 'win32api', 'win32con',
    'pywintypes', 'win32cred', 'win32file', 'win32pipe', 'win32process'

    # 網絡與 Web 服務
    'socket', 'selectors', 'email', 'ftplib',
    'telnetlib', 'nntplib', 'poplib', 'smtpd', 'smtplib',
    'mailbox', 'asyncio', 'ssl', '_ssl', 'http',
    'urllib.request', 'gopherlib', 'imaplib', 'wsgiref',
    'webbrowser', 'cgi', 'cgitb', 'xmlrpc'

    # 型科學與網頁框架 (若未使用)
    'numpy', 'pandas', 'scipy', 'matplotlib',
    'requests', 'flask', 'jinja2', 'werkzeug', 'sqlalchemy',
    'PIL', 'Pillow', 'pygame',

    # 數據庫
    'sqlite3', 'dbm', 'dbm.gnu', 'dbm.ndbm', 'dbm.dumb',

    # 數據解析
    # 排除除 JSON 和基本配置外的所有數據格式處理器
    'xml', 'xml.dom', 'xml.sax', 'xml.etree', 'csv', 'configparser',
    'html', 'email', 'json.tool', 'tarfile', 'zipapp', 'plistlib', 'xdrlib',

    # 加密與壓縮
    'hmac', 'secrets', 'bz2', 'lzma', 'gzip', 'zlib', 

    # 並發與多進程
    'multiprocessing', 'concurrent',

    # 不常用標準庫
    'argparse', 'copyreg', 'getopt', 'calendar', 'optparse',
    'getpass', 'gettext', 'decimal', 'fractions', 'statistics',
    'msilib', 'shelve', 'symtable', 'tabnanny'

    # 有風險 (激進)
    'msvcrt', 'pickle', 'hashlib', '_hashlib', 'ctypes', '_ctypes',
    'encodings.koi8_r', 'encodings.koi8_t', 'encodings.koi8_u', 'encodings.kz1048',
    'encodings.mac_cyrillic', 'encodings.mac_greek', 'encodings.mac_iceland',
    'encodings.mac_latin2', 'encodings.mac_roman', 'encodings.mac_turkish',
    'encodings.iso8859_2', 'encodings.iso8859_3', 'encodings.iso8859_4',
    'encodings.iso8859_5', 'encodings.iso8859_6', 'encodings.iso8859_7',
    'encodings.iso8859_8', 'encodings.iso8859_9', 'encodings.iso8859_10',
    'encodings.iso8859_11', 'encodings.iso8859_13', 'encodings.iso8859_14',
    'encodings.iso8859_15', 'encodings.iso8859_16',
    'encodings.cp037', 'encodings.cp273', 'encodings.cp424', 'encodings.cp437',
    'encodings.cp500', 'encodings.cp720', 'encodings.cp737', 'encodings.cp775',
    'encodings.cp850', 'encodings.cp852', 'encodings.cp855', 'encodings.cp856',
    'encodings.cp857', 'encodings.cp858', 'encodings.cp860', 'encodings.cp861',
    'encodings.cp862', 'encodings.cp863', 'encodings.cp864', 'encodings.cp865',
    'encodings.cp866', 'encodings.cp869', 'encodings.cp874', 'encodings.cp875',
    'encodings.cp932', 'encodings.cp949', 'encodings.cp950', 'encodings.cp1006',
    'encodings.cp1026', 'encodings.cp1125', 'encodings.cp1140',
    'encodings.palmos', 'encodings.ptcp154', 'encodings.tis_620', 'encodings.hp_roman8',
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