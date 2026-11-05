"""푸시 발송. 실제 FCM은 서비스계정 키(GOOGLE_APPLICATION_CREDENTIALS)가 있을 때만 사용."""
import logging
from datetime import date, timedelta
from typing import Protocol

from sqlalchemy import select
from sqlalchemy.orm import Session

from .matching import matches, remind_kind
from .models import Device, Notice, NotificationLog, Subscription

log = logging.getLogger(__name__)


class Sender(Protocol):
    def send(self, token: str, title: str, body: str, data: dict) -> None: ...


class LogSender:
    def send(self, token, title, body, data):
        log.info("PUSH -> %s | %s | %s", token[:8], title, body)


class FcmSender:
    def __init__(self):
        import firebase_admin
        from firebase_admin import credentials, messaging
        if not firebase_admin._apps:
            firebase_admin.initialize_app(credentials.ApplicationDefault())
        self._m = messaging

    def send(self, token, title, body, data):
        self._m.send(self._m.Message(
            token=token, data={k: str(v) for k, v in data.items()},
            notification=self._m.Notification(title=title, body=body)))


def _already(session: Session, device_id: str, notice_id: int, kind: str) -> bool:
    return session.scalar(select(NotificationLog.id).where(
        NotificationLog.device_id == device_id, NotificationLog.notice_id == notice_id,
        NotificationLog.kind == kind)) is not None


def _deliver(session, sender, dev, n, kind, title, body) -> bool:
    if _already(session, dev.id, n.id, kind):
        return False
    try:
        sender.send(dev.fcm_token, title, body, {"notice_id": n.id, "kind": kind, "url": n.url})
    except Exception:
        log.exception("send failed device=%s", dev.id)
        return False
    session.add(NotificationLog(device_id=dev.id, notice_id=n.id, kind=kind))
    return True


def _subs(session):
    rows = session.execute(select(Subscription, Device).join(Device, Device.id == Subscription.device_id)).all()
    return [(s, d) for s, d in rows if d.fcm_token]


def notify_new(session: Session, sender: Sender, notices: list[Notice]) -> int:
    sent = 0
    cutoff = date.today() - timedelta(days=14)  # 오래된 공고가 '신규'로 푸시되는 것 방지
    notices = [n for n in notices if n.announce_date is None or n.announce_date >= cutoff]
    for sub, dev in _subs(session):
        for n in notices:
            if matches(sub, n):
                label = "/".join(t for t in n.tags if t not in ("정정", "기타")) or "공고"
                sent += _deliver(session, sender, dev, n, "new", f"[{n.source}] 새 {label} 공고", n.title)
    session.commit()
    return sent


def notify_reminders(session: Session, sender: Sender, today: date | None = None) -> int:
    today = today or date.today()
    notices = session.scalars(select(Notice).where(Notice.apply_end >= today)).all()
    sent = 0
    for sub, dev in _subs(session):
        for n in notices:
            kind = remind_kind(sub, n, today)
            if kind and matches(sub, n):
                d = kind.replace("remind", "")
                sent += _deliver(session, sender, dev, n, kind, f"접수 마감 D-{d}", n.title)
    session.commit()
    return sent
