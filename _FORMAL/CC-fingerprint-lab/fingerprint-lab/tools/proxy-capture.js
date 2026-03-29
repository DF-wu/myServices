#!/usr/bin/env node
/**
 * HTTP/HTTPS 代理抓包工具
 * 攔截 Claude Code 對 platform.claude.com 和 api.anthropic.com 的請求
 *
 * 用法:
 *   node proxy-capture.js                      # 啟動代理在 :18766
 *   HTTP_PROXY=http://localhost:18766 claude    # 讓 Claude Code 走代理
 *
 * 注意: HTTPS CONNECT 隧道中的內容無法解密，只能看到目標域名。
 * 若需要解密 HTTPS，請使用 mitmproxy:
 *   mitmproxy --listen-port 18766 --set stream_large_bodies=0
 *   HTTP_PROXY=http://localhost:18766 HTTPS_PROXY=http://localhost:18766 \
 *     NODE_TLS_REJECT_UNAUTHORIZED=0 claude
 */

const http = require('http');
const net = require('net');
const fs = require('fs');

const PORT = parseInt(process.env.CAPTURE_PORT || '18766');
const LOG_FILE = process.env.CAPTURE_LOG || '/tmp/fingerprint-lab/evidence/proxy-capture.jsonl';

function log(entry) {
    const line = JSON.stringify({ ...entry, timestamp: new Date().toISOString() });
    console.log(line);
    fs.appendFileSync(LOG_FILE, line + '\n');
}

const server = http.createServer((req, res) => {
    // Plain HTTP request (non-CONNECT)
    const entry = {
        type: 'http',
        method: req.method,
        url: req.url,
        headers: {},
        rawHeaders: []
    };

    for (let i = 0; i < req.rawHeaders.length; i += 2) {
        entry.rawHeaders.push({ name: req.rawHeaders[i], value: req.rawHeaders[i + 1] });
        entry.headers[req.rawHeaders[i].toLowerCase()] = req.rawHeaders[i + 1];
    }

    let body = '';
    req.on('data', c => body += c);
    req.on('end', () => {
        if (body) {
            try {
                const parsed = JSON.parse(body);
                // Redact tokens
                ['refresh_token', 'code', 'code_verifier', 'access_token'].forEach(k => {
                    if (parsed[k]) parsed[k] = `[REDACTED:${String(parsed[k]).substring(0, 10)}...]`;
                });
                entry.body = parsed;
            } catch (e) {
                entry.body_raw = body.substring(0, 1000);
            }
        }
        log(entry);
        res.writeHead(502, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'capture_mode' }));
    });
});

// HTTPS CONNECT tunnel — 記錄目標但正常轉發
server.on('connect', (req, clientSocket, head) => {
    const [host, port] = req.url.split(':');

    log({
        type: 'connect',
        target: req.url,
        host,
        port: parseInt(port) || 443,
        headers: req.headers
    });

    const serverSocket = net.connect(parseInt(port) || 443, host, () => {
        clientSocket.write('HTTP/1.1 200 Connection Established\r\n\r\n');
        serverSocket.write(head);
        serverSocket.pipe(clientSocket);
        clientSocket.pipe(serverSocket);
    });

    serverSocket.on('error', (e) => {
        log({ type: 'connect_error', target: req.url, error: e.message });
        clientSocket.end();
    });

    clientSocket.on('error', () => serverSocket.destroy());
});

server.listen(PORT, () => {
    console.error(`Proxy capture server running on :${PORT}`);
    console.error(`Log file: ${LOG_FILE}`);
    console.error('');
    console.error('Usage:');
    console.error(`  HTTP_PROXY=http://localhost:${PORT} HTTPS_PROXY=http://localhost:${PORT} claude`);
    console.error('');
    console.error('For HTTPS decryption, use mitmproxy instead:');
    console.error(`  mitmproxy --listen-port ${PORT}`);
    console.error(`  HTTP_PROXY=http://localhost:${PORT} HTTPS_PROXY=http://localhost:${PORT} NODE_TLS_REJECT_UNAUTHORIZED=0 claude`);
});
