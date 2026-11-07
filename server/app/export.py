"""수집 결과를 정적 JSON 으로 내보낸다. (DB·상시 서버 없이 앱이 이 파일만 읽는다)

    python -m app.export --out public            # public/notices.json, public/meta.json 생성

이전 실행 결과(public/notices.json)를 읽어 합친다:
 - 이미 가져온 주택형(types)은 다시 요청하지 않는다.
 - 한 소스가 실패하면 그 소스의 이전 공고를 그대로 보존한다.
 - 마감 후 RETAIN_DAYS 일이 지난 공고만 목록에서 뺀다.
 - meta.json 의 new / changed 는 나중에 푸시를 붙일 때 쓴다.
"""
import argparse
import hashlib
import json
import logging
import re
import os
import sys
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

from .classify import is_relevant, sido_for, tags_for
from .collectors import COLLECTORS
from .collectors.base import RawNotice
from .ingest import _detail

log = logging.getLogger(__name__)

RETAIN_DAYS = 30        # 접수 마감 후 목록에 남기는 기간
TYPES_PER_RUN = 150     # 한 번 실행에서 주택형을 새로 가져올 최대 공고 수
TYPES_SKIP_AFTER = 3    # 마감 후 이 기간이 지난 공고는 주택형을 새로 안 가져옴
REF_KEYS = ("op", "manage_no", "pblanc_no")
FILES_PER_RUN = 80      # 한 번 실행에서 공고문 파일을 새로 조회할 최대 공고 수
GEO_PER_RUN = 80        # 한 번 실행에서 좌표를 새로 조회할 최대 공고 수
PHOTO_PER_RUN = 60      # 한 번 실행에서 대표 이미지를 새로 찾을 최대 공고 수
PLAN_PER_RUN = 25       # 한 번 실행에서 평면도를 새로 찾을 최대 공고 수
MARKET_PER_RUN = 60     # 한 번 실행에서 시·군·구 코드를 새로 찾을 최대 공고 수
PHOTO_RETRY_DAYS = 7    # 이미지를 못 찾았을 때 다시 보는 간격
GEO_RETRY_DAYS = 7      # 위치를 못 찾았을 때 다시 시도하는 간격
FILES_RETRY_DAYS = 3    # 파일이 아직 없을 때, 처음 본 뒤 이 기간 동안만 다시 확인


def stable_id(source: str, ext_id: str) -> str:
    return f"{source}:{ext_id}"


def _iso(d: date | None) -> str | None:
    return d.isoformat() if d else None


def _hash(item: dict) -> str:
    key = f'{item["title"]}|{item.get("announce_date")}|{item.get("apply_end")}'
    return hashlib.sha256(key.encode()).hexdigest()[:16]


def to_item(r: RawNotice) -> dict:
    info = _detail(r)
    ref = {k: info.pop(k) for k in REF_KEYS if k in info}
    fref = info.pop("files_ref", None)  # 공고문 파일 조회용 참조(앱에는 필요 없음)
    item = {
        "id": stable_id(r.source, r.ext_id),
        "source": r.source,
        "title": r.title,
        "tags": tags_for(r.title, r.type_text),
        "sido": sido_for(r.region),
        "announce_date": _iso(r.announce_date),
        "apply_end": _iso(r.apply_end),
        "url": r.url,
        "info": info,
    }
    if ref:
        item["ref"] = ref
    if fref:
        item["fref"] = fref
    return item


def _keep(item: dict, today: date) -> bool:
    end = item.get("apply_end")
    if not end:
        # 마감일이 없으면 공고일 기준으로 60일까지만
        ann = item.get("announce_date")
        return not ann or date.fromisoformat(ann) >= today - timedelta(days=60)
    return date.fromisoformat(end) >= today - timedelta(days=RETAIN_DAYS)


