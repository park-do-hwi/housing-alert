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
            extra={"files_ref": {"src": "SH", "seq": m.group(1)}},
        ))
    return out


def collect(pages: int = 3) -> list[RawNotice]:
    """한 페이지에 10건뿐이라 몰려 올라온 날에도 놓치지 않게 앞 몇 페이지를 본다."""
    out: list[RawNotice] = []
    seen: set[str] = set()
    for p in range(1, pages + 1):
        try:
            rows = parse(fetch(SH_LIST if p == 1 else f"{SH_LIST}?page={p}"))
        except Exception:  # noqa: BLE001
            if p == 1:
                raise
            break
        new = [n for n in rows if n.ext_id not in seen]
        if not new:
            break
        seen.update(n.ext_id for n in new)
        out += new
    return out
