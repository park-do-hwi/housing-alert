"""SH/LH 분양·무순위·장기전세 공고 알림.

사용법:
  python housing_alert.py            # 새 공고 확인 후 텔레그램 발송
  python housing_alert.py --dry-run  # 발송 없이 매칭 결과만 출력 (상태 저장 안 함)
  python housing_alert.py --init     # 현재 공고를 모두 '확인함'으로 저장 (첫 실행 시 알림 폭주 방지)

설정: config.json (config.example.json 참고). 환경변수 TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID 우선.
"""
import argparse
import json
import os
import re
import sys
from pathlib import Path

import requests
from bs4 import BeautifulSoup

BASE = Path(__file__).parent
STATE = BASE / "seen.json"
UA = {"User-Agent": "Mozilla/5.0 (housing-alert)"}

LH_LIST = "https://apply.lh.or.kr/lhapply/apply/wt/wrtanc/selectWrtancList.do?mi=1026"
SH_LIST = "https://www.i-sh.co.kr/main/lay2/program/S1T294C297/www/brd/m_241/list.do"
SH_VIEW = "https://www.i-sh.co.kr/main/lay2/program/S1T294C297/www/brd/m_241/view.do?seq={seq}"


def fetch(url):
    r = requests.get(url, headers=UA, timeout=20)
    r.raise_for_status()
    for enc in ("utf-8", "cp949"):
        try:
            return r.content.decode(enc)
        except UnicodeDecodeError:
            continue
    return r.content.decode("utf-8", errors="ignore")


def collect_lh():
    soup = BeautifulSoup(fetch(LH_LIST), "html.parser")
    items = []
    for tr in soup.select("tbody tr"):
        a = tr.select_one("a.wrtancInfoBtn")
        if not a:
            continue
        tds = [td.get_text(" ", strip=True) for td in tr.find_all("td")]
        title = re.sub(r"\s+", " ", a.get_text(" ", strip=True))
        items.append({
            "id": "LH-" + a.get("data-id1", title),
            "org": "LH",
            "type": tds[1] if len(tds) > 1 else "",
            "title": title,
            "region": tds[3] if len(tds) > 3 else "",
            "date": tds[5] if len(tds) > 5 else "",
            "deadline": tds[6] if len(tds) > 6 else "",
            "status": tds[7] if len(tds) > 7 else "",
            "url": LH_LIST,  # 상세는 JS 호출이라 목록 페이지로 연결
        })
    return items


def collect_sh():
    soup = BeautifulSoup(fetch(SH_LIST), "html.parser")
    items = []
    for a in soup.select("td.txtL a[onclick*=getDetailView]"):
        m = re.search(r"getDetailView\('(\d+)'\)", a.get("onclick", ""))
        if not m:
            continue
        tr = a.find_parent("tr")
        tds = tr.find_all("td")
        title = re.sub(r"\s+", " ", a.get_text(" ", strip=True)).replace("NEW", "").strip()
        items.append({
            "id": "SH-" + m.group(1),
            "org": "SH",
            "type": "",
            "title": title,
            "region": "서울",
            "date": tds[-2].get_text(strip=True) if len(tds) >= 2 else "",
            "deadline": "",
            "status": "",
            "url": SH_VIEW.format(seq=m.group(1)),
        })
    return items


def match(item, cfg):
    text = f'{item["title"]} {item["type"]}'
    if any(k in text for k in cfg["exclude_keywords"]):
        return False
    if not any(k in text for k in cfg["keywords"]):
        return False
    regions = cfg.get("regions") or []
    if regions and item["org"] == "LH" and not any(r in item["region"] for r in regions):
        return False
    return True


def fmt(item):
    lines = [f'🏠 [{item["org"]}] {item["title"]}']
    meta = " · ".join(x for x in (item["type"], item["region"]) if x)
    if meta:
        lines.append(meta)
    if item["date"] or item["deadline"]:
        lines.append(f'공고 {item["date"]}' + (f' ~ 마감 {item["deadline"]}' if item["deadline"] else ""))
    lines.append(item["url"])
    return "\n".join(lines)


def send_telegram(token, chat_id, text):
    r = requests.post(
        f"https://api.telegram.org/bot{token}/sendMessage",
        data={"chat_id": chat_id, "text": text, "disable_web_page_preview": "true"},
        timeout=20,
    )
    r.raise_for_status()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--init", action="store_true")
    args = ap.parse_args()

    cfg = json.loads((BASE / "config.json").read_text(encoding="utf-8")) if (BASE / "config.json").exists() \
        else json.loads((BASE / "config.example.json").read_text(encoding="utf-8"))
    token = os.environ.get("TELEGRAM_BOT_TOKEN") or cfg.get("telegram_bot_token", "")
    chat = os.environ.get("TELEGRAM_CHAT_ID") or cfg.get("telegram_chat_id", "")

    items = []
    for name, fn in (("LH", collect_lh), ("SH", collect_sh)):
        try:
            got = fn()
            print(f"{name}: {len(got)}건 수집")
            items += got
        except Exception as e:  # 한쪽 실패해도 다른 쪽은 계속
            print(f"{name} 수집 실패: {e}", file=sys.stderr)

    seen = set(json.loads(STATE.read_text(encoding="utf-8"))) if STATE.exists() else set()
    first_run = not STATE.exists()
    hits = [i for i in items if match(i, cfg)]
    new = [i for i in hits if i["id"] not in seen]

    if args.dry_run:
        for i in hits:
            print(("NEW " if i["id"] not in seen else "    ") + fmt(i).replace("\n", " | "))
        return

    if args.init or first_run:
        STATE.write_text(json.dumps(sorted(seen | {i["id"] for i in items}), ensure_ascii=False), encoding="utf-8")
        print(f"초기화: {len(items)}건을 확인함 처리 (알림 없음)")
        return

    if new and not (token and chat):
        print("텔레그램 토큰/chat_id가 없어 발송 못함", file=sys.stderr)
        sys.exit(1)
    for i in reversed(new):
        send_telegram(token, chat, fmt(i))
        seen.add(i["id"])
    seen |= {i["id"] for i in items}
    STATE.write_text(json.dumps(sorted(seen), ensure_ascii=False), encoding="utf-8")
    print(f"신규 알림 {len(new)}건 발송")


if __name__ == "__main__":
    main()