def build(previous: list[dict], collectors: dict, fetch_types, today: date | None = None,
          now: datetime | None = None, fetch_files=None, geocode=None, find_photo=None, search_photo=None, search_plan=None, market=None, validate=None, plan_validate=None) -> tuple[list[dict], dict]:
    """returns (items, meta). fetch_types(op, manage_no, pblanc_no) -> list[dict],
    fetch_files(fref) -> [{name, url, size}] (LH·SH 공고문 파일. None 이면 조회하지 않음)"""
    today = today or date.today()
    now = now or datetime.now(timezone.utc)
    prev = {p["id"]: p for p in previous}
    fresh: dict[str, dict] = {}
    failed: set[str] = set()

    for source, fn in collectors.items():
        try:
            raws = fn()
        except Exception:
            log.exception("collector %s failed", source)
            failed.add(source)
            continue
        if not raws:  # 0건은 구조 변경 의심 → 이전 데이터를 지우지 않는다
            log.warning("collector %s returned 0 items", source)
            failed.add(source)
            continue
        for r in raws:
            it = to_item(r)
            if not is_relevant(it["title"], it["tags"]):
                continue
            fresh[it["id"]] = it

    new_ids, changed_ids = [], []
    merged: dict[str, dict] = {}
    for iid, it in fresh.items():
        old = prev.get(iid)
        if old is None:
            it["first_seen"] = now.isoformat()
            new_ids.append(iid)
        else:
            it["first_seen"] = old.get("first_seen", now.isoformat())
            if "types" in old:
                it["types"] = old["types"]
            if old.get("info", {}).get("files"):
                it["info"]["files"] = old["info"]["files"]
            if "fchk" in old:
                it["fchk"] = old["fchk"]
            for k in ("geo", "gchk", "photo", "photo_hi", "pchk", "plan", "plan_hi", "plans", "pv", "plchk", "plv", "sgg", "mkt"):
                if k in old:
                    it[k] = old[k]
            if _hash(old) != _hash(it):
                changed_ids.append(iid)
        merged[iid] = it

    # 이번에 못 가져온 것: 실패한 소스의 이전 공고는 보존, 나머지는 보존 기간 안에서만 유지
    for iid, old in prev.items():
        if iid in merged or not is_relevant(old["title"], old.get("tags", ["기타"])):
            continue
        if old["source"] in failed or _keep(old, today):
            merged[iid] = old

    # 주택형(청약홈만): 아직 없는 것만, 한 번에 최대 TYPES_PER_RUN 건
    budget = TYPES_PER_RUN
    for it in sorted(merged.values(), key=lambda x: x.get("apply_end") or "9999", reverse=False):
        if budget <= 0:
            break
        ref = it.get("ref")
        if not ref or it.get("types"):
            continue
        end = it.get("apply_end")
        if end and date.fromisoformat(end) < today - timedelta(days=TYPES_SKIP_AFTER):
            continue
        budget -= 1
        try:
            types = fetch_types(ref["op"], ref["manage_no"], ref["pblanc_no"])
        except Exception:
            log.exception("types fetch failed: %s", it["id"])
            continue
        if types:  # 아직 공개 전이라 빈 응답이면 저장하지 않고 다음 실행에서 다시 시도
            it["types"] = types

    if fetch_files:
        _fill_files(merged, fetch_files, today, now)
    if geocode:
        _fill_geo(merged, geocode, today)
    if find_photo:
        _fill_photo(merged, find_photo, today, search_photo, validate)
    if search_plan:
        _fill_plan(merged, search_plan, today, plan_validate)
    if market:
        _fill_market(merged, market, today)

    items = sorted(merged.values(), key=lambda x: (x.get("announce_date") or ""), reverse=True)
    meta = {
        "generated_at": now.isoformat(),
        "count": len(items),
        "failed_sources": sorted(failed),
        "new": new_ids,
        "changed": changed_ids,
    }
    return items, meta


