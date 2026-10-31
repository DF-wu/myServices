# LibreChat 與自架 Code Interpreter

LibreChat 已恢復在原本的 `ChatStack/docker-compose.yml`，由 **Portainer 的既有
`chatstack` Git stack** 部署。對外仍是 `192.168.10.13:43065`，配合現有
`https://chat.dfder.tw`。Code Interpreter 和資料庫不開 host port。

這次只修改 recipe 與說明，沒有建立、啟動、重啟或進入容器，也沒有改動生產
appdata／資料庫或操作 Portainer。下列初始化流程會在你讓 Portainer 部署時執行。

## 此主機的部署決策

2026-10-31 查核：axolotl 為 x86_64、Linux 6.18、Docker Compose 5.6.1；
`/dev/kvm` 不存在，CPU 沒有暴露 vmx/svm。`/mnt/appdata` 是 NFSv4，帳號映射成
`3000:3000`，不能依賴 Docker 在新目錄上 chown。

- **應用程式：** 使用 LibreChat `v0.8.8` 的固定 digest，與現有 `1.3.17` 設定
  schema 相符。保留 DF-Gateway、模型清單、加密金鑰、登入金鑰與公開網址。
- **舊資料：** MongoDB、Meilisearch、RAG uploads 明確引用既有 external volumes；
  找不到會拒絕部署，不會悄悄建立空白替代品。RAG 接回現有 PostgreSQL
  `librechat_rag` database / role；已以唯讀連線驗證舊密碼和 pgvector extension。
- **程式執行：** 官方 Code Interpreter `v1.10.13`，使用 HTTP backend 和 direct
  NsJail runner，不掛不存在的 KVM device。每次執行有獨立 namespace、工作目錄、
  UID mapping 與上游 seccomp；容器另限制 2 CPUs、6 GiB RAM、512 PIDs，最多
  2 個工作，單次執行上限 5 分鐘。這與有獨立 guest kernel 的 microVM 隔離不同。
- **語言套件：** 官方 direct image 沒有附 `/pkgs`。一次性的
  `librechat-code-packages` 會使用同版本官方 baked image，安裝 `e2fsprogs`，用
  `debugfs` 將映像內的 `/pkgs` 複製到本機 named volume。只讀取 ext4 檔案，
  不 mount／boot guest，不在主機安裝套件。包含 Python 3.14.4、Node.js 24.22.1、
  Bun 1.4.4（JS/TS）與 Bash 5.2.0，以及上游打包的離線分析套件。
- **檔案儲存：** 使用官方 RustFS `1.0.4` 的 S3 API。查核時上游 Compose 使用的
  MinIO public image 在 Docker Hub／Quay 都回 401，故不交付不可拉取的 image。
  Code Interpreter 的 MinIO SDK／`MINIO_*` 設定可指定 S3 endpoint，本 recipe
  指向內部 RustFS。檔案上傳／下載的完整相容性仍須部署後驗收。
- **新持久化資料：** 佇列、S3 物件、語言套件與新金鑰全部使用 Docker local
  named volumes，避開 NFS chown。只有 LibreChat 本體沿用既有 NFS 目錄，
  本體使用 `3000:3000`。MongoDB 和 Meilisearch 保留映像原本的執行使用者；
  RAG 保留官方 image 的預設使用者，以相容舊 uploads volume。
- **Portainer：** 只拉預建映像，沒有 `build:`、Compose profiles 或依賴相對路徑的
  repo bind mounts。所有啟動腳本已嵌入主 Compose，Portainer CE 不需要額外複製
  Git checkout 檔案到 Docker host。既有 host secrets 用唯讀 bind mount，沒有
  讓 Portainer 容器讀取它看不到的 host `env_file`。

## 接回的既有資料

本 recipe 預期以下資料已存在；這些路徑在本次調查中都已找到：

```text
/mnt/appdata/ChatStack/librechat/
  config/app.env          原 CREDS_KEY、CREDS_IV、JWT、DF_LLM_API_KEY、網址
  config/meili.env        原 MEILI_MASTER_KEY
  config/rag.env          原 RAG DB 密碼、JWT、embedding API key
  config/librechat.yaml   原 custom endpoints 與功能設定
  images/ uploads/ logs/ skill/ data/

chatstack_librechat_mongodb_data
chatstack_librechat_mongodb_config
chatstack_librechat_meili_data_v1_35_1
chatstack_librechat_rag_uploads
```

