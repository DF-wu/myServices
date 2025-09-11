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
import sys
import json
from time import sleep
import requests
from datetime import datetime

RETRY_LIMIT = 1  # 最大重試次數

def log(message):
    """帶時間戳的日誌記錄器"""
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {message}")

def get_flaresolverr_session(base_url):
    """
    第一階段：透過 FlareSolverr 訪問網站首頁以解決 Cloudflare 挑戰。
    成功時返回 (cf_clearance_cookie, user_agent)，失敗時返回 (None, None)。
    """
    flaresolverr_url = os.environ.get("FLARESOLVERR_URL")
    if not flaresolverr_url:
        log("❌ 錯誤：未設定 FLARESOLVERR_URL 環境變數。")
        return None, None

    log(f"ℹ️  正在透過 FlareSolverr 為 {base_url} 獲取 Cloudflare cookies...")
    payload = {
        'cmd': 'request.get',
        'url': base_url,
        'maxTimeout': 60000
    }
    
    try:
        response = requests.post(f"{flaresolverr_url.rstrip('/')}/v1", json=payload, timeout=70)
        if response.status_code != 200:
            log(f"❌ 連接 FlareSolverr 失敗，狀態碼: {response.status_code}")
            log(f"   錯誤訊息: {response.text}")
            return None, None

        data = response.json()
        if data.get('status') == 'ok' and data.get('solution'):
            solution = data['solution']
            # 從 solution 中尋找 cf_clearance cookie
            cf_clearance_cookie = next((c['value'] for c in solution.get('cookies', []) if c['name'] == 'cf_clearance'), None)
            user_agent = solution.get('userAgent')
            
            if cf_clearance_cookie and user_agent:
                log("✅ 成功從 FlareSolverr 獲取 cf_clearance cookie 和 User-Agent。")
                return cf_clearance_cookie, user_agent
            else:
                log("❌ FlareSolverr 的回應中未找到 cf_clearance cookie 或 User-Agent。")
                return None, None
        else:
            log(f"❌ FlareSolverr 解決挑戰失敗: {data.get('message', '未知錯誤')}")
            return None, None

    except requests.exceptions.RequestException as e:
        log(f"❌ 訪問 FlareSolverr 時發生網路錯誤: {e}")
        return None, None
    except Exception as e:
        log(f"❌ 處理 FlareSolverr 回應時發生未知錯誤: {e}")
        return None, None

def send_checkin_request(checkin_url, headers, cookies):
    """
    第二階段：使用從 FlareSolverr 獲取的 session資訊，發送最終的簽到請求。
    """
    log("ℹ️  正在發送最終的簽到 API 請求...")
    try:
        response = requests.post(checkin_url, headers=headers, cookies=cookies, json={}, timeout=30)
        
        if response.status_code == 200:
            data = response.json()
            if data.get('success'):
                quota = data.get('data', {}).get('quota', 0)
                message = data.get('message', '簽到成功')
                log(f"✅ {message} - 獲得額度: {quota}")
                return True
            else:
                error_msg = data.get('message', '簽到失敗')
                if "已经签到" in error_msg or "checked in" in error_msg:
                    log(f"ℹ️  今天已經簽到過了: {error_msg}")
                    return True # 已經簽到過也算成功
                else:
                    log(f"❌ 簽到失敗: {error_msg}")
                    return False
        else:
            log(f"❌ 簽到 API 請求失敗，狀態碼: {response.status_code}")
            log(f"   錯誤訊息: {response.text}")
            return False
            
    except requests.exceptions.RequestException as e:
        log(f"❌ 簽到 API 請求時發生網路錯誤: {e}")
        return False
    except Exception as e:
        log(f"❌ 處理簽到 API 回應時發生未知錯誤: {e}")
        return False

