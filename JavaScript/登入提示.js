// ==UserScript==
// @name        自動登入器
// @name:zh-TW  自動登入器
// @name:zh-CN  自動登入器
// @name:ja     自動登入器
// @name:ko     自動登入器
// @name:en     自動登入器
// @version      0.0.1
// @author       Canaan HS
// @description        自動登入器
// @description:zh-TW  自動登入器
// @description:zh-CN  自動登入器
// @description:ja     自動登入器
// @description:ko     自動登入器
// @description:en     自動登入器

// @match        *://*/*

// @noframes
// @license      MPL-2.0
// @namespace    https://greasyfork.org/users/989635
// @icon         https://cdn-icons-png.flaticon.com/512/7960/7960597.png

// @grant        GM_setValue
// @grant        GM_getValue
// @grant        GM_deleteValue
// @grant        GM_registerMenuCommand
// @grant        GM_unregisterMenuCommand

// @require      https://update.greasyfork.org/scripts/487608/1647211/SyntaxLite_min.js
// @require      https://cdnjs.cloudflare.com/ajax/libs/crypto-js/4.2.0/crypto-js.min.js
// @require      https://cdnjs.cloudflare.com/ajax/libs/lz-string/1.5.0/lz-string.min.js

// @run-at       document-end
// ==/UserScript==

/**
 * 所有的實現, 盡量以純 Css 與 原生 JS 來實現, 盡量減少性能開銷
 * 當無法自己實現時, 就採用一些第三方的套件, 盡量以最輕量的方式來實現
 * 
 * 核心 UI: 浮動控制面板 (Floating Control Panel)
 * 
 * 核心介面將是一個非侵入式的浮動面板，而非傳統鎖定背景的模態視窗。
 * 
 * - 互動設計 (Interaction):
 *   - 可拖動: 面板頂部應作為拖動手柄，方便使用者移動。
 *   - 可拉伸: 面板側面提供拉伸手柄，方便使用者調整大小。
 *   - 定位: 預設位置在畫面頂部、水平置中。
 * 
 * - 主題與樣式 (Theming & Style):
 *   - 雙模式: 提供「亮色」與「暗黑」兩種預設主題。
 *
 * ---
 *
 * 功能分頁與使用者體驗 (Feature Tabs & UX)
 * 
 * 面板將採用分頁設計，將不同功能清晰地隔離開來。
 *
 * 1. 主頁 (Home Tab)
 *   - 核心功能:
 *     - 帳號 (Account) 輸入框。
 *     - 密碼 (Password) 輸入框，並附帶一個「眼睛」圖示來切換密碼可見性。
 *     - 如果有自訂加密金鑰, 額外顯示輸入密鑰框, 跟解密按鈕
 *     - 「保存」與「關閉」按鈕。
 *
 * 2. 功能設置 (Settings Tab)
 *   - 自動填入/登入 (Auto-fill/Auto-login):
 *     - 一個開關 (Switch Checkbox) 用於啟用或禁用「自動填入帳號密碼」(預設開啟)。
 *     - 另一個開關來決定填入後是否「自動點擊登入」 (預設關閉)。
 *     - 提供自訂後操作輸入框 (預設關閉)
 * 
 *   - 登入提示 (Login Prompting - UX Enhancement):
 *     - [獨立菜單]
 *     - 觸發方式: 當腳本偵測到頁面上有登入欄位時，自動彈出菜單。
 *     - 互動: 根據判斷是否有自訂加密金鑰，顯示解密輸入框，輸入完成後直接顯示解密結果。
 *     - 標籤顯示帳號 與 密碼, 密碼不直接顯示, 只提供 123*** 之類的, 並且兩個旁邊各自有複製按鈕
 *
 *   - 自訂加密金鑰 (Custom Encryption Key):
 *     - 一個開關 (Switch Checkbox) 用於啟用此功能。
 *     - 安全機制: 啟用此功能後，將強制禁用「自動填入/登入」功能。
 *
 * 3. 進階功能 (Advanced Features)
 *   - 自訂登入操作 (Custom Login Scripts):
 *     - 提供一個文本框, 可直接使用 js 代碼
 *     - 目的: 應對需要額外驗證步驟（如驗證碼、兩步驟驗證）的複雜登入流程。
 *     - 安全實現:
 *       - 採用 new Function(userCode) 作為更安全的替代方案。
 *       - 原理: new Function() 創建的函數在全域作用域中執行，無法直接存取
 *         腳本的局部變數和閉包，提供了一層基礎的沙盒保護。
 *
 * 4. 菜單設置 (Menu Customization Tab)
 *   - 主題選擇:
 *     - 單選按鈕 (Radio Button) 在「預設主題」和「自訂主題」之間選擇。
 *     - 預設主題下，提供開關切換亮色/暗黑模式。
 *   - 顏色自訂:
 *     - 在「自訂主題」下，提供顏色選擇器 JSColor 來設計 讓使用者
 *       修改 CSS 變數的值（如背景、文字顏色），並即時預覽效果。
 *   - 語言選擇 (Localization):
 *     - 一個下拉列表 (Dropdown) 用於切換介面語言。
 * 
 * ----- 實現功能改進 -----
 * 
 * 如果可以盡量不使用第三方庫來實現, 全都採用第一方庫來實現
 * 如果對應加解密功能, 瀏覽器內建都有, 也改成內建版本
 * 我覺得自動填入, 應該另外在設計一個, 自動提示的功能, 作為二選一操作, 自動提示是在該頁面, 跳出乾淨的提示窗口
 * 當前的許多打印操作, 跟藉助插件菜單功能的, 之後都改成菜單版本, 或是用 css 功能等, 不過為了避免通用, 要用獨立的 shadow dom
 * 查找對應元素功能阿, 後續自動填寫跟登入功能阿, 等等的你都應該重新幫我使用更先進的處理方式, 我以前都是根據我觀察到的來處理的, 還是很多不完善
 * 
 * 上面是我以前些的 UI 想法, 但是老實說, 我現在都不知道我當時要什麼, 總之你主要還是用你的方式設計, 我的話參考用就好, 要先像我確認的就問
 * 全部確認完成再來實作
 * 
 */

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