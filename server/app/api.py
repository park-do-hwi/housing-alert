import calendar
from datetime import date

from fastapi import Depends, FastAPI, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from .db import SessionLocal, init_db
from .models import Device, Favorite, Notice, Subscription

app = FastAPI(title="Housing Alert API")


@app.on_event("startup")
def _startup():
    init_db()


def get_session():
    with SessionLocal() as s:
        yield s


class DeviceIn(BaseModel):
    fcm_token: str = ""
    platform: str = ""


class SubscriptionIO(BaseModel):
    sido: list[str] = Field(default_factory=list)
    categories: list[str] = Field(default_factory=list)
    keywords: list[str] = Field(default_factory=list)
    exclude_keywords: list[str] = Field(default_factory=list)
    remind_days: list[int] = Field(default_factory=lambda: [3, 1])


def notice_out(n: Notice) -> dict:
    return {
        "id": n.id, "source": n.source, "title": n.title, "tags": n.tags, "sido": n.sido,
        "announce_date": n.announce_date, "apply_end": n.apply_end, "url": n.url,
    }


@app.post("/devices")
def register_device(body: DeviceIn, s: Session = Depends(get_session)):
    dev = Device(fcm_token=body.fcm_token, platform=body.platform)
    s.add(dev)
    s.flush()
    s.add(Subscription(device_id=dev.id))
    s.commit()
    return {"device_id": dev.id}


@app.put("/devices/{device_id}/token")
def update_token(device_id: str, body: DeviceIn, s: Session = Depends(get_session)):
    dev = s.get(Device, device_id)
    if not dev:
        raise HTTPException(404, "device not found")
    dev.fcm_token = body.fcm_token
    s.commit()
    return {"ok": True}


@app.get("/devices/{device_id}/subscription", response_model=SubscriptionIO)
def get_subscription(device_id: str, s: Session = Depends(get_session)):
    sub = s.get(Subscription, device_id)
    if not sub:
        raise HTTPException(404, "device not found")
    return sub


@app.put("/devices/{device_id}/subscription", response_model=SubscriptionIO)
def put_subscription(device_id: str, body: SubscriptionIO, s: Session = Depends(get_session)):
    sub = s.get(Subscription, device_id)
    if not sub:
        raise HTTPException(404, "device not found")
    for k, v in body.model_dump().items():
        setattr(sub, k, v)
    s.commit()
    return sub


@app.get("/devices/{device_id}/favorites")
def list_favorites(device_id: str, s: Session = Depends(get_session)):
    """저장한 공고. 접수 마감이 가까운 순(마감일 없는 건 뒤)."""
    if not s.get(Device, device_id):
        raise HTTPException(404, "device not found")
    rows = s.scalars(select(Notice).join(Favorite, Favorite.notice_id == Notice.id)
                     .where(Favorite.device_id == device_id)).all()
    rows.sort(key=lambda n: (n.apply_end is None, n.apply_end or date.max, -n.id))
    return [notice_out(n) for n in rows]


@app.put("/devices/{device_id}/favorites/{notice_id}")
def add_favorite(device_id: str, notice_id: int, s: Session = Depends(get_session)):
    if not s.get(Device, device_id):
        raise HTTPException(404, "device not found")
    if not s.get(Notice, notice_id):
        raise HTTPException(404, "notice not found")
    exists = s.scalar(select(Favorite.id).where(Favorite.device_id == device_id,
                                                Favorite.notice_id == notice_id))
    if exists is None:  # 멱등: 이미 저장돼 있으면 그대로 성공
        s.add(Favorite(device_id=device_id, notice_id=notice_id))
        s.commit()
    return {"ok": True}


@app.delete("/devices/{device_id}/favorites/{notice_id}")
def remove_favorite(device_id: str, notice_id: int, s: Session = Depends(get_session)):
    fav = s.scalar(select(Favorite).where(Favorite.device_id == device_id,
                                          Favorite.notice_id == notice_id))
    if fav:
        s.delete(fav)
        s.commit()
    return {"ok": True}


