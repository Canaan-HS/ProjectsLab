import open from "fs";

function Out(Path, Data) {
    open.writeFile(Path, Data, err => {
        err ? console.log(`輸出失敗: ${err}`) : console.log("輸出成功");
    });
}

function Read(Path) {
    return new Promise((resolve, reject) => {
        let Cache = "";
        open.readFile(Path, "utf-8", (err, data) => {
            if (err) return reject(err);

            for (const [key, value] of Object.entries(JSON.parse(data))) {

                if (key === "元數據") continue;
                
                for (const item of Object.values(value)) {
                    for (const link of Object.values(Object.assign({}, item["圖片連結"], item["影片連結"], item["下載連結"]))) {
                        Cache += `${link}\n`;
                    }
                }
            }

            if (Cache.endsWith('\n')) Cache = Cache.slice(0, -1); // 如果最後一行是 \n 就排除掉這行
            resolve(Cache);
        });
    });
};

Read("").then(read=> {
    Out("R:/DownloadList.txt", read);
})