def _fill_files(merged: dict, fetch_files, today: date, now: datetime) -> None:
    """파일이 아직 없는 LH·SH 공고만 조회한다. 한 번에 FILES_PER_RUN 건까지.
    조회했는데 비어 있으면 fchk(확인한 날)를 남기고, 처음 보인 지 FILES_RETRY_DAYS 일 안에서만 다시 시도한다."""
    budget = FILES_PER_RUN
    # 마감이 가까운(급한) 공고부터
    for it in sorted(merged.values(), key=lambda x: x.get("apply_end") or "9999"):
        if budget <= 0:
            break
        fref = it.get("fref")
        if not fref or it.get("info", {}).get("files"):
            continue
        first = it.get("first_seen")
        young = bool(first) and (
            now.replace(tzinfo=None) - datetime.fromisoformat(first).replace(tzinfo=None)
        ).days <= FILES_RETRY_DAYS
        if it.get("fchk") and not young:
            continue
        end = it.get("apply_end")
        if end and date.fromisoformat(end) < today - timedelta(days=TYPES_SKIP_AFTER):
            continue
        budget -= 1
        try:
            files = fetch_files(fref)
        except Exception:
            log.exception("files fetch failed: %s", it["id"])
            continue
        if files:
            it.setdefault("info", {})["files"] = files
            it.pop("fchk", None)
        else:
            it["fchk"] = today.isoformat()


def _fill_geo(merged: dict, geocode, today: date) -> None:
    """좌표가 없는 공고만 한 번에 GEO_PER_RUN 건까지 조회한다. 못 찾은 것은 gchk(확인한 날)를 남기고
    GEO_RETRY_DAYS 일 뒤에 다시 시도한다."""
    budget = GEO_PER_RUN
    for it in sorted(merged.values(), key=lambda x: x.get("apply_end") or "9999"):
        if budget <= 0:
            break
        if it.get("geo"):
            continue
        chk = it.get("gchk")
        if chk and (today - date.fromisoformat(chk)).days < GEO_RETRY_DAYS:
            continue
        end = it.get("apply_end")
        if end and date.fromisoformat(end) < today - timedelta(days=TYPES_SKIP_AFTER):
            continue
        budget -= 1
        try:
            geo = geocode(it)
        except Exception:
            log.exception("geocode failed: %s", it["id"])
            continue
        if geo:
            it["geo"] = geo
            it.pop("gchk", None)
        else:
            it["gchk"] = today.isoformat()


def _fill_photo(merged: dict, find_photo, today: date, search_photo=None, validate=None) -> None:
    """분양 홈페이지 주소가 있고 아직 이미지가 없는 공고만, 한 번에 PHOTO_PER_RUN 건까지 조회한다.
    못 찾은 것은 pchk(확인한 날)를 남기고 PHOTO_RETRY_DAYS 일 뒤에 다시 본다(사진은 나중에 올라오기도 한다)."""
    budget = PHOTO_PER_RUN
    if validate:  # 예전에 저장한 검색 결과 중 지도 같은 그림은 빼고 다시 찾게 한다(검사한 것은 pv=1)
        for it in merged.values():
            u = it.get("photo") or ""
            if u and not it.get("pv"):
                try:
                    if validate(u):
                        for k in ("photo", "photo_hi", "pchk"):
                            it.pop(k, None)  # 바로 다시 찾는다(새 검색은 지도를 거른다)
                    else:
                        it["pv"] = 1
                except Exception:
                    log.warning("photo validate failed: %s", it["id"])

    def stale_thumb(x):  # 작은 썸네일만 있는 것(상세에서 흐릿함)을 먼저 원본으로 바꾼다
        return not ("kakaocdn.net" in (x.get("photo") or "") and not x.get("photo_hi"))

    for it in sorted(merged.values(), key=lambda x: (stale_thumb(x), x.get("apply_end") or "9999")):
        if budget <= 0:
            break
        hp = (it.get("info") or {}).get("homepage")
        use_search = search_photo is not None and (it.get("source") == "APPLYHOME" or bool(it.get("geo")))
        if it.get("photo") and not (use_search and "kakaocdn.net" in it["photo"] and not it.get("photo_hi")):
            continue  # (예전에 썸네일만 저장한 검색 결과는 원본 주소를 얻으려고 다시 찾는다)
        if not hp and not use_search:
            continue
        chk = it.get("pchk")
        if chk and (today - date.fromisoformat(chk)).days < PHOTO_RETRY_DAYS:
            continue
        end = it.get("apply_end")
        if end and date.fromisoformat(end) < today - timedelta(days=TYPES_SKIP_AFTER):
            continue
        budget -= 1
        url = None
        try:
            url = find_photo(hp) if hp else None
            if url and validate and validate(url):
                url = None  # 홈페이지 대표 이미지가 로고·지도·도면이면 쓰지 않는다
        except Exception:
            log.warning("photo fetch failed: %s", it["id"])
        if not url and use_search:
            try:
                found = search_photo(it)
                if found:
                    url = found[0]
                    if found[1]:
                        it["photo_hi"] = found[1]
            except Exception:
                log.warning("photo search failed: %s", it["id"])
        if url:
            it["photo"] = url
            if validate is not None or (search_photo is not None and "kakaocdn.net" in url):
                it["pv"] = 1
            it.pop("pchk", None)
        else:
            it["pchk"] = today.isoformat()


