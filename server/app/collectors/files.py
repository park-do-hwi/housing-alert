"""공고문 첨부 파일(PDF·HWP 등) 목록 조회: LH·SH.

두 사이트 모두 목록 화면에는 파일이 없어서 공고마다 한 번 더 요청해야 한다.
 - LH : POST /lhapply/wt/wrtanc/wrtFileDownl.do (JSON) → /lhapply/lhFile.do?fileid=<번호> 로 내려받는다.
 - SH : 공고 상세 페이지의 `initParam.downList` JSON → /main/com/file/innoFD.do?... 로 내려받는다.
둘 다 로그인 없이 받아진다. 청약홈은 API에 파일 정보가 없어 원문 공고 페이지로 연결한다.
"""
import json
import re
from urllib.parse import urlencode

import requests

from .base import UA, decode

LH_BASE = "https://apply.lh.or.kr"
LH_FILE_LIST = LH_BASE + "/lhapply/wt/wrtanc/wrtFileDownl.do"
LH_DOWNLOAD = LH_BASE + "/lhapply/lhFile.do?fileid={sn}"

SH_BASE = "https://www.i-sh.co.kr"
SH_VIEW = SH_BASE + "/main/lay2/program/S1T294C297/www/brd/m_241/view.do?seq={seq}"
SH_DOWNLOAD = SH_BASE + "/main/com/file/innoFD.do"

MAX_FILES = 8  # 한 공고에서 앱에 싣는 최대 파일 수

_ORDER = {".pdf": 0, ".hwp": 1, ".hwpx": 1}


def _rank(name: str) -> int:
    n = name.lower()
    for ext, r in _ORDER.items():
        if n.endswith(ext):
            return r
    return 9


def parse_lh(rows: list[dict]) -> list[dict]:
    out = []
    for r in rows:
        name, sn = r.get("cmnAhflNm"), r.get("cmnAhflSn")
        if not name or not sn:
            continue
        out.append({"name": name, "url": LH_DOWNLOAD.format(sn=sn), "size": r.get("cmnAhflSz")})
    return sorted(out, key=lambda f: _rank(f["name"]))[:MAX_FILES]


def parse_sh(html: str) -> list[dict]:
    m = re.search(r"initParam\.downList\s*=\s*(\[.*?\])\s*;", html, re.S)
    if not m:
        return []
    try:
        rows = json.loads(m.group(1))
    except json.JSONDecodeError:
        return []
    out = []
    for r in rows:
        name = r.get("oriFileNm")
        if not name:
            continue
        q = urlencode({"brdId": r.get("brdId", ""), "seq": r.get("seq", ""),
                       "fileTp": r.get("fileTp", ""), "fileSeq": r.get("fileSeq", "")})
        out.append({"name": name, "url": f"{SH_DOWNLOAD}?{q}",
                    "size": int(r["fileSize"]) if str(r.get("fileSize", "")).isdigit() else None})
    return sorted(out, key=lambda f: _rank(f["name"]))[:MAX_FILES]


def fetch_files(fref: dict) -> list[dict]:
    """fref 는 목록 수집 때 만든 참조. 반환: [{name, url, size}] (없으면 빈 목록)."""
    src = fref.get("src")
    if src == "LH":
        p = fref["p"]  # [uppAisTpCd, aisTpCd, ccrCnntSysDsCd, lsSst, panId]
        data = {"uppAisTpCd1": p[0], "aisTpCd1": p[1], "ccrCnntSysDsCd1": p[2],
                "lsSst1": p[3], "panId1": p[4]}
        r = requests.post(LH_FILE_LIST, data=data, headers=UA, timeout=20)
        r.raise_for_status()
        return parse_lh(json.loads(decode(r.content)))
    if src == "SH":
        r = requests.get(SH_VIEW.format(seq=fref["seq"]), headers=UA, timeout=20)
        r.raise_for_status()
        return parse_sh(decode(r.content))
    return []
