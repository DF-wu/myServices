#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
New-API 自動簽到腳本（優先使用 FlareSolverr，保持瀏覽器指紋一致）

配置優先級：
1. 環境變數 NEWAPI_AUTOSIGN_*（含 SECRETS_CONTEXT 中的同名項）
2. 本地 config.json（僅當沒有環境變數時使用）

必要欄位：base_url, user_id, access_token
- base_url 例如：https://newapi.netlib.re
- user_id 例如：1898（對應 New-Api-User）
- access_token：API token（用於 Authorization: Bearer）

Cloudflare 攔截處理策略（依官方文件最佳實踐）：
- 若提供 FLARESOLVERR_URL：全程使用 FlareSolverr session（request.get 取得 clearance + request.post 完成簽到），避免重新開啟非瀏覽器指紋。
- 若 FlareSolverr 失敗：最後嘗試一次直連（帶瀏覽器 UA）。
- 若未提供 FLARESOLVERR_URL：僅直連重試三次。
- Turnstile/Recaptcha 官方尚未支援自動解（CAPTCHA_SOLVER 不可用）。
"""

import json
import os
import sys
from datetime import datetime
from time import sleep
from typing import Optional

import requests

DEFAULT_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/122.0.0.0 Safari/537.36"
)


def log(msg: str) -> None:
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {msg}")


def truncate(text: str, length: int = 400) -> str:
    if text is None:
        return ""
    return text[:length] + ("…" if len(text) > length else "")


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
            is_template = any(
                str(cfg.get(k, "")).strip() in template_words
                for k in ("base_url", "user_id", "access_token")
            )
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


def parse_api_response(body: str) -> Optional[dict]:
    try:
        return json.loads(body)
    except Exception:
        return None


def newapi_checkin_direct(cfg: dict, user_agent: str = DEFAULT_UA) -> bool:
    """直接請求，不經 FlareSolverr（帶瀏覽器 UA）。"""
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
        "User-Agent": user_agent,
    }

    log(f"🌐 直連簽到: {checkin_url}")
    try:
        resp = requests.post(checkin_url, headers=headers, json={}, timeout=20)
    except Exception as e:
        log(f"❌ 直連請求失敗: {e}")
        return False

    log(f"ℹ️ 直連回應 HTTP {resp.status_code}")
    if resp.status_code != 200:
        log(f"⚠️ 回應內容: {truncate(resp.text)}")
        return False

    data = parse_api_response(resp.text)
    if not data:
        log(f"❌ 回應非 JSON: {truncate(resp.text)}")
        return False

    if data.get("success"):
        quota = data.get("data", {}).get("quota")
        log(f"✅ 直連簽到成功，quota: {quota}")
        return True

    msg = data.get("message", "簽到失敗")
    if "已" in msg and "签" in msg:
        log(f"ℹ️ {msg}")
        return True

    log(f"❌ 直連簽到失敗: {msg}")
    return False


def newapi_checkin_flaresolverr(cfg: dict, flaresolverr_url: str) -> bool:
    """經 FlareSolverr 取得 clearance 並於同一 session 內 POST 簽到。"""
    base_url = cfg["base_url"].rstrip('/')
    user_id = str(cfg["user_id"])
    token = cfg["access_token"]
    flaresolverr_url = flaresolverr_url.rstrip('/')
    session_id = None

    log(f"🧩 FlareSolverr 流程開始: {base_url}")
    try:
        # 建立 session
        r = requests.post(
            f"{flaresolverr_url}/v1", json={"cmd": "sessions.create"}, timeout=20, verify=False
        )
        r.raise_for_status()
        session_id = r.json().get("session")
        if not session_id:
            log("❌ FlareSolverr 未返回 session")
            return False
        log(f"ℹ️ FlareSolverr session 建立: {session_id}")

        # 取得 clearance
        r = requests.post(
            f"{flaresolverr_url}/v1",
            json={"cmd": "request.get", "url": base_url, "session": session_id, "maxTimeout": 60000},
            timeout=70,
            verify=False,
        )
        r.raise_for_status()
        data = r.json()
        if data.get("status") != "ok":
            log(f"❌ FlareSolverr get 狀態非 ok: {data}")
            return False
        solution = data.get("solution", {})
        solution_status = solution.get("status")
        user_agent = solution.get("userAgent") or DEFAULT_UA
        log(f"ℹ️ clearance HTTP {solution_status}, UA: {user_agent}")

        # 在同一 session 內執行 POST 簽到
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
        payload = {
            "cmd": "request.post",
            "url": checkin_url,
            "session": session_id,
            "headers": headers,
            "postData": "{}",  # 保持空 JSON 主體
            "maxTimeout": 60000,
        }
        r = requests.post(f"{flaresolverr_url}/v1", json=payload, timeout=70, verify=False)
        r.raise_for_status()
        data = r.json()
        if data.get("status") != "ok":
            log(f"❌ FlareSolverr post 狀態非 ok: {data}")
            return False

        solution = data.get("solution", {})
        http_status = solution.get("status")
        body = solution.get("response", "")
        log(f"ℹ️ FlareSolverr 簽到回應 HTTP {http_status}")

        if http_status != 200:
            log(f"⚠️ 回應內容: {truncate(body)}")
            return False

        data_json = parse_api_response(body)
        if not data_json:
            log(f"❌ 回應非 JSON: {truncate(body)}")
            return False

        if data_json.get("success"):
            quota = data_json.get("data", {}).get("quota")
            log(f"✅ 簽到成功（FlareSolverr），quota: {quota}")
            return True

        msg = data_json.get("message", "簽到失敗")
        if "已" in msg and "签" in msg:
            log(f"ℹ️ {msg}")
            return True

        log(f"❌ 簽到失敗: {msg}")
        return False

    except Exception as e:
        log(f"❌ FlareSolverr 流程錯誤: {e}")
        return False
    finally:
        if session_id:
            try:
                requests.post(
                    f"{flaresolverr_url}/v1",
                    json={"cmd": "sessions.destroy", "session": session_id},
                    timeout=10,
                    verify=False,
                )
            except Exception:
                pass


def checkin_with_strategy(cfg: dict, flaresolverr_url: str) -> bool:
    """依照策略執行簽到：優先 FlareSolverr，其次直連。"""
    if flaresolverr_url:
        for attempt in range(2):
            log(f"🔄 FlareSolverr 嘗試 {attempt + 1}/2")
            if newapi_checkin_flaresolverr(cfg, flaresolverr_url):
                return True
            sleep(2)
        log("🔀 FlareSolverr 失敗，改用直連 fallback")
        return newapi_checkin_direct(cfg)

    # 無 FlareSolverr，直連重試 3 次
    for attempt in range(3):
        if newapi_checkin_direct(cfg):
            return True
        if attempt < 2:
            log(f"🔁 直連重試 {attempt + 1}/2")
            sleep(2)
    return False


def main():
    configs = load_configs()
    if not configs:
        sys.exit(1)

    flaresolverr_url = os.environ.get("FLARESOLVERR_URL", "").strip()
    if flaresolverr_url:
        log(f"ℹ️ 將使用 FlareSolverr: {flaresolverr_url}")
    else:
        log("ℹ️ 未提供 FLARESOLVERR_URL，僅直連模式")

    any_failed = False
    for cfg in configs:
        log(f"🚀 開始簽到: {cfg['base_url']}")
        success = checkin_with_strategy(cfg, flaresolverr_url)
        if not success:
            any_failed = True

    sys.exit(1 if any_failed else 0)


if __name__ == "__main__":
    main()
