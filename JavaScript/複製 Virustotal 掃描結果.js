// ==UserScript==
// @name         複製 Virustotal 掃描結果
// @version      0.0.1
// @author       Canaan HS
// @description  複製 Virustotal 掃描結果

// @noframes
// @match        *://*/*
// @icon         https://www.virustotal.com/gui/images/manifest/icon-192x192.png

// @license      MPL-2.0
// @grant        GM_setClipboard
// @grant        GM_registerMenuCommand

// @run-at       document-end
// ==/UserScript==

(() => {
    function depthSelector(select, root = document.body) {
        const result = root.querySelector(select);
        if (result) return result;

        const tree = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT, null);

        while (tree.nextNode()) {
            const node = tree.currentNode;
            if (!node.shadowRoot) continue;
            const result = depthSelector(select, node.shadowRoot);
            if (result) return result;
        }

        return null;
    };

    GM_registerMenuCommand("複製結果", () => {
        const detect = depthSelector("#detections");
        if (detect) {
            const resultText = [...detect.querySelectorAll(".detection")].map(detection => {
                const name = detection.querySelector(".engine-name")?.textContent;
                const result = detection.querySelector(".individual-detection")?.textContent;
                if (name && result && result !== "Undetected") {
                    return name + ": " + result;
                }
            }).filter(Boolean).join("\n");

            if (resultText) {
                GM_setClipboard(resultText);
                alert("已複製到剪貼簿");
            } else alert("獲取文本失敗");
        } else alert("未找到掃描結果");
    })
})();