MongoDB volume 已確認存在，沒有啟動 MongoDB 去檢查歷史訊息內容；不要把
「volume 存在」當成完整的資料復原驗收。RAG 原帳密可以連線，兩張
`langchain_pg_*` 資料表存在，查核時 embedding 資料筆數為 0。RAG 使用
`qwen3-embedding-8b`，該 ID 已在舊 RAG API key 可取得的 gateway 模型清單確認，
沒有為此發送計費的 embedding 請求。

原本 `librechat.yaml` 以唯讀方式讀入，在 `/app/data/librechat.recipe.yaml` 產生
effective copy，增加 `execute_code`、`run_in_background`、`programmatic_tools`。
不覆寫原 YAML，也不把環境變數中的真實 API key 寫進這份 copy。缺少舊加密或
登入金鑰時會拒絕啟動，避免產生一套新金鑰而失去舊憑證。

## Portainer 部署

1. 確認這次 recipe 變更已推送到 Portainer 所追蹤的 Git ref。Portainer 只讀遠端
   repository，不讀本機 working tree。
2. 在原本 **chatstack** stack 更新 Git repository，Compose path 維持
   `ChatStack/docker-compose.yml`。不要另外建立同名 LibreChat，或建立空的
   MongoDB／Meilisearch volumes。
3. 本次新增服務**沒有需要手動填入的新 secret**。Portainer 部署時，
   `librechat-code-init` 用 Node crypto 產生獨立 Ed25519 金鑰與隨機服務密碼，
   寫入本機 named volumes；後續沿用同一組。既有 ChatStack Environment 保持原值。
4. 首次需下載約 1.3 GiB 的 baked runner（另有 app／direct runner 等映像），
   解壓離線套件，時間會比一般更新長；package initializer 需要連線 Fedora 套件站。
   先在 Portainer 看 `librechat-code-packages` 的 log。它和
   `librechat-code-init` 最終應為 **Exited (0)**，不需要保持 Running。
5. API 會等待 worker／檔案服務；worker 會等待 runner；runner 會等待語言套件、
   egress gateway 與金鑰。主應用程式最後才啟動。若初始化失敗，修正其原因後由
   Portainer 更新，不要刪除資料 volumes 來重試。

對外仍只新增 `43065`；可用 `LIBRECHAT_HOST_BIND`／`LIBRECHAT_HOST_PORT` 覆寫，
若改 port，NPM upstream 也要一致。現有 config 的 DOMAIN_CLIENT／DOMAIN_SERVER
仍是網址來源。沒有更動 NPM 設定，也沒有啟用公開註冊。

## 在 Agent 裡使用

部署完成後登入原帳號，在 **Agent Builder → Tools → Add → Run Code / Code
Interpreter** 加入工具並儲存；選擇 gateway 中支援 tool calling 的模型。
後端已設定每位使用者的 JWT 驗證，不必另外購買 hosted Code Interpreter API key。
上傳附件時選 **Upload to Code Environment**。

可以用以下任務驗收：

> 用 Python 計算 1 到 100 的平方和，寫出計算程式。接著建立一份含結果的 CSV
> 和一張圖，提供兩個檔案下載；再讀回 CSV 核對數值。

應看到程式實際執行的 stdout、正確數值 **338350**，以及可下載的輸出檔。再以
另一個帳號測試，確認無法讀取前一帳號的 sandbox 檔案。最後用原本的聊天紀錄、
登入、附件與 RAG 檢索確認復原內容。

本 recipe 已提供 **每次隔離執行的 Code Interpreter**，agent 可自行寫程式、看
結果、修改程式再執行，並可使用背景工具。一般程式沒有任意網路連線；若要在
程式裡編排 MCP，還要在 Agent 中加入對應 MCP 工具並標記 Programmatic。

