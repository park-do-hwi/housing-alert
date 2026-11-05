import json
from datetime import date, datetime, timezone

from app.collectors.base import RawNotice
from app.export import TYPES_PER_RUN, build, load_previous, write

TODAY = date(2026, 11, 5)
NOW = datetime(2026, 11, 5, 9, tzinfo=timezone.utc)


def lh(i="1", title="A 무순위 모집", end=date(2026, 11, 20)):
    return RawNotice("LH", i, title, region="경기도", announce_date=date(2026, 11, 1), apply_end=end, url="u")


def ah(i="9", end=date(2026, 11, 12)):
    return RawNotice("APPLYHOME", f"op:{i}:{i}", f"단지{i}", type_text="APT 분양", region="서울",
                     announce_date=date(2026, 11, 3), apply_end=end,
                     extra={"op": "getAPTLttotPblancDetail", "manage_no": i, "pblanc_no": i,
                            "apply_start": date(2026, 11, 9), "total_households": 30})


class Types:
    def __init__(self, value=None, boom=False):
        self.calls, self.value, self.boom = [], value, boom

    def __call__(self, op, m, p):
        self.calls.append((op, m, p))
        if self.boom:
            raise RuntimeError("down")
        return self.value if self.value is not None else [{"type": "84A", "price_man": 1000, "total": 3}]


def run(prev, cols, ft=None):
    return build(prev, cols, ft or Types(), today=TODAY, now=NOW)


def test_new_changed_and_stable_ids():
    items, meta = run([], {"LH": lambda: [lh()]})
    assert items[0]["id"] == "LH:1" and items[0]["sido"] == "경기" and "무순위" in items[0]["tags"]
    assert meta["new"] == ["LH:1"] and meta["changed"] == []
    first_seen = items[0]["first_seen"]

    items2, meta2 = run(items, {"LH": lambda: [lh()]})
    assert meta2["new"] == [] and meta2["changed"] == []
    assert items2[0]["first_seen"] == first_seen

    items3, meta3 = run(items2, {"LH": lambda: [lh(end=date(2026, 11, 25))]})
    assert meta3["changed"] == ["LH:1"] and items3[0]["apply_end"] == "2026-11-25"


def test_info_dates_are_iso_and_ref_is_separate():
    items, _ = run([], {"APPLYHOME": lambda: [ah()]})
    it = items[0]
    assert it["info"]["apply_start"] == "2026-11-09" and it["info"]["total_households"] == 30
    assert "op" not in it["info"] and it["ref"]["manage_no"] == "9"
    json.dumps(items)  # 직렬화 가능


def test_types_fetched_once_then_cached():
    ft = Types()
    items, _ = run([], {"APPLYHOME": lambda: [ah()]}, ft)
    assert items[0]["types"][0]["type"] == "84A" and len(ft.calls) == 1
    items2, _ = run(items, {"APPLYHOME": lambda: [ah()]}, ft)
    assert len(ft.calls) == 1 and items2[0]["types"]


def test_types_failure_or_empty_is_retried_next_run():
    boom = Types(boom=True)
    items, _ = run([], {"APPLYHOME": lambda: [ah()]}, boom)
    assert "types" not in items[0]                      # 실패해도 공고 자체는 나온다
    empty = Types(value=[])
    items, _ = run(items, {"APPLYHOME": lambda: [ah()]}, empty)
    assert "types" not in items[0] and len(empty.calls) == 1
    ok = Types()
    items, _ = run(items, {"APPLYHOME": lambda: [ah()]}, ok)
    assert items[0]["types"]


def test_types_skipped_for_long_closed_and_budget_limited():
    ft = Types()
    run([], {"APPLYHOME": lambda: [ah("1", end=date(2026, 10, 1))]}, ft)
    assert ft.calls == []                               # 마감 한참 지남
    ft = Types()
    many = [ah(str(i)) for i in range(TYPES_PER_RUN + 20)]
    items, _ = run([], {"APPLYHOME": lambda: many}, ft)
    assert len(ft.calls) == TYPES_PER_RUN
    assert sum(1 for i in items if i.get("types")) == TYPES_PER_RUN


def test_failed_or_empty_source_keeps_previous_items():
    items, _ = run([], {"LH": lambda: [lh()], "SH": lambda: [RawNotice("SH", "5", "SH 장기전세", region="서울")]})
    assert {i["id"] for i in items} == {"LH:1", "SH:5"}

    def boom():
        raise RuntimeError("site down")

    items2, meta = run(items, {"LH": lambda: [lh()], "SH": boom})
    assert {i["id"] for i in items2} == {"LH:1", "SH:5"} and meta["failed_sources"] == ["SH"]
    items3, meta = run(items, {"LH": lambda: [lh()], "SH": lambda: []})          # 0건 = 구조 변경 의심
    assert "SH:5" in {i["id"] for i in items3} and meta["failed_sources"] == ["SH"]


def test_old_items_dropped_after_retention():
    old = lh("2", end=date(2026, 9, 1))                   # 마감 65일 전
    items, _ = run([], {"LH": lambda: [old]})
    assert items                                          # 이번 수집에 있으면 일단 포함
    items2, _ = run(items, {"LH": lambda: [lh()]})        # 다음 수집에서 사라지고 보존기간도 지남
    assert [i["id"] for i in items2] == ["LH:1"]


def test_write_and_load_roundtrip(tmp_path):
    items, meta = run([], {"LH": lambda: [lh()]})
    write(tmp_path / "public", items, meta)
    assert not list((tmp_path / "public").glob("*.tmp"))
    assert load_previous(tmp_path / "public" / "notices.json")[0]["id"] == "LH:1"
    assert json.loads((tmp_path / "public" / "meta.json").read_text(encoding="utf-8"))["count"] == 1
    assert load_previous(tmp_path / "none.json") == []
