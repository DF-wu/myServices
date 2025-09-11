#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Veloera 自動簽到腳本 - 支援 Cloudflare 保護繞過

本腳本實現了兩種簽到策略：
1. 直接簽到：適用於無 Cloudflare 保護的網站
2. 混合簽到：使用 FlareSolverr 繞過 Cloudflare 保護

作者：AI Assistant
版本：2.0
最後更新：2025-09-11
"""

import os
import sys
import json
from time import sleep
import requests
from datetime import datetime

# ==================== 配置常數 ====================
RETRY_LIMIT = 2  # 最大重試次數：涵蓋 Cloudflare 多段挑戰
REQUEST_TIMEOUT = 30  # API 請求超時時間（秒）
FLARESOLVERR_TIMEOUT = 70  # FlareSolverr 請求超時時間（秒）

# ==================== 工具函數 ====================

def log(message):
    """
    帶時間戳的日誌記錄器
    
    Args:
        message (str): 要記錄的訊息
    """
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    print(f"[{timestamp}] {message}")

# ==================== 簽到策略實現 ====================

def direct_checkin(checkin_url, headers):
    """
    策略 A: 直接簽到
    
    適用於無 Cloudflare 保護的網站，直接使用 requests 發送 POST 請求
    
    Args:
        checkin_url (str): 簽到 API 端點 URL
        headers (dict): HTTP 請求標頭，包含認證信息
        
    Returns:
        bool: 簽到是否成功
    """
    log("ℹ️  偵測到非 Cloudflare 站點，執行直接簽到...")
    
    try:
        # 發送簽到請求
        response = requests.post(
            checkin_url, 
            headers=headers, 
            json={}, 
            timeout=REQUEST_TIMEOUT
        )
        
        # 處理成功回應
        if response.status_code == 200:
            data = response.json()
            
            if data.get('success'):
                # 簽到成功
                quota = data.get('data', {}).get('quota', 0)
                message = data.get('message', '簽到成功')
                log(f"✅ {message} - 獲得額度: {quota}")
                return True
            else:
                # 檢查是否已經簽到過
                error_msg = data.get('message', '簽到失敗')
                if "已经签到" in error_msg or "checked in" in error_msg:
                    log(f"ℹ️  今天已經簽到過了: {error_msg}")
                    return True
                else:
                    log(f"❌ 簽到失敗: {error_msg}")
                    return False
        else:
            # HTTP 錯誤
            log(f"❌ 直接簽到請求失敗，狀態碼: {response.status_code}")
            log(f"   錯誤訊息: {response.text}")
            return False
            
    except requests.exceptions.RequestException as e:
        log(f"❌ 直接簽到時發生網路錯誤: {e}")
        return False
    except Exception as e:
        log(f"❌ 處理直接簽到回應時發生未知錯誤: {e}")
        return False

def flaresolverr_checkin(base_url, checkin_url, headers):
    """
    策略 B: 混合簽到（FlareSolverr + 直接 API 請求）
    
    這是核心創新：
    1. 使用 FlareSolverr 獲取 Cloudflare clearance cookies 和 User-Agent
    2. 使用獲取的 cookies 和 User-Agent 直接發送認證 API 請求
    
    這種方法解決了 FlareSolverr v3+ 不支援自定義 headers 的問題
    
    Args:
        base_url (str): 網站基礎 URL
        checkin_url (str): 簽到 API 端點 URL  
        headers (dict): 包含認證信息的 HTTP 標頭
        
    Returns:
        bool: 簽到是否成功
    """
    log("ℹ️  偵測到 Cloudflare 站點，執行混合簽到流程...")
    
    # 檢查 FlareSolverr 環境變數
    flaresolverr_url = os.environ.get("FLARESOLVERR_URL")
    if not flaresolverr_url:
        log("❌ 錯誤：未設定 FLARESOLVERR_URL 環境變數。")
        return False

    session_id = None
    
    try:
        # ========== 步驟 1: 建立 FlareSolverr Session ==========
        log("   [1/3] 正在建立 FlareSolverr session...")
        
        create_session_payload = {'cmd': 'sessions.create'}
        response = requests.post(
            f"{flaresolverr_url.rstrip('/')}/v1", 
            json=create_session_payload, 
            timeout=20
        )
        
        if response.status_code != 200:
            log(f"   ❌ 建立 session 失敗，狀態碼: {response.status_code}, 回應: {response.text}")
            return False
            
        data = response.json()
        if data.get('status') != 'ok' or not data.get('session'):
            log(f"   ❌ 建立 session 失敗: {data.get('message')}")
            return False
            
        session_id = data['session']
        log(f"   ✅ Session 已建立: {session_id}")

        # ========== 步驟 2: 獲取 Cloudflare Clearance ==========
        log(f"   [2/3] 正在使用 FlareSolverr 獲取 Cloudflare clearance...")
        
        # 訪問網站首頁以觸發並解決 Cloudflare 挑戰
        get_payload = {
            'cmd': 'request.get',
            'url': base_url,
            'session': session_id,
            'maxTimeout': 60000  # 60 秒超時，足夠解決複雜挑戰
        }
        
        response = requests.post(
            f"{flaresolverr_url.rstrip('/')}/v1", 
            json=get_payload, 
            timeout=FLARESOLVERR_TIMEOUT
        )
        
        if response.status_code != 200 or response.json().get('status') != 'ok':
            log(f"   ❌ 獲取 clearance 失敗，狀態碼: {response.status_code}, 回應: {response.text}")
            return False
        
        # 提取 clearance 信息
        homepage_data = response.json()
        solution = homepage_data.get('solution', {})
        cookies = solution.get('cookies', [])
        user_agent = solution.get('userAgent', '')
        
        log(f"   ✅ 已獲取 Cloudflare clearance，cookies: {len(cookies)} 個")
        log(f"   ✅ User-Agent: {user_agent}")

        # ========== 步驟 3: 使用 Clearance 發送認證 API 請求 ==========
        log(f"   [3/3] 正在使用 clearance 直接發送簽到請求...")
        
        # 構建 cookies 字典
        cookie_dict = {}
        for cookie in cookies:
            cookie_dict[cookie.get('name')] = cookie.get('value')
        
        # 構建完整的 HTTP 標頭
        # 關鍵：結合 FlareSolverr 的 User-Agent 和原始的認證標頭
        api_headers = {
            'Authorization': headers.get('Authorization', ''),  # Bearer token
            'Veloera-User': headers.get('Veloera-User', ''),   # 用戶 ID
            'User-Agent': user_agent,  # 使用 FlareSolverr 的 User-Agent（重要！）
            'Accept': 'application/json, text/plain, */*',
            'Content-Type': 'application/json;charset=UTF-8',
            'Origin': base_url,
            'Referer': f'{base_url}/',
        }
        
        # 發送認證 API 請求
        api_response = requests.post(
            checkin_url, 
            headers=api_headers, 
            cookies=cookie_dict,  # 使用 FlareSolverr 獲取的 cookies
            json={}, 
            timeout=REQUEST_TIMEOUT
        )
        
        log(f"   📋 API 回應狀態碼: {api_response.status_code}")
        
        # ========== 處理 API 回應 ==========
        if api_response.status_code == 200:
            try:
                data = api_response.json()
                
                if data.get('success'):
                    # 簽到成功
                    quota = data.get('data', {}).get('quota', 0)
                    message = data.get('message', '簽到成功')
                    log(f"✅ {message} - 獲得額度: {quota}")
                    return True
                else:
                    # 檢查是否已經簽到過
                    error_msg = data.get('message', '簽到失敗')
                    if "已经签到" in error_msg or "checked in" in error_msg:
                        log(f"ℹ️  今天已經簽到過了: {error_msg}")
                        return True
                    else:
                        log(f"❌ 簽到失敗: {error_msg}")
                        return False
                        
            except json.JSONDecodeError:
                log(f"   ❌ API 回應不是有效的 JSON: {api_response.text[:200]}")
                return False
                
        elif api_response.status_code == 403:
            log(f"   ❌ API 請求被 Cloudflare 攔截，可能需要更新 clearance")
            log(f"   📋 回應內容: {api_response.text[:200]}")
            return False
        else:
            log(f"   ❌ API 請求失敗，狀態碼: {api_response.status_code}")
            log(f"   📋 回應內容: {api_response.text[:200]}")
            return False

    except requests.exceptions.RequestException as e:
        log(f"❌ FlareSolverr 流程中發生網路錯誤: {e}")
        return False
    except Exception as e:
        log(f"❌ FlareSolverr 流程中發生未知錯誤: {e}")
        return False
    finally:
        # ========== 清理：銷毀 FlareSolverr Session ==========
        if session_id:
            log(f"   [清理] 正在銷毀 session: {session_id}...")
            destroy_payload = {'cmd': 'sessions.destroy', 'session': session_id}
            try:
                requests.post(
                    f"{flaresolverr_url.rstrip('/')}/v1", 
                    json=destroy_payload, 
                    timeout=20
                )
                log("   ✅ Session 已銷毀。")
            except Exception as e:
                log(f"   ⚠️ 銷毀 session 時發生錯誤: {e}")

# ==================== 配置管理 ====================

def load_configs():
    """
    載入簽到配置
    
    支援多種配置來源（按優先級排序）：
    1. 環境變數 SECRETS_CONTEXT（GitHub Actions）
    2. 本地 configs.json（陣列格式，用於多站點）
    3. 本地 config.json（單個物件格式，用於單站點）
    
    Returns:
        list: 配置列表，每個元素包含 base_url, user_id, access_token
    """
    configs = []
    
    # ========== 優先級 1: 環境變數（GitHub Actions） ==========
    secrets_context_json = os.environ.get("SECRETS_CONTEXT")
    if secrets_context_json:
        log("資訊：偵測到 SECRETS_CONTEXT，將從中解析設定。")
        try:
            secrets_context = json.loads(secrets_context_json)
            
            # 查找所有以 VELOERA_AUTOSIGN_ 開頭的 secrets
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

    # ========== 優先級 2 & 3: 本地配置檔案 ==========
    log("資訊：未從環境變數載入設定，嘗試從本地配置檔案讀取。")
    script_dir = os.path.dirname(os.path.abspath(__file__))
    
    # 優先嘗試 configs.json（陣列格式，支援多站點）
    configs_path = os.path.join(script_dir, "configs.json")
    try:
        with open(configs_path, 'r', encoding='utf-8') as f:
            local_configs = json.load(f)
            
            if isinstance(local_configs, list):
                # 陣列格式：多站點配置
                for i, config in enumerate(local_configs):
                    if all(k in config for k in ["base_url", "user_id", "access_token"]):
                        config['base_url'] = config['base_url'].rstrip('/')
                        configs.append(config)
                    else:
                        log(f"警告：configs.json 中的第 {i+1} 個設定缺少必要欄位。")
                
                if configs:
                    log(f"資訊：從 configs.json 成功載入 {len(configs)} 個簽到設定。")
                    return configs
            else:
                log("警告：configs.json 不是陣列格式，嘗試讀取 config.json。")
                
    except FileNotFoundError:
        log("資訊：未找到 configs.json，嘗試讀取 config.json。")
    except json.JSONDecodeError:
        log("警告：configs.json 格式不正確，嘗試讀取 config.json。")
    
    # 備用：嘗試 config.json（單個物件格式）
    config_path = os.path.join(script_dir, "config.json")
    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            single_config = json.load(f)
            
            if isinstance(single_config, dict):
                # 物件格式：單站點配置
                if all(k in single_config for k in ["base_url", "user_id", "access_token"]):
                    single_config['base_url'] = single_config['base_url'].rstrip('/')
                    configs.append(single_config)
                    log(f"資訊：從 config.json 成功載入 1 個簽到設定。")
                    return configs
                else:
                    log("錯誤：config.json 缺少必要欄位。")
            else:
                log("錯誤：config.json 不是物件格式。")
                
    except FileNotFoundError:
        log("錯誤：在本地找不到 config.json 檔案。")
    except json.JSONDecodeError:
        log("錯誤：config.json 檔案格式不正確。")
    
    return []

# ==================== 主程序邏輯 ====================

def main():
    """
    主函數：執行自動簽到流程
    
    流程：
    1. 載入配置
    2. 對每個配置執行簽到（支援重試）
    3. 根據結果決定退出狀態
    """
    # 載入配置
    configs = load_configs()
    if not configs:
        log("❌ 未找到有效的配置，程序退出。")
        sys.exit(1)

    any_task_failed = False
    print("-" * 50)

    # 處理每個站點的簽到
    for config in configs:
        base_url = config.get("base_url")
        user_id = config.get("user_id")
        access_token = config.get("access_token")

        # 驗證配置完整性
        if not all([base_url, user_id, access_token]):
            log(f"❌ 錯誤：設定資訊不完整，跳過此項。")
            any_task_failed = True
            continue

        log(f"🚀 開始為 User ID: {user_id} ({base_url}) 執行簽到任務...")
        
        # ========== 構建請求參數 ==========
        checkin_url = f"{base_url}/api/user/check_in"
        headers = {
            'Authorization': f'Bearer {access_token}',  # API 認證 token
            'Veloera-User': str(user_id),              # 用戶 ID 標頭
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
            'Accept': 'application/json, text/plain, */*',
            'Content-Type': 'application/json;charset=UTF-8',
            'Origin': base_url,
            'Referer': f'{base_url}/',
        }
        
        # ========== 執行簽到（支援重試） ==========
        success = False
        for attempt in range(RETRY_LIMIT + 1):
            # 根據網站類型選擇簽到策略
            if 'zone.veloera.org' in base_url:
                # Cloudflare 保護的站點：使用混合策略
                success = flaresolverr_checkin(base_url, checkin_url, headers)
            else:
                # 普通站點：直接簽到
                success = direct_checkin(checkin_url, headers)
            
            if success:
                break
            
            # 重試邏輯
            if attempt < RETRY_LIMIT:
                log(f"🔄 任務失敗，將在 3 秒後重試... (第 {attempt + 1} 次)")
                sleep(3)
        
        # 記錄最終結果
        if not success:
            log(f"❌ 為 User ID: {user_id} 的簽到任務在多次嘗試後最終失敗。")
            any_task_failed = True

        print("-" * 50)
        sleep(2)  # 避免請求過於頻繁
        
    # ========== 程序退出 ==========
    if any_task_failed:
        log("SUMMARY: 至少有一個簽到任務失敗，腳本以錯誤狀態退出。")
        sys.exit(1)
    else:
        log("SUMMARY: 所有簽到任務均已成功或已簽到。")

# ==================== 程序入口 ====================

if __name__ == "__main__":
    main()