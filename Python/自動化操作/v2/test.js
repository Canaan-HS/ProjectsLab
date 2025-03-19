const { chromium } = require('playwright');

(async () => {
    // 啟動瀏覽器
    const browser = await chromium.launch({
        headless: false, // 顯示瀏覽器窗口
        args: [
            '--disable-blink-features=AutomationControlled', // 隱藏自動化標誌
            '--window-size=1920,1080',
            '--start-maximized',
            '--disable-notifications',
            '--no-first-run',
            '--no-default-browser-check',
            '--disable-infobars', // 禁用信息欄
            '--disable-automation', // 額外禁用自動化標誌
        ],
    });

    // 創建新上下文
    const context = await browser.newContext({
        userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36',
        viewport: { width: 1920, height: 1080 },
    });

    // 創建新頁面
    const page = await context.newPage();
    await page.goto('https://pass.levelinfinite.com/', { waitUntil: 'domcontentloaded' });

    setTimeout(()=> {
        browser.close();
    }, 1e4);
})();