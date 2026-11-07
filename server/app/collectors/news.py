"""부동산 뉴스: 구글 뉴스 RSS(키 없이 사용 가능)에서 청약·분양·임대 관련 기사를 모은다."""
import re
import xml.etree.ElementTree as ET
from email.utils import parsedate_to_datetime
from urllib.parse import quote

import requests

QUERIES = ["청약 분양", "공공임대 LH SH", "부동산 정책 주택공급"]


def parse(xml_text: str) -> list[dict]:
    out = []
    for it in ET.fromstring(xml_text).iter("item"):
        title = (it.findtext("title") or "").strip()
        link = (it.findtext("link") or "").strip()
        src = (it.findtext("source") or "").strip()
        if " - " in title:  # 구글 뉴스는 제목 끝에 " - 언론사"를 붙인다
            title = title.rsplit(" - ", 1)[0]
        try:
            at = parsedate_to_datetime(it.findtext("pubDate") or "").isoformat()
        except Exception:
            at = ""
        if title and link.startswith("http"):
            out.append({"t": re.sub(r"\s+", " ", title), "u": link, "s": src, "at": at})
    return out


def fetch(limit: int = 40) -> list[dict]:
    seen, items = set(), []
    for q in QUERIES:
        url = f"https://news.google.com/rss/search?q={quote(q)}+when:3d&hl=ko&gl=KR&ceid=KR:ko"
        r = requests.get(url, timeout=15, headers={"User-Agent": "Mozilla/5.0"})
        r.raise_for_status()
        for n in parse(r.text):
            if n["t"] not in seen:
                seen.add(n["t"])
                items.append(n)
    items = [n for n in items if _ON_TOPIC.search(n["t"]) and not _OFF.search(n["t"])]
    items.sort(key=lambda x: x["at"], reverse=True)
    return items[:limit]


_ON_TOPIC = re.compile(r"청약|분양|임대|LH|SH|공공|행복주택|무순위|특별공급|당첨|입주|주택공급|공공주택|전세|신혼|재건축|재개발")
_OFF = re.compile(r"비트코인|코인|주식|오피스텔 투자|경매 강의")
VIDEO_QUERIES = ["청약 분양 정보", "공공임대 신청 방법", "부동산 청약 가이드"]


def fetch_videos(key: str, limit: int = 12) -> list[dict]:
    """분양·임대 정보 유튜브 영상(카카오 동영상 검색에서 유튜브만)."""
    from .videos import _YT

    seen, out = set(), []
    for q in VIDEO_QUERIES:
        r = requests.get("https://dapi.kakao.com/v2/search/vclip", params={"query": q, "size": 10, "sort": "accuracy"},
                         headers={"Authorization": f"KakaoAK {key}"}, timeout=10)
        r.raise_for_status()
        for d in r.json().get("documents", []):
            u, th = d.get("url") or "", d.get("thumbnail") or ""
            t = re.sub(r"<[^>]+>", "", d.get("title") or "")
            if _YT.match(u) and th.startswith("https://") and u not in seen and _ON_TOPIC.search(t) and not _OFF.search(t):
                seen.add(u)
                out.append({"t": t[:70], "u": u, "img": th, "s": d.get("author") or "",
                            "at": d.get("datetime") or ""})
    return out[:limit]
