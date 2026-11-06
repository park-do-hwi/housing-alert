from datetime import date
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.pool import StaticPool
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app import api, db
from app.classify import pushable, sido_for, tags_for
from app.collectors import lh, sh
from app.collectors.base import RawNotice, decode
from app.ingest import upsert
from app.models import Device, Notice, Subscription
from app.push import notify_new, notify_reminders

FIX = Path(__file__).parent / "fixtures"


class Capture:
    def __init__(self):
        self.sent = []

    def send(self, token, title, body, data):
        self.sent.append((token, title, body, data))


@pytest.fixture()
def session():
    eng = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    db.init_db(eng)
    S = sessionmaker(bind=eng, expire_on_commit=False)
    with S() as s:
        yield s


# ---- 파서 (실제 페이지 스냅샷) ----
def test_lh_parser():
    items = lh.parse(decode((FIX / "lh_list.html").read_bytes()))
    assert len(items) >= 10
    a = items[0]
    assert a.source == "LH" and a.ext_id and a.title and a.announce_date and a.apply_end
    assert "전" not in a.title[-3:] or not a.title.endswith("일전")


def test_sh_parser():
    items = sh.parse(decode((FIX / "sh_list.html").read_bytes()))
    assert len(items) >= 5
    assert all(i.source == "SH" and i.ext_id.isdigit() and i.title for i in items)
    assert not any(i.title.startswith("NEW") for i in items)


# ---- 분류 ----
def test_classify():
    assert "장기전세" in tags_for("제50차 장기전세주택1 모집")
    assert {"무순위", "분양"} <= set(tags_for("OO단지 무순위 공공분양 모집"))
    assert "결과" in tags_for("장기전세 당첨자 발표")
    assert not pushable(tags_for("장기전세 당첨자 발표"))
    assert not pushable(tags_for("용역 입찰 공고"))
    assert sido_for("경기도") == "경기" and sido_for("서울특별시") == "서울" and sido_for("충청남도") == "충남"


# ---- 수집 → 저장 → 변경 감지 ----
def test_upsert_new_then_changed(session):
    r = RawNotice("LH", "1", "A단지 무순위 모집", region="경기도", apply_end=date(2026, 12, 1))
    new, ch = upsert(session, [r])
    assert len(new) == 1 and not ch
    new, ch = upsert(session, [r])
    assert not new and not ch
    r2 = RawNotice("LH", "1", "A단지 무순위 모집", region="경기도", apply_end=date(2026, 12, 5))
    new, ch = upsert(session, [r2])
    assert not new and len(ch) == 1


# ---- 푸시 ----
def _sub(session, **kw):
    dev = Device(fcm_token="tok-abcdefgh", platform="android")
    session.add(dev)
    session.flush()
    session.add(Subscription(device_id=dev.id, **kw))
    session.commit()


def test_push_matching_and_dedup(session):
    _sub(session, sido=["서울"], categories=["장기전세"])
    new, _ = upsert(session, [
        RawNotice("SH", "10", "제51차 장기전세주택 모집", region="서울"),
        RawNotice("SH", "11", "제50차 장기전세주택 당첨자 발표", region="서울"),   # 결과 → 제외
        RawNotice("LH", "12", "OO 무순위 공공분양", region="경기도"),               # 지역 불일치
    ])
    cap = Capture()
    assert notify_new(session, cap, new) == 1
    assert notify_new(session, cap, new) == 0  # 중복 방지
    assert len(cap.sent) == 1


def test_reminder(session):
    _sub(session)
    upsert(session, [RawNotice("LH", "20", "OO 행복주택 입주자 모집", region="서울", apply_end=date(2026, 11, 8))])
    cap = Capture()
    assert notify_reminders(session, cap, today=date(2026, 11, 5)) == 1   # D-3
    assert notify_reminders(session, cap, today=date(2026, 11, 5)) == 0
    assert notify_reminders(session, cap, today=date(2026, 11, 7)) == 1   # D-1
    assert notify_reminders(session, cap, today=date(2026, 11, 6)) == 0   # D-2는 대상 아님


# ---- API ----
def test_api_flow(session):
    def override():
        yield session

    api.app.dependency_overrides[api.get_session] = override
    c = TestClient(api.app)
    did = c.post("/devices", json={"fcm_token": "t", "platform": "ios"}).json()["device_id"]
    r = c.put(f"/devices/{did}/subscription", json={"sido": ["서울"], "categories": ["무순위"]})
    assert r.status_code == 200 and c.get(f"/devices/{did}/subscription").json()["sido"] == ["서울"]
    upsert(session, [RawNotice("SH", "30", "무순위 장기전세 모집", region="서울", apply_end=date(2026, 11, 20))])
    assert len(c.get("/notices", params={"category": "무순위"}).json()) == 1
    assert c.get("/calendar", params={"month": "2026-11"}).json()["days"]["2026-11-20"]
    assert c.get("/notices/9999").status_code == 404
    api.app.dependency_overrides.clear()


