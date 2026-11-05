# Open WebUI 公司 Logo

沿用 ChatStack 的官方 Open WebUI 映像，用單檔唯讀掛載替換 Logo。無需自訂映像、啟動腳本或安裝額外套件。

## 素材

`branding/` 使用 Ming-Chyuan-NC repo 的 MW 標誌，來源為 commit `21ca7040007addceec15efbc53affa11005ddbfc` 下的：

```text
archive/brand/2026-11-04-mw-vector-rebuild/delivery/03_Logo向量檔/SVG/MW_logo_彩色.svg
archive/brand/2026-11-04-mw-vector-rebuild/delivery/03_Logo向量檔/SVG/MW_logo_反白.svg
```

保留原始向量輪廓與品牌色（綠 `#2C7A46`、紅 `#DD373B`）。小圖示加白色圓底及留白，以適應側邊欄的圓形裁切；淺色載入畫面使用彩色版，深色使用反白版。SVG 以 `rsvg-convert` 輸出 PNG，ICO 以 ImageMagick 產生多尺寸版本。

| 檔案 | 用途／尺寸 |
| --- | --- |
| `favicon.png` | 登入頁、側邊欄及分頁備援，512 × 512 |
| `favicon.svg`、`favicon.ico` | 瀏覽器分頁；ICO 包含 16、32、48、64、128、256 px |
| `favicon-96x96.png` | 96 × 96 分頁圖示 |
| `apple-touch-icon.png` | 180 × 180 Apple 圖示 |
| `logo.png` | 500 × 500，Open WebUI 動態 PWA manifest 使用 |
| `web-app-manifest-192x192.png`、`web-app-manifest-512x512.png` | 192／512 px 靜態 manifest 圖示 |
| `splash.png`、`splash-dark.png` | 淺色／深色載入畫面，寬 1024 px |

僅替換圖片，應用程式名稱沿用 Open WebUI。使用前須符合 Open WebUI 的[品牌授權條件](https://docs.openwebui.com/license/)，包括小規模部署的適用門檻。

## 手動套用

以下步驟留待需要部署時自行執行；修改 recipe 本身不會更新正在執行的容器。

1. 在 Docker 主機的 `ChatStack/` 目錄下，先將素材複製到固定的主機目錄：

   ```sh
   mkdir -p /mnt/appdata/ChatStack/open-webui-branding
   cp ./open-webui/branding/* /mnt/appdata/ChatStack/open-webui-branding/
   ```

2. 再透過既有 Portainer stack 套用更新的 recipe，讓 `open-webui` 容器重新建立以載入掛載。需要其他素材目錄時，在 stack 環境變數設定 `OPENWEBUI_BRANDING_DIR` 為 Docker 主機上的絕對路徑。

務必先準備上述全部檔案；短格式 bind mount 在來源缺失時可能建立同名目錄。只重新啟動舊容器不會載入新增的掛載。

掛載目標是 `/app/build/static/` 的個別圖片。已核對 Open WebUI v0.13.0：後端啟動時會將這些來源圖片複製到對外提供的靜態目錄，因此重啟後仍會使用公司 Logo；其餘 JavaScript、CSS 與靜態資源繼續來自官方映像。

套用後檢查登入頁、側邊欄、深淺色載入畫面與分頁圖示。瀏覽器 favicon 或已安裝 PWA 可能需要清除快取或重新安裝才會更新。升級官方映像時，確認圖片路徑仍相容。
