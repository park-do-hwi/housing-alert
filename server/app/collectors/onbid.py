"""온비드 공매 물건(한국자산관리공사, 공공데이터포털 '캠코공매물건조회서비스'): 주거용 건물 매각 물건.

공매는 법원경매와 다른 제도이고 입찰은 온비드(onbid.co.kr)에서 한다. 앱에는 목록만 보여주고 원문으로 연결한다.
"""
import os
import xml.etree.ElementTree as ET
from datetime import date

import requests

URL = "http://openapi.onbid.co.kr/openapi/services/KamcoPblsalThingInquireSvc/getKamcoPbctCltrList"
SIDOS = ["서울특별시", "부산광역시", "대구광역시", "인천광역시", "광주광역시", "대전광역시", "울산광역시", "세종특별자치시",
         "경기도", "강원특별자치도", "충청북도", "충청남도", "전북특별자치도", "전라남도", "경상북도", "경상남도", "제주특별자치도"]


def _num(s):
    try:
        return int(float(str(s).replace(",", "").strip()))
    except (TypeError, ValueError):
        return None


def _day(s: str | None) -> str:
    s = (s or "").strip()
    return f"{s[:4]}-{s[4:6]}-{s[6:8]}" if len(s) >= 8 and s[:8].isdigit() else ""


def parse(xml_text: str) -> list[dict]:
    root = ET.fromstring(xml_text)
    out = []
    for it in root.iter("item"):
        g = lambda k: (it.findtext(k) or "").strip()  # noqa: E731
        name = g("CLTR_NM")
        if not name:
            continue
        no, hstr = g("CLTR_NO"), g("CLTR_HSTR_NO")
        link = ("https://www.onbid.co.kr/op/cta/cltrdtl/collateralRealEstateDetail.do?"
                f"cltrHstrNo={hstr}&cltrNo={no}&plnmNo={g('PLNM_NO')}&pbctNo={g('PBCT_NO')}&scrnGrpCd={g('SCRN_GRP_CD') or '0001'}"
                f"&pbctCdtnNo={g('PBCT_CDTN_NO')}")
        img = ""
        for e in it.iter("CLTR_IMG_FILE"):
            if (e.text or "").startswith("http"):
                img = e.text.strip()
                break
        out.append({
            "id": f"{no}-{g('PBCT_NO')}",
            "t": name,
            "cat": g("CTGR_FULL_NM"),
            "min": _num(g("MIN_BID_PRC") or g("LOW_BID_PRC")),
            "apsl": _num(g("APSL_ASES_AVG_AMT") or g("APSL_ASES_AMT")),
            "beg": _day(g("PBCT_BEGN_DTM")),
            "end": _day(g("PBCT_CLS_DTM")),
            "u": link,
            "img": img,
        })
    return out


def fetch(key: str | None = None, today: date | None = None, per_sido: int = 60) -> list[dict]:
    """시·도마다 주거용 건물 매각 물건 최대 per_sido 건. 입찰이 끝난 것은 뺀다."""
    key = key or os.environ.get("DATA_GO_KR_KEY")
    today = today or date.today()
    items: list[dict] = []
    ok = False
    for sido in SIDOS:
        try:
            r = requests.get(URL, params={"ServiceKey": key, "numOfRows": per_sido, "pageNo": 1, "DPSL_MTD_CD": "0001",
                                          "CTGR_HIRK_ID": "10000", "CTGR_HIRK_ID_MID": "10200", "SIDO": sido}, timeout=25)
            r.raise_for_status()
            got = parse(r.text)
            ok = True
        except Exception as e:  # 한 곳이 실패해도 나머지는 계속
            print(f"공매 {sido} 실패:", e)
            continue
        for g in got:
            g["sido"] = sido
            if not g["end"] or g["end"] >= today.isoformat():
                items.append(g)
    if not ok:
        raise RuntimeError("공매 API 호출이 모두 실패했습니다(활용신청·키 확인)")
    items.sort(key=lambda x: x["end"] or "9999")
    return items
