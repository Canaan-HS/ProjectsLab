// ==UserScript==
// @name        自動登入器
// @name:zh-TW  自動登入器
// @name:zh-CN  自動登入器
// @name:en     自動登入器
// @version      0.0.1-Alpha
// @author       Canaan HS
// @description        自動登入器
// @description:zh-TW  自動登入器
// @description:zh-CN  自動登入器
// @description:en     自動登入器

// @match        *://*/*

// @noframes
// @license      MPL-2.0
// @namespace    https://greasyfork.org/users/989635
// @supportURL   https://github.com/Canaan-HS/MonkeyScript/issues
// @icon         https://cdn-icons-png.flaticon.com/512/7960/7960597.png

// @require      https://update.greasyfork.org/scripts/487608/1909139/SyntaxLite_min.js

// @grant        GM_getValue
// @grant        GM_setValue
// @grant        GM_deleteValue
// @grant        GM_listValues
// @grant        GM_registerMenuCommand
// @grant        GM_unregisterMenuCommand

// @run-at       document-end
// ==/UserScript==

(function () {
    class AutoLogin {
        constructor() {
            const url = new URL(Lib.$url);
            this.URL = (url.origin + url.pathname).toLowerCase();
            this.loginInfo = Lib.getV(Lib.$domain, {});

            this.observer = null;
            this.loginInProgress = false;

            this.deleteMenu = null;

            // 保存資訊模板
            this.saveTemplate = [
                "Account", // 帳號
                "Password", // 密碼
                "Autologin", // 填寫後是否自動登入
                "Encrypted", // 後續判斷是否為加密
                "Operate" // 其餘的操作
            ];

            // 加解密算法
            this.algorithm = {
                _UTF16LE: {
                    Parse: (str) => CryptoJS.enc.Utf16LE.parse(LZString.compress(str)),
                    Stringify: (str) => LZString.decompress(CryptoJS.enc.Utf16LE.stringify(str))
                },
                _IV: (str) => CryptoJS.RIPEMD160(str).toString(),
                _SHA3_KEY: (str) => CryptoJS.SHA3(str).toString(),
                _SHA512_KEY: (str) => CryptoJS.SHA512(str).toString(),
                encry: function (Content, Password) {
                    const Text = JSON.stringify(Content);
                    const IV = this._IV(Password);
                    const SHA3_Key = this._SHA3_KEY(Password);
                    const Encrypted_1 = CryptoJS.AES.encrypt(this._UTF16LE.Parse(Text), SHA3_Key, { iv: IV, mode: CryptoJS.mode.CBC, padding: CryptoJS.pad.Iso97971 }).toString();
                    const Encrypted_2 = CryptoJS.AES.encrypt(this._UTF16LE.Parse(Encrypted_1), this._SHA512_KEY(IV), { iv: this._IV(SHA3_Key), mode: CryptoJS.mode.CBC, padding: CryptoJS.pad.Iso97971 }).toString();
                    return Encrypted_2;
                },
                decrypt: function (Content, Password) {
                    const IV = this._IV(Password);
                    const SHA3_Key = this._SHA3_KEY(Password);
                    const Decrypted_1 = this._UTF16LE.Stringify(CryptoJS.AES.decrypt(Content, this._SHA512_KEY(IV), { iv: this._IV(SHA3_Key), mode: CryptoJS.mode.CBC, padding: CryptoJS.pad.Iso97971 }));
                    const Decrypted_2 = this._UTF16LE.Stringify(CryptoJS.AES.decrypt(Decrypted_1, SHA3_Key, { iv: IV, mode: CryptoJS.mode.CBC, padding: CryptoJS.pad.Iso97971 }));
                    return JSON.parse(Decrypted_2);
                }
            };
        }

        _simulateUserInput(element, text) {
            if (element.value === text) return;
            element.focus();
            const prototype = Object.getPrototypeOf(element);
            const valueSetter = Object.getOwnPropertyDescriptor(prototype, 'value')?.set;

            if (valueSetter) {
                valueSetter.call(element, text);
            } else {
                element.value = text;
            }

            element.dispatchEvent(new Event('input', { bubbles: true, cancelable: true }));
            element.dispatchEvent(new Event('change', { bubbles: true, cancelable: true }));
            element.blur();
        }

        _simulateClick(element) {
            if (!element || element.disabled) return;
            const eventOptions = { bubbles: true, cancelable: true };
            element.dispatchEvent(new MouseEvent('mousedown', eventOptions));
            element.dispatchEvent(new MouseEvent('mouseup', eventOptions));
            element.dispatchEvent(new MouseEvent('click', eventOptions));
            if (element.type === 'submit' && element.form) {
                element.form.requestSubmit();
            }
        }

        _findSubmitButton(searchScope) {
            const submitRegex = /login|sign|submit|confirm|enter|next/i;
            return Lib.$q("button[type='submit'], input[type='submit']", { root: searchScope }) ||
                [...searchScope.querySelectorAll("button, [role='button']")].find(btn => submitRegex.test(btn.textContent));
        }

        _findLoginFields() {
            const passwordField = Lib.$q("input[type='password']:not([disabled]):not([readonly])");
            if (!passwordField || passwordField.offsetParent === null) return null;

            const loginForm = passwordField.closest('form');
            const searchScope = loginForm || document.body;

            const highConfidenceField = searchScope.querySelector("input[autocomplete='username'], input[autocomplete='email']");
            if (highConfidenceField && highConfidenceField.offsetParent !== null) {
                return { accountField: highConfidenceField, passwordField, submitButton: this._findSubmitButton(searchScope) };
            }

            const passwordRect = passwordField.getBoundingClientRect();
            const accountRegex = /user|acc|mail|login|id|auth|ident/i;
            const candidates = [];
            const inputs = searchScope.querySelectorAll("input[type='text'], input[type='email'], input[type='tel']");

            inputs.forEach(input => {
                if (input.offsetParent === null || input.disabled || input.readOnly) return;
                let score = 0;
                const id = input.id || '', name = input.name || '', placeholder = input.placeholder || '', ariaLabel = input.ariaLabel || '', type = input.type || '';
                if (type === 'email') score += 5;
                if (accountRegex.test(id)) score += 5;
                if (accountRegex.test(name)) score += 5;
                if (accountRegex.test(placeholder)) score += 3;
                if (accountRegex.test(ariaLabel)) score += 3;

                const candidateRect = input.getBoundingClientRect();
                const verticalDistance = passwordRect.top - candidateRect.bottom;
                const horizontalOffset = Math.abs((passwordRect.left + passwordRect.width / 2) - (candidateRect.left + candidateRect.width / 2));

                if (verticalDistance >= 0 && verticalDistance < 150 && horizontalOffset < 100) {
                    score += 15 + ((150 - verticalDistance) / 10) + ((100 - horizontalOffset) / 10);
                }
                if (score > 0) candidates.push({ element: input, score });
            });

            if (candidates.length === 0) return { passwordField, submitButton: this._findSubmitButton(searchScope) };

            candidates.sort((a, b) => b.score - a.score);
            return { accountField: candidates[0].element, passwordField, submitButton: this._findSubmitButton(searchScope) };
        }

        _saveAccount() {
            const save = prompt("輸入以下數據, 請確實按照順序輸入\n帳號, 密碼, 其餘操作");
            if (!save) return;

            const data = save.split(/\s*[,|/]\s*/);
            if (data.length > 1) {
                const saveBox = {};

                this.saveTemplate.forEach((key, index) => {
                    let info = data[index] ?? false;

                    if (key === "Account" || key === "Password") {
                        info = this.algorithm.encry(info, `${Lib.$domain}@Default_${key}@`);
                    } else if (key === "Autologin" && info === "true") {
                        info = true;
                    }

                    saveBox[key] = info;
                });

                // 目前預設都是加密
                saveBox["Encrypted"] = true;

                setTimeout(() => {
                    Lib.setV(Lib.$domain, Object.assign({ Url: this.URL }, saveBox));
                    this._createDeleteMenu();
                }, 1000);
            } else {
                alert("輸入錯誤");
            }
        }

        _createDeleteMenu() {
            this.deleteMenu ??= GM_registerMenuCommand("🚮 刪除登入資訊", () => {
                Lib.delV(Lib.$domain);
                GM_unregisterMenuCommand(this.deleteMenu);
                this.deleteMenu = null;
            });
        }

        _attemptLogin() {
            if (this.loginInProgress) return;
            this.loginInProgress = true; // 上鎖
            this.observer && this.observer.disconnect(); // 停止觀察

            const loginFields = this._findLoginFields();

            if (loginFields && loginFields.accountField && loginFields.passwordField) {
                const { accountField, passwordField, submitButton } = loginFields;
                let Account = this.loginInfo.Account;
                let Password = this.loginInfo.Password;

                if (this.loginInfo.Encrypted) {
                    try {
                        Account = this.algorithm.decrypt(Account, `${Lib.$domain}@Default_Account@`);
                        Password = this.algorithm.decrypt(Password, `${Lib.$domain}@Default_Password@`);
                    } catch (e) {
                        console.error("解密失敗:", e);
                        this.loginInProgress = false;
                        this.observer && this.observer.observe(document.body, { childList: true, subtree: true });
                        return;
                    }
                }

                this._simulateUserInput(accountField, Account);
                this._simulateUserInput(passwordField, Password);

                if (this.loginInfo.Autologin) {
                    setTimeout(() => {
                        this._simulateClick(submitButton);
                    }, 500);
                }
            } else {
                this.loginInProgress = false; // 如果沒找到欄位，也需要解鎖
                this.observer && this.observer.observe(document.body, { childList: true, subtree: true });
            }
        }

        run() {
            Lib.regMenu({
                "📝 添加登入資訊": () => this._saveAccount()
            })

            const info = this.loginInfo;
            if (!info?.Url || !this.URL.startsWith(info.Url)) return;

            this._createDeleteMenu();

            // 立即嘗試一次，應對非動態載入的頁面
            this._attemptLogin();

            // 設置觀察者，應對動態載入的登入表單
            this.observer = new MutationObserver(Lib.$throttle(() => {
                this._attemptLogin();
            }, 1e3));

            this.observer.observe(document.body, { childList: true, subtree: true });
        }
    }

    const Login = new AutoLogin();
    Login.run();
})();

