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
import os
import sys
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

from .classify import sido_for, tags_for
from .collectors import COLLECTORS
from .collectors.base import RawNotice
from .ingest import _detail

log = logging.getLogger(__name__)

RETAIN_DAYS = 30        # 접수 마감 후 목록에 남기는 기간
TYPES_PER_RUN = 150     # 한 번 실행에서 주택형을 새로 가져올 최대 공고 수
TYPES_SKIP_AFTER = 3    # 마감 후 이 기간이 지난 공고는 주택형을 새로 안 가져옴
REF_KEYS = ("op", "manage_no", "pblanc_no")


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
    return item


def _keep(item: dict, today: date) -> bool:
    end = item.get("apply_end")
    if not end:
        # 마감일이 없으면 공고일 기준으로 60일까지만
        ann = item.get("announce_date")
        return not ann or date.fromisoformat(ann) >= today - timedelta(days=60)
    return date.fromisoformat(end) >= today - timedelta(days=RETAIN_DAYS)


def build(previous: list[dict], collectors: dict, fetch_types, today: date | None = None,
          now: datetime | None = None) -> tuple[list[dict], dict]:
    """returns (items, meta). fetch_types(op, manage_no, pblanc_no) -> list[dict]"""
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
            if _hash(old) != _hash(it):
                changed_ids.append(iid)
        merged[iid] = it

    # 이번에 못 가져온 것: 실패한 소스의 이전 공고는 보존, 나머지는 보존 기간 안에서만 유지
    for iid, old in prev.items():
        if iid in merged:
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

    items = sorted(merged.values(), key=lambda x: (x.get("announce_date") or ""), reverse=True)
    meta = {
        "generated_at": now.isoformat(),
        "count": len(items),
        "failed_sources": sorted(failed),
        "new": new_ids,
        "changed": changed_ids,
    }
    return items, meta


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
    items, meta = build(load_previous(out / "notices.json"), COLLECTORS, applyhome.fetch_types)
    if meta["failed_sources"] and not items:
        print("모든 소스가 실패해 파일을 쓰지 않았습니다:", meta["failed_sources"], file=sys.stderr)
        sys.exit(1)
    write(out, items, meta)
    print(f'공고 {meta["count"]}건 (신규 {len(meta["new"])}, 변경 {len(meta["changed"])}, '
          f'실패 소스 {meta["failed_sources"] or "없음"}) -> {out}')


if __name__ == "__main__":
    main()
