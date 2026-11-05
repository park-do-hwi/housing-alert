import re

from bs4 import BeautifulSoup

from .base import RawNotice, fetch, parse_date

LH_LIST = "https://apply.lh.or.kr/lhapply/apply/wt/wrtanc/selectWrtancList.do?mi=1026"


def parse(html: str) -> list[RawNotice]:
    soup = BeautifulSoup(html, "html.parser")
    out = []
    for tr in soup.select("tbody tr"):
        a = tr.select_one("a.wrtancInfoBtn")
        if not a:
            continue
        tds = [td.get_text(" ", strip=True) for td in tr.find_all("td")]
        title = re.sub(r"\s+", " ", a.get_text(" ", strip=True))
        title = re.sub(r"\s*\d+(일|시간|분)전$", "", title)  # '1일전' 배지 제거
        extra = {"status": tds[7] if len(tds) > 7 else ""}
        f = tr.select_one("a.listFileDown")  # 첨부 목록을 부르는 데 필요한 값
        if f:
            extra["files_ref"] = {"src": "LH", "p": [
                f.get("data-id1", ""), f.get("data-id2", ""), f.get("data-id3", ""),
                f.get("data-id4", ""), f.get("data-id5", "")]}
        out.append(RawNotice(
            source="LH",
            ext_id=a.get("data-id1") or title,
            title=title,
            type_text=tds[1] if len(tds) > 1 else "",
            region=tds[3] if len(tds) > 3 else "",
            announce_date=parse_date(tds[5]) if len(tds) > 5 else None,
            apply_end=parse_date(tds[6]) if len(tds) > 6 else None,
            url=LH_LIST,  # 상세는 JS 호출이라 목록으로 연결
            extra=extra,
        ))
    return out


def collect() -> list[RawNotice]:
    return parse(fetch(LH_LIST))