這套 HTTP backend **不是實驗性的 Stateful Code Sessions backend**，所以不
顯示 stateful 開關，也不保證 Python 變數／臨時安裝套件跨次保留。檔案延續由
LibreChat 的對話檔案回復流程處理。官方 stateful profile 另需 AWS Lambda
MicroVM 或獨立 remote-bridge／worker；本次沒有將 axolotl 主機的 shell 或 Docker
socket 當作 agent 工具。若之後要求長駐 VM workspace，應獨立規劃那個後端。

## 維護、驗證與備份

維護來源在此目錄；改完後重新產生主 Compose 的 managed block：

```sh
rtk proxy python3 ChatStack/librechat/render.py
rtk proxy python3 ChatStack/librechat/render.py --check
rtk proxy docker compose -f ChatStack/docker-compose.yml config --quiet
rtk proxy python3 -m unittest discover -s ChatStack/librechat -p 'test_*.py' -v
```

上述命令都不啟動容器。完整的 config merge 測試需要 Node.js 和 `js-yaml`；若 host
沒有，可在暫存目錄安裝後以 NODE_PATH 執行（不改 repo dependencies）：

```sh
rtk proxy npm install --prefix /tmp/librechat-recipe-test-node --no-audit --no-fund js-yaml@4.1.1
rtk proxy env NODE_PATH=/tmp/librechat-recipe-test-node/node_modules python3 -m unittest discover -s ChatStack/librechat -p 'test_*.py' -v
```

測試涵蓋舊資料 volume 接回、機密隔離、金鑰重用與簽章驗證、損壞狀態拒絕重置、
原設定不被覆寫、Compose dollar escaping 與 shell 語法。這些是靜態及本機檔案測試，
不代表已完成容器內的端到端執行驗收。

備份除了原 MongoDB／PostgreSQL／附件與 host secrets，還要包含
`chatstack_librechat_code_keys`、`chatstack_librechat_code_storage_data` 與
`chatstack_librechat_code_redis_data`。各 `code_auth_*` volume 可由原 keys volume
重建，但 keys 本身不可遺失；不要把它的內容或完整 env dump 提交至 Git。
語言套件 volume `chatstack_librechat_code_packages_v1_10_13` 是可重建快取。

更新 Code Interpreter 時，要一起鎖定所有服務的同一個上游 revision、更新套件
initializer 的版本檢查與版本化 volume，並同步檢查 seccomp。不要單獨更新 API
或 runner。`images.lock.json` 內均為已核對 linux/amd64 的不可變 digest。

## 官方依據

- [LibreChat Code Interpreter：部署、JWT、背景與 stateful 的區別](https://www.librechat.ai/docs/features/code_interpreter)
- [LibreChat v0.8.8 發布說明](https://github.com/LibreChat-AI/LibreChat/releases/tag/v0.8.8)
- [Agents capabilities 與設定](https://www.librechat.ai/docs/configuration/librechat_yaml/object_structure/agents)
- [Code Interpreter v1.10.13 原始碼](https://github.com/LibreChat-AI/code-interpreter/tree/v1.10.13)
- [上游 direct NsJail Compose override](https://github.com/LibreChat-AI/code-interpreter/blob/v1.10.13/docker-compose.mac.yml)
- [上游 sandbox Dockerfile 與 package-builder](https://github.com/LibreChat-AI/code-interpreter/blob/v1.10.13/api/Dockerfile)
- [RustFS 官方容器部署](https://docs.rustfs.com/en/installation/container)
- [Portainer Git stack 與相對路徑限制](https://docs.portainer.io/user/docker/stacks/add)
- [Portainer Git image build 限制](https://docs.portainer.io/faqs/troubleshooting/stacks-deployments-and-updates/can-i-build-an-image-while-deploying-a-stack-application-from-git)

研究使用 `smart-search exa-search` 找官方來源，再以 `smart-search fetch` 讀取全文；
另外讀取上游固定版本原始碼並直接查核 registry manifests，沒有執行上游容器。
`nsjail.seccomp.json` 原封不動取自 Code Interpreter
`2fa9f0d43e8e38b7d6240bc76e2483c6a47c64c7`，原專案採 Apache-2.0；見其
[LICENSE](https://github.com/LibreChat-AI/code-interpreter/blob/v1.10.13/LICENSE)。
