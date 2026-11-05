import uuid
from datetime import date, datetime, timezone

from sqlalchemy import JSON, Date, DateTime, ForeignKey, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from .db import Base


def now():
    return datetime.now(timezone.utc)


class Notice(Base):
    __tablename__ = "notice"
    __table_args__ = (UniqueConstraint("source", "ext_id"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    source: Mapped[str] = mapped_column(String(16))
    ext_id: Mapped[str] = mapped_column(String(64))
    title: Mapped[str] = mapped_column(String(500))
    tags: Mapped[list] = mapped_column(JSON, default=list)
    sido: Mapped[str] = mapped_column(String(16), default="")
    announce_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    apply_end: Mapped[date | None] = mapped_column(Date, nullable=True)
    url: Mapped[str] = mapped_column(String(500), default="")
    raw_hash: Mapped[str] = mapped_column(String(64), default="")
    # 청약홈 상세(일정·주소·세대수 등)와 주택형 캐시. 날짜는 ISO 문자열로 저장.
    detail: Mapped[dict] = mapped_column(JSON, default=dict)
    first_seen: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)


class Device(Base):
    __tablename__ = "device"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    fcm_token: Mapped[str] = mapped_column(String(300), default="")
    platform: Mapped[str] = mapped_column(String(16), default="")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)


class Subscription(Base):
    """빈 리스트 = 전체. 한 기기당 1개."""
    __tablename__ = "subscription"

    device_id: Mapped[str] = mapped_column(ForeignKey("device.id"), primary_key=True)
    sido: Mapped[list] = mapped_column(JSON, default=list)
    categories: Mapped[list] = mapped_column(JSON, default=list)
    keywords: Mapped[list] = mapped_column(JSON, default=list)
    exclude_keywords: Mapped[list] = mapped_column(JSON, default=list)
    remind_days: Mapped[list] = mapped_column(JSON, default=lambda: [3, 1])


class Favorite(Base):
    """기기별 관심(저장) 공고."""
    __tablename__ = "favorite"
    __table_args__ = (UniqueConstraint("device_id", "notice_id"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    device_id: Mapped[str] = mapped_column(ForeignKey("device.id"))
    notice_id: Mapped[int] = mapped_column(ForeignKey("notice.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)


class NotificationLog(Base):
    __tablename__ = "notification_log"
    __table_args__ = (UniqueConstraint("device_id", "notice_id", "kind"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    device_id: Mapped[str] = mapped_column(ForeignKey("device.id"))
    notice_id: Mapped[int] = mapped_column(ForeignKey("notice.id"))
    kind: Mapped[str] = mapped_column(String(16))  # new / remind3 / remind1 / changed
    sent_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)
