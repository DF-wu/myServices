#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
New-API 自動簽到腳本（無需 FlareSolverr）

配置優先級：
1. 環境變數 NEWAPI_AUTOSIGN_*（含 SECRETS_CONTEXT 中的同名項）
2. 本地 config.json（僅當沒有環境變數時使用）

必要欄位：base_url, user_id, access_token
- base_url 例如：https://newapi.netlib.re
- user_id 例如：1898（對應 New-Api-User）
- access_token：API token（用於 Authorization: Bearer）
"""

import os
import sys
import json
from datetime import datetime
from time import sleep

import requests


def log(msg: str) -> None:
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {msg}")


def load_configs():
    """載入配置：優先環境變數，備用 config.json"""
    configs = []

    log("🔍 檢查 NEWAPI_AUTOSIGN_* 環境變數…")

    # 1) SECRETS_CONTEXT（GitHub Actions secrets 傳入）
    secrets_context_json = os.environ.get("SECRETS_CONTEXT")
    if secrets_context_json:
        try:
            secrets_context = json.loads(secrets_context_json)
            for key, value in secrets_context.items():
                if key.startswith("NEWAPI_AUTOSIGN_"):
                    try:
                        cfg = json.loads(value)
                        if all(k in cfg for k in ("base_url", "user_id", "access_token")):
                            cfg["base_url"] = cfg["base_url"].rstrip('/')
                            configs.append(cfg)
                            log(f"✅ 從 SECRETS_CONTEXT 讀取 {key}: {cfg['base_url']}")
                        else:
                            log(f"⚠️ {key} 缺少必要欄位")
                    except json.JSONDecodeError as e:
                        log(f"❌ {key} 解析失敗: {e}")
        except json.JSONDecodeError as e:
            log(f"❌ SECRETS_CONTEXT 解析失敗: {e}")

    # 2) 直接環境變數
    for key, value in os.environ.items():
        if key.startswith("NEWAPI_AUTOSIGN_"):
            try:
                cfg = json.loads(value)
                if all(k in cfg for k in ("base_url", "user_id", "access_token")):
                    cfg["base_url"] = cfg["base_url"].rstrip('/')
                    configs.append(cfg)
                    log(f"✅ 從環境變數 {key} 讀取: {cfg['base_url']}")
            except json.JSONDecodeError as e:
                log(f"❌ {key} 解析失敗: {e}")

    if configs:
        return configs

    log("⚠️ 未找到 NEWAPI_AUTOSIGN_*，嘗試讀取 config.json")

    # 3) config.json（僅在無環境變數時使用）
    config_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "config.json")
    if os.path.exists(config_path):
        try:
            with open(config_path, "r", encoding="utf-8") as f:
                cfg = json.load(f)
            template_words = ["目標站點", "使用者 ID", "api token"]
            is_template = any(str(cfg.get(k, "")).strip() in template_words for k in ("base_url", "user_id", "access_token"))
            if not is_template and all(k in cfg for k in ("base_url", "user_id", "access_token")):
                cfg["base_url"] = cfg["base_url"].rstrip('/')
                configs.append(cfg)
                log(f"✅ 從 config.json 讀取: {cfg['base_url']}")
            else:
                log("⚠️ config.json 為範本或缺欄位，忽略")
        except Exception as e:
            log(f"❌ 讀取 config.json 失敗: {e}")

    if not configs:
        log("❌ 未找到任何有效配置")
    return configs


def newapi_checkin_direct(cfg: dict) -> bool:
    """直接請求，不經 FlareSolverr。"""
    base_url = cfg["base_url"].rstrip('/')
    user_id = str(cfg["user_id"])
    token = cfg["access_token"]

    checkin_url = f"{base_url}/api/user/checkin"
    headers = {
        "Authorization": f"Bearer {token}",
        "New-Api-User": user_id,
        "Accept": "application/json, text/plain, */*",
        "Content-Type": "application/json;charset=UTF-8",
        "Origin": base_url,
        "Referer": f"{base_url}/",
    }

    try:
        resp = requests.post(checkin_url, headers=headers, json={}, timeout=20)
    except Exception as e:
        log(f"❌ 請求失敗: {e}")
        return False

    if resp.status_code != 200:
        log(f"❌ HTTP {resp.status_code}: {resp.text[:200]}")
        return False

    try:
        data = resp.json()
    except Exception:
        log(f"❌ 回應非 JSON: {resp.text[:200]}")
        return False

    if data.get("success"):
        quota = data.get("data", {}).get("quota")
        log(f"✅ 簽到成功，quota: {quota}")
        return True

    msg = data.get("message", "簽到失敗")
    if "已" in msg and "签" in msg:
        log(f"ℹ️ {msg}")
        return True

    log(f"❌ 簽到失敗: {msg}")
    return False


def newapi_checkin_flaresolverr(cfg: dict, flaresolverr_url: str) -> bool:
    """經 FlareSolverr 取得 clearance 後再簽到（若目標站點開啟防護）。"""
    base_url = cfg["base_url"].rstrip('/')
    user_id = str(cfg["user_id"])
    token = cfg["access_token"]
    flaresolverr_url = flaresolverr_url.rstrip('/')

    # 建立 session
    try:
        r = requests.post(f"{flaresolverr_url}/v1", json={"cmd": "sessions.create"}, timeout=20, verify=False)
        r.raise_for_status()
        session_id = r.json().get("session")
    except Exception as e:
        log(f"❌ FlareSolverr 建立 session 失敗: {e}")
        return False

    try:
        # 取得 clearance（cookies + UA）
        r = requests.post(
            f"{flaresolverr_url}/v1",
            json={"cmd": "request.get", "url": base_url, "session": session_id, "maxTimeout": 60000},
            timeout=70,
            verify=False,
        )
        r.raise_for_status()
        if r.json().get("status") != "ok":
            log("❌ FlareSolverr 未返回 ok 狀態")
            return False
        solution = r.json().get("solution", {})
        cookies = {c.get("name"): c.get("value") for c in solution.get("cookies", [])}
        user_agent = solution.get("userAgent", "")

        # 攜帶 clearance 發送簽到
        checkin_url = f"{base_url}/api/user/checkin"
        headers = {
            "Authorization": f"Bearer {token}",
            "New-Api-User": user_id,
            "Accept": "application/json, text/plain, */*",
            "Content-Type": "application/json;charset=UTF-8",
            "Origin": base_url,
            "Referer": f"{base_url}/",
            "User-Agent": user_agent,
        }
        resp = requests.post(checkin_url, headers=headers, cookies=cookies, json={}, timeout=30, verify=False)
    except Exception as e:
        log(f"❌ FlareSolverr 簽到流程失敗: {e}")
        return False
    finally:
        try:
            requests.post(f"{flaresolverr_url}/v1", json={"cmd": "sessions.destroy", "session": session_id}, timeout=10, verify=False)
        except Exception:
            pass

    if resp.status_code != 200:
        log(f"❌ HTTP {resp.status_code}: {resp.text[:200]}")
        return False

    try:
        data = resp.json()
    except Exception:
        log(f"❌ 回應非 JSON: {resp.text[:200]}")
        return False

    if data.get("success"):
        quota = data.get("data", {}).get("quota")
        log(f"✅ 簽到成功（FlareSolverr），quota: {quota}")
        return True

    msg = data.get("message", "簽到失敗")
    if "已" in msg and "签" in msg:
        log(f"ℹ️ {msg}")
        return True

    log(f"❌ 簽到失敗: {msg}")
    return False


def main():
    configs = load_configs()
    if not configs:
        sys.exit(1)

    any_failed = False
    flaresolverr_url = os.environ.get("FLARESOLVERR_URL", "").strip()

    for cfg in configs:
        log(f"🚀 開始簽到: {cfg['base_url']}")
        success = False
        for attempt in range(3):
            if flaresolverr_url:
                success = newapi_checkin_flaresolverr(cfg, flaresolverr_url)
            else:
                success = newapi_checkin_direct(cfg)
            if success:
                break
            if attempt < 2:
                log(f"🔄 重試 {attempt + 1}/2")
                sleep(2)
        if not success:
            any_failed = True


    sys.exit(1 if any_failed else 0)


if __name__ == "__main__":
    main()
