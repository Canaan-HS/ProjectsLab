function NameSearchCore(original) {
    const searchDict = {};
    const originalTable = original;
    const Type = (object) => Object.prototype.toString.call(object).slice(8, -1);

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
        addData: (dataObj) => { // 創建實例後, 先將數據物件添加
            for (const [key, value] of Object.entries(dataObj)) {
                addEntry(searchDict, key, value);
            }
        },
        searchData: (str) => { // 輸入任意字串進行搜索
            if (typeof str === "string" && str.length > 0) {
                return searchRecursively(searchDict, capitalize(str), 0);
            }
            return false;
        }
    }
};