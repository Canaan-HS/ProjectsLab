// 一個臨時寫的小工具, 目前只根據當前目錄下的文件來命名

const fs = require('fs');
const path = require('path');

const runPath = __dirname; // 取得當前文件所在目錄

/* 重命名文件 */
function renameFile(oldPath, newPath) {
    const oldName = path.basename(oldPath);
    const newName = path.basename(newPath);

    return new Promise((resolve, reject) => {
        fs.rename(oldPath, newPath, (err) => {
            if (err) {
                console.error(`命名失敗: ${oldName}`);
                resolve(err);
            } else {
                console.log(`命名成功: ${oldName} -> ${newName}`);
                resolve();
            }
        });
    });
};

async function readMeta(metaCallBack) {
    const meta = {};

    // 讀取當前目錄下的所有文件和文件夾
    fs.readdir(runPath, (err, files) => {
        if (err) {
            console.error('無法讀取目錄:', err);
            return;
        };

        const children = [];

        for (const file of files) {
            if (file.endsWith(".js")) continue; // 排除 Js 文件

            const fullPath = path.join(runPath, file);

            if (file === "!ReNameRecord.json") {
                meta["Record"] = fullPath;
            } else {
                children.push({
                    Dir: runPath,
                    Name: file,
                    Path: fullPath,
                });
            }
        };

        meta["Children"] = children;
        metaCallBack(meta);
    });
};

/**
 * @param {String|RegExp} clearStr - 清除的字串
 * @param {String|RegExp} replaceStr1 - 批配的字串
 * @param {String|RegExp} replaceStr2 - 替換的字串
 */
function rename(clearStr = "", replaceStr1 = "", replaceStr2 = "") {
    const standardize = (str) => str.replace(/[-\/\\^$*+?.()|[\]{}]/g, "\\$&").replace(/\s+/g, "\\s+");
    const regular = (str) => str ? new RegExp(standardize(str), "gi") : null;

    // 創建正則表達式
    const clearRegex = clearStr instanceof RegExp ? clearStr : regular(clearStr);
    const replaceRegex = replaceStr1 instanceof RegExp ? replaceStr1 : regular(replaceStr1);

    readMeta(meta => {
        for (let { Dir, Name, Path } of meta["Children"]) {

            let newName = Name;

            // 清除字串
            if (clearRegex) newName = Name.replace(clearRegex, "").trim();

            // 替換字串
            if (replaceRegex) newName = newName.replace(replaceRegex, replaceStr2);

            // 最終判斷名稱變更, 則進行重命名
            if (newName !== Name) renameFile(Path, path.join(Dir, newName));
        }
    })
};

/* 臨時的重命名 (可根據 Json 紀錄恢復) */
async function temporaryRename() {
    readMeta(async meta => {
        const [recordFile, childrenMeta] = [meta["Record"], meta["Children"]];

        if (recordFile) { // 有 Json 紀錄
            // 讀取紀錄文件
            fs.readFile(recordFile, "utf8", (err, data) => {
                if (err) {
                    console.error(`\n紀錄讀取失敗: ${err}`);
                    return;
                }

                const RecordData = JSON.parse(data); // 解析紀錄數據

                let renamePromises = childrenMeta.map(({ Dir, Name, Path }) => {
                    const originalName = RecordData[Name]; // 查找對應的原始路徑

                    if (originalName) {
                        return renameFile(Path, path.join(Dir, originalName)); // 如果找到了對應的原始路徑，執行重命名
                    } else {
                        return Promise.resolve(`無法找到對應的原始路徑: ${Path}`);
                    }
                });

                // 等待所有的重命名操作完成
                Promise.all(renamePromises)
                    .then(() => { // 刪除 recordFile 文件
                        fs.unlink(recordFile, (err) => {
                            if (err) {
                                console.error(`\n刪除紀錄文件失敗: ${err}`);
                            } else {
                                console.log('\n紀錄文件已成功刪除');
                            }
                        });
                    })
                    .catch((err) => {
                        console.error(err);
                    });
            });

        } else { // 沒有 Json 紀錄, 就是修改成 Temporary 文件名
            const renamedFiles = {};  // 用來儲存原始路徑和新路徑的對象
            const getFingerprint = (str) => {
                let h1 = 1779033703, h2 = 3024733165, h3 = 3362453630, h4 = 2197574221;
                for (let i = 0, k; i < str.length; i++) {
                    k = str.charCodeAt(i);
                    h1 = h2 ^ Math.imul(h1 ^ k, 597399067);
                    h2 = h3 ^ Math.imul(h2 ^ k, 2869860233);
                    h3 = h4 ^ Math.imul(h3 ^ k, 951274213);
                    h4 = h1 ^ Math.imul(h4 ^ k, 2716044179);
                }
                return [h1, h2, h3, h4].map(v =>
                    (((v ^ (v >>> 16)) * 2246822507) >>> 0).toString(16).padStart(8, '0')
                ).join('');
            };

            // 這裡使用 map() 來建立一個 Promise 陣列，然後用 Promise.all() 等待所有重命名操作完成
            const renamePromises = childrenMeta.map(({ Dir, Name, Path }) => {

                // 組成臨時路徑
                const temporaryName = `${getFingerprint(Name)}${path.extname(Name)}`;
                renamedFiles[temporaryName] = Name; // 添加紀錄

                // 返回重命名的 Promise
                return renameFile(Path, path.join(Dir, temporaryName));
            });

            try {
                // 等待所有重命名操作完成
                await Promise.all(renamePromises);

                // 所有檔案重命名完成後，再寫入 JSON 紀錄
                fs.writeFile(path.join(runPath, "!ReNameRecord.json"), JSON.stringify(renamedFiles, null, 2), (err) => {
                    if (err) {
                        console.error(`\n紀錄儲存失敗: ${err}`);
                    } else {
                        console.log('\n紀錄儲存成功');
                    }
                });
            } catch (err) {
                console.error(`\n重命名過程中出錯: ${err}`);
            }
        }
    });
};

/* ----- Main ----- */

rename("", "", "");