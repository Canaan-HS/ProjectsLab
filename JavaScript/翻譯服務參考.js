// 來源: https://github.com/Vendicated/Vencord/blob/main/src/plugins/translate/utils.ts
// 語言支援: https://docs.cloud.google.com/translate/docs/languages

// 無論是短句還是長句, 翻譯效果都不錯


const googleKey = (() => {
    // 假設有多個 API Key
    const keyList = [];

    function* indexGenerator(length) {
        let index = 0;
        while (true) {
            yield index;
            index = (index + 1) % length;
        }
    }

    const keyIterator = indexGenerator(keyList.length);

    return {
        generator: () => keyList[keyIterator.next().value]
    }
})();

function googleTranslate(text, sourceLang = "auto", targetLang = "zh-TW") {
    const url = "https://translate-pa.googleapis.com/v1/translate?" + new URLSearchParams({
        "params.client": "gtx",
        "dataTypes": "TRANSLATION",
        "key": "AIzaSyDLEeFI5OtFBwYBIoK_jj5m32rZK5CkCXA",
        "query.sourceLanguage": sourceLang,
        "query.targetLanguage": targetLang,
        "query.text": text,
    });

    return new Promise((resolve, reject) => {
        fetch(url)
            .then(res => res.json())
            .then(raw => {
                try {
                    resolve(raw.translation);
                } catch (error) {
                    reject(error);
                }
            })
            .catch(err => {
                reject(err);
            });
    });
}

googleTranslate("Hello world").then(console.log);


// 整頁翻譯的 API, 適合翻譯大量短語句內容, 長篇效果不佳
function googleTranslateList(textList, sourceLang = "auto", targetLang = "zh-TW") {
    const url = "https://translate-pa.googleapis.com/v1/translateHtml?" + new URLSearchParams({
        "key": "AIzaSyATBXajvzQLTDHEQbcpq0Ihe0vWDHmO520",
    });

    return new Promise((resolve, reject) => {
        fetch(url, {
            method: "POST",
            headers: {
                "Content-Type": "application/json+protobuf",
            },
            body: JSON.stringify([[textList, sourceLang, targetLang], "t"]),
        })
            .then(res => res.json())
            .then(raw => {
                try {
                    resolve(raw[0]);
                } catch (error) {
                    reject(error);
                }
            })
            .catch(err => {
                reject(err);
            });
    });
}

googleTranslateList([
    "apple",
    "banana",
    "elephant",
    "microscope",
    "universe",
    "algorithm",
    "horizon",
    "velocity",
    "symphony",
    "catalyst"
]).then(console.log);