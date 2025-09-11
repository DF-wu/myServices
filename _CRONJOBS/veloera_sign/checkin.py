# Veloera 多站點自動簽到腳本
#
# --- 使用說明 ---
#
# 本腳本支援兩種執行方式：
#
# 1. GitHub Actions (自動化 CI/CD)
#    - Workflow 會將所有 Secrets 打包成一個 JSON 字串，並存入名為 `SECRETS_CONTEXT` 的環境變數中。
#    - 本腳本會解析 `SECRETS_CONTEXT`，並找出所有以 `VELOERA_AUTOSIGN_` 開頭的密鑰來執行簽到。
#    - 您需要設定的 Secret 格式如下：
#      - 名稱: VELOERA_AUTOSIGN_SITE_A
#      - 內容: {"base_url": "https://a.com", "user_id": 123, "access_token": "tokenA"}
#    - 您需要在 GitHub Secrets 中設定 `FLARESOLVERR_URL`，指向您的 FlareSolverr 服務位址。
#
# 2. 本地執行 (手動測試)
#    - 在腳本相同目錄下建立一個名為 `configs.json` (注意有 's') 的檔案。
#    - `configs.json` 的內容必須是一個 JSON 列表 (list)，其中包含多個簽到設定物件。
#    - 您需要設定一個名為 `FLARESOLVERR_URL` 的環境變數。
#
# 腳本會優先讀取環境變數，如果找不到任何相關環境變數，才會
import os
import json
from time import sleep
import requests
from datetime import datetime

RETRY_LIMIT = 1  # 最大重試次數


def load_configs():
    """
    從環境變數或本地 configs.json 檔案載入多個網站的設定。
    """
    configs = []
    
    # 優先從環境變數 SECRETS_CONTEXT 讀取
    secrets_context_json = os.environ.get("SECRETS_CONTEXT")
    if secrets_context_json:
        print("資訊：偵測到 SECRETS_CONTEXT，將從中解析設定。")
        try:
            secrets_context = json.loads(secrets_context_json)
            for key, value in secrets_context.items():
                if key.startswith("VELOERA_AUTOSIGN_"):
                    try:
                        config = json.loads(value)
                        if all(k in config for k in ["base_url", "user_id", "access_token"]):
                            config['base_url'] = config['base_url'].rstrip('/')
                            configs.append(config)
                        else:
                            print(f"警告：Secret {key} 中的 JSON 缺少必要欄位。")
                    except json.JSONDecodeError:
                        print(f"警告：無法解析 Secret {key} 的 JSON 內容。")
            
            if configs:
                print(f"資訊：從 SECRETS_CONTEXT 成功載入 {len(configs)} 個簽到設定。")
                return configs
        except json.JSONDecodeError:
            print("警告：無法解析 SECRETS_CONTEXT 的 JSON 內容，將嘗試讀取本地檔案。")

    # 若環境變數中沒有設定，則嘗試從本地 configs.json 讀取
    print("資訊：未從環境變數載入設定，嘗試從本地 configs.json 檔案讀取。")
    try:
        script_dir = os.path.dirname(os.path.abspath(__file__))
        config_path = os.path.join(script_dir, "configs.json")
        with open(config_path, 'r', encoding='utf-8') as f:
            local_configs = json.load(f)
            if not isinstance(local_configs, list):
                print("錯誤：configs.json 的根元素必須是一個列表 (list)。")
                return []
            
            for i, config in enumerate(local_configs):
                if all(k in config for k in ["base_url", "user_id", "access_token"]):
                    config['base_url'] = config['base_url'].rstrip('/')
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

def get_clearance_cookie(base_url):
    """
    透過 FlareSolverr 獲取 cf_clearance cookie。
    """
    flaresolverr_url = os.environ.get("FLARESOLVERR_URL")
    if not flaresolverr_url:
        print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] ❌ 錯誤：未設定 FLARESOLVERR_URL 環境變數。")
        return None, None

    payload = {
        'cmd': 'request.get',
        'url': base_url,
        'maxTimeout': 60000
    }
    
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] ℹ️  正在透過 FlareSolverr 從 {base_url} 獲取 clearance cookie...")
    
    try:
        response = requests.post(f"{flaresolverr_url.rstrip('/')}/v1", json=payload, timeout=70)
        if response.status_code == 200:
            flaresolverr_data = response.json()
            if flaresolverr_data.get('status') == 'ok':
                solution = flaresolverr_data.get('solution', {})
                user_agent = solution.get('userAgent')
                cookies = solution.get('cookies')
                
                cf_cookie = next((c for c in cookies if c['name'] == 'cf_clearance'), None)
                
                if cf_cookie:
                    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] ✅ 成功獲取 clearance cookie。")
                    return {'cf_clearance': cf_cookie['value']}, user_agent
                else:
                    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] ❌ 未在 FlareSolverr 回應中找到 cf_clearance cookie。")
                    return None, None
            else:
                print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] ❌ FlareSolverr 錯誤: {flaresolverr_data.get('message')}")
                return None, None
        else:
            print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] ❌ 連接 FlareSolverr 失敗，狀態碼: {response.status_code}")
            return None, None
    except Exception as e:
        print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] ❌ 獲取 cookie 時發生錯誤: {e}")
        return None, None

def check_in(config):
    """為單一設定執行簽到"""
    base_url = config.get("base_url")
    user_id = config.get("user_id")
    access_token = config.get("access_token")

    if not all([base_url, user_id, access_token]):
        print("錯誤：設定資訊不完整，跳過此項。")
        return
        
    print("-" * 50)
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] 🚀 正在為 User ID: {user_id} ({base_url}) 執行簽到...")

    cookies, user_agent = get_clearance_cookie(base_url)
    
    if not (cookies and user_agent):
        print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] ❌ 無法繼續簽到，因為獲取 cookie 失敗。")
        return
        
    checkin_url = f"{base_url}/api/user/check_in"
    
    headers = {
        'Authorization': f'Bearer {access_token}',
        'Veloera-User': str(user_id),
        'User-Agent': user_agent, # 使用 FlareSolverr 提供的 User-Agent
        'Accept': 'application/json, text/plain, */*',
        'Content-Type': 'application/json;charset=UTF-8',
        'Origin': base_url,
        'Referer': f'{base_url}/',
    }

    # if first sign error, retry RETRY_LIMIT times
    if not send_signAction(checkin_url, headers, cookies):
        for attempt in range(RETRY_LIMIT):
            sleep(2)
            if send_signAction(checkin_url, headers, cookies):
                break
            else:
                print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] 🔄 重試中... (第 {attempt + 1} 次)")
       
def send_signAction(checkin_url, headers, cookies):
    """使用標準 requests 帶上 cookie 執行簽到"""
    try:
        response = requests.post(checkin_url, headers=headers, cookies=cookies, json={}, timeout=30)
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
                    return False
        else:
            print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] ❌ 請求失敗，狀態碼: {response.status_code}")
            print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] 錯誤訊息: {response.text}")
            return False

    except requests.exceptions.RequestException as e:
        print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] ❌ 網路錯誤: {e}")
        return False
    except Exception as e:
        print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] ❌ 發生未知錯誤: {e}")
        return False
    return True


if __name__ == "__main__":
    all_configs = load_configs()
    if all_configs:
        for config in all_configs:
            check_in(config)
    else:
        print("未找到任何有效的簽到設定，程式結束。")