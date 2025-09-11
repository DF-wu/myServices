#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
通用自動簽到腳本 - 統一使用 FlareSolverr

配置優先級：
1. 環境變數 VELOERA_AUTOSIGN_*
2. 本地 config.json（僅當無環境變數時）

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
    """載入配置：優先環境變數，備用 config.json"""
    configs = []
    
    log("🔍 檢查 VELOERA_AUTOSIGN_ 環境變數...")
    
    # 優先級 1: 檢查 VELOERA_AUTOSIGN_ 開頭的環境變數
    # 先檢查 SECRETS_CONTEXT 中的環境變數
    secrets_context_json = os.environ.get("SECRETS_CONTEXT")
    if secrets_context_json:
        log("📋 找到 SECRETS_CONTEXT 環境變數")
        try:
            secrets_context = json.loads(secrets_context_json)
            log(f"📋 SECRETS_CONTEXT 包含 {len(secrets_context)} 個 secrets")
            
            for key, value in secrets_context.items():
                if key.startswith("VELOERA_AUTOSIGN_"):
                    log(f"🔑 找到 VELOERA_AUTOSIGN_ 環境變數: {key}")
                    try:
                        config = json.loads(value)
                        if all(k in config for k in ["base_url", "user_id", "access_token"]):
                            config['base_url'] = config['base_url'].rstrip('/')
                            configs.append(config)
                            log(f"✅ 從環境變數 {key} 載入配置: {config['base_url']}")
                        else:
                            log(f"⚠️ 環境變數 {key} 缺少必要欄位")
                    except json.JSONDecodeError as e:
                        log(f"❌ 環境變數 {key} JSON 解析失敗: {e}")
                        continue
        except json.JSONDecodeError as e:
            log(f"❌ SECRETS_CONTEXT JSON 解析失敗: {e}")
    
    # 檢查直接環境變數
    for key, value in os.environ.items():
        if key.startswith("VELOERA_AUTOSIGN_"):
            log(f"🔑 找到直接環境變數: {key}")
            try:
                config = json.loads(value)
                if all(k in config for k in ["base_url", "user_id", "access_token"]):
                    config['base_url'] = config['base_url'].rstrip('/')
                    configs.append(config)
                    log(f"✅ 從直接環境變數 {key} 載入配置: {config['base_url']}")
            except json.JSONDecodeError as e:
                log(f"❌ 直接環境變數 {key} JSON 解析失敗: {e}")
                continue
    
    # 如果找到環境變數配置，直接返回
    if configs:
        log(f"✅ 從環境變數載入了 {len(configs)} 個配置")
        return configs
    
    log("⚠️ 未找到 VELOERA_AUTOSIGN_ 環境變數，嘗試讀取 config.json")
    
    # 優先級 2: config.json（只有在沒有環境變數時才使用）
    script_dir = os.path.dirname(os.path.abspath(__file__))
    config_path = os.path.join(script_dir, "config.json")
    
    if os.path.exists(config_path):
        try:
            with open(config_path, 'r', encoding='utf-8') as f:
                config = json.load(f)
            
            # 檢查是否為範本檔案（包含中文佔位符）
            template_indicators = ["目標站點", "veloera 的使用者 ID", "veloera system api token"]
            is_template = any(
                str(config.get(key, "")).strip() in template_indicators
                for key in ["base_url", "user_id", "access_token"]
            )
            
            if not is_template and all(k in config for k in ["base_url", "user_id", "access_token"]):
                config['base_url'] = config['base_url'].rstrip('/')
                configs.append(config)
                log(f"✅ 從 config.json 載入配置: {config['base_url']}")
            else:
                log("⚠️ config.json 是範本檔案，無法使用")
        except (json.JSONDecodeError, FileNotFoundError) as e:
            log(f"❌ 讀取 config.json 失敗: {e}")
    else:
        log("⚠️ config.json 檔案不存在")
    
    if not configs:
        log("❌ 未找到任何有效配置")
        return []
    
    log(f"✅ 總共載入了 {len(configs)} 個配置")
    return configs

def flaresolverr_checkin(base_url, checkin_url, headers):
    """統一 FlareSolverr 簽到方法"""
    flaresolverr_url = os.environ.get("FLARESOLVERR_URL", "http://localhost:8191")

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