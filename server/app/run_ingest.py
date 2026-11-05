"""cron/스케줄러에서 호출: python -m app.run_ingest [--init]
--init : 현재 공고를 저장만 하고 푸시는 보내지 않음(최초 1회, 알림 폭주 방지)"""
import logging
import os
import sys

from .collectors import COLLECTORS
from .db import SessionLocal, init_db
from .ingest import run_collectors
from .push import FcmSender, LogSender, notify_new, notify_reminders


def main():
    logging.basicConfig(level=logging.INFO)
    init_db()
    with SessionLocal() as s:
        new, changed = run_collectors(s, COLLECTORS)
        print(f"신규 {len(new)}건, 변경 {len(changed)}건")
        if "--init" in sys.argv:
            return
        sender = FcmSender() if os.environ.get("GOOGLE_APPLICATION_CREDENTIALS") else LogSender()
        print("신규 푸시", notify_new(s, sender, new), "건, 리마인더", notify_reminders(s, sender), "건")


if __name__ == "__main__":
    main()