# ---- 청약홈 ----
def test_applyhome_parse_and_tags(session):
    from app.collectors import applyhome
    rows = [
        {"HOUSE_MANAGE_NO": "2026000111", "PBLANC_NO": "2026000111", "HOUSE_NM": "래미안 OO",
         "SUBSCRPT_AREA_CODE_NM": "서울", "RCRIT_PBLANC_DE": "2026-11-03", "RCEPT_ENDDE": "2026-11-12",
         "PBLANC_URL": "https://www.applyhome.co.kr/x", "HOUSE_SECD_NM": "APT"},
        {"HOUSE_NM": "관리번호 없음"},  # 건너뜀
    ]
    items = applyhome.parse_rows(rows, "APT 무순위 잔여세대", "getRemndrLttotPblancDetail")
    assert len(items) == 1 and items[0].apply_end == date(2026, 11, 12)
    new, _ = upsert(session, items)
    n = new[0]
    assert n.sido == "서울" and {"무순위"} <= set(n.tags) and pushable(n.tags)


def test_applyhome_without_key_is_skipped(monkeypatch):
    from app.collectors import applyhome
    monkeypatch.delenv("DATA_GO_KR_KEY", raising=False)
    assert applyhome.collect() == []


# ---- 관심 공고 ----
def test_favorites(session):
    def override():
        yield session

    api.app.dependency_overrides[api.get_session] = override
    c = TestClient(api.app)
    did = c.post("/devices", json={}).json()["device_id"]
    other = c.post("/devices", json={}).json()["device_id"]
    upsert(session, [
        RawNotice("LH", "f1", "A 무순위", region="서울", apply_end=date(2026, 12, 20)),
        RawNotice("LH", "f2", "B 무순위", region="서울", apply_end=date(2026, 12, 10)),
        RawNotice("LH", "f3", "C 무순위", region="서울"),  # 마감일 없음 → 맨 뒤
    ])
    ids = {n["title"][0]: n["id"] for n in c.get("/notices").json()}
    for k in "ACB":
        assert c.put(f"/devices/{did}/favorites/{ids[k]}").status_code == 200
    assert c.put(f"/devices/{did}/favorites/{ids['A']}").status_code == 200   # 멱등
    favs = c.get(f"/devices/{did}/favorites").json()
    assert [f["title"][0] for f in favs] == ["B", "A", "C"]                   # 마감 임박순
    assert c.get(f"/devices/{other}/favorites").json() == []                   # 기기별 분리
    assert c.delete(f"/devices/{did}/favorites/{ids['B']}").status_code == 200
    assert [f["title"][0] for f in c.get(f"/devices/{did}/favorites").json()] == ["A", "C"]
    assert c.put(f"/devices/{did}/favorites/99999").status_code == 404
    assert c.put(f"/devices/nope/favorites/{ids['A']}").status_code == 404
    api.app.dependency_overrides.clear()


# ---- 상세 · 주택형 · 비교 ----
def test_parse_types_normalizes_fields():
    from app.collectors import applyhome
    rows = [
        {"HOUSE_TY": "074.9823B", "LTTOT_TOP_AMOUNT": "49,392", "SUPLY_HSHLDCO": 5, "SPSPLY_HSHLDCO": 0, "SUPLY_AR": None},
        {"TP": "59A-1", "EXCLUSE_AR": "59.8947", "SUPLY_AR": "82.8550", "SUPLY_AMOUNT": "19380",
         "SUPLY_HSHLDCO": 34, "SPSPLY_YGMN_HSHLDCO": 2, "SPSPLY_NEW_MRRG_HSHLDCO": 3},
    ]
    a, b = applyhome.parse_types(rows)
    assert a["exclusive_area"] == 74.98 and a["price_man"] == 49392 and a["total"] == 5 and a["supply_area"] is None
    assert b["type"] == "59A-1" and b["supply_area"] == 82.86 and b["special"] == 5 and b["total"] == 39


