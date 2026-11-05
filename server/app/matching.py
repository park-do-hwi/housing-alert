from datetime import date

from .classify import pushable
from .models import Notice, Subscription


def matches(sub: Subscription, n: Notice) -> bool:
    """빈 조건 = 전체. 결과성 공고는 구독 조건과 무관하게 푸시하지 않는다."""
    if not pushable(n.tags):
        return False
    if sub.sido and n.sido not in sub.sido:
        return False
    if sub.categories and not (set(sub.categories) & set(n.tags)):
        return False
    if sub.keywords and not any(k in n.title for k in sub.keywords):
        return False
    if sub.exclude_keywords and any(k in n.title for k in sub.exclude_keywords):
        return False
    return True


def remind_kind(sub: Subscription, n: Notice, today: date) -> str | None:
    """마감 D-N 일 때 'remindN' 반환 (구독의 remind_days에 포함된 경우)."""
    if n.apply_end is None:
        return None
    d = (n.apply_end - today).days
    return f"remind{d}" if d in (sub.remind_days or []) else None
