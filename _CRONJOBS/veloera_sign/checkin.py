import os
import json
import requests
from datetime import datetime

def load_config():
    """
    優先從環境變數載入設定，若無則從 config.json 檔案載入。
    """
    # 嘗試從環境變數讀取
    base_url = os.environ.get("BASE_URL")
    user_id = os.environ.get("USER_ID")
    access_token = os.environ.get("ACCESS_TOKEN")

    if all([base_url, user_id, access_token]):
        print("資訊：偵測到環境變數，將使用環境變數進行設定。")
        return {
            "base_url": base_url,
            "user_id": user_id,
            "access_token": access_token
        }

    # 若環境變數不完整，則嘗試從 config.json 讀取
    print("資訊：未偵測到完整的環境變數，嘗試從 config.json 讀取設定。")
    try:
        # 取得目前 .py 檔案所在的目錄
        script_dir = os.path.dirname(os.path.abspath(__file__))
        config_path = os.path.join(script_dir, "config.json")
        with open(config_path, 'r', encoding='utf-8') as f:
            config = json.load(f)
            if not all(k in config for k in ["base_url", "user_id", "access_token"]):
                print("錯誤：config.json 檔案缺少必要的欄位 (base_url, user_id, access_token)。")
                return None
            return config
    except FileNotFoundError:
        print("錯誤：找不到 config.json 檔案。")
        return None
    except json.JSONDecodeError:
        print("錯誤：config.json 檔案格式不正確。")
        return None

def check_in(config):
    """執行簽到"""
    base_url = config.get("base_url")
    user_id = config.get("user_id")
    access_token = config.get("access_token")

    if not all([base_url, user_id, access_token]):
        print("錯誤：設定資訊不完整，無法執行簽到。")
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

    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] 🚀 正在為 User ID: {user_id} 執行簽到...")

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
    config = load_config()
    if config:
        check_in(config)