def test_applyhome_extra_saved_and_detail_endpoint(session):
    from app.collectors import applyhome
    raw = applyhome.parse_rows([{
        "HOUSE_MANAGE_NO": "M1", "PBLANC_NO": "P1", "HOUSE_NM": "상세 단지", "SUBSCRPT_AREA_CODE_NM": "경기",
        "RCRIT_PBLANC_DE": "2026-11-03", "RCEPT_ENDDE": "2026-11-12", "RCEPT_BGNDE": "2026-11-11",
        "HSSPLY_ADRES": "경기도 OO", "TOT_SUPLY_HSHLDCO": 32, "PRZWNER_PRESNATN_DE": "2026-11-19",
        "MVN_PREARNGE_YM": "202808",
    }], "APT 무순위 잔여세대", "getRemndrLttotPblancDetail")
    upsert(session, raw)
    calls = []

    def fake_fetch(op, manage_no, pblanc_no):
        calls.append((op, manage_no, pblanc_no))
        return [{"type": "84A", "exclusive_area": 84.0, "supply_area": None, "price_man": 50000,
                 "general": 3, "special": 0, "total": 3}]

    def override():
        yield session

    api.app.dependency_overrides[api.get_session] = override
    api.app.dependency_overrides[api.get_type_fetcher] = lambda: fake_fetch
    c = TestClient(api.app)
    nid = c.get("/notices").json()[0]["id"]
    d = c.get(f"/notices/{nid}/detail").json()
    assert d["info"]["address"] == "경기도 OO" and d["info"]["total_households"] == 32
    assert d["info"]["apply_start"] == "2026-11-11" and "op" not in d["info"]
    assert d["types"][0]["type"] == "84A" and d["types_error"] is False
    c.get(f"/notices/{nid}/detail")
    assert calls == [("getRemndrLttotPblancDetail", "M1", "P1")]   # 두 번째는 캐시

    # 재수집해도 주택형 캐시가 지워지지 않는다
    upsert(session, raw)
    assert c.get(f"/notices/{nid}/detail").json()["types"][0]["type"] == "84A"
    assert len(calls) == 1
    api.app.dependency_overrides.clear()


def test_detail_fetch_failure_and_compare_validation(session):
    from app.collectors import applyhome
    raw = applyhome.parse_rows([
        {"HOUSE_MANAGE_NO": f"M{i}", "PBLANC_NO": f"P{i}", "HOUSE_NM": f"단지{i}", "SUBSCRPT_AREA_CODE_NM": "서울"}
        for i in range(1, 5)], "APT 분양", "getAPTLttotPblancDetail")
    upsert(session, raw)

    def boom(*a):
        raise RuntimeError("down")

    def override():
        yield session

    api.app.dependency_overrides[api.get_session] = override
    api.app.dependency_overrides[api.get_type_fetcher] = lambda: boom
    c = TestClient(api.app)
    ids = [n["id"] for n in c.get("/notices").json()]
    d = c.get(f"/notices/{ids[0]}/detail").json()
    assert d["types"] is None and d["types_error"] is True       # 오류여도 기본 정보는 내려준다
    ok = c.get("/compare", params={"ids": f"{ids[0]},{ids[1]}"})
    assert ok.status_code == 200 and len(ok.json()) == 2
    assert c.get("/compare", params={"ids": str(ids[0])}).status_code == 400            # 1개
    assert c.get("/compare", params={"ids": ",".join(map(str, ids))}).status_code == 400  # 4개
    assert c.get("/compare", params={"ids": "a,b"}).status_code == 400
    assert c.get("/compare", params={"ids": f"{ids[0]},99999"}).status_code == 404
    api.app.dependency_overrides.clear()


def test_is_relevant_filters_noise():
    from app.classify import is_relevant
    def rel(t):
        return is_relevant(t, tags_for(t))
    assert rel("제50차 장기전세주택 모집")
    assert rel("옥정중앙역 무순위 분양 잔여세대 모집")
    assert not rel("조직활성화 교육으로 인한 휴무 안내")
    assert not rel("2026년 제1차 건설약정방식 매입임대주택 매입공고(수정)")
    assert not rel("장기안심주택 2027년 4월 재계약 대상자 심사서류 제출 안내")
    assert not rel("인천계양 A3블록 가정어린이집 운영예정자 모집공고(1회차)")


def test_file_list_parsers():
    from app.collectors.files import parse_lh, parse_sh
    lh_rows = [
        {"cmnAhflSn": 2, "cmnAhflNm": "공고문.hwpx", "cmnAhflSz": 100},
        {"cmnAhflSn": 3, "cmnAhflNm": "공고문.pdf", "cmnAhflSz": 200},
        {"cmnAhflSn": None, "cmnAhflNm": "깨진.pdf"},
    ]
    got = parse_lh(lh_rows)
    assert [f["name"] for f in got] == ["공고문.pdf", "공고문.hwpx"]  # PDF 먼저, 깨진 항목 제외
    assert got[0]["url"].endswith("lhFile.do?fileid=3")

    html = ('x initParam.downList = [{"brdId":"GS0401","seq":"1","fileSeq":"2","fileSize":"86528",'
            '"oriFileNm":"추천서.hwp","fileTp":"A"},{"brdId":"GS0401","seq":"1","fileSeq":"1",'
            '"fileSize":"368185","oriFileNm":"공고문.pdf","fileTp":"A"}];  initInnorix();')
    sh = parse_sh(html)
    assert [f["name"] for f in sh] == ["공고문.pdf", "추천서.hwp"]
    assert "innoFD.do?brdId=GS0401&seq=1&fileTp=A&fileSeq=1" in sh[0]["url"]
    assert parse_sh("<html>첨부 없음</html>") == []


