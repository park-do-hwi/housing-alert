import re
from dataclasses import dataclass, field
from datetime import date

import requests

UA = {"User-Agent": "Mozilla/5.0 (housing-alert-app; contact via app store listing)"}


@dataclass
class RawNotice:
    source: str            # LH / SH / APPLYHOME
    ext_id: str
    title: str
    type_text: str = ""
    region: str = ""
    announce_date: date | None = None
    apply_end: date | None = None
    url: str = ""
    extra: dict = field(default_factory=dict)


def decode(content: bytes) -> str:
    for enc in ("utf-8", "cp949"):
        try:
            return content.decode(enc)
        except UnicodeDecodeError:
            continue
    return content.decode("utf-8", errors="ignore")


def fetch(url: str) -> str:
    r = requests.get(url, headers=UA, timeout=20)
    r.raise_for_status()
    return decode(r.content)


def parse_date(text: str) -> date | None:
    m = re.search(r"(\d{4})[.\-/](\d{1,2})[.\-/](\d{1,2})", text or "")         or re.fullmatch(r"\s*(\d{4})(\d{2})(\d{2})\s*", text or "")  # 20261112 형식
    if not m:
        return None
    try:
        return date(int(m[1]), int(m[2]), int(m[3]))
    except ValueError:
        return None
