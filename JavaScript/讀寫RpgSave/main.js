#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const readline = require('readline');
const LZString = require('lz-string');

let lastSourceRpgsavePath = null;
let lastOutputJsonPath = null;

// node main.js

const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
    prompt: '請輸入檔案路徑 (.rpgsave / .json) 或輸入 -e 回寫存檔：\n> '
});

console.log('=== RPG Maker 存檔轉換工具 ===');
rl.prompt();

rl.on('line', (line) => {
    const input = line.trim().replace(/^["']|["']$/g, '');

    if (input.toLowerCase() === 'exit') {
        console.log('退出工具');
        rl.close();
        return;
    }

    if (input === '-e') {
        // 回寫模式
        if (!lastSourceRpgsavePath || !lastOutputJsonPath) {
            console.log("❌ 沒有可回寫的記錄，請先輸入 .rpgsave 進行解壓。");
            rl.prompt();
            return;
        }

        try {
            console.log("⏳ 正在將 JSON 回寫為 rpgsave...");
            const jsonStr = fs.readFileSync(lastOutputJsonPath, 'utf8');
            const jsonObj = JSON.parse(jsonStr);
            const compressed = LZString.compressToBase64(JSON.stringify(jsonObj));
            fs.writeFileSync(lastSourceRpgsavePath, compressed, 'utf8');
            console.log(`✅ 已覆蓋原始存檔：${lastSourceRpgsavePath}`);
        } catch (err) {
            console.log("❌ 回寫失敗：", err.message);
        }
        rl.prompt();
        return;
    }

    // 處理路徑輸入
    const filePath = input;
    const ext = path.extname(filePath).toLowerCase();

    if (ext !== '.rpgsave' && ext !== '.json') {
        console.log('❌ 檔案副檔名必須為 .rpgsave 或 .json');
        rl.prompt();
        return;
    }

    if (!fs.existsSync(filePath)) {
        console.log('❌ 找不到檔案');
        rl.prompt();
        return;
    }

    const baseName = path.basename(filePath, ext);
    const outputDir = process.cwd();

    try {
        if (ext === '.rpgsave') {
            // rpgsave → json
            console.log('⏳ 正在解壓縮存檔...');
            const compressedData = fs.readFileSync(filePath, 'utf8');
            const jsonStr = LZString.decompressFromBase64(compressedData);
            if (!jsonStr) throw new Error('解壓縮失敗，可能不是有效存檔');
            const jsonObj = JSON.parse(jsonStr);

            const outJson = path.join(outputDir, baseName + '.json');
            fs.writeFileSync(outJson, JSON.stringify(jsonObj, null, 4), 'utf8');

            console.log(`✅ 已輸出 JSON → ${outJson}`);

            // 記錄用於 -e 回寫
            lastSourceRpgsavePath = filePath;
            lastOutputJsonPath = outJson;
        } else {
            // json → rpgsave
            console.log('⏳ 正在壓縮 JSON...');
            const jsonStr = fs.readFileSync(filePath, 'utf8');
            const jsonObj = JSON.parse(jsonStr);
            const compressed = LZString.compressToBase64(JSON.stringify(jsonObj));
            const outRpg = path.join(outputDir, baseName + '.rpgsave');
            fs.writeFileSync(outRpg, compressed, 'utf8');
            console.log(`✅ 已輸出 RPG 存檔 → ${outRpg}`);
        }
    } catch (err) {
        console.log('❌ 發生錯誤：', err.message);
    }

    rl.prompt();
}).on('close', () => {
    console.log('工具已結束');
    process.exit(0);
});