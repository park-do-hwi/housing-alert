import re

from bs4 import BeautifulSoup

from .base import RawNotice, fetch, parse_date

SH_LIST = "https://www.i-sh.co.kr/main/lay2/program/S1T294C297/www/brd/m_241/list.do"
SH_VIEW = SH_LIST.replace("list.do", "view.do") + "?seq={seq}"


def parse(html: str) -> list[RawNotice]:
    soup = BeautifulSoup(html, "html.parser")
    out = []
    for a in soup.select("td.txtL a[onclick*=getDetailView]"):
        m = re.search(r"getDetailView\('(\d+)'\)", a.get("onclick", ""))
        if not m:
            continue
        tr = a.find_parent("tr")
        tds = tr.find_all("td")
        title = re.sub(r"\s+", " ", a.get_text(" ", strip=True))
        title = re.sub(r"^NEW\s*", "", title).strip()
        out.append(RawNotice(
            source="SH",
            ext_id=m.group(1),
            title=title,
            region="서울",
            announce_date=parse_date(tds[-2].get_text(strip=True)) if len(tds) >= 2 else None,
            url=SH_VIEW.format(seq=m.group(1)),
        ))
    return out


def collect() -> list[RawNotice]:
    return parse(fetch(SH_LIST))
