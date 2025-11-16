const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const axios = require('axios');

// 配置 - 動態組裝
const _p1 = 'x';
const _p2 = String.fromCharCode(54) + String.fromCharCode(54) + String.fromCharCode(54);
const _p3 = String.fromCharCode(46) + 'm' + String.fromCharCode(101);
const _sd = String.fromCharCode(113) + String.fromCharCode(100) + '.';
const _proto = ['h', 't', 't', 'p', 's', ':', '/', '/'].join('');
const LOTTERY_URL = process.env.LOTTERY_URL || (_proto + _sd + _p1 + _p2 + _p3);
const COOKIES_JSON = process.env.LINUXDO_COOKIES;
const CONNECT_COOKIES_JSON = process.env.CONNECT_COOKIES;
const FLARESOLVERR_URL = process.env.FLARESOLVERR_URL;

// 确保截图目录存在
const screenshotDir = path.join(__dirname, 'screenshots');
if (!fs.existsSync(screenshotDir)) {
  fs.mkdirSync(screenshotDir, { recursive: true });
}

async function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function solveTurnstile(url) {
  if (!FLARESOLVERR_URL) {
    console.log('⚠️ FLARESOLVERR_URL 未设置，跳过 FlareSolverr');
    return null;
  }

  console.log(`🔧 使用 FlareSolverr 解决 Cloudflare 验证: ${url}`);

  try {
    const response = await axios.post(FLARESOLVERR_URL, {
      cmd: 'request.get',
      url: url,
      maxTimeout: 60000
    }, {
      timeout: 70000
    });

    if (response.data && response.data.solution) {
      console.log('✅ FlareSolverr 解决成功');
      return {
        cookies: response.data.solution.cookies,
        userAgent: response.data.solution.userAgent,
        html: response.data.solution.response
      };
    } else {
      console.log('❌ FlareSolverr 解决失败');
      return null;
    }
  } catch (error) {
    console.error('❌ FlareSolverr 错误:', error.message);
    return null;
  }
}

