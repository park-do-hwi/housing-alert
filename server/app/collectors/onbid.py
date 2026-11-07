"""온비드 공매 물건(한국자산관리공사 '차세대 온비드 부동산 물건목록 조회서비스', 공공데이터포털): 주거용 건물 매각 물건.

공매는 법원경매와 다른 제도이고 입찰은 온비드(onbid.co.kr)에서 한다. 앱에는 목록만 보여주고 원문으로 연결한다.
옛 openapi.onbid.co.kr 주소는 더 이상 응답하지 않아, 새 게이트웨이(apis.data.go.kr/B010003)를 쓴다.
"""
import os
from datetime import date

import requests

URL = "https://apis.data.go.kr/B010003/OnbidRlstListSrvc2/getRlstCltrList2"
HOUSING = "10200"  # 용도 중분류: 주거용건물


def _num(s):
    try:
        return int(float(str(s).replace(",", "").strip()))
    except (TypeError, ValueError):
        return None


def _day(s) -> str:
    s = str(s or "").strip()
    if len(s) >= 8 and s[:8].isdigit() and not s.startswith("2999"):
        return f"{s[:4]}-{s[4:6]}-{s[6:8]}"
    return ""  # 일정 미정(2999...)은 빈 값


def _rows(node) -> list[dict]:
    """응답 어디에 있든 물건 행(cltrMngNo 를 가진 dict)을 모은다."""
    if isinstance(node, dict):
        if "cltrMngNo" in node:
            return [node]
        return [r for v in node.values() for r in _rows(v)]
    if isinstance(node, list):
        return [r for v in node for r in _rows(v)]
    return []


def parse(payload: dict) -> list[dict]:
    out = []
    for r in _rows(payload):
        g = lambda k: str(r.get(k) or "").strip()  # noqa: E731
        ids = [g("onbidCltrno"), g("onbidPbancNo"), g("pbctNo"), g("pbctCdtnNo")]
        name = g("onbidCltrNm")
        if not name or not all(ids):
            continue  # 식별자가 하나라도 없으면 원문 링크가 깨진다
        link = ("https://www.onbid.co.kr/op/cltrpbancinf/cltrdtl/CltrDtlController/mvmnCltrDtl.do?"
                f"onbidCltrno={ids[0]}&onbidPbancNo={ids[1]}&pbctNo={ids[2]}&pbctCdtnNo={ids[3]}")
        img = g("thnlImgUrlAdr")
        out.append({
            "id": f"{ids[0]}-{ids[2]}",
            "t": name,
            "cat": g("cltrUsgSclsCtgrNm") or g("cltrUsgMclsCtgrNm"),
            "mid": g("cltrUsgMclsCtgrId"),
            "sido": g("lctnSdnm"),
            "min": _num(g("lowstBidPrcIndctCont")),
            "apsl": _num(g("apslEvlAmt")),
            "beg": _day(g("cltrBidBgngDt")),
            "end": _day(g("cltrBidEndDt")),
            "fail": _num(g("usbdNft")),
            "st": g("pbctStatNm"),
            "u": link,
            "img": img if img.startswith("http") else "",
        })
    return out


def check(payload: dict) -> None:
    """오류 봉투(게이트웨이/서비스)이면 이유를 담아 예외를 낸다."""
    gw = (payload.get("OpenAPI_ServiceResponse") or {}).get("cmmMsgHeader")
    if gw:
        raise RuntimeError(f"온비드 게이트웨이 오류: {gw.get('errMsg')} / {gw.get('returnAuthMsg')} (활용신청·키 확인)")
    hdr = (payload.get("response") or payload).get("header") or {}
    if hdr.get("resultCode") not in (None, "00"):
        raise RuntimeError(f"온비드 오류 {hdr.get('resultCode')}: {hdr.get('resultMsg')}")


def fetch(key: str | None = None, today: date | None = None, limit: int = 600) -> list[dict]:
    """주거용 매각 물건 중 입찰 마감일이 오늘 이후인 것을 마감 임박순으로. 일정 미정·마감된 것은 뺀다."""
    key = key or os.environ.get("DATA_GO_KR_KEY")
    today = today or date.today()
    seen: dict[str, dict] = {}
    for yn in ("N", "Y"):
        for page in range(1, 8):
            r = requests.get(URL, params={"serviceKey": key, "resultType": "json", "numOfRows": 3000, "pageNo": page,
                                          "dspsMthodCd": "0001", "pvctTrgtYn": yn}, timeout=60)
            try:
                payload = r.json()
            except ValueError:
                raise RuntimeError(f"온비드 응답을 읽지 못했어요(HTTP {r.status_code}): {r.text[:120]}")
            check(payload)
            got = parse(payload)
            body = (payload.get("response") or payload).get("body") or {}
            print(f"공매 {yn} p{page}: 응답 {len(_rows(payload))}행, 읽음 {len(got)}, 주거 {sum(g['mid'] == HOUSING for g in got)}, "
                  f"마감일 있음 {sum(bool(g['end']) for g in got)}, 전체 {body.get('totalCount')}")
            if page == 1 and not got:
                print("공매 응답 앞부분:", str(payload)[:400])
            for g in got:
                if g["mid"] == HOUSING and g["end"] and g["end"] >= today.isoformat() and g["min"]:
                    seen.setdefault(g["id"], g)
            if len(_rows(payload)) < 3000:
                break
    items = sorted(seen.values(), key=lambda x: x["end"])
    return items[:limit]
