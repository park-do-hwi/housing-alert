"""공고문 PDF 첨부에서 주택형·모집 세대수를 읽는다(LH·SH·GH처럼 주택형 정보가 따로 없는 공고용).

표를 못 찾거나 읽을 수 없으면 빈 목록을 돌려주고, 앱은 그 공고에서 해당 칸을 보여주지 않는다.
"""
import re

import requests

_TYPE = re.compile(r"주택\s*형|공급\s*형별")
_COUNT = re.compile(r"모집\s*호수|모집\s*할|모집\s*예비자|공급\s*가능|공급\s*호수|공급\s*세대|세대\s*수|모집\s*세대")
_EXCL = re.compile(r"주거\s*전용|전용\s*면적")
_LABEL = re.compile(r"주택\s*타입|타입")


def _clean(c) -> str:
    return re.sub(r"\s+", "", str(c or ""))


def _area(cell: str) -> float | None:
    """'0748500A .' → 74.85, '3528.(14평)' → 35.28, '49A' → 49. PDF에서 소수점이 빠져 있다."""
    m = re.match(r"^(\d+)", cell.replace(" ", ""))
    if not m:
        return None
    d = m.group(1)
    if len(d) >= 6:
        return float(f"{int(d[:3])}.{d[3:]}")
    if len(d) in (4, 5):
        v = int(d) / 100
        return v if 10 <= v <= 150 else None
    n = int(d)
    return float(n) if 10 <= n <= 300 else None


def _label(raw: str, area: float | None) -> str:
    raw = raw.replace(" ", "")
    m = re.match(r"^\d+\.?([A-Za-z]\w*)?", raw)
    letters = (m.group(1) or "") if m else ""
    if len(re.match(r"^\d+", raw).group(0)) >= 4 and area:
        return f"{area:g}{letters}"
    return re.sub(r"[ .,\-]+$|[ .,]", "", raw)


def _int(s: str) -> int | None:
    s = re.sub(r"[^0-9]", "", s)
    return int(s) if s else None


def parse_table(rows: list[list]) -> list[dict]:
    """한 표에서 [{type, exclusive_area, total}]. 주택형·모집(공급) 호수 열이 없으면 빈 목록."""
    rows = [[_clean(c) for c in r] for r in rows]
    h = next((i for i, r in enumerate(rows[:4]) if any(_TYPE.search(c) for c in r)), None)
    if h is None:
        return []
    head = rows[h:h + 3]
    width = max(len(r) for r in head)
    tcol = next((j for r in head for j, c in enumerate(r) if _TYPE.search(c)), None)
    ccol = next((j for r in head for j, c in enumerate(r) if _COUNT.search(c)), None)
    ecol = next((j for r in head for j, c in enumerate(r) if _EXCL.search(c)), None)
    if tcol is None or ccol is None or ccol >= width:
        return []
    lcol = next((j for r in head for j, c in enumerate(r) if _LABEL.search(c)), None)
    out, seen = [], set()
    body_start = h + 1
    while body_start < len(rows) and not any(re.search(r"\d", c) for c in rows[body_start]):
        body_start += 1
    for r in rows[body_start:]:
        if len(r) <= max(tcol, ccol):
            continue
        raw = r[tcol]
        n = _int(r[ccol])
        if not raw or not n or not re.match(r"^\d", raw):
            continue
        area = _area(raw)
        if ecol is not None and ecol < len(r) and _area(r[ecol]):
            area = _area(r[ecol])
        m = re.match(r"^(\d{2,3})(?!\d)", raw)
        if m and area and abs(area - int(m.group(1))) > 3:
            area = float(m.group(1))  # 소수점 복원이 주택형 숫자와 크게 어긋나면 주택형 숫자를 쓴다
        label = r[lcol] if lcol is not None and lcol < len(r) and r[lcol] else _label(raw, area)
        key = (label, area)
        if key in seen:
            continue
        seen.add(key)
        out.append({"type": label, "exclusive_area": area, "supply_area": None, "price_man": None,
                    "general": None, "special": None, "total": n})
    return out


def extract_types(files: list[dict], max_mb: float = 8, max_pages: int = 16) -> list[dict]:
    """공고문 PDF(이름에 공고·모집·안내가 든 것 먼저)를 내려받아 표에서 주택형·세대수를 읽는다."""
    import pymupdf

    pdfs = [f for f in files if (f.get("name") or "").lower().endswith(".pdf") and (f.get("size") or 0) < max_mb * 1e6]
    pdfs.sort(key=lambda f: not re.search(r"공고|모집|안내", f.get("name") or ""))
    for f in pdfs[:2]:
        try:
            r = requests.get(f["url"], timeout=40, headers={"User-Agent": "Mozilla/5.0"})
            if r.content[:4] != b"%PDF":
                continue
            doc = pymupdf.open(stream=r.content, filetype="pdf")
        except Exception:
            continue
        for pi, pg in enumerate(doc):
            if pi >= max_pages:
                break
            try:
                tables = pg.find_tables().tables
            except Exception:
                continue
            for t in tables:
                got = parse_table(t.extract())
                if got:
                    return got
    return []
