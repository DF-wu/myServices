# Infinite Canvas Proxy

已加入 `ChatStack/docker-compose.yml`，使用公開的 `node:24-bookworm-slim` image，直接執行官方指令：

```sh
npx --yes @basketikun/canvas-proxy@latest --host 0.0.0.0
```

單一容器，使用官方預設 port `23210`，不發布主機 port。不需 build image、環境變數、設定檔或持久化掛載；啟動時需要連線 npm registry。

既有 Infinite Canvas 入口會將 `/canvas-proxy/` 轉送到此 proxy，沿用畫布的網址與 port；不需為 proxy 另建網域或調整外部反向代理。路由在容器啟動時加入映像內的 Nginx 設定，不掛載主機設定檔。

更新 ChatStack 的 `infinite-canvas` 與 `infinite-canvas-proxy` 後：

1. 在 Infinite Canvas「配置 → 本地代理」填入 **目前畫布網址的 Origin + `/canvas-proxy`**，例如 `https://canvas.example.com/canvas-proxy`，啟用開關並測試連線。不要填 Docker 服務名稱。
2. 在 WebDAV 設定填入原本的 WebDAV URL、帳號、密碼及同步目錄，再測試連線。這些資料只在瀏覽器填寫，不放進 Compose。
3. 連線成功後執行同步；官方同步包含畫布、我的資產與工作台媒體檔。

WebDAV 測試與同步都會透過此路由。瀏覽器只連畫布本身，跨站的 WebDAV 請求由官方 proxy 轉送，可避開 WebDAV 伺服器未允許 CORS 預檢的問題。

來源：[官方 zero-config proxy 文件](https://github.com/basketikun/infinite-canvas/blob/9cd3deacbcc598361807afc16c059a80dd18b6f9/canvas-proxy/README.md)。