@app.get("/notices")
def list_notices(sido: str | None = None, category: str | None = None, q: str | None = None,
                 limit: int = Query(50, le=200), offset: int = 0, s: Session = Depends(get_session)):
    stmt = select(Notice).order_by(Notice.announce_date.desc().nullslast(), Notice.id.desc())
    if sido:
        stmt = stmt.where(Notice.sido == sido)
    if q:
        stmt = stmt.where(Notice.title.contains(q))
    rows = s.scalars(stmt).all()
    if category:  # JSON 컬럼이라 파이썬에서 필터 (MVP 규모에서 충분)
        rows = [n for n in rows if category in n.tags]
    return [notice_out(n) for n in rows[offset:offset + limit]]


def get_type_fetcher():
    """주택형별 상세 조회 함수. 테스트에서 override 한다."""
    from .collectors import applyhome
    return applyhome.fetch_types


HIDDEN_INFO = {"types", "op", "manage_no", "pblanc_no"}


def detail_out(s: Session, n: Notice, fetch_types) -> dict:
    """공고 + 청약홈 상세 정보 + 주택형별 목록(처음 요청 때 가져와 캐시)."""
    d = dict(n.detail or {})
    types, error = d.get("types"), False
    if types is None and n.source == "APPLYHOME" and d.get("op"):
        try:
            types = fetch_types(d["op"], d["manage_no"], d["pblanc_no"])
            if types:  # 아직 공개 전이라 빈 목록이면 캐시하지 않는다
                n.detail = {**d, "types": types}
                s.commit()
        except Exception:
            types, error = None, True
    return {
        **notice_out(n),
        "info": {k: v for k, v in d.items() if k not in HIDDEN_INFO},
        "types": types,
        "types_error": error,
    }


@app.get("/notices/{notice_id}/detail")
def notice_detail(notice_id: int, s: Session = Depends(get_session), fetch_types=Depends(get_type_fetcher)):
    n = s.get(Notice, notice_id)
    if not n:
        raise HTTPException(404, "notice not found")
    return detail_out(s, n, fetch_types)


@app.get("/compare")
def compare(ids: str = Query(..., description="쉼표로 구분한 공고 id, 최대 3개"),
            s: Session = Depends(get_session), fetch_types=Depends(get_type_fetcher)):
    try:
        id_list = list(dict.fromkeys(int(x) for x in ids.split(",") if x.strip()))
    except ValueError:
        raise HTTPException(400, "ids must be integers")
    if not 2 <= len(id_list) <= 3:
        raise HTTPException(400, "비교는 2~3개 공고만 가능합니다")
    notices = {n.id: n for n in s.scalars(select(Notice).where(Notice.id.in_(id_list)))}
    missing = [i for i in id_list if i not in notices]
    if missing:
        raise HTTPException(404, f"notice not found: {missing}")
    return [detail_out(s, notices[i], fetch_types) for i in id_list]


@app.get("/notices/{notice_id}")
def get_notice(notice_id: int, s: Session = Depends(get_session)):
    n = s.get(Notice, notice_id)
    if not n:
        raise HTTPException(404, "notice not found")
    return notice_out(n)


@app.get("/calendar")
def calendar_view(month: str = Query(..., pattern=r"^\d{4}-\d{2}$"), sido: str | None = None,
                  s: Session = Depends(get_session)):
    """해당 월에 접수 마감이 있는 공고를 날짜별로 묶어서 반환 (지역별 접수 시점)."""
    y, m = map(int, month.split("-"))
    start, end = date(y, m, 1), date(y, m, calendar.monthrange(y, m)[1])
    stmt = select(Notice).where(Notice.apply_end >= start, Notice.apply_end <= end)
    if sido:
        stmt = stmt.where(Notice.sido == sido)
    days: dict[str, list] = {}
    for n in s.scalars(stmt.order_by(Notice.apply_end)):
        if "결과" in n.tags:
            continue
        days.setdefault(n.apply_end.isoformat(), []).append(notice_out(n))
    return {"month": month, "days": days}
