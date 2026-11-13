"""(주제 푸시) 새 공고를 FCM 주제(topic)로 푸시한다. 서버·기기 등록 없이, 앱이 관심 지역·유형 주제를 구독해 두면 된다.

주제 이름: n_<시·도 번호>_<유형 번호> (번호 못 찾으면 x). 앱의 lib/core/push.dart(app/push.py 는 기존 기기 토큰 방식) 와 같은 규칙이어야 한다.
인증: 환경변수 FCM_SERVICE_ACCOUNT(서비스 계정 JSON 전체). 없으면 아무것도 보내지 않는다.
"""
import json
import logging
import os
import re

import requests

log = logging.getLogger(__name__)

SIDO = ["서울", "경기", "인천", "부산", "대구", "광주", "대전", "울산", "세종",
        "강원", "충북", "충남", "전북", "전남", "경북", "경남", "제주"]
CATS = ["분양", "무순위", "장기전세", "임대"]
MAX_PER_RUN = 5          # 한 번(30분)에 보내는 알림 수. 넘치는 건 다음 회차로 미룬다
FRESH_DAYS = 3           # 공고일이 이보다 오래된 건 알림을 보내지 않는다(목록에는 그대로 있다)
QUIET_START, QUIET_END = 23, 7   # 한국 시간 23시~07시는 알림을 보내지 않고 아침으로 미룬다


def is_quiet(now_utc=None) -> bool:
    from datetime import datetime, timedelta, timezone

    now = (now_utc or datetime.now(timezone.utc)) + timedelta(hours=9)
    return now.hour >= QUIET_START or now.hour < QUIET_END


def is_fresh(item: dict, today_iso: str) -> bool:
    from datetime import date, timedelta

    ann = item.get("announce_date")
    if not ann:
        return True
    return date.fromisoformat(ann[:10]) >= date.fromisoformat(today_iso[:10]) - timedelta(days=FRESH_DAYS)


def topics_for(item: dict) -> list[str]:
    s = SIDO.index(item["sido"]) if item.get("sido") in SIDO else "x"
    cats = [CATS.index(t) for t in item.get("tags") or [] if t in CATS] or ["x"]
    return [f"n_{s}_{c}" for c in cats]


def condition_for(item: dict) -> str:
    """한 기기가 여러 주제를 구독해도 알림이 한 번만 가도록 조건(||)으로 묶는다(최대 5개)."""
    return " || ".join(f"'{t}' in topics" for t in topics_for(item)[:5])


def _md(iso: str | None) -> str:
    return f"{int(iso[5:7])}/{int(iso[8:10])}" if iso and len(iso) >= 10 else ""


def body_for(item: dict, today_iso: str | None = None) -> str:
    """공고명 + 접수 기간(남은 일수) + 전용면적·세대수 + 위치. 있는 정보만 줄로 붙인다."""
    from datetime import date

    info = item.get("info") or {}
    lines = [item.get("title", "")]
    start, end = info.get("apply_start") or info.get("rank1_start"), item.get("apply_end")
    if end:
        span = f"{_md(start)}~{_md(end)}" if start and start != end else _md(end)
        left = ""
        try:
            d = (date.fromisoformat(end[:10]) - date.fromisoformat((today_iso or date.today().isoformat())[:10])).days
            left = " (오늘 마감)" if d == 0 else f" (D-{d})" if d > 0 else ""
        except ValueError:
            pass
        lines.append(f"📅 접수 {span}{left}")
    facts = []
    areas = sorted({round(t["exclusive_area"]) for t in item.get("types") or [] if t.get("exclusive_area")})
    if areas:
        facts.append("전용 " + "·".join(str(a) for a in areas[:4]) + "㎡")
    total = info.get("total_households") or sum(t.get("total") or 0 for t in item.get("types") or [])
    if total and str(total) != "0":
        facts.append(f"총 {total}세대")
    if facts:
        lines.append("🏠 " + " · ".join(facts))
    place = info.get("address") or " ".join(x for x in (item.get("sido"), item.get("dong")) if x)
    if place:
        lines.append(f"📍 {place}")
    return "\n".join(lines)


