"""분양 홈페이지(청약홈 공고의 홈페이지 주소)에서 대표 이미지(og:image) 주소를 찾는다.

이미지를 내려받아 저장하지는 않는다. 원본 주소만 알려 주고, 앱이 그 주소에서 직접 불러 보여 준다.
로고·공유용 아이콘처럼 보이는 것은 걸러낸다: 사진 확장자(jpg/webp)만, https 만, 파일 크기 30KB 이상만,
이름에 logo/favicon/sns/icon/banner 가 든 것은 제외.
"""
import logging
import re
from urllib.parse import urljoin, urlparse

import requests

log = logging.getLogger(__name__)
UA = {"User-Agent": "Mozilla/5.0 (compatible; CheongyakRadar/1.0)"}
BAD = re.compile(r"logo|favicon|sns|icon|banner|share|kakao|naver|default|noimage|blank", re.I)
OG = [
    re.compile(r'<meta[^>]+property=["\']og:image["\'][^>]+content=["\']([^"\']+)', re.I),
    re.compile(r'<meta[^>]+content=["\']([^"\']+)["\'][^>]+property=["\']og:image', re.I),
]
MIN_BYTES = 30 * 1024


def pick_image(html: str, base_url: str) -> str | None:
    """HTML 에서 쓸 만한 대표 이미지 주소. 없으면 None."""
    for rx in OG:
        m = rx.search(html)
        if not m:
            continue
        url = urljoin(base_url, m.group(1).strip())
        p = urlparse(url)
        if p.scheme != "https":
            return None
        if not re.search(r"\.(jpe?g|webp)(\?|$)", p.path + ("?" + p.query if p.query else ""), re.I):
            return None
        if BAD.search(p.path):
            return None
        return url
    return None


def find_photo(homepage: str) -> str | None:
    if not homepage or "apply.lh.or.kr" in homepage:
        return None
    url = homepage if homepage.startswith("http") else "http://" + homepage
    r = requests.get(url, headers=UA, timeout=8)
    r.encoding = r.apparent_encoding or r.encoding
    img = pick_image(r.text, r.url)
    if not img:
        return None
    h = requests.head(img, headers=UA, timeout=8, allow_redirects=True)
    ctype = h.headers.get("Content-Type", "")
    size = int(h.headers.get("Content-Length", "0") or 0)
    if h.status_code != 200 or not ctype.startswith("image/") or size < MIN_BYTES:
        return None
    return str(h.url) if str(h.url).startswith("https") else img


def is_map_like(url: str) -> bool:
    """지도·도면 같은 그림인지(조감도 사진이 아닌지). 색이 아주 선명한 픽셀이 많으면 지도로 본다.
    (실제 단지 사진은 선명한 픽셀이 10% 안쪽, 지구 위치 지도는 20% 넘게 나왔다.)"""
    import io

    from PIL import Image

    r = requests.get(url, headers=UA, timeout=10)
    r.raise_for_status()
    im = Image.open(io.BytesIO(r.content)).convert("HSV").resize((64, 64))
    vivid = sum(1 for _, s, v in im.getdata() if s > 140 and v > 150) / 4096
    return vivid > 0.15


def search_plan(item: dict, type_label: str = "", key: str | None = None):
    """평면도(참고): '단지명 [84A] 평면도' 이미지 검색 결과."""
    return search_photo(item, key, kind=f"{type_label} 평면도".strip())


def search_photo(item: dict, key: str | None = None, kind: str = "조감도") -> tuple[str, str | None] | None:
    """홈페이지에서 못 찾은 단지: 카카오 이미지 검색으로 '단지명 조감도' 의 첫 쓸 만한 결과. (썸네일 주소, 원본 주소)."""
    import os
    from .geo import search_query

    key = key or os.environ.get("KAKAO_REST_KEY")
    q = search_query(item.get("title", ""))
    if not key or len(q.replace(" ", "")) < 3:
        return None
    r = requests.get("https://dapi.kakao.com/v2/search/image",
                     params={"query": f"{q} {kind}", "size": 10, "sort": "accuracy"},
                     headers={"Authorization": f"KakaoAK {key}"}, timeout=10)
    r.raise_for_status()
    cands = []
    for d in r.json().get("documents", []):
        th = d.get("thumbnail_url") or ""
        hi = d.get("image_url") or ""
        hi = hi if hi.startswith("https://") and re.search(r"\.(jpe?g|webp|png)(\?|$)", hi, re.I) else None
        w = d.get("width") or 0
        if th.startswith("https://") and w >= 400 and not BAD.search(d.get("image_url", "")):
            cands.append((th, hi, w))
    # 상세에서 선명하게 보이도록 큰 원본(가로 800 이상, 원본 주소 있음)을 먼저, 그 안에서는 관련도 순서 그대로
    cands.sort(key=lambda c: not (c[1] and c[2] >= 800))
    for th, hi, _ in cands:
        if kind == "조감도":
            try:
                if is_map_like(th):
                    continue
            except Exception:
                pass  # 판별 실패는 그냥 쓴다
        return th, hi
    return None
