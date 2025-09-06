import os
import json
import requests
from datetime import datetime

def load_config():
    """從 config.json 載入設定"""
    try:
        with open("veloera-checkin-script/config.json", 'r', encoding='utf-8') as f:
            return json.load(f)
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
        print("錯誤：config.json 檔案缺少必要的欄位 (base_url, user_id, access_token)。")
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