def _type_label(t: str) -> str:
    """'084.9500A' -> '84A' (앞 0 제거, 소수점 이하 제거, 뒤의 문자 유지)"""
    m = re.match(r"0*(\d+)(?:\.\d+)?\s*([A-Za-z가-힣]*)", t or "")
    return f"{m.group(1)}{m.group(2)}" if m else (t or "")


def _fill_plan(merged: dict, search_plan, today: date, validate=None) -> None:
    """평면도(참고) 이미지: 청약홈 분양 단지만, 한 번에 PLAN_PER_RUN 건. 주택형(84A 등)이 있으면 주택형별로
    (면적이 큰 순 최대 4개), 없으면 단지 평면도 한 장. 못 찾으면 plchk 를 남기고 일주일 뒤 재시도."""
    budget = PLAN_PER_RUN
    if validate:  # 이미 저장된 평면도 중 평면도가 아닌 그림(배치도 등)은 지우고 다시 찾는다
        vb = 40
        for it in merged.values():
            if vb <= 0:
                break
            if it.get("plv") or not (it.get("plans") or it.get("plan")):
                continue
            vb -= 1
            try:
                if it.get("plans"):
                    keep = [p for p in it["plans"] if not validate(p["img"])]
                    if len(keep) != len(it["plans"]):
                        it["plans"] = keep
                        if not keep:
                            it.pop("plans")
                            it.pop("plchk", None)
                elif validate(it["plan"]):
                    for k in ("plan", "plan_hi"):
                        it.pop(k, None)
                it["plv"] = 1
            except Exception:
                pass
    for it in sorted(merged.values(), key=lambda x: x.get("apply_end") or "9999"):
        if budget <= 0:
            break
        types = it.get("types") or []
        done = ("plans" in it) if types else bool(it.get("plan"))
        if it.get("source") != "APPLYHOME" or done:
            continue
        chk = it.get("plchk")
        if chk and (today - date.fromisoformat(chk)).days < PHOTO_RETRY_DAYS:
            continue
        end = it.get("apply_end")
        if end and date.fromisoformat(end) < today - timedelta(days=TYPES_SKIP_AFTER):
            continue
        budget -= 1
        try:
            if types:
                labels, seen, plans = [], set(), []
                for t in sorted(types, key=lambda x: -(x.get("exclusive_area") or 0)):
                    lb = _type_label(t.get("type", ""))
                    if lb and lb not in labels:
                        labels.append(lb)
                for lb in labels[:4]:
                    found = search_plan(it, lb)
                    if found and found[0] not in seen:
                        seen.add(found[0])
                        plans.append({"t": lb, "img": found[0], **({"hi": found[1]} if found[1] else {})})
                if plans:
                    it["plans"] = plans
                    it.pop("plchk", None)
                else:
                    it["plchk"] = today.isoformat()
            else:
                found = search_plan(it)
                if found:
                    it["plan"] = found[0]
                    if found[1]:
                        it["plan_hi"] = found[1]
                    it.pop("plchk", None)
                else:
                    it["plchk"] = today.isoformat()
        except Exception:
            log.warning("plan search failed: %s", it["id"])


