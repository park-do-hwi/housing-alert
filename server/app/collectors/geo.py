"""공고 위치를 좌표로 바꾼다. 카카오 로컬 API(REST 키)를 쓴다. 키가 없으면 아무것도 하지 않는다.

 - 주소가 있으면(청약홈) 주소 검색 → 정확한 위치.
 - 주소가 없으면(LH·SH·GH) 공고 제목에서 지구·단지 이름을 뽑아 키워드 검색 → 대략적인 위치(approx).
   검색 결과의 지역이 공고의 시·도와 맞을 때만 받아들인다.
"""
import logging
import os
import re

import requests

log = logging.getLogger(__name__)
ADDRESS_URL = "https://dapi.kakao.com/v2/local/search/address.json"
KEYWORD_URL = "https://dapi.kakao.com/v2/local/search/keyword.json"

# 시·도 → 카카오 주소 앞머리
_SIDO_PREFIX = {
    "서울": "서울", "부산": "부산", "대구": "대구", "인천": "인천", "광주": "광주", "대전": "대전",
    "울산": "울산", "세종": "세종", "경기": "경기", "강원": "강원", "충북": "충북", "충남": "충남",
    "전북": "전북", "전남": "전남", "경북": "경북", "경남": "경남", "제주": "제주",
}
_NOISE = re.compile(r"\(.*?\)|\[.*?\]|\d{4}년|\d+차|\d+단지|\d+블록|[A-Z]{1,3}-?\d+(?:-\d+)?[A-Z]*|\d+[A-Z]{1,3}|"
                    r"입주자|모집|공고|공급|추가|정정|재공고|국민임대|행복주택|영구임대|매입임대|장기전세|"
                    r"무순위|사전청약|토지임대부|본청약|사전|예비입주자|분양전환|공공임대|주택|아파트|일반|예비|청년|신혼|신혼부부|"
                    r"자격완화|접수|안내|계약|잔여세대|잔여|세대|통합|및|등")


def search_query(title: str) -> str:
    q = _NOISE.sub(" ", title)
    q = re.sub(r"[^\w가-힣\s]", " ", q)
    words = [w for w in q.split() if len(w) >= 2]
    return " ".join(words[:2])


def _get(url: str, params: dict, key: str) -> list[dict]:
    r = requests.get(url, params=params, headers={"Authorization": f"KakaoAK {key}"}, timeout=10)
    r.raise_for_status()
    return r.json().get("documents", [])


def geocode(item: dict, key: str | None = None) -> dict | None:
    """{'lat','lng','approx'} 또는 None. 네트워크 오류는 예외로 올려 보낸다(호출한 쪽이 재시도 판단)."""
    key = key or os.environ.get("KAKAO_REST_KEY")
    if not key:
        return None
    sido = item.get("sido") or ""
    addr = (item.get("info") or {}).get("address")
    if addr:
        addr = re.sub(r"\(.*?\)|외\s*\d*필지|일원|일대", " ", addr).strip()
        docs = _get(ADDRESS_URL, {"query": addr, "size": 1}, key)
        if not docs:  # 번지수가 안 맞으면 동·리까지만 다시
            short = " ".join(addr.split()[:4])
            docs = _get(ADDRESS_URL, {"query": short, "size": 1}, key) if short != addr else []
        if docs:
            return {"lat": float(docs[0]["y"]), "lng": float(docs[0]["x"]), "approx": False}
    q = search_query(item.get("title", ""))
    if not q:
        return None
    docs = _get(KEYWORD_URL, {"query": f"{sido} {q}".strip(), "size": 3}, key)
    prefix = _SIDO_PREFIX.get(sido, "")
    for d in docs:
        if not prefix or (d.get("address_name") or "").startswith(prefix):
            return {"lat": float(d["y"]), "lng": float(d["x"]), "approx": True}
    return None
