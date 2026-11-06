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


def months_back(today: date, n: int = 3) -> list[str]:
    y, m, out = today.year, today.month, []
    for _ in range(n):
        out.append(f"{y}{m:02d}")
        m -= 1
        if m == 0:
            y, m = y - 1, 12
    return out


def fetch_trades(sgg: str, ymd: str, key: str | None = None) -> list[tuple[float, int]]:
    """[(전용면적㎡, 거래금액 만원)]"""
    key = key or os.environ.get("DATA_GO_KR_KEY")
    out: list[tuple[float, int]] = []
    page = 1
    while page <= 5:
        r = requests.get(TRADE_URL, params={"serviceKey": key, "LAWD_CD": sgg, "DEAL_YMD": ymd,
                                            "numOfRows": 1000, "pageNo": page}, timeout=20)
        r.raise_for_status()
        root = ET.fromstring(r.content)
        items = root.findall(".//item")
        for it in items:
            if (it.findtext("cdealType") or "").strip():  # 해제된 거래
                continue
            try:
                out.append((float(it.findtext("excluUseAr")), int(it.findtext("dealAmount").replace(",", "").strip())))
            except (TypeError, ValueError, AttributeError):
                continue
        total = int(root.findtext(".//totalCount") or 0)
        if page * 1000 >= total:
            break
        page += 1
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
