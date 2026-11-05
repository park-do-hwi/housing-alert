"""한국부동산원 청약홈 분양정보 (공공데이터포털 api.odcloud.kr).

서비스키: 환경변수 DATA_GO_KR_KEY (공공데이터포털 '청약홈 분양정보 조회 서비스' 활용신청 후 발급).
엔드포인트별로 실패해도 나머지는 계속 수집한다.
"""
import logging
import os
from datetime import date, timedelta

import requests

from .base import UA, RawNotice, parse_date

log = logging.getLogger(__name__)

BASE = "https://api.odcloud.kr/api/ApplyhomeInfoDetailSvc/v1/"
# (operation, 유형 라벨) — 라벨은 분류기가 태그를 붙일 때 제목과 함께 쓰인다.
ENDPOINTS = [
    ("getAPTLttotPblancDetail", "APT 분양"),
    ("getRemndrLttotPblancDetail", "APT 무순위 잔여세대"),
    ("getOPTLttotPblancDetail", "임의공급 무순위"),
    ("getUrbtyOfctlLttotPblancDetail", "오피스텔 도시형 분양"),
    ("getPblPvtRentLttotPblancDetail", "공공지원 민간임대"),
]


def _pick(row: dict, *keys: str) -> str:
    for k in keys:
        v = row.get(k)
        if v:
            return str(v)
    return ""


def _to_int(v) -> int | None:
    try:
        return int(str(v).replace(",", "").strip())
    except (TypeError, ValueError):
        return None


def _to_float(v) -> float | None:
    try:
        return float(str(v).replace(",", "").strip())
    except (TypeError, ValueError):
        return None


def parse_types(rows: list[dict]) -> list[dict]:
    """주택형별 응답(항목마다 필드명이 다름)을 한 형태로 맞춘다.
    면적 ㎡, 금액 만원, 세대수는 정수. 알 수 없는 값은 None."""
    out = []
    for r in rows:
        ty = _pick(r, "TP", "HOUSE_TY").strip()
        excl = _to_float(r.get("EXCLUSE_AR"))
        if excl is None:  # HOUSE_TY 는 '074.9823B' 처럼 앞쪽 숫자가 전용면적
            head = "".join(ch for ch in _pick(r, "HOUSE_TY") if ch.isdigit() or ch == ".")
            excl = _to_float(head)
        general = _to_int(_pick(r, "SUPLY_HSHLDCO", "GNSPLY_HSHLDCO"))
        special = _to_int(r.get("SPSPLY_HSHLDCO"))
        if special is None:
            parts = [_to_int(v) for k, v in r.items() if k.startswith("SPSPLY_") and k.endswith("_HSHLDCO")]
            special = sum(p for p in parts if p) if any(p is not None for p in parts) else None
        out.append({
            "type": ty,
            "exclusive_area": round(excl, 2) if excl is not None else None,
            "supply_area": round(_to_float(r.get("SUPLY_AR")), 2) if _to_float(r.get("SUPLY_AR")) is not None else None,
            "price_man": _to_int(_pick(r, "LTTOT_TOP_AMOUNT", "SUPLY_AMOUNT")),
            "general": general,
            "special": special,
            "total": (general or 0) + (special or 0) if (general is not None or special is not None) else None,
        })
    return out


def fetch_types(op: str, manage_no: str, pblanc_no: str, key: str | None = None) -> list[dict]:
    """공고 하나의 주택형별 상세. op 는 수집 때 쓴 '...Detail' 이름."""
    key = key or os.environ.get("DATA_GO_KR_KEY", "")
    if not key:
        raise RuntimeError("DATA_GO_KR_KEY 없음")
    r = requests.get(BASE + op.replace("Detail", "Mdl"), headers=UA, timeout=20, params={
        "serviceKey": key, "page": 1, "perPage": 100,
        "cond[HOUSE_MANAGE_NO::EQ]": manage_no, "cond[PBLANC_NO::EQ]": pblanc_no,
    })
    r.raise_for_status()
    return parse_types(r.json().get("data", []))


def parse_rows(rows: list[dict], label: str, op: str) -> list[RawNotice]:
    out = []
    for r in rows:
        manage_no = _pick(r, "HOUSE_MANAGE_NO")
        pblanc_no = _pick(r, "PBLANC_NO")
        name = _pick(r, "HOUSE_NM")
        if not (manage_no and name):
            continue
        out.append(RawNotice(
            source="APPLYHOME",
            ext_id=f"{op}:{manage_no}:{pblanc_no}",
            title=name,
            type_text=f"{label} {_pick(r, 'HOUSE_SECD_NM', 'HOUSE_DTL_SECD_NM')}",
            region=_pick(r, "SUBSCRPT_AREA_CODE_NM"),
            announce_date=parse_date(_pick(r, "RCRIT_PBLANC_DE")),
            apply_end=parse_date(_pick(r, "RCEPT_ENDDE", "SUBSCRPT_RCEPT_ENDDE", "GNRL_RCEPT_ENDDE")),
            url=_pick(r, "PBLANC_URL") or "https://www.applyhome.co.kr",
            extra={
                "op": op, "manage_no": manage_no, "pblanc_no": pblanc_no,
                "apply_start": parse_date(_pick(r, "RCEPT_BGNDE", "SUBSCRPT_RCEPT_BGNDE", "GNRL_RCEPT_BGNDE")),
                "winner_date": parse_date(_pick(r, "PRZWNER_PRESNATN_DE")),
                "contract_start": parse_date(_pick(r, "CNTRCT_CNCLS_BGNDE")),
                "address": _pick(r, "HSSPLY_ADRES"),
                "total_households": _to_int(r.get("TOT_SUPLY_HSHLDCO")),
                "builder": _pick(r, "CNSTRCT_ENTRPS_NM"),
                "sponsor": _pick(r, "BSNS_MBY_NM"),
                "tel": _pick(r, "MDHS_TELNO"),
                "homepage": _pick(r, "HMPG_ADRES"),
                "move_in_ym": _pick(r, "MVN_PREARNGE_YM"),
            },
        ))
    return out


def fetch_endpoint(op: str, key: str, since: date, per_page: int = 100, max_pages: int = 5) -> list[dict]:
    rows: list[dict] = []
    for page in range(1, max_pages + 1):
        r = requests.get(BASE + op, headers=UA, timeout=20, params={
            "serviceKey": key, "page": page, "perPage": per_page,
            "cond[RCRIT_PBLANC_DE::GTE]": since.isoformat(),
        })
        r.raise_for_status()
        body = r.json()
        data = body.get("data", [])
        rows += data
        # totalCount는 날짜 필터와 무관한 전체 건수라 쓰지 않는다. 짧은 페이지면 끝.
        if len(data) < per_page:
            break
    return rows


def collect(days: int = 60) -> list[RawNotice]:
    key = os.environ.get("DATA_GO_KR_KEY", "")
    if not key:
        log.warning("DATA_GO_KR_KEY 없음 → 청약홈 수집 건너뜀")
        return []
    since = date.today() - timedelta(days=days)
    out: list[RawNotice] = []
    for op, label in ENDPOINTS:
        try:
            # 서버측 날짜 필터가 항목마다 다르게 동작해서 클라이언트에서도 거른다.
            out += [n for n in parse_rows(fetch_endpoint(op, key, since), label, op)
                    if n.announce_date is None or n.announce_date >= since]
        except Exception:
            log.exception("applyhome %s failed", op)
    return out
