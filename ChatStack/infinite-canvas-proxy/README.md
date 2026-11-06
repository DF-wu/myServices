# Infinite Canvas 與 WebDAV

Canvas 使用既有公開 image `ghcr.io/basketikun/infinite-canvas:latest`，保留映像原本的啟動指令。

## WebDAV 同步

在既有站點管理器替 Canvas 配置 HTTPS 入口，並將該站點的 `/webdav/` 固定轉送到指定 WebDAV 資料夾。這些站點與上游設定由管理器保存，不在公開 repo 寫入私人網域、位址或帳密。

在 Infinite Canvas 設定：

1. 關閉「本地代理」。
2. WebDAV URL 填入 Canvas 站點的 `/webdav/` 完整網址，例如 `https://canvas.example.com/webdav/`。
3. 填入原有 WebDAV 帳密，設定同步子目錄，再測試連線與同步。

同站點路徑可避免瀏覽器的跨站 CORS 問題。若要從原本的區網 Canvas 同步既有資產，站點的 WebDAV 路徑也須允許該區網 Origin 的預檢、Authorization 與 WebDAV 方法。換網站網址會使用另一份瀏覽器本地資料；先在舊網址同步原有資產，再到新站點同步。

## 可選官方代理

`infinite-canvas-proxy` 使用公開的 `node:24-bookworm-slim` image，直接執行 `npx --yes @basketikun/canvas-proxy@latest --host 0.0.0.0`。單一容器，官方預設 port `23210`，不發布主機 port；不需 build image、設定檔或持久化掛載。此服務不需要用於上述 WebDAV 同步方式。

來源：[官方 proxy 文件](https://github.com/basketikun/infinite-canvas/blob/9cd3deacbcc598361807afc16c059a80dd18b6f9/canvas-proxy/README.md)、[官方 WebDAV 同步程式](https://github.com/basketikun/infinite-canvas/blob/9cd3deacbcc598361807afc16c059a80dd18b6f9/web/src/services/webdav-sync.ts)。