def message_for(item: dict, today_iso: str | None = None) -> dict:
    tags = "/".join(t for t in item.get("tags") or [] if t in CATS) or "청약"
    where = f"{item['sido']} " if item.get("sido") else ""
    return {
        "message": {
            "condition": condition_for(item),
            "notification": {"title": f"🔔 {where}{tags} 새 공고", "body": body_for(item, today_iso)},
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


PUSH_OK_RE = re.compile(r"모집|분양|공급|매각|접수|신청|청약")
PUSH_BAD_RE = re.compile(r"발표|안내|수칙|대상자|선정|서류심사|명단|당첨|통보|결과|합격|심사")


def worth_push(item: dict) -> bool:
    """'새 공고' 알림을 보낼 만한가: 결과·입주안내 같은 결과성 글, 정정공고, 신청자와 무관한 잡글은 보내지 않는다."""
    from .classify import NOISE_RE, pushable

    tags = item.get("tags") or []
    title = item.get("title", "")
    # 모집·분양·공급 공고만. '발표·안내·수칙·대상자' 같은 사후 안내글은 신청받는 공고가 아니라 알리지 않는다.
    # 청약홈 공고는 제목이 단지 이름뿐이라 이 검사를 하지 않는다(게시판 글인 LH·SH·GH 에만 적용).
    if not str(item.get("id", "")).startswith("APPLYHOME") and (
        not PUSH_OK_RE.search(title) or PUSH_BAD_RE.search(title)
    ):
        return False
    return pushable(tags) and "정정" not in tags and not NOISE_RE.search(item.get("title", ""))


def plan(items: list[dict], new_ids: list[str], pending: list[str], today_iso: str, quiet: bool) -> tuple[list[str], list[str]]:
    """(이번에 보낼 id, 다음으로 미룰 id). 새벽엔 전부 미루고, 아니면 MAX_PER_RUN 건만 보낸다.
    공고일이 오래됐거나 접수가 끝난 건 아예 버린다(대량 수집 때 한꺼번에 울리지 않게)."""
    by_id = {i["id"]: i for i in items}
    queue: list[str] = []
    for i in list(pending) + list(new_ids):
        it = by_id.get(i)
        if i in queue or not it or not worth_push(it) or not is_fresh(it, today_iso):
            continue
        if it.get("apply_end") and it["apply_end"] < today_iso:
            continue
        queue.append(i)
    if quiet:
        return [], queue
    return queue[:MAX_PER_RUN], queue[MAX_PER_RUN:]


def notify(items: list[dict], new_ids: list[str], today_iso: str, raw_account: str | None = None) -> list[dict]:
    """보낸 공고 목록을 돌려준다."""
    raw = raw_account if raw_account is not None else os.environ.get("FCM_SERVICE_ACCOUNT", "")
    if not raw or not new_ids:
        return []
    info = json.loads(raw)
    by_id = {i["id"]: i for i in items}
    todo = [by_id[i] for i in new_ids if i in by_id and worth_push(by_id[i])
            and (not by_id[i].get("apply_end") or by_id[i]["apply_end"] >= today_iso)]
    todo = todo[:MAX_PER_RUN]
    if not todo:
        return []
    tok = _token(info)
    url = f"https://fcm.googleapis.com/v1/projects/{info['project_id']}/messages:send"
    sent: list[dict] = []
    for it in todo:
        r = requests.post(url, json=message_for(it, today_iso), headers={"Authorization": f"Bearer {tok}"}, timeout=20)
        if r.ok:
            sent.append(it)
        else:
            log.warning("push failed %s: %s %s", it["id"], r.status_code, r.text[:200])
    return sent


HISTORY_LIMIT = 100


def history_entry(item: dict, at: str) -> dict:
    return {"id": item.get("id", ""), "title": item.get("title", ""), "sido": item.get("sido", ""),
            "tags": [t for t in item.get("tags") or [] if t != "기타"], "url": item.get("url", ""), "at": at}


def merge_history(prev: list[dict], sent: list[dict], at: str) -> list[dict]:
    """알림 기록(최근 것이 앞). 같은 공고는 한 번만 남기고 HISTORY_LIMIT 건까지."""
    new = [history_entry(i, at) for i in sent]
    seen = {e["id"] for e in new}
    return (new + [e for e in prev if e.get("id") not in seen])[:HISTORY_LIMIT]
