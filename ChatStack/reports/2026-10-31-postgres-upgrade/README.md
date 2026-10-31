# ChatStack PostgreSQL／pgvector 升級研究

查核日期：2026-10-31。僅進行唯讀盤點與研究，未執行資料庫升級、重啟或設定變更。

[閱讀已發布的網頁報告](https://aionc.dfder.tw/raw/4TAB5KALCnDWqNn/index.html)

- [完整決策報告（Markdown）](report.md)
- [網頁報告原始檔](index.html)
- [官方來源台帳（HTML）](sources.html)
- [PostgreSQL 版本與替代引擎研究附件](engine-options.md)
- [各服務相依與固定 revision 查核附件](service-requirements.md)

建議保留 PostgreSQL＋pgvector；現場 PostgreSQL 17.11 已是本次查得的 17 最新 minor，先在副本確認逐庫 pgvector 0.8.7、備份還原、NFS 與連線池，再獨立演練 PostgreSQL 18.6。已確認三個直接客戶端；Infinite Canvas 目前是靜態前端，遺留 PG 設定不構成實際連線證據，歷史資料庫仍保留。

兩份研究附件各自記錄查核範圍與限制；最終部署結論以完整決策報告為準。附件提及的原始 fetch 證據、runtime metadata 與私有盤點沒有加入此公開 repository，也未上傳帳密、連線字串或用戶內容。

本地可直接開啟 index.html；報告無外部 JavaScript 或字型依賴，支援手機閱讀、服務篩選、Markdown 下載與列印。版本資訊需於真正執行前重新查核。
