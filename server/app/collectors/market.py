"""주변 시세(참고): 국토부 아파트 매매 실거래가로 같은 시·군·구의 최근 3개월 평균을 계산한다.

공고 위치(위도·경도)에서 카카오로 시·군·구 코드(법정동 앞 5자리)를 얻고, 그 코드로 실거래를 받는다.
단지 바로 옆이 아니라 '같은 시·군·구' 평균이라 참고용이다.
"""
import os
import statistics
import xml.etree.ElementTree as ET
from datetime import date

import requests

COORD_URL = "https://dapi.kakao.com/v2/local/geo/coord2regioncode.json"
TRADE_URL = "https://apis.data.go.kr/1613000/RTMSDataSvcAptTrade/getRTMSDataSvcAptTrade"


def sgg_of(lat: float, lng: float, key: str | None = None) -> str | None:
    key = key or os.environ.get("KAKAO_REST_KEY")
    if not key:
        return None
    r = requests.get(COORD_URL, params={"x": lng, "y": lat}, headers={"Authorization": f"KakaoAK {key}"}, timeout=10)
    r.raise_for_status()
    for d in r.json().get("documents", []):
        if d.get("region_type") == "B" and d.get("code"):
            return d["code"][:5]
    return None


def dong_of(lat: float, lng: float, key: str | None = None) -> str:
    """법정동 이름(예: 광교동). 못 찾으면 빈 문자열."""
    key = key or os.environ.get("KAKAO_REST_KEY")
    if not key:
        return ""
    r = requests.get(COORD_URL, params={"x": lng, "y": lat}, headers={"Authorization": f"KakaoAK {key}"}, timeout=10)
    r.raise_for_status()
    for d in r.json().get("documents", []):
        if d.get("region_type") == "B":
            return d.get("region_3_depth_name") or ""
    return ""


def months_back(today: date, n: int = 3) -> list[str]:
    y, m, out = today.year, today.month, []
    for _ in range(n):
        out.append(f"{y}{m:02d}")
        m -= 1
        if m == 0:
            y, m = y - 1, 12
    return out


def fetch_rows(sgg: str, ymd: str, key: str | None = None) -> list[dict]:
    """실거래 한 건씩: {dong, apt, a(전용㎡), p(만원), d(YYYYMMDD), f(층)}"""
    key = key or os.environ.get("DATA_GO_KR_KEY")
    out: list[dict] = []
    page = 1
    while page <= 5:
        r = requests.get(TRADE_URL, params={"serviceKey": key, "LAWD_CD": sgg, "DEAL_YMD": ymd,
                                            "numOfRows": 1000, "pageNo": page}, timeout=20)
        r.raise_for_status()
        root = ET.fromstring(r.content)
        for it in root.findall(".//item"):
            if (it.findtext("cdealType") or "").strip():  # 해제된 거래
                continue
            try:
                out.append({
                    "dong": (it.findtext("umdNm") or "").strip(),
                    "apt": (it.findtext("aptNm") or "").strip(),
                    "a": float(it.findtext("excluUseAr")),
                    "p": int(it.findtext("dealAmount").replace(",", "").strip()),
                    "d": f"{int(it.findtext('dealYear')):04d}{int(it.findtext('dealMonth')):02d}{int(it.findtext('dealDay')):02d}",
                    "f": (it.findtext("floor") or "").strip(),
                })
            except (TypeError, ValueError, AttributeError):
                continue
        total = int(root.findtext(".//totalCount") or 0)
        if page * 1000 >= total:
            break
        page += 1
    return out


def fetch_trades(sgg: str, ymd: str, key: str | None = None) -> list[tuple[float, int]]:
    """[(전용면적㎡, 거래금액 만원)]"""
    return [(r["a"], r["p"]) for r in fetch_rows(sgg, ymd, key)]


def near_trades(rows: list[dict], dong: str, limit: int = 6) -> list[dict]:
    """같은 법정동의 최근 실거래를 단지(아파트) 이름 기준으로 한 건씩, 최신순으로 고른다."""
    if not dong:
        return []
    seen, out = set(), []
    for r in sorted((r for r in rows if r.get("dong") == dong and r["a"] >= 40), key=lambda r: r["d"], reverse=True):
        key = (r["apt"], round(r["a"]))
        if not r["apt"] or key in seen:
            continue
        seen.add(key)
        out.append({"n": r["apt"], "a": round(r["a"], 1), "p": r["p"], "d": r["d"], "f": r["f"]})
        if len(out) >= limit:
            break
    return out


def summarize(trades: list[tuple[float, int]], today: date) -> dict | None:
    """{'n','per_m2'(만원/㎡ 중앙값),'avg84'(전용 80~88㎡ 평균 만원),'n84','ym'}"""
    t = [(a, p) for a, p in trades if a >= 30]
    if len(t) < 10:
        return None
    per = statistics.median(p / a for a, p in t)
    m84 = [p for a, p in t if 80 <= a <= 88]
    res = {"n": len(t), "per_m2": round(per), "ym": months_back(today)[-1] + "~" + months_back(today)[0]}
    if len(m84) >= 3:
        res["avg84"] = round(statistics.median(m84))
        res["n84"] = len(m84)
    return res


def stats_for(sgg: str, today: date) -> dict | None:
    """시·군·구 하나의 최근 3개월 실거래 요약 + 원본 행(_rows, 내보내기 전에 단지별 목록으로 바뀐다)."""
    rows = [r for ym in months_back(today) for r in fetch_rows(sgg, ym)]
    st = summarize([(r["a"], r["p"]) for r in rows], today)
    return {**st, "_rows": rows} if st else None
