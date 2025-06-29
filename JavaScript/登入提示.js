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
// @grant        GM_notification
// @grant        GM_registerMenuCommand
// @grant        GM_unregisterMenuCommand

// @require      https://update.greasyfork.org/scripts/487608/1616382/SyntaxLite_min.js
// @require      https://cdnjs.cloudflare.com/ajax/libs/crypto-js/4.2.0/crypto-js.min.js
// @require      https://cdnjs.cloudflare.com/ajax/libs/lz-string/1.5.0/lz-string.min.js

// @run-at       document-end
// ==/UserScript==

/**
 * 保存輸入帳號, 密碼
 * 密碼進行加密, 密碼添加顯示眼睛
 *
 * 加密Key設置, 選擇是否加密
 * 調整選單設置, 背景色, 文字色, 透明度, 位置
 *
 * 範例明文: 12345678
 * 範例密碼: password
 */

(function () {
    class AutoLogin {
        constructor() {
            this.Url = Syn.$url.split("?")[0];
            this.LoginInfo = Syn.gV(Syn.$domain, {});

            // 保存資訊模板
            this.SaveTemplate = [
                "Account", // 帳號
                "Password", // 密碼
                "Autologin", // 填寫後是否自動登入
                "Encrypted", // 後續判斷是否為加密
                "Operate" // 其餘的操作
            ];

            // 這個監聽動態變化並不始終有效
            this.OBL = (element, value) => {
                Syn.Observer(element, () => {
                    element.value != value && (element.value = value);
                }, { subtree: false, childList: false }, () => {
                    element.value = value;
                })
            };

            // 加解密算法
            this.Algorithm = {
                UTF16LE: {
                    Parse: (str) => CryptoJS.enc.Utf16LE.parse(LZString.compress(str)),
                    Stringify: (str) => LZString.decompress(CryptoJS.enc.Utf16LE.stringify(str))
                },
                IV: (str) => CryptoJS.RIPEMD160(str).toString(),
                SHA3_KEY: (str) => CryptoJS.SHA3(str).toString(),
                SHA512_KEY: (str) => CryptoJS.SHA512(str).toString(),
                Encry: function (Content, Password) {
                    const Text = JSON.stringify(Content);

                    const IV = this.IV(Password);
                    const SHA3_Key = this.SHA3_KEY(Password);

                    // 第一次加密
                    const Encrypted_1 = CryptoJS.AES.encrypt(
                        this.UTF16LE.Parse(Text),
                        SHA3_Key,
                        {
                            iv: IV,
                            mode: CryptoJS.mode.CBC,
                            padding: CryptoJS.pad.Iso97971
                        }).toString();
                    // 第二次加密
                    const Encrypted_2 = CryptoJS.AES.encrypt(
                        this.UTF16LE.Parse(Encrypted_1),
                        this.SHA512_KEY(IV),
                        {
                            iv: this.IV(SHA3_Key),
                            mode: CryptoJS.mode.CBC,
                            padding: CryptoJS.pad.Iso97971
                        }).toString();

                    return Encrypted_2; // 傳回加密字串
                },
                Decrypt: function (Content, Password) {
                    const IV = this.IV(Password);
                    const SHA3_Key = this.SHA3_KEY(Password);

                    // 第一次解密
                    const Decrypted_1 = this.UTF16LE.Stringify(
                        CryptoJS.AES.decrypt(
                            Content,
                            this.SHA512_KEY(IV),
                            {
                                iv: this.IV(SHA3_Key),
                                mode: CryptoJS.mode.CBC,
                                padding: CryptoJS.pad.Iso97971
                            }
                        )
                    );
                    // 第二次解密
                    const Decrypted_2 = this.UTF16LE.Stringify(
                        CryptoJS.AES.decrypt(
                            Decrypted_1,
                            SHA3_Key,
                            {
                                iv: IV,
                                mode: CryptoJS.mode.CBC,
                                padding: CryptoJS.pad.Iso97971
                            }
                        )
                    );

                    return JSON.parse(Decrypted_2); // 傳回解密物件
                }
            };
        }

        async Save() {
            const save = prompt("輸入以下數據, 請確實按照順序輸入\n帳號, 密碼, 其餘操作");

            if (save && save != "") {
                const Data = save.split(/\s*[,|/]\s*/); // , | / 作為分割符號

                if (Data.length > 1) {
                    const SaveBox = {};

                    this.SaveTemplate.forEach((key, index) => {
                        let Info = Data[index] ?? "";

                        if (key === "Account" || key === "Password") { // 目前先用預設加密
                            Info = this.Algorithm.Encry(Info, `${Syn.$domain}@Default_${key}@`);
                        }

                        SaveBox[key] = Info;
                    });

                    SaveBox["Encrypted"] = true; // 如果有加密了話

                    setTimeout(() => {
                        Syn.sV(Syn.$domain, Object.assign({ Url: this.Url }, SaveBox));
                        GM_notification({
                            title: "保存成功",
                            text: "以存入登入資訊",
                            timeout: 1500
                        });
                    }, 1000);

                    this.Delete();
                } else {
                    alert("輸入錯誤");
                }
            }
        }

        async Delete() {
            const Menu = GM_registerMenuCommand("🚮 刪除登入資訊", () => {
                Syn.dV(Syn.$domain);
                GM_unregisterMenuCommand(Menu);
            })
        }

        async Main() {
            GM_registerMenuCommand("📝 添加登入資訊", () => this.Save());

            // 檢測登入資訊中, 是否含有當前網址
            const Info = this.LoginInfo;

            if (Info?.Url && this.Url.startsWith(Info.Url)) {
                this.Delete(); // 註冊刪除登入資訊的選單

                let Account = Info.Account;
                let Password = Info.Password;

                if (Info.Encrypted === true) {
                    Account = this.Algorithm.Decrypt(Account, `${Syn.$domain}@Default_Account@`);
                    Password = this.Algorithm.Decrypt(Password, `${Syn.$domain}@Default_Password@`);
                }

                Syn.WaitElem("input[type='password']", PasswordEnter => {
                    const click = new MouseEvent("click", { // 創建點擊事件, 避免有被阻止的情況
                        bubbles: true,
                        cancelable: true
                    });

                    const LoginRegex = /acc|login|log|user|name|email|mail|id|ident|oninput|auth/i;
                    const AccountEnter = [...document.querySelectorAll("input:not([type='password']):not([type='search'])")]
                        .filter(input => {
                            return [...input.attributes].some(attr => LoginRegex.test(attr.value));
                        });

                    Syn.Log("自動登入資訊", { // 除錯資訊
                        AccountObject: AccountEnter,
                        PasswordObject: PasswordEnter
                    });

                    // 當只有一個立即輸入
                    if (AccountEnter.length == 1) {
                        this.OBL(AccountEnter[0], Account);
                    } else { // 多個帳號輸入類型, 暴力解法 全部都輸入
                        AccountEnter.forEach(Enter => {
                            this.OBL(Enter, Account); // 動態輸入帳號
                        });
                    }
                    this.OBL(PasswordEnter, Password); // 動態輸入密碼

                    if (Info.Autologin == "true") { // 自動登入 (目前保存方式的 true, 會是一個字串)
                        setTimeout(() => {
                            const submit = Syn.$$("input[type='submit'], button[type='submit']", { all: true });
                            submit[0]?.dispatchEvent(click);
                        }, 500);
                    }

                }, { raf: true });
            };
        }
    }

    const Login = new AutoLogin();
    Login.Main();
})();