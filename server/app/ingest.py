"""수집 결과를 DB에 반영하고 신규/변경 공고를 돌려준다."""
import hashlib
import logging

from sqlalchemy import select
from sqlalchemy.orm import Session

from .classify import sido_for, tags_for
from .collectors.base import RawNotice
from .models import Notice, now

log = logging.getLogger(__name__)


def _hash(r: RawNotice) -> str:
    key = f"{r.title}|{r.announce_date}|{r.apply_end}"
    return hashlib.sha256(key.encode()).hexdigest()


def _detail(r: RawNotice) -> dict:
    """RawNotice.extra 를 JSON 저장 가능한 dict 로 (date → ISO, 빈 값 제거)."""
    out = {}
    for k, v in (r.extra or {}).items():
        if v in (None, ""):
            continue
        out[k] = v.isoformat() if hasattr(v, "isoformat") else v
    return out


def upsert(session: Session, raws: list[RawNotice]) -> tuple[list[Notice], list[Notice]]:
    """returns (new, changed)"""
    new, changed = [], []
    for r in raws:
        row = session.scalar(select(Notice).where(Notice.source == r.source, Notice.ext_id == r.ext_id))
        h = _hash(r)
        if row is None:
            row = Notice(
                source=r.source, ext_id=r.ext_id, title=r.title,
                tags=tags_for(r.title, r.type_text), sido=sido_for(r.region),
                announce_date=r.announce_date, apply_end=r.apply_end, url=r.url, raw_hash=h,
                detail=_detail(r),
            )
            session.add(row)
            new.append(row)
            continue
        # 주택형 캐시(types)는 유지하면서 상세 정보만 갱신
        merged = {**(row.detail or {}), **_detail(r)}
        if merged != (row.detail or {}):
            row.detail = merged
        if row.raw_hash != h:
            row.title, row.apply_end, row.announce_date = r.title, r.apply_end, r.announce_date
            row.tags = tags_for(r.title, r.type_text)
            row.raw_hash, row.updated_at = h, now()
            changed.append(row)
    session.commit()
    return new, changed


def run_collectors(session: Session, collectors: dict) -> tuple[list[Notice], list[Notice]]:
    """한 소스가 실패해도 나머지는 계속. 0건이면 구조 변경 의심으로 경고."""
    all_new, all_changed = [], []
    for name, fn in collectors.items():
        try:
            raws = fn()
        except Exception:
            log.exception("collector %s failed", name)
            continue
        if not raws:
            log.warning("collector %s returned 0 items (구조 변경 의심)", name)
            continue
        n, c = upsert(session, raws)
        all_new += n
        all_changed += c
    return all_new, all_changed
