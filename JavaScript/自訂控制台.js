// ==================== 自定義控制台系統 ====================
window.CustomConsole = {
    // 配置
    config: {
        maxLines: 100,          // 最大保留行數
        fontSize: 14,           // 字體大小
        width: 600,             // 寬度
        height: 400,            // 高度
        backgroundColor: 'rgba(0, 0, 0, 0.85)',
        position: { x: 10, y: 10 }
    },

    // 歷史記錄
    history: [],
    commandHistory: [],
    historyIndex: -1,

    // 原始console方法備份
    originalConsole: {
        log: console.log,
        warn: console.warn,
        error: console.error,
        info: console.info,
        debug: console.debug,
        clear: console.clear
    },

    // 初始化
    init() {
        this.hookConsole();
        this.createUI();
        this.bindEvents();
        console.log('%c自定義控制台已啟動', 'color: #4CAF50; font-weight: bold');
    },

    // 攔截console方法
    hookConsole() {
        const self = this;

        // 攔截console.log
        console.log = function (...args) {
            self.addLine('log', args);
            self.originalConsole.log.apply(console, args);
        };

        // 攔截console.warn
        console.warn = function (...args) {
            self.addLine('warn', args);
            self.originalConsole.warn.apply(console, args);
        };

        // 攔截console.error
        console.error = function (...args) {
            self.addLine('error', args);
            self.originalConsole.error.apply(console, args);
        };

        // 攔截console.info
        console.info = function (...args) {
            self.addLine('info', args);
            self.originalConsole.info.apply(console, args);
        };

        // 攔截console.clear
        console.clear = function () {
            self.clear();
            self.originalConsole.clear.apply(console);
        };

        // 攔截console.table
        console.table = function (data) {
            self.addTable(data);
            self.originalConsole.log.apply(console, [data]);
        };
    },

    // 創建UI
    createUI() {
        // 主容器
        const container = document.createElement('div');
        container.id = 'custom-console';
        container.style.cssText = `
            position: fixed;
            left: ${this.config.position.x}px;
            top: ${this.config.position.y}px;
            width: ${this.config.width}px;
            height: ${this.config.height}px;
            background: ${this.config.backgroundColor};
            border: 1px solid #333;
            border-radius: 5px;
            font-family: 'Consolas', 'Monaco', monospace;
            font-size: ${this.config.fontSize}px;
            color: #fff;
            z-index: 10000;
            display: none;
            flex-direction: column;
            box-shadow: 0 4px 6px rgba(0,0,0,0.3);
        `;

        // 標題欄
        const header = document.createElement('div');
        header.style.cssText = `
            background: #222;
            padding: 5px 10px;
            border-bottom: 1px solid #444;
            cursor: move;
            display: flex;
            justify-content: space-between;
            align-items: center;
        `;
        header.innerHTML = `
            <span>🖥️ Console</span>
            <div>
                <button id="console-clear" style="margin-right: 5px;">Clear</button>
                <button id="console-minimize">_</button>
                <button id="console-close">X</button>
            </div>
        `;

        // 輸出區域
        const output = document.createElement('div');
        output.id = 'console-output';
        output.style.cssText = `
            flex: 1;
            overflow-y: auto;
            padding: 10px;
            background: #1a1a1a;
        `;

        // 輸入區域
        const inputWrapper = document.createElement('div');
        inputWrapper.style.cssText = `
            display: flex;
            border-top: 1px solid #444;
            background: #222;
        `;

        const inputPrefix = document.createElement('span');
        inputPrefix.textContent = '> ';
        inputPrefix.style.cssText = `
            padding: 5px;
            color: #4CAF50;
            font-weight: bold;
        `;

        const input = document.createElement('input');
        input.id = 'console-input';
        input.type = 'text';
        input.style.cssText = `
            flex: 1;
            background: transparent;
            border: none;
            color: #fff;
            padding: 5px;
            outline: none;
            font-family: inherit;
            font-size: inherit;
        `;
        input.placeholder = '輸入命令...';

        // 組裝UI
        inputWrapper.appendChild(inputPrefix);
        inputWrapper.appendChild(input);
        container.appendChild(header);
        container.appendChild(output);
        container.appendChild(inputWrapper);
        document.body.appendChild(container);

        // 保存引用
        this.container = container;
        this.output = output;
        this.input = input;
        this.header = header;
    },

    // 綁定事件
    bindEvents() {
        const self = this;

        // 輸入框事件
        this.input.addEventListener('keydown', (e) => {
            if (e.key === 'Enter') {
                const command = e.target.value.trim();
                if (command) {
                    self.executeCommand(command);
                    e.target.value = '';
                }
            } else if (e.key === 'ArrowUp') {
                e.preventDefault();
                self.navigateHistory(-1);
            } else if (e.key === 'ArrowDown') {
                e.preventDefault();
                self.navigateHistory(1);
            }
        });

        // 按鈕事件
        document.getElementById('console-clear').onclick = () => self.clear();
        document.getElementById('console-minimize').onclick = () => self.minimize();
        document.getElementById('console-close').onclick = () => self.hide();

        // 拖動功能
        let isDragging = false;
        let dragOffset = { x: 0, y: 0 };

        this.header.addEventListener('mousedown', (e) => {
            if (e.target === self.header || e.target.tagName === 'SPAN') {
                isDragging = true;
                dragOffset.x = e.clientX - self.container.offsetLeft;
                dragOffset.y = e.clientY - self.container.offsetTop;
            }
        });

        document.addEventListener('mousemove', (e) => {
            if (isDragging) {
                self.container.style.left = (e.clientX - dragOffset.x) + 'px';
                self.container.style.top = (e.clientY - dragOffset.y) + 'px';
            }
        });

        document.addEventListener('mouseup', () => {
            isDragging = false;
        });

        // 快捷鍵 (F12 或 `)
        document.addEventListener('keydown', (e) => {
            if (e.key === 'F12' || e.key === '`') {
                e.preventDefault();
                self.toggle();
            }
            // ESC 關閉
            if (e.key === 'Escape' && self.isVisible()) {
                self.hide();
            }
        });
    },

    // 添加輸出行
    addLine(type, args) {
        const line = document.createElement('div');
        line.className = `console-${type}`;
        line.style.cssText = this.getLineStyle(type);

        // 格式化輸出
        const content = args.map(arg => {
            if (typeof arg === 'object') {
                try {
                    return JSON.stringify(arg, null, 2);
                } catch (e) {
                    return String(arg);
                }
            }
            return String(arg);
        }).join(' ');

        // 處理特殊格式（如 %c）
        let formattedContent = content;
        if (typeof args[0] === 'string' && args[0].includes('%c')) {
            formattedContent = args[0].replace(/%c/g, '');
            if (args[1]) {
                const style = args[1];
                line.style.cssText += ';' + style;
            }
        }

        line.textContent = `[${type.toUpperCase()}] ${formattedContent}`;
        this.output.appendChild(line);

        // 保存歷史
        this.history.push({ type, content: formattedContent, time: new Date() });
        if (this.history.length > this.config.maxLines) {
            this.history.shift();
            this.output.removeChild(this.output.firstChild);
        }

        // 自動滾動到底部
        this.output.scrollTop = this.output.scrollHeight;
    },

    // 添加表格
    addTable(data) {
        const table = document.createElement('pre');
        table.style.cssText = `
            color: #fff;
            background: #2a2a2a;
            padding: 5px;
            border-radius: 3px;
            margin: 5px 0;
            overflow-x: auto;
        `;

        if (Array.isArray(data)) {
            const headers = Object.keys(data[0] || {});
            let tableStr = headers.join('\t') + '\n';
            tableStr += headers.map(() => '---').join('\t') + '\n';

            data.forEach(row => {
                tableStr += headers.map(h => row[h] || '').join('\t') + '\n';
            });

            table.textContent = tableStr;
        } else {
            table.textContent = JSON.stringify(data, null, 2);
        }

        this.output.appendChild(table);
        this.output.scrollTop = this.output.scrollHeight;
    },

    // 獲取行樣式
    getLineStyle(type) {
        const styles = {
            log: 'color: #fff; margin: 2px 0;',
            warn: 'color: #ff9800; margin: 2px 0; background: rgba(255,152,0,0.1);',
            error: 'color: #f44336; margin: 2px 0; background: rgba(244,67,54,0.1);',
            info: 'color: #2196f3; margin: 2px 0;',
            debug: 'color: #9e9e9e; margin: 2px 0;',
            command: 'color: #4CAF50; margin: 2px 0; font-weight: bold;',
            result: 'color: #fff; margin: 2px 0; padding-left: 20px;'
        };
        return styles[type] || styles.log;
    },

    // 執行命令
    executeCommand(command) {
        // 顯示命令
        const cmdLine = document.createElement('div');
        cmdLine.className = 'console-command';
        cmdLine.style.cssText = this.getLineStyle('command');
        cmdLine.textContent = '> ' + command;
        this.output.appendChild(cmdLine);

        // 保存命令歷史
        this.commandHistory.push(command);
        this.historyIndex = this.commandHistory.length;

        // 執行命令
        try {
            // 使用 Function 構造函數來執行，這樣可以訪問全局作用域
            const result = new Function('return ' + command)();

            // 顯示結果
            const resultLine = document.createElement('div');
            resultLine.className = 'console-result';
            resultLine.style.cssText = this.getLineStyle('result');

            if (result === undefined) {
                resultLine.textContent = '← undefined';
            } else if (typeof result === 'object') {
                resultLine.textContent = '← ' + JSON.stringify(result, null, 2);
            } else {
                resultLine.textContent = '← ' + String(result);
            }

            this.output.appendChild(resultLine);
        } catch (error) {
            // 嘗試作為語句執行
            try {
                new Function(command)();
                const resultLine = document.createElement('div');
                resultLine.className = 'console-result';
                resultLine.style.cssText = this.getLineStyle('result');
                resultLine.textContent = '← undefined';
                this.output.appendChild(resultLine);
            } catch (e) {
                const errorLine = document.createElement('div');
                errorLine.className = 'console-error';
                errorLine.style.cssText = this.getLineStyle('error');
                errorLine.textContent = '✖ ' + e.message;
                this.output.appendChild(errorLine);
            }
        }

        this.output.scrollTop = this.output.scrollHeight;
    },

    // 導航歷史命令
    navigateHistory(direction) {
        if (this.commandHistory.length === 0) return;

        this.historyIndex += direction;

        if (this.historyIndex < 0) {
            this.historyIndex = 0;
        } else if (this.historyIndex >= this.commandHistory.length) {
            this.historyIndex = this.commandHistory.length;
            this.input.value = '';
            return;
        }

        this.input.value = this.commandHistory[this.historyIndex];
    },

    // 清空控制台
    clear() {
        this.output.innerHTML = '';
        this.history = [];
    },

    // 顯示/隱藏
    show() {
        this.container.style.display = 'flex';
        this.input.focus();
    },

    hide() {
        this.container.style.display = 'none';
    },

    toggle() {
        if (this.isVisible()) {
            this.hide();
        } else {
            this.show();
        }
    },

    isVisible() {
        return this.container.style.display !== 'none';
    },

    minimize() {
        const isMinimized = this.output.style.display === 'none';
        this.output.style.display = isMinimized ? 'block' : 'none';
        this.input.parentElement.style.display = isMinimized ? 'flex' : 'none';
        this.container.style.height = isMinimized ? `${this.config.height}px` : '40px';
    },

    // 設置位置
    setPosition(x, y) {
        this.container.style.left = x + 'px';
        this.container.style.top = y + 'px';
    },

    // 設置大小
    setSize(width, height) {
        this.container.style.width = width + 'px';
        this.container.style.height = height + 'px';
    }
};

// 自動初始化
CustomConsole.init();