async function parseCookies(cookiesJson) {
  try {
    const cookieArray = JSON.parse(cookiesJson);
    return cookieArray.map(cookie => {
      // 提取域名
      let domain = cookie['Host raw'];
      if (domain) {
        domain = domain.replace(/^https?:\/\//, '').replace(/\/$/, '');
        if (domain.startsWith('.')) {
          // 已经是通配域名
        } else {
          // 转换为准确域名格式
          domain = domain;
        }
      }

      return {
        name: cookie['Name raw'],
        value: cookie['Content raw'],
        domain: domain,
        path: cookie['Path raw'] || '/',
        expires: cookie['Expires raw'] !== '0' ? parseInt(cookie['Expires raw']) : -1,
        httpOnly: cookie['HTTP only raw'] === 'true',
        secure: cookie['Send for raw'] === 'true',
        sameSite: cookie['SameSite raw'] === 'lax' ? 'Lax' :
                  cookie['SameSite raw'] === 'strict' ? 'Strict' :
                  cookie['SameSite raw'] === 'none' ? 'None' : undefined
      };
    });
  } catch (error) {
    console.error('❌ Cookie 解析失败:', error.message);
    throw error;
  }
}

async function takeScreenshot(page, name) {
  const filename = path.join(screenshotDir, `${name}-${Date.now()}.png`);
  await page.screenshot({ path: filename, fullPage: true });
  console.log(`📸 截图已保存: ${filename}`);
}

async function main() {
  console.log('🎰 开始抽奖自动化流程...\n');

  if (!COOKIES_JSON) {
    console.error('❌ 错误: 未设置 LINUXDO_COOKIES 环境变量');
    process.exit(1);
  }

  const browser = await chromium.launch({
    headless: true,
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-blink-features=AutomationControlled',
      '--disable-dev-shm-usage',
      '--disable-web-security',
      '--disable-features=IsolateOrigins,site-per-process'
    ]
  });

  const context = await browser.newContext({
    userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    viewport: { width: 1920, height: 1080 },
    locale: 'zh-CN',
    timezoneId: 'Asia/Shanghai',
    // 添加額外的 headers 來模擬真實瀏覽器
    extraHTTPHeaders: {
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
      'Accept-Encoding': 'gzip, deflate, br',
      'Sec-Ch-Ua': '"Google Chrome";v="131", "Chromium";v="131", "Not_A Brand";v="24"',
      'Sec-Ch-Ua-Mobile': '?0',
      'Sec-Ch-Ua-Platform': '"Windows"',
      'Sec-Fetch-Dest': 'document',
      'Sec-Fetch-Mode': 'navigate',
      'Sec-Fetch-Site': 'none',
      'Upgrade-Insecure-Requests': '1'
    }
  });

  // 隱藏 webdriver 特徵
  await context.addInitScript(() => {
    Object.defineProperty(navigator, 'webdriver', {
      get: () => undefined
    });

    // 模擬 Chrome 對象
    window.chrome = {
      runtime: {}
    };

    // 模擬權限
    const originalQuery = window.navigator.permissions.query;
    window.navigator.permissions.query = (parameters) => (
      parameters.name === 'notifications' ?
        Promise.resolve({ state: Notification.permission }) :
        originalQuery(parameters)
    );
  });

  const page = await context.newPage();

  try {
    // Step 1: 解析并注入 Cookies
    console.log('Step 1: 注入 linux.do Cookies...');
    const cookies = await parseCookies(COOKIES_JSON);
    await context.addCookies(cookies);
    console.log(`✅ 已注入 ${cookies.length} 个 linux.do cookies`);

    // Step 1.5: 注入 OAuth 服務的 cookies
    if (CONNECT_COOKIES_JSON) {
      console.log('Step 1.5: 注入 OAuth 服務 Cookies...');
      const connectCookies = await parseCookies(CONNECT_COOKIES_JSON);
      await context.addCookies(connectCookies);
      console.log(`✅ 已注入 ${connectCookies.length} 个 OAuth 服務 cookies`);
    } else {
      console.log('⚠️ 未設置 OAuth 服務 cookies，可能會遇到驗證問題');
    }

    // Step 2: 访问抽奖页面
    console.log('\nStep 2: 访问抽奖页面...');
    await page.goto(LOTTERY_URL, { waitUntil: 'networkidle' });
    await sleep(2000);
    await takeScreenshot(page, '01-lottery-page');
    console.log('✅ 页面加载完成');

    // Step 3: 点击"开始转动"按钮
    console.log('\nStep 3: 点击开始转动按钮...');
    const spinButton = await page.locator('#spinButton, .spin-button');

    // 检查按钮状态
    const buttonText = await spinButton.textContent();
    console.log(`按钮文字: ${buttonText}`);

    if (buttonText.includes('已抽奖') || buttonText.includes('已签到')) {
      console.log('ℹ️ 今天已经抽过奖了');
      await takeScreenshot(page, '02-already-done');
      await browser.close();
      return;
    }

    await spinButton.click();
    console.log('✅ 已点击按钮');
    await sleep(3000);

    // 檢查是否跳轉到登入頁面（表示 cookies 過期）
    const currentUrl = page.url();
    console.log(`點擊後的 URL: ${currentUrl}`);

    if (currentUrl.includes('/login')) {
      console.error('❌ 跳轉到登入頁面，表示 linux.do cookies 已過期！');
      console.error('請重新導出 linux.do cookies 並更新 GitHub Secret: LINUXDO_COOKIES');
      await takeScreenshot(page, '03-login-page');
      throw new Error('Cookies 已過期，請更新 LINUXDO_COOKIES');
    }

    // Step 4: 等待跳转到 OAuth 授权页面
    console.log('\nStep 4: 等待跳转到 OAuth 授权页面...');
    try {
      await page.waitForURL('**/connect.linux.do/oauth2/authorize**', { timeout: 10000 });
      console.log('✅ 已跳转到授权页面');
      await sleep(1000);
      await takeScreenshot(page, '03-oauth-page');
    } catch (error) {
      console.log('⚠️ 未跳转到授权页面，可能已经授权过了');
      await takeScreenshot(page, '03-no-redirect');
    }

    // Step 5: 点击授权按钮
    const currentUrlBeforeAuth = page.url();
    if (currentUrlBeforeAuth.includes('connect.linux.do/oauth2/authorize')) {
      console.log('\nStep 5: 点击授权按钮 (.bg-red-500)...');

      // 等待授权按钮出现
      await page.waitForSelector('.bg-red-500', { timeout: 5000 });
      const authButton = await page.locator('.bg-red-500');
      const authButtonText = await authButton.textContent();
      console.log(`授权按钮文字: ${authButtonText}`);

      await authButton.click();
      console.log('✅ 已点击授权按钮');
      await sleep(3000); // 等待页面开始跳转
    } else {
      console.log('\nStep 5: 跳过授权（可能已授权）');
    }

    // Step 6: 处理 Cloudflare Turnstile 验证（如果有）
    console.log('\nStep 6: 检查并处理 Cloudflare 验证...');

    // 等待页面稳定或跳转
    await sleep(5000);

    const currentUrlAfterAuth = page.url();
    console.log(`当前 URL: ${currentUrlAfterAuth}`);

    const pageTitle = await page.title();
    console.log(`当前页面标题: ${pageTitle}`);

    // 检查是否在 approve 页面
    if (currentUrlAfterAuth.includes('oauth2/approve')) {
      console.log('📋 當前在 OAuth approve 頁面，等待 Cloudflare 自動驗證並跳轉...');
      await takeScreenshot(page, '04-approve-page');

      // 直接等待跳轉（最多 60 秒）
      let approvePageResolved = false;

      for (let i = 0; i < 30; i++) {
        await sleep(2000);
        const currentUrl = page.url();

        // 檢查是否跳轉到抽獎頁面
        if (currentUrl.includes(LOTTERY_URL)) {
          approvePageResolved = true;
          console.log('✅ approve 頁面已自動跳轉到抽獎頁面！');
          break;
        }

        // 檢查是否還在 approve 頁面
        if (!currentUrl.includes('oauth2/approve')) {
          console.log('⚠️ 頁面已跳轉但不是抽獎頁面:', currentUrl);
        }

        if ((i + 1) % 5 === 0) {
          console.log(`等待驗證中... (${(i + 1) * 2}秒)`);
          // 檢查頁面文本
          const bodyText = await page.locator('body').textContent();
          console.log('頁面文本片段:', bodyText.substring(0, 300));

          if (bodyText.includes('Enable JavaScript')) {
            console.log('⚠️ 仍在 Cloudflare 驗證頁面');
          }
        }
      }

      if (!approvePageResolved) {
        await takeScreenshot(page, '04-approve-timeout');
        throw new Error('approve 頁面未自動跳轉 - Cloudflare 驗證可能失敗');
      }
    } else {
      console.log('✅ 未檢測到 approve 頁面，繼續流程');
    }

    // Step 7: 等待回调并提取 token
    console.log('\nStep 7: 等待回调到抽奖页面...');
    await page.waitForURL(`${LOTTERY_URL}/**`, { timeout: 30000 });
    await sleep(3000);

    const callbackUrl = page.url();
    console.log(`回调 URL: ${callbackUrl}`);

    // 检查 URL 中的 token
    const tokenMatch = callbackUrl.match(/[?&]token=([^&]+)/);
    if (tokenMatch) {
      console.log(`✅ Token 已获取: ${tokenMatch[1].substring(0, 20)}...`);
    } else {
      console.log(`⚠️ URL 中未找到 token 參數`);
    }

    await takeScreenshot(page, '05-after-callback');

    // 檢查是否在根路徑且需要重新觸發抽獎
    if (callbackUrl === LOTTERY_URL || callbackUrl === `${LOTTERY_URL}/`) {
      console.log('⚠️ 當前在根路徑，檢查是否需要重新點擊抽獎按鈕...');

      const spinBtn = await page.locator('#spinButton');
      const spinBtnCount = await spinBtn.count();

      if (spinBtnCount > 0) {
        const btnText = await spinBtn.textContent();
        console.log(`轉盤按鈕文字: ${btnText}`);

        // 檢查是否已經抽過獎
        if (btnText.includes('已抽奖') || btnText.includes('已签到')) {
          console.log('✅ 按鈕顯示已抽獎，OAuth 流程完成');
          console.log('\n🎉 今天已經抽過獎了！');

          // 輸出到 GitHub Actions summary
          if (process.env.GITHUB_STEP_SUMMARY) {
            const summary = `
# 🎰 抽獎結果

**時間**: ${new Date().toLocaleString('zh-CN', { timeZone: 'Asia/Shanghai' })}

## 狀態
✅ 今天已經抽過獎了

---
*自動化運行成功* ✅
`;
            fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, summary);
          }

          await browser.close();
          return; // 直接退出，不進入 Step 8
        } else {
          console.log('⚠️ 檢測到按鈕未顯示已抽獎，可能 OAuth 流程有問題');
          console.log('嘗試檢查登入狀態...');

          // 檢查頁面上是否有登入信息
          const bodyText = await page.locator('body').textContent();
          console.log('頁面文本片段:', bodyText.substring(0, 500));
        }
      }
    }

    // Step 8: 等待转盘动画并获取结果
    console.log('\nStep 8: 等待抽奖结果...');

    // 先檢查頁面狀態
    const pageContent = await page.content();
    console.log('\n=== 當前頁面 HTML 片段 ===');
    console.log(pageContent.substring(0, 1000));
    console.log('... (總長度:', pageContent.length, '字符)\n');

    // 檢查關鍵元素
    const spinButtonExists = await page.locator('#spinButton').count();
    const resultModalExists = await page.locator('#resultModal').count();
    const resultInfoExists = await page.locator('#resultInfo').count();

    console.log('DOM 元素檢查:');
    console.log('- #spinButton 數量:', spinButtonExists);
    console.log('- #resultModal 數量:', resultModalExists);
    console.log('- #resultInfo 數量:', resultInfoExists);

    // 檢查轉盤按鈕狀態
    if (spinButtonExists > 0) {
      const buttonText = await page.locator('#spinButton').textContent();
      const buttonDisabled = await page.locator('#spinButton').getAttribute('disabled');
      console.log('- 轉盤按鈕文字:', buttonText);
      console.log('- 按鈕是否禁用:', buttonDisabled);
    }

    // 等待结果弹窗出现
    console.log('\n等待結果彈窗出現...');
    await page.waitForSelector('#resultModal[style*="flex"]', { timeout: 20000 });
    console.log('✅ 结果弹窗已出现');
    await sleep(1000);

    // 提取结果
    const resultInfo = await page.locator('#resultInfo').textContent();
    const resultCdk = await page.locator('#resultCdk').textContent();

    await takeScreenshot(page, '06-result');

    console.log('\n🎉 ========== 抽奖成功 ==========');
    console.log(`奖品: ${resultInfo.trim()}`);
    console.log(`兑换码: ${resultCdk.trim()}`);
    console.log('================================\n');

    // 输出到 GitHub Actions 的 summary
    if (process.env.GITHUB_STEP_SUMMARY) {
      const summary = `
# 🎰 抽奖结果

**时间**: ${new Date().toLocaleString('zh-CN', { timeZone: 'Asia/Shanghai' })}

## 获得奖品
${resultInfo.trim()}

## 兑换码
\`\`\`
${resultCdk.trim()}
\`\`\`

---
*自动化运行成功* ✅
`;
      fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, summary);
    }

  } catch (error) {
    console.error('\n❌ ========== 错误详情 ==========');
    console.error('错误类型:', error.name);
    console.error('错误消息:', error.message);
    console.error('错误堆栈:', error.stack);
    console.error('================================\n');

    try {
      await takeScreenshot(page, 'error');
    } catch (screenshotError) {
      console.error('⚠️ 截图失败:', screenshotError.message);
    }

    try {
      const currentUrl = page.url();
      console.error('当前页面 URL:', currentUrl);
      const title = await page.title().catch(() => 'N/A');
      console.error('当前页面标题:', title);
    } catch (stateError) {
      console.error('⚠️ 无法获取页面状态:', stateError.message);
    }

    throw error;
  } finally {
    await browser.close();
  }
}

// 运行主函数
main().catch(error => {
  console.error('Fatal error:', error);
  process.exit(1);
});
