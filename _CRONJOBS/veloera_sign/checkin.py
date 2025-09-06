
# Veloera 多站點自動簽到腳本
#
# --- 使用說明 ---
#
# 本腳本支援兩種執行方式：
#
# 1. GitHub Actions (自動化 CI/CD)
#    - 透過讀取 GitHub Secrets 中所有以 `VELOERA_AUTOSIGN_` 開頭的環境變數來執行。
#    - 每個 Secret 的值都必須是一個包含 `base_url`, `user_id`, `access_token` 的 JSON 字串。
#    - 範例 Secret:
#      - 名稱: VELOERA_AUTOSIGN_SITE_A
#      - 內容: {"base_url": "https://a.com", "user_id": 123, "access_token": "tokenA"}
#      - 名稱: VELOERA_AUTOSIGN_02
#      - 內容: {"base_url": "https://b.net", "user_id": 456, "access_token": "tokenB"}
#
# 2. 本地執行 (手動測試)
#    - 在腳本相同目錄下建立一個名為 `configs.json` (注意有 's') 的檔案。
#    - `configs.json` 的內容必須是一個 JSON 列表 (list)，其中包含多個簽到設定物件。
#    - 範例 `configs.json`:
#      [
#          {
#              "base_url": "https://zone.veloera.org",
#              "user_id": 2628,
#              "access_token": "some_token"
#          },
#          {
#              "base_url": "https://another.site.com",
#              "user_id": 5678,
#              "access_token": "another_token"
#          }
#      ]
#    - 接著直接執行 `python checkin.py` 即可。
#
# 腳本會優先讀取環境變數，如果找不到任何相關環境變數，才會
import os
import json
import requests
from datetime import datetime

def load_configs():
    """
    從環境變數或本地 configs.json 檔案載入多個網站的設定。
    """
    configs = []
    
    # 優先從環境變數讀取
    # 尋找所有以 VELOERA_AUTOSIGN_ 開頭的環境變數
    for key, value in os.environ.items():
        if key.startswith("VELOERA_AUTOSIGN_"):
            try:
                # 解析 JSON 字串
                config = json.loads(value)
                if all(k in config for k in ["base_url", "user_id", "access_token"]):
                    configs.append(config)
                else:
                    print(f"警告：環境變數 {key} 中的 JSON 缺少必要欄位。")
            except json.JSONDecodeError:
                print(f"警告：無法解析環境變數 {key} 的 JSON 內容。")
    
    if configs:
        print(f"資訊：從環境變數中成功載入 {len(configs)} 個簽到設定。")
        return configs

    # 若環境變數中沒有設定，則嘗試從本地 configs.json 讀取
    print("資訊：未從環境變數載入設定，嘗試從本地 configs.json 檔案讀取。")
    try:
        script_dir = os.path.dirname(os.path.abspath(__file__))
        config_path = os.path.join(script_dir, "configs.json")
        with open(config_path, 'r', encoding='utf-8') as f:
            local_configs = json.load(f)
            # 確保檔案內容是一個列表
            if not isinstance(local_configs, list):
                print("錯誤：configs.json 的根元素必須是一個列表 (list)。")
                return []
            
            # 驗證列表中的每個設定物件
            for i, config in enumerate(local_configs):
                if all(k in config for k in ["base_url", "user_id", "access_token"]):
                    configs.append(config)
                else:
                    print(f"警告：configs.json 中的第 {i+1} 個設定缺少必要欄位。")
            
            print(f"資訊：從 configs.json 成功載入 {len(configs)} 個簽到設定。")
            return configs
            
    except FileNotFoundError:
        print("錯誤：在本地找不到 configs.json 檔案。")
        return []
    except json.JSONDecodeError:
        print("錯誤：configs.json 檔案格式不正確。")
        return []

def check_in(config):
    """為單一設定執行簽到"""
    base_url = config.get("base_url")
    user_id = config.get("user_id")
    access_token = config.get("access_token")

    if not all([base_url, user_id, access_token]):
        print("錯誤：設定資訊不完整，跳過此項。")
        return

    checkin_url = f"{base_url}/api/user/check_in"
    
    headers = {
        'Authorization': f'Bearer {access_token}',
        'Veloera-User': str(user_id),
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        'Accept': 'application/json, text/plain, */*',
        'Content-Type': 'application/json;charset=UTF-8',
        'Origin': base_url,
        'Referer': f'{base_url}/',
    }

    print("-" * 50)
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] 🚀 正在為 User ID: {user_id} ({base_url}) 執行簽到...")

    try:
        response = requests.post(checkin_url, headers=headers, json={}, timeout=30)
        if response.status_code == 200:
            data = response.json()
            if data.get('success'):
                quota = data.get('data', {}).get('quota', 0)
                message = data.get('message', '簽到成功')
                print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] ✅ {message} - 獲得額度: {quota}")
            else:
                error_msg = data.get('message', '簽到失敗')
                if "已经签到" in error_msg or "checked in" in error_msg:
                    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] ℹ️  今天已經簽到過了: {error_msg}")
                else:
                    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] ❌ 簽到失敗: {error_msg}")
        else:
            print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] ❌ 請求失敗，狀態碼: {response.status_code}")
            print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] 錯誤訊息: {response.text}")

    except requests.exceptions.RequestException as e:
        print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] ❌ 網路錯誤: {e}")
    except Exception as e:
        print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] ❌ 發生未知錯誤: {e}")

if __name__ == "__main__":
    all_configs = load_configs()
    if all_configs:
        for config in all_configs:
            check_in(config)
    else:
        print("未找到任何有效的簽到設定，程式結束。")