def _fill_market(merged: dict, market, today: date) -> None:
    """위치가 잡힌 공고에 주변 시세(참고)를 붙인다. 시·군·구마다 하루에 한 번만 새로 받는다(공고들이 같이 쓴다).
    market = (sgg_of(lat, lng) -> 코드, stats(sgg) -> dict|None)"""
    sgg_of, stats = market
    cache: dict[str, dict | None] = {}
    budget = MARKET_PER_RUN
    for it in sorted(merged.values(), key=lambda x: x.get("apply_end") or "9999"):
        geo = it.get("geo")
        if not geo:
            continue
        end = it.get("apply_end")
        if end and date.fromisoformat(end) < today - timedelta(days=TYPES_SKIP_AFTER):
            continue
        old = it.get("mkt")
        if old and old.get("at") == today.isoformat():
            continue
        try:
            if not it.get("sgg"):
                if budget <= 0:
                    continue
                budget -= 1
                it["sgg"] = sgg_of(geo["lat"], geo["lng"])
            sgg = it.get("sgg")
            if not sgg:
                continue
            if sgg not in cache:
                cache[sgg] = stats(sgg)
            st = cache[sgg]
        except Exception:
            log.warning("market failed: %s", it["id"])
            continue
        if st:
            it["mkt"] = {**st, "at": today.isoformat()}


def write(out: Path, items: list[dict], meta: dict) -> None:
    out.mkdir(parents=True, exist_ok=True)
    # 임시 파일에 쓴 뒤 교체해서, 쓰는 도중에 앱이 반쪽짜리 파일을 읽지 않게 한다
    for name, payload in (("notices.json", {"generated_at": meta["generated_at"], "items": items}),
                          ("meta.json", meta)):
        tmp = out / (name + ".tmp")
        tmp.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
        os.replace(tmp, out / name)


def load_previous(path: Path) -> list[dict]:
    try:
        return json.loads(path.read_text(encoding="utf-8")).get("items", [])
    except (FileNotFoundError, json.JSONDecodeError):
        return []


def main(argv=None):
    from .collectors import applyhome

    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="public")
    args = ap.parse_args(argv)
    logging.basicConfig(level=logging.INFO)
    out = Path(args.out)
    from .collectors import files

    from .collectors import geo, market as mk, photo

    items, meta = build(load_previous(out / "notices.json"), COLLECTORS, applyhome.fetch_types,
                        fetch_files=files.fetch_files,
                        geocode=geo.geocode if os.environ.get("KAKAO_REST_KEY") else None,
                        find_photo=photo.find_photo,
                        search_photo=photo.search_photo if os.environ.get("KAKAO_REST_KEY") else None,
                        validate=photo.is_map_like if os.environ.get("KAKAO_REST_KEY") else None,
                        plan_validate=photo.is_not_floorplan if os.environ.get("KAKAO_REST_KEY") else None,
                        search_plan=photo.search_plan if os.environ.get("KAKAO_REST_KEY") else None,
                        market=(mk.sgg_of, lambda sgg: mk.summarize(
                            [t for ym in mk.months_back(date.today()) for t in mk.fetch_trades(sgg, ym)],
                            date.today()))
                        if os.environ.get("KAKAO_REST_KEY") and os.environ.get("DATA_GO_KR_KEY") else None)
    if meta["failed_sources"] and not items:
        print("모든 소스가 실패해 파일을 쓰지 않았습니다:", meta["failed_sources"], file=sys.stderr)
        sys.exit(1)
    write(out, items, meta)
    print(f'공고 {meta["count"]}건 (신규 {len(meta["new"])}, 변경 {len(meta["changed"])}, '
          f'실패 소스 {meta["failed_sources"] or "없음"}) -> {out}')


if __name__ == "__main__":
    main()
