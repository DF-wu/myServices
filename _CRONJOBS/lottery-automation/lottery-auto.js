const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const axios = require('axios');

// 配置
const LOTTERY_URL = process.env.LOTTERY_URL || 'https://qd.x666.me';
const COOKIES_JSON = process.env.LINUXDO_COOKIES;
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
    headless: true, // GitHub Actions 中使用 headless 模式
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });

  const context = await browser.newContext({
    userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    viewport: { width: 1920, height: 1080 },
    locale: 'zh-CN',
    timezoneId: 'Asia/Shanghai'
  });

  const page = await context.newPage();

  try {
    // Step 1: 解析并注入 Cookies
    console.log('Step 1: 注入 linux.do Cookies...');
    const cookies = await parseCookies(COOKIES_JSON);
    await context.addCookies(cookies);
    console.log(`✅ 已注入 ${cookies.length} 个 cookies`);

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
    await sleep(2000);

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
    const currentUrl = page.url();
    if (currentUrl.includes('connect.linux.do/oauth2/authorize')) {
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

    // 检查是否有 Cloudflare Turnstile 或停留在 approve 页面
    const hasTurnstile = await page.locator('iframe[src*="turnstile"]').count() > 0 ||
                         await page.locator('text=确认您是真人').count() > 0 ||
                         currentUrlAfterAuth.includes('challenges.cloudflare.com') ||
                         (currentUrlAfterAuth.includes('oauth2/approve') && !currentUrlAfterAuth.includes(LOTTERY_URL));

    if (hasTurnstile) {
      console.log('⚠️ 检测到 Cloudflare Turnstile 验证或 approve 页面');
      await takeScreenshot(page, '04-turnstile-before');

      // 使用 FlareSolverr 绕过验证
      // 如果在 approve 页面，就解决当前页面
      const targetUrl = currentUrlAfterAuth;

      console.log(`尝试解决的目标 URL: ${targetUrl}`);
      const solution = await solveTurnstile(targetUrl);

      if (solution && solution.cookies) {
        console.log('✅ 使用 FlareSolverr 获取的 cookies 注入到浏览器');

        // 将 FlareSolverr 返回的 cookies 注入到浏览器
        // 确保 cookies 设置到正确的域名
        const flareCookies = solution.cookies.map(cookie => {
          let domain = cookie.domain;

          // 如果 cookie 没有域名，使用当前 URL 的域名
          if (!domain) {
            const urlObj = new URL(targetUrl);
            domain = urlObj.hostname;
          }

          return {
            name: cookie.name,
            value: cookie.value,
            domain: domain,
            path: cookie.path || '/',
            expires: cookie.expires || -1,
            httpOnly: cookie.httpOnly || false,
            secure: cookie.secure || false,
            sameSite: cookie.sameSite || 'Lax'
          };
        });

        await context.addCookies(flareCookies);
        console.log(`✅ 已注入 ${flareCookies.length} 个 FlareSolverr cookies`);

        // 刷新当前页面以应用 cookies，等待自动跳转
        console.log('🔄 刷新页面以应用 cookies...');
        await page.reload({ waitUntil: 'networkidle' });

        await sleep(3000);
        await takeScreenshot(page, '04-turnstile-after');

        // 检查是否成功跳转
        const urlAfterReload = page.url();
        console.log(`刷新后 URL: ${urlAfterReload}`);

        if (urlAfterReload.includes(LOTTERY_URL)) {
          console.log('✅ Turnstile 验证已绕过，已跳转到抽奖页面！');
        } else {
          console.log('⚠️ 仍在等待跳转...');
        }
      } else {
        console.log('⚠️ FlareSolverr 未能解决，尝试手动等待...');

        // 回退到手动等待
        let verified = false;
        for (let i = 0; i < 24; i++) {
          await sleep(5000);
          const url = page.url();

          if (url.includes(LOTTERY_URL)) {
            verified = true;
            console.log('✅ Turnstile 验证通过！');
            break;
          }

          if ((i + 1) % 4 === 0) {
            console.log(`等待中... (已等待 ${(i + 1) * 5} 秒)`);
          }
        }

        if (!verified) {
          console.log('⚠️ Turnstile 验证超时，但继续尝试...');
        }
      }
    } else {
      console.log('✅ 无需 Turnstile 验证');
    }

    // Step 7: 等待回调并提取 token
    console.log('\nStep 7: 等待回调到抽奖页面...');
    await page.waitForURL(`${LOTTERY_URL}/**`, { timeout: 30000 });
    await sleep(2000);

    const callbackUrl = page.url();
    console.log(`回调 URL: ${callbackUrl}`);

    // 检查 URL 中的 token
    const tokenMatch = callbackUrl.match(/[?&]token=([^&]+)/);
    if (tokenMatch) {
      console.log(`✅ Token 已获取: ${tokenMatch[1].substring(0, 20)}...`);
    }

    await takeScreenshot(page, '05-after-callback');

    // Step 8: 等待转盘动画并获取结果
    console.log('\nStep 8: 等待抽奖结果...');

    // 等待结果弹窗出现
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