def main():
    """主函數"""
    configs = load_configs()
    if not configs:
        sys.exit(1)

    any_task_failed = False
    print("-" * 50)

    for config in configs:
        base_url = config.get("base_url")
        user_id = config.get("user_id")
        access_token = config.get("access_token")

        if not all([base_url, user_id, access_token]):
            log(f"❌ 錯誤：設定資訊不完整，跳過此項。")
            any_task_failed = True
            continue

        log(f"🚀 開始為 User ID: {user_id} ({base_url}) 執行簽到任務...")
        
        success = False
        for attempt in range(RETRY_LIMIT + 1):
            # 第一階段: 獲取 session
            cf_cookie, user_agent = get_flaresolverr_session(base_url)
            
            if cf_cookie and user_agent:
                # 第二階段: 發送簽到請求
                checkin_url = f"{base_url}/api/user/check_in"
                headers = {
                    'Authorization': f'Bearer {access_token}',
                    'Veloera-User': str(user_id),
                    'User-Agent': user_agent,  # 使用從 FlareSolverr 獲取的 User-Agent
                    'Accept': 'application/json, text/plain, */*',
                    'Content-Type': 'application/json;charset=UTF-8',
                    'Origin': base_url,
                    'Referer': f'{base_url}/',
                }
                cookies = {
                    'cf_clearance': cf_cookie
                }
                
                success = send_checkin_request(checkin_url, headers, cookies)
                if success:
                    break # 成功，跳出重試迴圈
            
            if attempt < RETRY_LIMIT:
                log(f"🔄 任務失敗，將在 3 秒後重試... (第 {attempt + 1} 次)")
                sleep(3)
        
        if not success:
            log(f"❌ 為 User ID: {user_id} 的簽到任務在多次嘗試後最終失敗。")
            any_task_failed = True

        print("-" * 50)
        sleep(2)
        
    if any_task_failed:
        log("SUMMARY: 至少有一個簽到任務失敗，腳本以錯誤狀態退出。")
        sys.exit(1)
    else:
        log("SUMMARY: 所有簽到任務均已成功或已簽到。")


def load_configs():
    """
    從環境變數或本地 configs.json 檔案載入多個網站的設定。
    (此函數保持不變)
    """
    configs = []
    
    secrets_context_json = os.environ.get("SECRETS_CONTEXT")
    if secrets_context_json:
        log("資訊：偵測到 SECRETS_CONTEXT，將從中解析設定。")
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
                            log(f"警告：Secret {key} 中的 JSON 缺少必要欄位。")
                    except json.JSONDecodeError:
                        log(f"警告：無法解析 Secret {key} 的 JSON 內容。")
            
            if configs:
                log(f"資訊：從 SECRETS_CONTEXT 成功載入 {len(configs)} 個簽到設定。")
                return configs
        except json.JSONDecodeError:
            log("警告：無法解析 SECRETS_CONTEXT 的 JSON 內容，將嘗試讀取本地檔案。")

    log("資訊：未從環境變數載入設定，嘗試從本地 configs.json 檔案讀取。")
    try:
        script_dir = os.path.dirname(os.path.abspath(__file__))
        config_path = os.path.join(script_dir, "configs.json")
        with open(config_path, 'r', encoding='utf-8') as f:
            local_configs = json.load(f)
            if not isinstance(local_configs, list):
                log("錯誤：configs.json 的根元素必須是一個列表 (list)。")
                return []
            
            for i, config in enumerate(local_configs):
                if all(k in config for k in ["base_url", "user_id", "access_token"]):
                    config['base_url'] = config['base_url'].rstrip('/')
                    configs.append(config)
                else:
                    log(f"警告：configs.json 中的第 {i+1} 個設定缺少必要欄位。")
            
            log(f"資訊：從 configs.json 成功載入 {len(configs)} 個簽到設定。")
            return configs
            
    except FileNotFoundError:
        log("錯誤：在本地找不到 configs.json 檔案。")
        return []
    except json.JSONDecodeError:
        log("錯誤：configs.json 檔案格式不正確。")
        return []


if __name__ == "__main__":
    main()