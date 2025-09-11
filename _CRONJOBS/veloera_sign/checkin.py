#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
通用自動簽到腳本 - 統一使用 FlareSolverr

配置優先級：
1. 本地 config.json
2. 環境變數 SECRETS_CONTEXT

統一使用 FlareSolverr 處理所有站點
"""

import os
import sys
import json
from time import sleep
import requests
from datetime import datetime

def log(message):
    """日誌記錄"""
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {message}")

def load_configs():
    """載入配置：優先 config.json，備用環境變數"""
    configs = []
    script_dir = os.path.dirname(os.path.abspath(__file__))
    
    # 優先級 1: 本地 config.json
    config_path = os.path.join(script_dir, "config.json")
    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            config = json.load(f)
        
        if all(k in config for k in ["base_url", "user_id", "access_token"]):
            config['base_url'] = config['base_url'].rstrip('/')
            configs.append(config)
            log(f"✅ 從 config.json 載入配置")
            return configs
    except (FileNotFoundError, json.JSONDecodeError):
        pass
    
    # 優先級 2: 環境變數
    secrets_context_json = os.environ.get("SECRETS_CONTEXT")
    if secrets_context_json:
        try:
            secrets_context = json.loads(secrets_context_json)
            for key, value in secrets_context.items():
                if key.startswith("VELOERA_AUTOSIGN_") or key.startswith("AUTOSIGN_"):
                    try:
                        config = json.loads(value)
                        if all(k in config for k in ["base_url", "user_id", "access_token"]):
                            config['base_url'] = config['base_url'].rstrip('/')
                            configs.append(config)
                    except json.JSONDecodeError:
                        continue
        except json.JSONDecodeError:
            pass
    
    return configs

def flaresolverr_checkin(base_url, checkin_url, headers):
    """統一 FlareSolverr 簽到方法"""
    flaresolverr_url = os.environ.get("FLARESOLVERR_URL")
    if not flaresolverr_url:
        log("❌ 未設定 FLARESOLVERR_URL")
        return False

    session_id = None
    try:
        # 建立 session
        response = requests.post(f"{flaresolverr_url.rstrip('/')}/v1", 
                               json={'cmd': 'sessions.create'}, timeout=20)
        if response.status_code != 200 or response.json().get('status') != 'ok':
            return False
        session_id = response.json()['session']

        # 獲取 clearance
        response = requests.post(f"{flaresolverr_url.rstrip('/')}/v1", json={
            'cmd': 'request.get',
            'url': base_url,
            'session': session_id,
            'maxTimeout': 60000
        }, timeout=70)
        
        if response.status_code != 200 or response.json().get('status') != 'ok':
            return False
        
        solution = response.json().get('solution', {})
        cookies = {c.get('name'): c.get('value') for c in solution.get('cookies', [])}
        user_agent = solution.get('userAgent', '')

        # 發送簽到請求
        api_headers = {
            'Authorization': headers.get('Authorization', ''),
            'Veloera-User': headers.get('Veloera-User', ''),
            'User-Agent': user_agent,
            'Accept': 'application/json, text/plain, */*',
            'Content-Type': 'application/json;charset=UTF-8',
            'Origin': base_url,
            'Referer': f'{base_url}/',
        }
        
        api_response = requests.post(checkin_url, headers=api_headers, 
                                   cookies=cookies, json={}, timeout=30)
        
        if api_response.status_code == 200:
            data = api_response.json()
            if data.get('success'):
                quota = data.get('data', {}).get('quota', 0)
                message = data.get('message', '簽到成功')
                log(f"✅ {message} - 獲得額度: {quota}")
                return True
            else:
                error_msg = data.get('message', '簽到失敗')
                if "已经签到" in error_msg or "checked in" in error_msg:
                    log(f"ℹ️ 今天已經簽到過了")
                    return True
                else:
                    log(f"❌ 簽到失敗: {error_msg}")
                    return False
        else:
            log(f"❌ API 請求失敗，狀態碼: {api_response.status_code}")
            return False

    except Exception as e:
        log(f"❌ 錯誤: {e}")
        return False
    finally:
        if session_id:
            try:
                requests.post(f"{flaresolverr_url.rstrip('/')}/v1", 
                            json={'cmd': 'sessions.destroy', 'session': session_id}, timeout=20)
            except:
                pass

def main():
    """主程序"""
    configs = load_configs()
    if not configs:
        log("❌ 未找到配置")
        sys.exit(1)

    any_failed = False
    for config in configs:
        base_url = config["base_url"]
        user_id = config["user_id"]
        access_token = config["access_token"]
        
        log(f"🚀 開始簽到: {base_url}")
        
        checkin_url = f"{base_url}/api/user/check_in"
        headers = {
            'Authorization': f'Bearer {access_token}',
            'Veloera-User': str(user_id),
        }
        
        # 重試機制
        success = False
        for attempt in range(3):
            success = flaresolverr_checkin(base_url, checkin_url, headers)
            if success:
                break
            if attempt < 2:
                log(f"🔄 重試 {attempt + 1}/2")
                sleep(3)
        
        if not success:
            any_failed = True
    
    sys.exit(1 if any_failed else 0)

if __name__ == "__main__":
    main()