def test_list_parsers_attach_file_refs():
    from app.collectors import lh, sh
    lh_items = lh.parse((FIX / "lh_list.html").read_text(encoding="utf-8", errors="ignore"))
    assert lh_items and lh_items[0].extra["files_ref"]["src"] == "LH"
    assert len(lh_items[0].extra["files_ref"]["p"]) == 5
    sh_items = sh.parse((FIX / "sh_list.html").read_text(encoding="utf-8", errors="ignore"))
    assert sh_items and sh_items[0].extra["files_ref"] == {"src": "SH", "seq": sh_items[0].ext_id}


def test_gh_parser_keeps_housing_rows_with_files():
    from app.collectors import gh
    items = gh.parse((FIX / "gh_list.html").read_text(encoding="utf-8"))
    assert items, "주택 공고가 한 건도 없음"
    assert all(i.source == "GH" and i.region == "경기" and i.ext_id.isdigit() for i in items)
    assert all(i.announce_date and i.announce_date.year >= 2026 for i in items)
    assert all("articleNo=" in i.url for i in items)
    with_files = [f for i in items for f in i.extra.get("files", [])]
    assert with_files and all(f["url"].startswith("https://gh.or.kr/") and f["name"] for f in with_files)
    # PDF 가 HWP 보다 앞
    for i in items:
        names = [f["name"].lower() for f in i.extra.get("files", [])]
        if any(n.endswith(".pdf") for n in names) and any(n.endswith(".hwp") for n in names):
            assert names.index(next(n for n in names if n.endswith(".pdf"))) < names.index(
                next(n for n in names if n.endswith(".hwp")))


def test_applyhome_stage_dates():
    from app.collectors import applyhome
    raw = applyhome.parse_rows([{
        "HOUSE_MANAGE_NO": "M2", "PBLANC_NO": "P2", "HOUSE_NM": "단계 단지", "RCRIT_PBLANC_DE": "2026-11-03",
        "RCEPT_BGNDE": "2026-11-02", "RCEPT_ENDDE": "2026-11-17",
        "SPSPLY_RCEPT_BGNDE": "2026-11-02", "SPSPLY_RCEPT_ENDDE": "2026-11-16",
        "GNRL_RNK1_CRSPAREA_RCPTDE": "2026-11-17", "GNRL_RNK1_CRSPAREA_ENDDE": "2026-11-17",
        "GNRL_RNK2_CRSPAREA_RCPTDE": None, "GNRL_RNK2_CRSPAREA_ENDDE": None,
    }], "APT 분양", "getAPTLttotPblancDetail")
    ex = raw[0].extra
    assert (ex["special_start"].isoformat(), ex["special_end"].isoformat()) == ("2026-11-02", "2026-11-16")
    assert ex["rank1_start"].isoformat() == "2026-11-17"
    assert ex["rank2_start"] is None


def test_geo_search_query_and_fill():
    from app.collectors.geo import search_query
    from app.export import _fill_geo
    from datetime import date

    assert "도청이전신도시" in search_query("도청이전신도시 RH10-2BL 국민임대주택 자격완화 추가모집(2026.10.27)")
    assert "BL" not in search_query("도청이전신도시 RH10-2BL 국민임대주택")
    assert search_query("[부산] 2026년 2차 일반 매입임대주택 입주자 모집 공고") == ""

    today = date(2026, 11, 6)
    items = {
        "a": {"id": "a", "title": "x", "apply_end": "2026-11-20"},
        "b": {"id": "b", "title": "y", "apply_end": "2026-11-21"},
        "c": {"id": "c", "title": "z", "apply_end": "2026-11-22", "geo": {"lat": 1, "lng": 2, "approx": False}},
        "d": {"id": "d", "title": "w", "apply_end": "2026-11-23", "gchk": "2026-11-04"},
    }
    seen = []

    def fake(it):
        seen.append(it["id"])
        return {"lat": 37.5, "lng": 127.0, "approx": True} if it["id"] == "a" else None

    _fill_geo(items, fake, today)
    assert seen == ["a", "b"]          # 이미 있는 것(c)·최근에 못 찾은 것(d)은 건너뜀
    assert items["a"]["geo"]["approx"] is True
    assert items["b"]["gchk"] == "2026-11-06" and "geo" not in items["b"]
