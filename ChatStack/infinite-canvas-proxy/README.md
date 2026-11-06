# Infinite Canvas Proxy

已加入 `ChatStack/docker-compose.yml`，使用公開的 `node:24-bookworm-slim` image，直接執行官方指令：

```sh
npx --yes @basketikun/canvas-proxy@latest --host 0.0.0.0
```

單一容器，使用官方預設 port `23210`，不發布主機 port。不需 build image、環境變數、設定檔或持久化掛載；啟動時需要連線 npm registry。

共用 Docker 網路的反向代理可連到 `http://infinite-canvas-proxy:23210`。在 Infinite Canvas「配置 → 本地代理」填入瀏覽器可連到的反向代理網址，並啟用開關。AI API Base URL 與 API Key 維持原設定。

來源：[官方 zero-config proxy 文件](https://github.com/basketikun/infinite-canvas/blob/9cd3deacbcc598361807afc16c059a80dd18b6f9/canvas-proxy/README.md)。