(() => {
    /* ======================================================================
     * 0. 常數 / 預設值
     * ==================================================================== */

    const namespace = 'CHS';
    const STORAGE_KEY_ACCOUNTS = 'ual_accounts';
    const STORAGE_KEY_GLOBAL = 'ual_global';

    const HIDDEN_CONST = 'ual-scr1pt-f1xed-s41t::v1::do-not-rely-on-this-for-real-security';

    const DEFAULT_GLOBAL = {
        theme: {
            mode: 'light', // 'light' | 'dark' | 'custom'
            vars: {}
        },
        panel: { x: null, y: null, w: 380, h: null }
    };

    const DEFAULT_ACCOUNT_FIELDS = () => ({
        id: '',
        hostname: '',
        pathPattern: [], // ['user', null, 'login'] null = 萬用字元
        account: '',
        password: '',
        encryptedMode: false,
        saveKey: false,
        encMeta: null, // { salt, iv } base64
        mode: 'autofill', // 'autofill' | 'autoprompt'
        autoLoginAfterFill: false,
        postFillOperation: '',
        customLoginScript: '',
        createdAt: 0,
        updatedAt: 0,
        lastUsed: 0
    });

    /* ======================================================================
     * 1. Storage 層 (GM_getValue / GM_setValue 封裝，優先同步)
     * ==================================================================== */

    const Store = {
        get(key, def) {
            try {
                if (typeof GM_getValue === 'function') {
                    const v = GM_getValue(key, def);
                    return v === undefined ? def : v;
                }
            } catch (e) { /* fallthrough */ }
            try {
                const raw = window.localStorage.getItem(namespace + '_fallback_' + key);
                return raw ? JSON.parse(raw) : def;
            } catch (e) {
                return def;
            }
        },
        set(key, value) {
            try {
                if (typeof GM_setValue === 'function') {
                    GM_setValue(key, value);
                    return;
                }
            } catch (e) { /* fallthrough */ }
            try {
                window.localStorage.setItem(namespace + '_fallback_' + key, JSON.stringify(value));
            } catch (e) { /* ignore */ }
        },
        getAccounts() {
            return this.get(STORAGE_KEY_ACCOUNTS, []);
        },
        saveAccounts(list) {
            this.set(STORAGE_KEY_ACCOUNTS, list);
        },
        getGlobal() {
            return Object.assign({}, DEFAULT_GLOBAL, this.get(STORAGE_KEY_GLOBAL, {}));
        },
        saveGlobal(g) {
            this.set(STORAGE_KEY_GLOBAL, g);
        }
    };

    /* ======================================================================
     * 2. Crypto 層 (Web Crypto API，全異步：PBKDF2 + AES-GCM)
     * ==================================================================== */

    function bufToB64(buf) {
        const bytes = new Uint8Array(buf);
        let bin = '';
        for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
        return btoa(bin);
    }
    function b64ToBuf(b64) {
        const bin = atob(b64);
        const bytes = new Uint8Array(bin.length);
        for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
        return bytes.buffer;
    }
    function bufToHex(buf) {
        return [...new Uint8Array(buf)].map(b => b.toString(16).padStart(2, '0')).join('');
    }

    const Crypto = {
        async _deriveKey(passphrase, saltBuf) {
            const keyMaterial = await crypto.subtle.importKey(
                'raw', new TextEncoder().encode(passphrase), 'PBKDF2', false, ['deriveKey']
            );
            const key = await crypto.subtle.deriveKey(
                { name: 'PBKDF2', salt: saltBuf, iterations: 120000, hash: 'SHA-256' },
                keyMaterial, { name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']
            );
            return key;
        },

        // 每個網域推導出的「預設金鑰」(非使用者可見)，僅供混淆用途
        async getDefaultPassphrase(hostname) {
            const data = new TextEncoder().encode(hostname + '::' + HIDDEN_CONST);
            const hashBuf = await crypto.subtle.digest('SHA-256', data);
            return bufToHex(hashBuf);
        },

        async encrypt(plaintext, passphrase) {
            const salt = crypto.getRandomValues(new Uint8Array(16));
            const iv = crypto.getRandomValues(new Uint8Array(12));
            const key = await this._deriveKey(passphrase, salt);
            const cipherBuf = await crypto.subtle.encrypt(
                { name: 'AES-GCM', iv }, key, new TextEncoder().encode(plaintext)
            );
            return {
                cipher: bufToB64(cipherBuf),
                salt: bufToB64(salt.buffer),
                iv: bufToB64(iv.buffer)
            };
        },

        async decrypt(cipherB64, passphrase, saltB64, ivB64) {
            const salt = new Uint8Array(b64ToBuf(saltB64));
            const iv = new Uint8Array(b64ToBuf(ivB64));
            const key = await this._deriveKey(passphrase, salt);
            const plainBuf = await crypto.subtle.decrypt(
                { name: 'AES-GCM', iv }, key, b64ToBuf(cipherB64)
            );
            return new TextDecoder().decode(plainBuf);
        }
    };

    /* ======================================================================
     * 3. 帳號加解密輔助（把 account/password 一起處理）
     * ==================================================================== */

    const AccountCrypto = {
        // 用「金鑰」加密一組帳密，回傳可直接存進 account entry 的欄位
        async encryptPair(account, password, passphrase) {
            const accEnc = await Crypto.encrypt(account, passphrase);
            const pwEnc = await Crypto.encrypt(password, passphrase);
            return {
                account: accEnc.cipher,
                password: pwEnc.cipher,
                // 帳號與密碼各自有獨立的 salt/iv，統一放進 encMeta
                encMeta: {
                    accSalt: accEnc.salt, accIv: accEnc.iv,
                    pwSalt: pwEnc.salt, pwIv: pwEnc.iv
                }
            };
        },
        async decryptPair(entry, passphrase) {
            const { encMeta } = entry;
            const account = await Crypto.decrypt(entry.account, passphrase, encMeta.accSalt, encMeta.accIv);
            const password = await Crypto.decrypt(entry.password, passphrase, encMeta.pwSalt, encMeta.pwIv);
            return { account, password };
        }
    };

    /* ======================================================================
     * 4. 儲存金鑰 (sessionless / localStorage，僅在使用者勾選「保存金鑰」時)
     * ==================================================================== */

    const KeyVault = {
        _lsKey(accountId) {
            return `${namespace}_key_${accountId}`;
        },
        save(accountId, passphrase) {
            try { window.localStorage.setItem(this._lsKey(accountId), passphrase); } catch (e) { /* ignore */ }
        },
        load(accountId) {
            try { return window.localStorage.getItem(this._lsKey(accountId)); } catch (e) { return null; }
        },
        remove(accountId) {
            try { window.localStorage.removeItem(this._lsKey(accountId)); } catch (e) { /* ignore */ }
        }
    };

    /* ======================================================================
     * 5. URL / 路徑比對邏輯
     * ==================================================================== */

    function isRandomSegment(seg) {
        if (/^\d{4,}$/.test(seg)) return true; // 純數字 >=4
        if (/^[0-9a-fA-F]{8,}$/.test(seg) && /[a-fA-F]/.test(seg)) return true; // hex-like >=8
        if (/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/i.test(seg)) return true; // uuid
        if (seg.length >= 12 && /^[a-zA-Z0-9_-]+$/.test(seg)) {
            // 長字串且非常見英文單字型態（全小寫或首字大寫）視為亂碼
            if (!/^[a-z]+$/.test(seg) && !/^[A-Z][a-z]+$/.test(seg)) return true;
        }
        return false;
    }

    function tokenizePathForSave(pathname) {
        return pathname.split('/').filter(s => s.length > 0)
            .map(seg => (isRandomSegment(seg) ? null : seg));
    }
    function tokenizePathRaw(pathname) {
        return pathname.split('/').filter(s => s.length > 0);
    }
    function matchPath(pattern, currentSegs) {
        if (!pattern) return currentSegs.length === 0;
        if (pattern.length !== currentSegs.length) return false;
        for (let i = 0; i < pattern.length; i++) {
            if (pattern[i] !== null && pattern[i] !== currentSegs[i]) return false;
        }
        return true;
    }
    function literalCount(pattern) {
        return (pattern || []).filter(s => s !== null).length;
    }

    function findAccountForCurrentPage() {
        const hostname = location.hostname;
        const all = Store.getAccounts();
        const sameHost = all.filter(a => a.hostname === hostname);
        if (sameHost.length === 0) return null;
        const curSegs = tokenizePathRaw(location.pathname);
        const matches = sameHost.filter(a => matchPath(a.pathPattern, curSegs));
        if (matches.length === 0) return null;
        if (matches.length === 1) return matches[0];
        matches.sort((a, b) => literalCount(b.pathPattern) - literalCount(a.pathPattern) || (b.lastUsed || 0) - (a.lastUsed || 0));
        return matches[0];
    }

    function upsertAccount(entry) {
        const all = Store.getAccounts();
        const idx = all.findIndex(a => a.id === entry.id);
        entry.updatedAt = Date.now();
        if (idx >= 0) all[idx] = entry; else { entry.createdAt = Date.now(); all.push(entry); }
        Store.saveAccounts(all);
    }
    function deleteAccount(id) {
        const all = Store.getAccounts().filter(a => a.id !== id);
        Store.saveAccounts(all);
        KeyVault.remove(id);
    }
    function touchAccount(id) {
        const all = Store.getAccounts();
        const idx = all.findIndex(a => a.id === id);
        if (idx >= 0) { all[idx].lastUsed = Date.now(); Store.saveAccounts(all); }
    }

    /* ======================================================================
     * 6. UI 工具框架 (Shadow DOM 元件建構器 + 主題)
     * ==================================================================== */

    const THEME_CSS = `
    :host {
        all: initial;
        --ual-bg: #ffffff;
        --ual-bg-2: #f4f5f7;
        --ual-fg: #1f2328;
        --ual-fg-muted: #6b7280;
        --ual-border: #e2e4e8;
        --ual-accent: #3b82f6;
        --ual-accent-fg: #ffffff;
        --ual-danger: #ef4444;
        --ual-radius: 10px;
        --ual-shadow: 0 8px 30px rgba(0,0,0,.18);
        --ual-font: -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang TC", "Microsoft JhengHei", sans-serif;
    }
    :host([data-theme="dark"]) {
        --ual-bg: #1e2126;
        --ual-bg-2: #262a31;
        --ual-fg: #eef0f2;
        --ual-fg-muted: #9aa0a8;
        --ual-border: #33373e;
        --ual-accent: #5b9bff;
        --ual-accent-fg: #0b0d10;
    }
    * { box-sizing: border-box; font-family: var(--ual-font); }
    .${namespace}-panel {
        position: fixed;
        top: var(--ual-panel-top, 12px);
        left: var(--ual-panel-left, 50%);
        transform: var(--ual-panel-transform, translateX(-50%));
        width: clamp(300px, var(--ual-panel-w, 380px), 96vw);
        max-height: 88vh;
        background: var(--ual-bg);
        color: var(--ual-fg);
        border: 1px solid var(--ual-border);
        border-radius: var(--ual-radius);
        box-shadow: var(--ual-shadow);
        z-index: 2147483000;
        display: flex;
        flex-direction: column;
        overflow: hidden;
        font-size: 13px;
    }
    .${namespace}-handle {
        cursor: grab;
        padding: 10px 12px;
        background: var(--ual-bg-2);
        border-bottom: 1px solid var(--ual-border);
        display: flex;
        align-items: center;
        justify-content: space-between;
        user-select: none;
        touch-action: none;
    }
    .${namespace}-handle:active { cursor: grabbing; }
    .${namespace}-title { font-weight: 600; font-size: 13px; }
    .${namespace}-close-btn {
        border: none; background: transparent; color: var(--ual-fg-muted);
        cursor: pointer; font-size: 16px; line-height: 1; padding: 2px 6px; border-radius: 6px;
    }
    .${namespace}-close-btn:hover { background: var(--ual-border); color: var(--ual-fg); }
    .${namespace}-tabs {
        display: flex;
        border-bottom: 1px solid var(--ual-border);
        overflow-x: auto;
    }
    .${namespace}-tab-btn {
        flex: 1 0 auto;
        padding: 9px 10px;
        text-align: center;
        border: none; background: transparent; color: var(--ual-fg-muted);
        cursor: pointer; font-size: 12.5px; white-space: nowrap;
        border-bottom: 2px solid transparent;
    }
    .${namespace}-tab-btn.active { color: var(--ual-accent); border-bottom-color: var(--ual-accent); font-weight: 600; }
    .${namespace}-tab-panel { display: none; padding: 14px; overflow-y: auto; }
    .${namespace}-tab-panel.active { display: block; }
    .${namespace}-field { margin-bottom: 12px; }
    .${namespace}-label { display: block; margin-bottom: 5px; font-size: 12px; color: var(--ual-fg-muted); }
    .${namespace}-input-wrap { position: relative; display: flex; align-items: center; }
    .${namespace}-input, .${namespace}-textarea, .${namespace}-select {
        width: 100%; padding: 8px 10px; border: 1px solid var(--ual-border);
        border-radius: 8px; background: var(--ual-bg); color: var(--ual-fg); font-size: 13px;
    }
    .${namespace}-input:focus, .${namespace}-textarea:focus, .${namespace}-select:focus { outline: 2px solid var(--ual-accent); outline-offset: 1px; }
    .${namespace}-textarea { min-height: 90px; font-family: monospace; resize: vertical; }
    .${namespace}-icon-btn {
        position: absolute; right: 6px; border: none; background: transparent;
        cursor: pointer; color: var(--ual-fg-muted); padding: 4px; border-radius: 6px; font-size: 13px;
    }
    .${namespace}-icon-btn:hover { background: var(--ual-border); }
    .${namespace}-row { display: flex; align-items: center; justify-content: space-between; gap: 10px; margin-bottom: 12px; }
    .${namespace}-row-label { font-size: 13px; }
    .${namespace}-row-desc { font-size: 11.5px; color: var(--ual-fg-muted); margin-top: 2px; }
    .${namespace}-switch { position: relative; width: 38px; height: 22px; flex: none; }
    .${namespace}-switch input { opacity: 0; width: 0; height: 0; }
    .${namespace}-slider {
        position: absolute; inset: 0; background: var(--ual-border); border-radius: 999px;
        cursor: pointer; transition: .15s;
    }
    .${namespace}-slider::before {
        content: ''; position: absolute; width: 16px; height: 16px; left: 3px; top: 3px;
        background: #fff; border-radius: 50%; transition: .15s;
    }
    .${namespace}-switch input:checked + .${namespace}-slider { background: var(--ual-accent); }
    .${namespace}-switch input:checked + .${namespace}-slider::before { transform: translateX(16px); }
    .${namespace}-btn {
        padding: 8px 14px; border-radius: 8px; border: 1px solid var(--ual-border);
        background: var(--ual-bg-2); color: var(--ual-fg); cursor: pointer; font-size: 12.5px; font-weight: 500;
    }
    .${namespace}-btn:hover { filter: brightness(0.97); }
    .${namespace}-btn.primary { background: var(--ual-accent); color: var(--ual-accent-fg); border-color: var(--ual-accent); }
    .${namespace}-btn.danger { background: transparent; color: var(--ual-danger); border-color: var(--ual-danger); }
    .${namespace}-btn-row { display: flex; gap: 8px; margin-top: 6px; }
    .${namespace}-resize-handle {
        position: absolute; right: 2px; bottom: 2px; width: 14px; height: 14px; cursor: nwse-resize;
        opacity: .5;
    }
    .${namespace}-resize-handle svg { width: 100%; height: 100%; }
    .${namespace}-radio-group { display: flex; gap: 14px; }
    .${namespace}-radio-item { display: flex; align-items: center; gap: 5px; font-size: 12.5px; }
    .${namespace}-hint { font-size: 11.5px; color: var(--ual-fg-muted); line-height: 1.5; margin-top: 4px; }
    .${namespace}-mask-value { font-family: monospace; font-size: 13px; }
    @media (max-width: 480px) {
        .${namespace}-panel { width: 94vw !important; left: 3vw !important; transform: none !important; top: 8px !important; }
        .${namespace}-tab-btn { font-size: 11.5px; padding: 8px 6px; }
    }
    `;

    function h(tag, attrs = {}, children = []) {
        const el = document.createElement(tag);
        for (const [k, v] of Object.entries(attrs || {})) {
            if (k === 'class') el.className = v;
            else if (k === 'html') el.innerHTML = v;
            else if (k.startsWith('on') && typeof v === 'function') el.addEventListener(k.slice(2), v);
            else if (v !== undefined && v !== null) el.setAttribute(k, v);
        }
        (Array.isArray(children) ? children : [children]).forEach(c => {
            if (c === null || c === undefined) return;
            el.appendChild(typeof c === 'string' ? document.createTextNode(c) : c);
        });
        return el;
    }

    function createSwitch({ checked = false, onChange } = {}) {
        const input = h('input', { type: 'checkbox' });
        input.checked = checked;
        if (onChange) input.addEventListener('change', () => onChange(input.checked));
        const label = h('label', { class: `${namespace}-switch` }, [input, h('span', { class: `${namespace}-slider` })]);
        label._input = input;
        return label;
    }

    function createRow({ label, desc, control }) {
        const left = h('div', {}, [
            h('div', { class: `${namespace}-row-label` }, label),
            desc ? h('div', { class: `${namespace}-row-desc` }, desc) : null
        ]);
        return h('div', { class: `${namespace}-row` }, [left, control]);
    }

    function createTextInput({ label, type = 'text', value = '', placeholder = '', onInput, iconBtn } = {}) {
        const input = h('input', { class: `${namespace}-input`, type, placeholder });
        input.value = value;
        if (onInput) input.addEventListener('input', () => onInput(input.value));
        const wrap = h('div', { class: `${namespace}-input-wrap` }, [input]);
        if (iconBtn) {
            const btn = h('button', { class: `${namespace}-icon-btn`, type: 'button', title: iconBtn.title || '' }, iconBtn.text || '👁');
            btn.addEventListener('click', () => iconBtn.onClick(btn, input));
            wrap.appendChild(btn);
            input.style.paddingRight = '32px';
        }
        const field = h('div', { class: `${namespace}-field` }, [
            label ? h('label', { class: `${namespace}-label` }, label) : null,
            wrap
        ]);
        field._input = input;
        return field;
    }

    function createTextArea({ label, value = '', placeholder = '', onInput } = {}) {
        const ta = h('textarea', { class: `${namespace}-textarea`, placeholder });
        ta.value = value;
        if (onInput) ta.addEventListener('input', () => onInput(ta.value));
        const field = h('div', { class: `${namespace}-field` }, [
            label ? h('label', { class: `${namespace}-label` }, label) : null,
            ta
        ]);
        field._input = ta;
        return field;
    }

    function createButton(label, { variant = '', onClick } = {}) {
        const btn = h('button', { class: `${namespace}-btn ${variant}`.trim(), type: 'button' }, label);
        if (onClick) btn.addEventListener('click', onClick);
        return btn;
    }

    function createTabs(tabDefs) {
        // tabDefs: [{ key, label, render(container) }]
        const tabsBar = h('div', { class: `${namespace}-tabs` });
        const body = h('div', {});
        const panels = {};
        tabDefs.forEach((def, i) => {
            const btn = h('button', { class: `${namespace}-tab-btn` + (i === 0 ? ' active' : ''), type: 'button' }, def.label);
            const panel = h('div', { class: `${namespace}-tab-panel` + (i === 0 ? ' active' : '') });
            def.render(panel);
            panels[def.key] = { btn, panel };
            btn.addEventListener('click', () => {
                Object.values(panels).forEach(p => { p.btn.classList.remove('active'); p.panel.classList.remove('active'); });
                btn.classList.add('active'); panel.classList.add('active');
            });
            tabsBar.appendChild(btn);
            body.appendChild(panel);
        });
        return h('div', {}, [tabsBar, body]);
    }

    /* ---- 拖動 / 拉伸 ---- */
    function makeDraggable(panelEl, handleEl, onEnd) {
        let dragging = false, startX, startY, startLeft, startTop;
        handleEl.addEventListener('pointerdown', (e) => {
            if (e.target.closest(`.${namespace}-close-btn`)) return;
            dragging = true;
            const rect = panelEl.getBoundingClientRect();
            startX = e.clientX; startY = e.clientY;
            startLeft = rect.left; startTop = rect.top;
            panelEl.style.transform = 'none';
            panelEl.style.left = startLeft + 'px';
            panelEl.style.top = startTop + 'px';
            handleEl.setPointerCapture(e.pointerId);
        });
        handleEl.addEventListener('pointermove', (e) => {
            if (!dragging) return;
            const dx = e.clientX - startX, dy = e.clientY - startY;
            let newLeft = startLeft + dx, newTop = startTop + dy;
            const maxLeft = window.innerWidth - 40, maxTop = window.innerHeight - 40;
            newLeft = Math.min(Math.max(newLeft, -panelEl.offsetWidth + 60), maxLeft);
            newTop = Math.min(Math.max(newTop, 0), maxTop);
            panelEl.style.left = newLeft + 'px';
            panelEl.style.top = newTop + 'px';
        });
        ['pointerup', 'pointercancel'].forEach(ev => handleEl.addEventListener(ev, () => {
            if (!dragging) return;
            dragging = false;
            if (onEnd) onEnd({ left: parseFloat(panelEl.style.left), top: parseFloat(panelEl.style.top) });
        }));
    }
    function makeResizable(panelEl, handleEl, onEnd) {
        let resizing = false, startX, startY, startW, startH;
        handleEl.addEventListener('pointerdown', (e) => {
            resizing = true;
            const rect = panelEl.getBoundingClientRect();
            startX = e.clientX; startY = e.clientY; startW = rect.width; startH = rect.height;
            handleEl.setPointerCapture(e.pointerId);
            e.stopPropagation();
        });
        handleEl.addEventListener('pointermove', (e) => {
            if (!resizing) return;
            const dw = e.clientX - startX, dh = e.clientY - startY;
            const newW = Math.max(300, startW + dw);
            const newH = Math.max(200, startH + dh);
            panelEl.style.setProperty('--ual-panel-w', newW + 'px');
            panelEl.style.maxHeight = newH + 'px';
        });
        ['pointerup', 'pointercancel'].forEach(ev => handleEl.addEventListener(ev, () => {
            if (!resizing) return;
            resizing = false;
            if (onEnd) onEnd({ w: panelEl.offsetWidth, h: panelEl.offsetHeight });
        }));
    }

    function createShadowHost(idSuffix) {
        const host = document.createElement('div');
        host.id = `${namespace}-host-${idSuffix}`;
        host.style.all = 'initial';
        document.documentElement.appendChild(host);
        const shadow = host.attachShadow({ mode: 'open' });
        const style = document.createElement('style');
        style.textContent = THEME_CSS;
        shadow.appendChild(style);
        return { host, shadow };
    }

    function applyTheme(hostEl, themeConfig) {
        if (themeConfig.mode === 'dark') hostEl.setAttribute('data-theme', 'dark');
        else hostEl.removeAttribute('data-theme');
        if (themeConfig.mode === 'custom' && themeConfig.vars) {
            Object.entries(themeConfig.vars).forEach(([k, v]) => hostEl.style.setProperty(`--ual-${k}`, v));
        }
    }

    /* ======================================================================
     * 7. 面板元件 (Home / Settings / Advanced / Menu)
     * ==================================================================== */

    let panelInstance = null;

    function makeAccountId(hostname, pathPattern) {
        return hostname + '|' + pathPattern.join('/');
    }

    function openPanel() {
        if (panelInstance) { panelInstance.panelEl.style.display = 'flex'; return; }

        const { host, shadow } = createShadowHost('panel');
        const global = Store.getGlobal();

        let current = findAccountForCurrentPage() || Object.assign(
            DEFAULT_ACCOUNT_FIELDS(),
            { hostname: location.hostname, pathPattern: tokenizePathForSave(location.pathname) }
        );
        current.id = current.id || makeAccountId(current.hostname, current.pathPattern);

        // ---- 頂部把手 ----
        const closeBtn = h('button', { class: `${namespace}-close-btn`, type: 'button', title: '關閉' }, '✕');
        closeBtn.addEventListener('click', () => { panelEl.style.display = 'none'; });
        const handle = h('div', { class: `${namespace}-handle` }, [
            h('span', { class: `${namespace}-title` }, '🔐 帳號管理面板'),
            closeBtn
        ]);

        /* ---------------- Home Tab ---------------- */
        function renderHome(container) {
            container.innerHTML = '';
            const hint = h('div', { class: `${namespace}-hint` }, `目前網址：${location.hostname}${location.pathname}`);
            const accField = createTextInput({ label: '帳號', value: current.account, onInput: v => current.account = v });
            let pwVisible = false;
            const pwField = createTextInput({
                label: '密碼', type: 'password', value: current.password,
                onInput: v => current.password = v,
                iconBtn: {
                    text: '👁',
                    title: '顯示/隱藏密碼',
                    onClick: (btn, input) => {
                        pwVisible = !pwVisible;
                        input.type = pwVisible ? 'text' : 'password';
                    }
                }
            });

            const keyWrap = h('div', {});
            function renderKeyInputIfNeeded() {
                keyWrap.innerHTML = '';
                if (current.encryptedMode) {
                    const keyField = createTextInput({ label: '自訂加密金鑰', type: 'password', placeholder: '輸入你的金鑰以加密/解密' });
                    const decryptBtn = createButton('🔓 用此金鑰解密目前資料', {
                        onClick: async () => {
                            try {
                                if (!current.encMeta) { alert('目前尚未有加密資料'); return; }
                                const { account, password } = await AccountCrypto.decryptPair(current, keyField._input.value);
                                accField._input.value = account;
                                pwField._input.value = password;
                                current.account = account;
                                current.password = password;
                                alert('解密成功，已帶入表單');
                            } catch (e) {
                                alert('解密失敗，金鑰錯誤或資料已損毀');
                            }
                        }
                    });
                    keyWrap.appendChild(keyField);
                    keyWrap.appendChild(decryptBtn);
                }
            }
            renderKeyInputIfNeeded();

            const saveBtn = createButton('💾 保存', {
                variant: 'primary',
                onClick: async () => {
                    current.account = accField._input.value;
                    current.password = pwField._input.value;
                    if (current.encryptedMode) {
                        const keyInput = keyWrap.querySelector(`.${namespace}-input`);
                        const passphrase = keyInput ? keyInput.value : '';
                        if (!passphrase) { alert('已啟用自訂加密金鑰，請輸入金鑰才能保存'); return; }
                        const enc = await AccountCrypto.encryptPair(current.account, current.password, passphrase);
                        current.account = enc.account;
                        current.password = enc.password;
                        current.encMeta = enc.encMeta;
                        if (current.saveKey) KeyVault.save(current.id, passphrase);
                        else KeyVault.remove(current.id);
                    } else {
                        const passphrase = await Crypto.getDefaultPassphrase(current.hostname);
                        const enc = await AccountCrypto.encryptPair(current.account, current.password, passphrase);
                        current.account = enc.account;
                        current.password = enc.password;
                        current.encMeta = enc.encMeta;
                    }
                    upsertAccount(current);
                    alert('已保存此帳號設定');
                }
            });
            const deleteBtn = createButton('🗑 刪除此帳號', {
                variant: 'danger',
                onClick: () => {
                    if (confirm('確定要刪除這組帳號設定？')) {
                        deleteAccount(current.id);
                        alert('已刪除');
                        panelEl.style.display = 'none';
                    }
                }
            });

            container.appendChild(hint);
            container.appendChild(accField);
            container.appendChild(pwField);
            container.appendChild(keyWrap);
            container.appendChild(h('div', { class: `${namespace}-btn-row` }, [saveBtn, deleteBtn]));
        }

        /* ---------------- Settings Tab ---------------- */
        function renderSettings(container) {
            container.innerHTML = '';

            const modeGroup = h('div', { class: `${namespace}-radio-group` });
            [['autofill', '自動填入'], ['autoprompt', '自動提示']].forEach(([val, label]) => {
                const radio = h('input', { type: 'radio', name: `${namespace}-mode`, value: val });
                radio.checked = current.mode === val;
                radio.addEventListener('change', () => { current.mode = val; refreshAutoLoginState(); });
                modeGroup.appendChild(h('label', { class: `${namespace}-radio-item` }, [radio, label]));
            });
            container.appendChild(h('div', { class: `${namespace}-field` }, [
                h('label', { class: `${namespace}-label` }, '偵測到登入欄位時的行為（二選一）'),
                modeGroup
            ]));

            const autoLoginSwitch = createSwitch({
                checked: current.autoLoginAfterFill,
                onChange: v => current.autoLoginAfterFill = v
            });
            const autoLoginRow = createRow({
                label: '填入後自動點擊登入',
                desc: '僅在「自動填入」模式下生效',
                control: autoLoginSwitch
            });
            container.appendChild(autoLoginRow);

            function refreshAutoLoginState() {
                const disabled = current.mode !== 'autofill';
                autoLoginSwitch._input.disabled = disabled;
                autoLoginRow.style.opacity = disabled ? .5 : 1;
            }
            refreshAutoLoginState();

            const opField = createTextInput({
                label: '填入/登入後自訂操作（選填，一段簡短說明或指令代稱，實際邏輯請至「進階功能」撰寫）',
                value: current.postFillOperation,
                onInput: v => current.postFillOperation = v
            });
            container.appendChild(opField);

            container.appendChild(h('hr', { style: `border-color: var(--${namespace}-border); opacity:.4; margin: 14px 0;` }));

            const encSwitch = createSwitch({
                checked: current.encryptedMode,
                onChange: v => {
                    current.encryptedMode = v;
                    if (v) { current.mode = 'autoprompt'; renderSettings(container); }
                    refreshSaveKeyRow();
                }
            });
            container.appendChild(createRow({
                label: '啟用自訂加密金鑰',
                desc: '啟用後將強制改為「自動提示」模式（無法背景自動登入，除非保存金鑰）',
                control: encSwitch
            }));

            const saveKeySwitch = createSwitch({
                checked: current.saveKey,
                onChange: v => current.saveKey = v
            });
            const saveKeyRow = createRow({
                label: '保存金鑰於此網站',
                desc: '保存後可自動解密並自動填入/登入；不保存則每次需手動輸入金鑰',
                control: saveKeySwitch
            });
            container.appendChild(saveKeyRow);
            function refreshSaveKeyRow() {
                saveKeyRow.style.display = current.encryptedMode ? 'flex' : 'none';
            }
            refreshSaveKeyRow();
        }

        /* ---------------- Advanced Tab ---------------- */
        function renderAdvanced(container) {
            container.innerHTML = '';
            container.appendChild(h('div', { class: `${namespace}-hint` },
                '此腳本會以 async function(ctx) 執行，可用 ctx.account, ctx.password, ctx.accountField, ctx.passwordField, ctx.submitButton, await ctx.delay(ms), ctx.type(el,text), ctx.click(el)'));
            const scriptArea = createTextArea({
                value: current.customLoginScript,
                placeholder: '例如：\nawait ctx.delay(1000);\nctx.click(ctx.submitButton);',
                onInput: v => current.customLoginScript = v
            });
            container.appendChild(scriptArea);
            container.appendChild(createButton('💾 保存腳本', {
                variant: 'primary',
                onClick: () => { upsertAccount(current); alert('已保存自訂腳本'); }
            }));
        }

        /* ---------------- Menu (主題) Tab ---------------- */
        function renderMenu(container) {
            container.innerHTML = '';
            const themeGroup = h('div', { class: `${namespace}-radio-group` });
            [['default', '預設主題'], ['custom', '自訂主題']].forEach(([val, label]) => {
                const radio = h('input', { type: 'radio', name: `${namespace}-theme-mode`, value: val });
                radio.checked = (global.theme.mode === val) || (val === 'default' && global.theme.mode !== 'custom');
                radio.addEventListener('change', () => {
                    if (val === 'default') global.theme.mode = 'light';
                    else global.theme.mode = 'custom';
                    Store.saveGlobal(global);
                    applyTheme(host, global.theme);
                    renderMenu(container);
                });
                themeGroup.appendChild(h('label', { class: `${namespace}-radio-item` }, [radio, label]));
            });
            container.appendChild(h('div', { class: `${namespace}-field` }, [
                h('label', { class: `${namespace}-label` }, '主題模式'),
                themeGroup
            ]));

            if (global.theme.mode !== 'custom') {
                const darkSwitch = createSwitch({
                    checked: global.theme.mode === 'dark',
                    onChange: v => {
                        global.theme.mode = v ? 'dark' : 'light';
                        Store.saveGlobal(global);
                        applyTheme(host, global.theme);
                    }
                });
                container.appendChild(createRow({ label: '暗黑模式', control: darkSwitch }));
            } else {
                const colorDefs = [
                    ['bg', '背景色', '#ffffff'], ['bg-2', '次要背景', '#f4f5f7'],
                    ['fg', '文字色', '#1f2328'], ['accent', '強調色', '#3b82f6'],
                    ['border', '邊框色', '#e2e4e8']
                ];
                colorDefs.forEach(([key, label, def]) => {
                    const val = global.theme.vars[key] || def;
                    const input = h('input', { type: 'color', value: val, style: 'width:44px;height:30px;border:none;background:none;cursor:pointer;' });
                    input.addEventListener('input', () => {
                        global.theme.vars[key] = input.value;
                        Store.saveGlobal(global);
                        applyTheme(host, global.theme);
                    });
                    container.appendChild(createRow({ label, control: input }));
                });
            }
        }

        const tabs = createTabs([
            { key: 'home', label: '主頁', render: renderHome },
            { key: 'settings', label: '功能設置', render: renderSettings },
            { key: 'advanced', label: '進階功能', render: renderAdvanced },
            { key: 'menu', label: '菜單設置', render: renderMenu }
        ]);

        const resizeHandle = h('div', { class: `${namespace}-resize-handle` },
            h('svg', { viewBox: '0 0 16 16', html: '<path d="M16 16H10L16 10Z" fill="currentColor"/><path d="M16 8L8 16" stroke="currentColor" stroke-width="1.2"/>' }));

        const panelEl = h('div', { class: `${namespace}-panel` }, [handle, tabs, resizeHandle]);
        if (global.panel.w) panelEl.style.setProperty('--ual-panel-w', global.panel.w + 'px');
        if (global.panel.x !== null) { panelEl.style.left = global.panel.x + 'px'; panelEl.style.transform = 'none'; }
        if (global.panel.y !== null) panelEl.style.top = global.panel.y + 'px';

        applyTheme(host, global.theme);
        shadow.appendChild(panelEl);

        makeDraggable(panelEl, handle, ({ left, top }) => {
            global.panel.x = left; global.panel.y = top; Store.saveGlobal(global);
        });
        makeResizable(panelEl, resizeHandle, ({ w }) => {
            global.panel.w = w; Store.saveGlobal(global);
        });

        panelInstance = { host, shadow, panelEl };
    }

    /* ======================================================================
     * 8. 自動提示彈窗 (獨立 Shadow DOM)
     * ==================================================================== */

    function maskPassword(pw) {
        if (!pw) return '';
        return pw.slice(0, Math.min(3, pw.length)) + '***';
    }

    function copyToClipboard(text) {
        try {
            navigator.clipboard.writeText(text);
        } catch (e) {
            const ta = document.createElement('textarea');
            ta.value = text; document.body.appendChild(ta); ta.select();
            document.execCommand('copy'); ta.remove();
        }
    }

    function showPromptPopup({ account, maskedPassword, rawPassword, onFillClick, allowFill }) {
        const { host, shadow } = createShadowHost('prompt-' + Date.now());
        const global = Store.getGlobal();
        applyTheme(host, global.theme);

        const closeBtn = h('button', { class: `${namespace}-close-btn`, type: 'button' }, '✕');
        const box = h('div', { class: `${namespace}-panel`, style: 'position:fixed; top:16px; right:16px; left:auto; transform:none; width: 280px;' });
        closeBtn.addEventListener('click', () => host.remove());

        const accCopyBtn = createButton('複製', { onClick: () => copyToClipboard(account) });
        const pwCopyBtn = createButton('複製', { onClick: () => copyToClipboard(rawPassword) });

        const body = h('div', { style: 'padding:14px;' }, [
            h('div', { class: `${namespace}-row` }, [h('span', {}, `帳號：${account}`), accCopyBtn]),
            h('div', { class: `${namespace}-row` }, [h('span', { class: `${namespace}-mask-value` }, `密碼：${maskedPassword}`), pwCopyBtn])
        ]);

        if (allowFill) {
            const fillBtn = createButton('✍️ 自動填寫', { variant: 'primary', onClick: () => { onFillClick(); host.remove(); } });
            body.appendChild(h('div', { class: `${namespace}-btn-row` }, [fillBtn]));
        }

        box.appendChild(h('div', { class: `${namespace}-handle` }, [h('span', { class: `${namespace}-title` }, '🔔 登入資訊提示'), closeBtn]));
        box.appendChild(body);
        shadow.appendChild(box);
    }

    function showDecryptPopup({ account }, onDecrypted) {
        const { host, shadow } = createShadowHost('decrypt-' + Date.now());
        const global = Store.getGlobal();
        applyTheme(host, global.theme);

        const closeBtn = h('button', { class: `${namespace}-close-btn`, type: 'button' }, '✕');
        const box = h('div', { class: `${namespace}-panel`, style: 'position:fixed; top:16px; right:16px; left:auto; transform:none; width: 300px;' });
        closeBtn.addEventListener('click', () => host.remove());

        const keyField = createTextInput({ label: '請輸入解密金鑰', type: 'password' });
        const decryptBtn = createButton('🔓 解密', {
            variant: 'primary',
            onClick: async () => {
                try {
                    const { account: acc, password: pw } = await AccountCrypto.decryptPair(account, keyField._input.value);
                    host.remove();
                    onDecrypted(acc, pw);
                } catch (e) {
                    alert('解密失敗，金鑰錯誤');
                }
            }
        });

        const body = h('div', { style: 'padding:14px;' }, [keyField, h('div', { class: `${namespace}-btn-row` }, [decryptBtn])]);
        box.appendChild(h('div', { class: `${namespace}-handle` }, [h('span', { class: `${namespace}-title` }, '🔐 需要金鑰解密'), closeBtn]));
        box.appendChild(body);
        shadow.appendChild(box);
    }

    function showKeyLostPopup(account) {
        const { host, shadow } = createShadowHost('keylost-' + Date.now());
        const global = Store.getGlobal();
        applyTheme(host, global.theme);

        const box = h('div', { class: `${namespace}-panel`, style: 'position:fixed; top:16px; right:16px; left:auto; transform:none; width: 300px;' });
        const closeBtn = h('button', { class: `${namespace}-close-btn`, type: 'button' }, '✕');
        closeBtn.addEventListener('click', () => {
            host.remove();
            deleteAccount(account.id);
        });
        const body = h('div', { style: 'padding:14px;' }, [
            h('div', {}, '🔑 金鑰遺失，此帳號資料已無法解密。'),
            h('div', { class: `${namespace}-hint` }, '關閉此視窗後，這組帳號設定將自動被清除。')
        ]);
        box.appendChild(h('div', { class: `${namespace}-handle` }, [h('span', { class: `${namespace}-title` }, '⚠️ 金鑰遺失'), closeBtn]));
        box.appendChild(body);
        shadow.appendChild(box);
    }

    /* ======================================================================
     * 9. 登入欄位偵測引擎
     * ==================================================================== */

    function isVisible(el) {
        if (!el) return false;
        const rect = el.getBoundingClientRect();
        if (rect.width === 0 && rect.height === 0) return false;
        const style = getComputedStyle(el);
        return style.visibility !== 'hidden' && style.display !== 'none';
    }

    function queryAllDeep(selector, root = document) {
        const results = [...root.querySelectorAll(selector)];
        const all = root.querySelectorAll('*');
        all.forEach(el => {
            if (el.shadowRoot) results.push(...queryAllDeep(selector, el.shadowRoot));
        });
        return results;
    }

    function findSubmitButton(scope) {
        const submitRegex = /login|sign|submit|confirm|enter|next|登入|登錄|送出|確定/i;
        const explicit = scope.querySelector("button[type='submit'], input[type='submit']");
        if (explicit) return explicit;
        const candidates = [...scope.querySelectorAll("button, [role='button'], input[type='button']")];
        return candidates.find(btn => submitRegex.test(btn.textContent || btn.value || '')) || null;
    }

    function findLoginFields() {
        const passwordFields = queryAllDeep("input[type='password']:not([disabled]):not([readonly])")
            .filter(isVisible);
        if (passwordFields.length === 0) return null;
        const passwordField = passwordFields[0];

        const loginForm = passwordField.closest('form');
        const searchScope = loginForm || passwordField.getRootNode().host?.closest?.('body') || document.body;

        const highConfidence = searchScope.querySelector("input[autocomplete='username'], input[autocomplete='email']");
        if (highConfidence && isVisible(highConfidence)) {
            return { accountField: highConfidence, passwordField, submitButton: findSubmitButton(searchScope) };
        }

        const pwRect = passwordField.getBoundingClientRect();
        const accountRegex = /user|acc|mail|login|id|auth|ident|帳號|賬號|用戶|信箱/i;
        const inputs = [...searchScope.querySelectorAll("input[type='text'], input[type='email'], input[type='tel']")]
            .filter(isVisible);

        const candidates = [];
        inputs.forEach(input => {
            let score = 0;
            const meta = [input.id, input.name, input.placeholder, input.getAttribute('aria-label'), input.type].join(' ');
            if (input.type === 'email') score += 5;
            if (accountRegex.test(meta)) score += 6;

            const rect = input.getBoundingClientRect();
            const vDist = pwRect.top - rect.bottom;
            const hOffset = Math.abs((pwRect.left + pwRect.width / 2) - (rect.left + rect.width / 2));
            if (vDist >= 0 && vDist < 150 && hOffset < 120) {
                score += 15 + (150 - vDist) / 10 + (120 - hOffset) / 10;
            }
            if (score > 0) candidates.push({ input, score });
        });

        if (candidates.length === 0) return { passwordField, submitButton: findSubmitButton(searchScope) };
        candidates.sort((a, b) => b.score - a.score);
        return { accountField: candidates[0].input, passwordField, submitButton: findSubmitButton(searchScope) };
    }

    /* ======================================================================
     * 10. 表單操作 / 自訂腳本執行
     * ==================================================================== */

    function simulateUserInput(element, text) {
        if (!element || element.value === text) return;
        element.focus();
        const proto = Object.getPrototypeOf(element);
        const setter = Object.getOwnPropertyDescriptor(proto, 'value')?.set;
        if (setter) setter.call(element, text); else element.value = text;
        element.dispatchEvent(new Event('input', { bubbles: true }));
        element.dispatchEvent(new Event('change', { bubbles: true }));
        element.blur();
    }
    function simulateClick(element) {
        if (!element || element.disabled) return;
        const opts = { bubbles: true, cancelable: true };
        element.dispatchEvent(new MouseEvent('mousedown', opts));
        element.dispatchEvent(new MouseEvent('mouseup', opts));
        element.dispatchEvent(new MouseEvent('click', opts));
        if (element.type === 'submit' && element.form) element.form.requestSubmit();
    }

    async function runCustomScript(code, ctxExtra) {
        if (!code || !code.trim()) return;
        const AsyncFunction = Object.getPrototypeOf(async function () { }).constructor;
        try {
            const fn = new AsyncFunction('ctx', code);
            await fn({
                delay: ms => new Promise(r => setTimeout(r, ms)),
                click: simulateClick,
                type: simulateUserInput,
                ...ctxExtra
            });
        } catch (e) {
            console.error('[UAL] 自訂腳本執行錯誤:', e);
        }
    }

    /* ======================================================================
     * 11. 自動填入 / 自動提示 Controller
     * ==================================================================== */

    let handledOnce = false;

    function throttle(fn, wait) {
        let last = 0, timer = null;
        return (...args) => {
            const now = Date.now();
            if (now - last >= wait) { last = now; fn(...args); }
            else {
                clearTimeout(timer);
                timer = setTimeout(() => { last = Date.now(); fn(...args); }, wait - (now - last));
            }
        };
    }

    async function handleDetection() {
        const account = findAccountForCurrentPage();
        if (!account) return;

        const fields = findLoginFields();
        if (!fields || !fields.passwordField) return;
        // 自動提示模式需要三者皆存在才觸發；自動填入模式帳密欄位存在即可嘗試
        if (account.mode === 'autoprompt' && (!fields.accountField || !fields.submitButton)) return;
        if (!fields.accountField) return;

        if (handledOnce) return;
        handledOnce = true;
        touchAccount(account.id);

        const doFill = async (plainAccount, plainPassword) => {
            simulateUserInput(fields.accountField, plainAccount);
            simulateUserInput(fields.passwordField, plainPassword);
            if (account.autoLoginAfterFill) {
                await new Promise(r => setTimeout(r, 400));
                simulateClick(fields.submitButton);
            }
            await runCustomScript(account.customLoginScript, {
                account: plainAccount, password: plainPassword,
                accountField: fields.accountField, passwordField: fields.passwordField, submitButton: fields.submitButton
            });
        };

        try {
            if (!account.encryptedMode) {
                // 一般模式：用預設金鑰全自動解密
                const passphrase = await Crypto.getDefaultPassphrase(account.hostname);
                const { account: acc, password: pw } = await AccountCrypto.decryptPair(account, passphrase);
                if (account.mode === 'autofill') {
                    await doFill(acc, pw);
                } else {
                    showPromptPopup({
                        account: acc, maskedPassword: maskPassword(pw), rawPassword: pw,
                        allowFill: true, onFillClick: () => doFill(acc, pw)
                    });
                }
                return;
            }

            // 自訂加密金鑰模式
            if (account.saveKey) {
                const savedKey = KeyVault.load(account.id);
                if (!savedKey) { showKeyLostPopup(account); return; }
                try {
                    const { account: acc, password: pw } = await AccountCrypto.decryptPair(account, savedKey);
                    if (account.mode === 'autofill') {
                        await doFill(acc, pw);
                    } else {
                        showPromptPopup({
                            account: acc, maskedPassword: maskPassword(pw), rawPassword: pw,
                            allowFill: true, onFillClick: () => doFill(acc, pw)
                        });
                    }
                } catch (e) {
                    showKeyLostPopup(account);
                }
            } else {
                // 未保存金鑰：一律跳出手動輸入金鑰的提示窗
                showDecryptPopup(account, (acc, pw) => {
                    showPromptPopup({
                        account: acc, maskedPassword: maskPassword(pw), rawPassword: pw,
                        allowFill: true, onFillClick: () => doFill(acc, pw)
                    });
                });
            }
        } catch (e) {
            console.error('[UAL] 處理登入偵測時發生錯誤:', e);
        } finally {
            // 允許之後頁面動態改變時重新偵測（例如換頁但未整頁刷新）
            setTimeout(() => { handledOnce = false; }, 3000);
        }
    }

    /* ======================================================================
     * 12. 進場邏輯
     * ==================================================================== */

    function bootstrap() {
        try {
            if (typeof GM_registerMenuCommand === 'function') {
                GM_registerMenuCommand('🔐 開啟帳號管理面板', () => openPanel());
            }
        } catch (e) { console.error('[UAL] 選單註冊失敗:', e); }

        const throttled = throttle(() => { handleDetection(); }, 1000);
        handleDetection();
        const observer = new MutationObserver(throttled);
        observer.observe(document.body, { childList: true, subtree: true });
    }
})();