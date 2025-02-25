import path from 'path';
import { File } from './!File.mjs';
import { fileURLToPath } from 'url';
import { execSync } from 'child_process';

// 獲取物件類型
const Type = (object) => Object.prototype.toString.call(object).slice(8, -1);

// 獲取對象大小
function objectSize(object) {
    const calculateCollectionSize = (value, cache, iteratee) => {
        if (!value || cache.has(value)) return 0;
        cache.add(value);
        let bytes = 0;
        for (const item of iteratee(value)) {
            bytes += Calculate[Type(item[0])] ?. (item[0], cache) ?? 0;
            bytes += Calculate[Type(item[1])] ?. (item[1], cache) ?? 0;
        }
        return bytes;
    };
    const Calculate = {
        Boolean: ()=> 4,
        Date: ()=> 8,
        Number: ()=> 8,
        String: (value) => value.length * 2,
        RegExp: (value) => value.toString().length * 2,
        Symbol: (value) => (value.description || '').length * 2,
        DataView: (value) => value.byteLength,
        TypedArray: (value) => value.byteLength,
        ArrayBuffer: (value) => value.byteLength,
        Array: (value, cache) => calculateCollectionSize(value, cache, function* (arr) {
            for (const item of arr) {
                yield [item];
            }
        }),
        Set: (value, cache) => calculateCollectionSize(value, cache, function* (set) {
            for (const item of set) {
                yield [item];
            }
        }),
        Object: (value, cache) => calculateCollectionSize(value, cache, function* (obj) {
            for (const key in obj) {
                if (Object.prototype.hasOwnProperty.call(obj, key)) {
                    yield [key, obj[key]];
                }
            }
        }),
        Map: (value, cache) => calculateCollectionSize(value, cache, function* (map) {
            for (const [key, val] of map) {
                yield [key, val];
            }
        })
    };

    const bytes = Calculate[Type(object)]?.(object, new WeakSet()) ?? 0;
    return {
        Bytes: bytes,
        KB: (bytes / 1024).toFixed(2),
        MB: (bytes / 1024 / 1024).toFixed(2)
    };
};

// 這是用於名稱, 即時搜尋對象的算法 回傳 -> {Length: ?, Data_n: obj...}
function NameSearchCore(original) {
    const searchDict = {};
    const originalTable = original;

    const getSubstrings = (str) => {
        const substrings = [];
        for (let i = 0; i < str.length; i++) {
            for (let j = i + 1; j <= str.length; j++) {
                substrings.push(str.slice(i, j));
            }
        }
        return substrings;
    };
    // 添加數據處理
    const addEntry = (node, key, value) => {
        getSubstrings(key).forEach(substring => {
            let currentNode = node;
            for (const char of substring) {
                if (!currentNode[char]) currentNode[char] = {};
                currentNode = currentNode[char];
            }

            const type = Type(currentNode.data);
            if (!currentNode.data) {
                currentNode.data = value; // 如果 data 不存在，直接賦值為字符串
            } else if (type == "String") {
                // 如果 data 是字符串，轉換為數組並添加新的值
                if (currentNode.data !== value) {
                    currentNode.data = [currentNode.data, value];
                }
            } else if (type == "Array") {
                // 如果 data 已經是數組，添加新的值並 Set 去重
                currentNode.data = [...new Set([...currentNode.data, value])];
            }
        })
    };

    // 將最終數據解析為對應物件回傳
    const objectMerge = () => {
        const Merge = {Length: 0};
        const Records = new Set();
        let Count = 1;
        return {
            add: (data)=> {
                const URL = data.IMG_URL;
                if (URL && !Records.has(URL)) {
                    Merge[`Data_${Count++}`] = data;
                    Records.add(URL);
                }
            },
            result: ()=> {
                Merge.Length = Records.size; // 根據紀錄設置長度
                return Merge;
            }
        }
    };
    const finalObject = (results) => {
        let resultsLen = Object.keys(results).length;

        if (resultsLen == 0) return;

        const Merge = objectMerge(); // 創建合併對象
        const process = { // 創建處理物件
            String: (data)=> Merge.add(originalTable[data] ?? {}),
            Object: (data)=> Merge.add(data),
            Array: function(data) {
                for (const str of data) {this.String(str)}
            }
        };

        for (const data of results) { // 開始遍歷處理
            const type = Type(data);
            process[type](data) // 不處理例外
        }

        return Merge.result();
    };

    // 遞迴找到最終所有符合的 .data 數據
    const collectAllNames = (node) => {
        const results = [];
        if (node.data) results.push(node.data);

        for (const key in node) {
            const nodeKey = node[key];

            if (typeof nodeKey === "object") {
                results.push(...collectAllNames(nodeKey));
            }
        }

        return results;
    };
    // 遞歸搜尋
    const searchRecursively = (node, str, index) => {
        if (index >= str.length) return;

        const nextNode = node[str[index]];

        if (!nextNode) return;

        if (index === str.length - 1) {
            return finalObject(collectAllNames(nextNode));
        }

        return searchRecursively(nextNode, str, index + 1);
    };

    // 將輸入字串轉成首字母大寫
    const capitalize = (str) => str[0].toUpperCase() + str.slice(1).toLowerCase();

    return {
        showData: () => { // 展示添加結果
            console.log(JSON.stringify(searchDict, null, 4));
        },
        showSize: (Return=false) => { // 展示搜尋數據大小
            const Size = objectSize(searchDict);

            if (Return) return Size;
            console.log(`數據大小: ${Size.KB} KB`);
            console.log(`數據大小: ${Size.MB} MB`);
        },
        putData: function () { // 輸出轉換數據
            const Size = this.showSize(true);
            const Data = Object.assign({
                "Meta": {"KB": +Size.KB, "MB": +Size.MB}
            }, searchDict);
            File.Write("R:/SearchData.json", Data);
        },
        addData: (dataObj) => { // 創建實例後, 先將數據物件添加
            for (const [key, value] of Object.entries(dataObj)) {
                addEntry(searchDict, key, value);
            }
        },
        searchData: (str) => { // 輸入任意字串進行搜索
            if (typeof str === "string" && str.length > 0) {
                return searchRecursively(searchDict, capitalize(str), 0);
            }
            return;
        }
    };
};

