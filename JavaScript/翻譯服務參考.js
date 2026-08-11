// 來源: https://github.com/Vendicated/Vencord/blob/main/src/plugins/translate/utils.ts
// 語言支援: https://docs.cloud.google.com/translate/docs/languages

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