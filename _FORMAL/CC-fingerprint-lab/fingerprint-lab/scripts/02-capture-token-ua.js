#!/usr/bin/env node
/**
 * 精確模擬 Claude Code 的 token exchange/refresh 行為並抓取實際 headers
 *
 * 用法:
 *   node 02-capture-token-ua.js                     # 使用系統 axios
 *   AXIOS_VERSION=1.8.4 node 02-capture-token-ua.js # 指定 axios 版本 (需先 npm install)
 *
 * 此腳本會：
 * 1. 啟動一個本地 HTTP server
 * 2. 精確複製 Claude Code 的 token exchange 呼叫方式 (只帶 Content-Type)
 * 3. 捕獲並顯示 axios 自動附加的所有 headers (包含 User-Agent)
 */

const http = require('http');

async function main() {
    let axios;
    try {
        axios = require('axios');
    } catch (e) {
        console.error('Error: axios not installed. Run: npm install axios');
        process.exit(1);
    }

    const results = [];

    const server = http.createServer((req, res) => {
        const capture = {
            method: req.method,
            url: req.url,
            headers_raw: [],
            headers: {}
        };

        // rawHeaders 保留原始大小寫和順序
        for (let i = 0; i < req.rawHeaders.length; i += 2) {
            capture.headers_raw.push({
                name: req.rawHeaders[i],
                value: req.rawHeaders[i + 1]
            });
            capture.headers[req.rawHeaders[i]] = req.rawHeaders[i + 1];
        }

        let body = '';
        req.on('data', c => body += c);
        req.on('end', () => {
            if (body) {
                try {
                    const parsed = JSON.parse(body);
                    // redact sensitive fields
                    ['refresh_token', 'code', 'code_verifier', 'access_token'].forEach(k => {
                        if (parsed[k]) parsed[k] = `[REDACTED:${String(parsed[k]).substring(0, 8)}...]`;
                    });
                    capture.body = parsed;
                } catch (e) {
                    capture.body_raw = body.substring(0, 500);
                }
            }
            results.push(capture);

            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({
                access_token: 'sk-ant-oat01-test',
                refresh_token: 'sk-ant-ort01-test',
                expires_in: 28800,
                scope: 'user:inference user:profile'
            }));
        });
    });

    await new Promise(resolve => server.listen(0, resolve));
    const port = server.address().port;
    const TOKEN_URL = `http://localhost:${port}/v1/oauth/token`;

    console.log('='.repeat(70));
    console.log('Claude Code OAuth Token UA Capture');
    console.log('='.repeat(70));
    console.log(`axios version: ${axios.VERSION}`);
    console.log(`Node.js version: ${process.version}`);
    console.log(`Capture server: ${TOKEN_URL}`);
    console.log('');

    // === Test 1: Token Exchange (模擬 Claude Code 的 ZjA 函數) ===
    console.log('--- Test 1: Token Exchange (模擬 ZjA 函數) ---');
    await axios.post(TOKEN_URL, {
        grant_type: "authorization_code",
        code: "test_auth_code_12345",
        redirect_uri: "http://localhost:12345/callback",
        client_id: "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
        code_verifier: "test_verifier_abcdef",
        state: "test_state_xyz"
    }, {
        // Claude Code 的 exact headers — 只有 Content-Type
        headers: { "Content-Type": "application/json" },
        timeout: 15000
    });

    // === Test 2: Token Refresh (模擬 Claude Code 的 $pH 函數) ===
    console.log('--- Test 2: Token Refresh (模擬 $pH 函數) ---');
    await axios.post(TOKEN_URL, {
        grant_type: "refresh_token",
        refresh_token: "sk-ant-ort01-test_refresh_token",
        client_id: "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
        scope: "user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload"
    }, {
        headers: { "Content-Type": "application/json" },
        timeout: 15000
    });

    // === Test 3: 帶 User-Agent 的請求 (模擬其他 API 調用) ===
    console.log('--- Test 3: API Request (模擬帶 UA 的請求) ---');
    await axios.post(TOKEN_URL, {
        test: true
    }, {
        headers: {
            "Content-Type": "application/json",
            "User-Agent": "claude-cli/2.1.81 (external, cli)"
        },
        timeout: 15000
    });

    server.close();

    // === 輸出結果 ===
    console.log('');
    console.log('='.repeat(70));
    console.log('CAPTURED RESULTS');
    console.log('='.repeat(70));

    const testNames = ['Token Exchange', 'Token Refresh', 'API Request (with explicit UA)'];
    results.forEach((r, i) => {
        console.log(`\n[${ testNames[i] }] ${r.method} ${r.url}`);
        console.log('Headers (wire order):');
        r.headers_raw.forEach(h => {
            const highlight = h.name.toLowerCase() === 'user-agent' ? ' ← KEY' : '';
            console.log(`  ${h.name}: ${h.value}${highlight}`);
        });
        if (r.body) {
            console.log('Body:', JSON.stringify(r.body, null, 2));
        }
    });

    // === Summary ===
    console.log('\n' + '='.repeat(70));
    console.log('SUMMARY');
    console.log('='.repeat(70));
    console.log(`axios version: ${axios.VERSION}`);
    console.log(`Token Exchange UA: ${results[0]?.headers['User-Agent'] || 'NOT SET'}`);
    console.log(`Token Refresh UA:  ${results[1]?.headers['User-Agent'] || 'NOT SET'}`);
    console.log(`API Request UA:    ${results[2]?.headers['User-Agent'] || 'NOT SET'}`);
    console.log(`Accept-Encoding:   ${results[0]?.headers['Accept-Encoding'] || 'NOT SET'}`);
}

main().catch(e => {
    console.error('Error:', e.message);
    process.exit(1);
});