// 用於清洗數據
function CleanCore() {
    const DefaultProcessing = [
        "攻擊屬性",
        "防禦裝甲",
        "角色武器",
        "戰略定位",
        "戰術類別",
        "戰鬥站位",
        "角色評級",
        "角色學園",
        "獲取管道",
        "角色稀有"
    ];

    const jsonFormat = (obj) => JSON.stringify(obj, null, 4);
    const AllowType = (obj) => {;

        if (Type(obj) != "Object") {
            console.error("傳入數據只能是物件");
            return false;
        } else if (Object.keys(obj).length == 0) {
            console.error("傳入物件不能為空");
            return false;
        }

        return true;
    };

    /* 回傳除重後乾淨對象 */
    const getCleanArray = (arr) =>[...new Set(arr)];
    const getCleanObject = (obj)=> {
        const merge = {}
        for (const [key, value] of Object.entries(obj)) {
            merge[key] = getCleanArray(value);
        }
        return merge;
    };

    /* 回傳重複對象 */
    const getArrayRepeat = (arr) => {
        const cache = new Set();
        const result = arr.filter(item => cache.has(item) ? item : !cache.add(item));
        return result.length > 0 ? result : false; // 沒有重複的回傳 false
    };
    const getObjectRepeat = (obj) => {
        const alone = {}; // 各自判斷
        let cache = []; // 緩存整體判斷所需數據

        for (const [key, value] of Object.entries(obj)) {
            const array = getArrayRepeat(value);
            if (array) alone[key] = array;
            cache = [...cache, ...value];
        }

        return {
            "整體重複": getArrayRepeat(cache), // 整體判斷
            "個別重複": Object.keys(alone).length > 0 ? alone : false
        }
    };

    return {
        getCleanArray,
        getCleanObject,
        getArrayRepeat,
        getObjectRepeat,
        getData: (DB, {Write=false, Type="Clean", Operate=DefaultProcessing}={})=> {
            /*
             * 取得數據
             * DB : 完整數據庫
             * {
             *      Write : 是否輸出文件 (預設 false, 直接打印)
             *      Type : 操作的類型 ("Clean", "Repeat") (預設 Clean)
             *      Operate : 要讀取的操作 key, 一個 array (預設 DefaultProcessing)
             * }
             */

            if (AllowType(DB)) {
                const display = {};
                for (const check of Operate) {
                    const process = DB[check];

                    if (!process) {
                        console.error("錯誤的檢查對象:", check);
                        continue;
                    }

                    const result = Type == "Clean"
                        ? getCleanObject(process)
                        : Type == "Repeat"
                        ? getObjectRepeat(process)
                        : getCleanObject(process); // 預設值為清潔

                    if (result) display[check] = result;
                }

                if (Write) {
                    File.Write("R:/ProcessedData.json", display);
                } else {
                    console.log(jsonFormat(display));
                }
            }
        },
        getInfo: (DB, Name)=> {
            /*
             * 取得角色資訊
             * DB : 完整數據庫
             * Name : 要搜尋的角色名稱         
            */

            if (AllowType(DB)) {

                if (Type(Name) != "String") {
                    console.error("Name 類型需要為 String");
                    return;
                };

                // 移除不需要數據
                ["角色別稱", "詳細資訊"].forEach(key => delete DB[key]);
                // 儲存結果
                const result = {};

                for (const category in DB) {
                    for (const subCategory in DB[category]) {
                        if (DB[category][subCategory].includes(Name)) {
                            result[category] = subCategory;
                        }
                    }
                }

                console.log({ [Name]: result });
            }
        }
    }
};

// 實驗區塊 ========================

// 取得當前文件的目錄
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
// 生成絕對路徑
const filePath = path.join(__dirname, "../DataBase/DB.json");

(async ()=> {
    const Clean = CleanCore();
    const DB = await File.Read(filePath);

    /* 獲取角色基本資訊 */
    Clean.getInfo(DB, "");

    /* 獲取清洗後的 Json */
    // console.log(
        // JSON.stringify(
            // Clean.getCleanArray(DB['攻擊屬性']['爆炸']),
        // null, 4)
    // );

    /* 確認物件重複狀態 */
    // Clean.getData(DB, {Type: "Repeat"});

    // const Details = DB['詳細資訊'];
    // const Search = Object.assign(DB['角色別稱'], Details);

    // 創建實例要先傳遞初始表 (未被轉換)
    // const SC = NameSearchCore(Details);

    // 添加需轉換的表
    // SC.addData(Search);
    // SC.showData();
    // SC.showSize();
    // SC.putData();

    // console.log(SC.searchData(""));

    //? 在 CMD 調式時用 (只適用 Windows)
    // execSync("pause", { stdio: "inherit" });
})();

// 實驗區塊 ========================