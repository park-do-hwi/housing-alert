"""GH(경기주택도시공사) 분양·임대 공고 게시판.

목록 한 번으로 제목·등록일·첨부파일(PDF·HWP)까지 나온다. 공고 전용 게시판이라
'주택' 구분만 쓰고 택지·산업단지는 뺀다. 접수 마감일은 목록에 없다(원문 공고에 있다).
"""
import re
from urllib.parse import urljoin

from bs4 import BeautifulSoup

from .base import RawNotice, fetch, parse_date

GH_LIST = "https://gh.or.kr/gh/announcement-of-salerental001.do"
MAX_FILES = 8
_RANK = {".pdf": 0, ".hwp": 1, ".hwpx": 1}


def _rank(name: str) -> int:
    n = name.lower()
    return next((r for ext, r in _RANK.items() if n.endswith(ext)), 9)


def _file_name(a) -> str:
    img = a.find("img")
    if img and img.get("alt"):
        name = re.sub(r"\s*-\s*다운로드\s*$", "", img["alt"])
    else:
        for s in a.select(".sr-only"):
            s.extract()
        name = a.get_text(" ", strip=True)
    return re.sub(r"\s+", " ", name).strip()


def _parse_date(text: str):
    """'26.11.06'(연 두 자리) 도 읽는다."""
    m = re.fullmatch(r"\s*(\d{2})\.(\d{1,2})\.(\d{1,2})\s*", text or "")
    return parse_date(f"20{m[1]}.{m[2]}.{m[3]}") if m else parse_date(text)


def parse(html: str) -> list[RawNotice]:
    soup = BeautifulSoup(html, "html.parser")
    out = []
    for tr in soup.select("table.board-list-table tbody tr"):
        a = tr.select_one("td.title a[href*='articleNo=']")
        cat = tr.select_one("td.category")
        if not a or (cat and cat.get_text(strip=True) != "주택"):
            continue
        m = re.search(r"articleNo=(\d+)", a["href"])
        if not m:
            continue
        files, seen = [], set()
        for d in tr.select("td.attach a[href*='mode=download'], .modal-body a[href*='mode=download']"):
            url = urljoin(GH_LIST, d["href"])
            name = _file_name(d)
            if name and url not in seen:
                seen.add(url)
                files.append({"name": name, "url": url, "size": None})
        files = sorted(files, key=lambda f: _rank(f["name"]))[:MAX_FILES]
        date_td = tr.select_one("td.date")
        extra = {"files": files} if files else {}
        out.append(RawNotice(
            source="GH",
            ext_id=m.group(1),
            title=re.sub(r"\s+", " ", a.get_text(" ", strip=True)),
            region="경기",
            announce_date=_parse_date(date_td.get_text(strip=True)) if date_td else None,
            url=urljoin(GH_LIST, a["href"]),
            extra=extra,
        ))
    return out


def collect() -> list[RawNotice]:
    return parse(fetch(GH_LIST + "?article.offset=0&articleLimit=100"))
