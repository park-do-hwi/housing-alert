"""공고와 관련된 유튜브 영상: 카카오 동영상 검색(vclip)에서 유튜브 영상만 고른다."""
import re

import requests

from .geo import search_query

_YT = re.compile(r"^https?://(www\.)?(youtube\.com/watch|youtu\.be/|m\.youtube\.com/watch)", re.I)


def search_videos(item: dict, key: str | None = None, limit: int = 4) -> list[dict]:
    import os

    key = key or os.environ.get("KAKAO_REST_KEY")
    q = search_query(item.get("title", ""))
    if not key or len(q.replace(" ", "")) < 3:
        return []
    kind = "임대" if item.get("category") in ("임대", "장기전세") else "분양"
    r = requests.get("https://dapi.kakao.com/v2/search/vclip",
                     params={"query": f"{q} {kind}", "size": 15, "sort": "accuracy"},
                     headers={"Authorization": f"KakaoAK {key}"}, timeout=10)
    r.raise_for_status()
    key_words = [w for w in q.split() if len(w) >= 2][:2]
    out, seen = [], set()
    for d in r.json().get("documents", []):
        u, th, t = d.get("url") or "", d.get("thumbnail") or "", re.sub(r"<[^>]+>", "", d.get("title") or "")
        if not _YT.match(u) or not th.startswith("https://") or u in seen:
            continue
        from .news import _PROMO, TRUSTED

        if not TRUSTED.search(d.get("author") or "") or _PROMO.search(t):  # 공식 기관·언론사 채널만
            continue
        if key_words and not any(w in t for w in key_words):  # 단지 이름이 제목에 있는 영상만
            continue
        seen.add(u)
        out.append({"t": t[:60], "u": u, "img": th})
        if len(out) >= limit:
            break
    return out
