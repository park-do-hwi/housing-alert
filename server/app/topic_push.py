"""(주제 푸시) 새 공고를 FCM 주제(topic)로 푸시한다. 서버·기기 등록 없이, 앱이 관심 지역·유형 주제를 구독해 두면 된다.

주제 이름: n_<시·도 번호>_<유형 번호> (번호 못 찾으면 x). 앱의 lib/core/push.dart(app/push.py 는 기존 기기 토큰 방식) 와 같은 규칙이어야 한다.
인증: 환경변수 FCM_SERVICE_ACCOUNT(서비스 계정 JSON 전체). 없으면 아무것도 보내지 않는다.
"""
import json
import logging
import os

import requests

log = logging.getLogger(__name__)

SIDO = ["서울", "경기", "인천", "부산", "대구", "광주", "대전", "울산", "세종",
        "강원", "충북", "충남", "전북", "전남", "경북", "경남", "제주"]
CATS = ["분양", "무순위", "장기전세", "임대"]
MAX_PER_RUN = 20


def topics_for(item: dict) -> list[str]:
    s = SIDO.index(item["sido"]) if item.get("sido") in SIDO else "x"
    cats = [CATS.index(t) for t in item.get("tags") or [] if t in CATS] or ["x"]
    return [f"n_{s}_{c}" for c in cats]


def condition_for(item: dict) -> str:
    """한 기기가 여러 주제를 구독해도 알림이 한 번만 가도록 조건(||)으로 묶는다(최대 5개)."""
    return " || ".join(f"'{t}' in topics" for t in topics_for(item)[:5])


def message_for(item: dict) -> dict:
    where = f"{item['sido']} · " if item.get("sido") else ""
    return {
        "message": {
            "condition": condition_for(item),
            "notification": {"title": f"새 공고 · {where}{'/'.join(t for t in item.get('tags') or [] if t != '기타') or '청약'}",
                             "body": item.get("title", "")},
            "data": {"id": str(item.get("id", "")), "url": item.get("url", "")},
            "android": {"priority": "HIGH"},
        }
    }


def _token(info: dict) -> str:
    from google.auth.transport.requests import Request
    from google.oauth2 import service_account

    cred = service_account.Credentials.from_service_account_info(
        info, scopes=["https://www.googleapis.com/auth/firebase.messaging"])
    cred.refresh(Request())
    return cred.token


def notify(items: list[dict], new_ids: list[str], today_iso: str, raw_account: str | None = None) -> int:
    raw = raw_account if raw_account is not None else os.environ.get("FCM_SERVICE_ACCOUNT", "")
    if not raw or not new_ids:
        return 0
    info = json.loads(raw)
    by_id = {i["id"]: i for i in items}
    todo = [by_id[i] for i in new_ids if i in by_id and (not by_id[i].get("apply_end") or by_id[i]["apply_end"] >= today_iso)]
    todo = todo[:MAX_PER_RUN]
    if not todo:
        return 0
    tok = _token(info)
    url = f"https://fcm.googleapis.com/v1/projects/{info['project_id']}/messages:send"
    sent = 0
    for it in todo:
        r = requests.post(url, json=message_for(it), headers={"Authorization": f"Bearer {tok}"}, timeout=20)
        if r.ok:
            sent += 1
        else:
            log.warning("push failed %s: %s %s", it["id"], r.status_code, r.text[:200])
    return sent
