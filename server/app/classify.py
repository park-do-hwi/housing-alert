"""공고 제목/유형 텍스트 → 태그·시도 분류."""
import re

# 푸시 대상에서 제외하는 '결과성' 공고
RESULT_WORDS = ("당첨자", "결과", "계약안내", "입주안내", "사전방문", "예비입주자")

SIDO_PREFIX = {
    "서울": "서울", "경기": "경기", "인천": "인천", "부산": "부산", "대구": "대구",
    "광주": "광주", "대전": "대전", "울산": "울산", "세종": "세종", "강원": "강원",
    "충북": "충북", "충청북": "충북", "충남": "충남", "충청남": "충남",
    "전북": "전북", "전라북": "전북", "전남": "전남", "전라남": "전남",
    "경북": "경북", "경상북": "경북", "경남": "경남", "경상남": "경남", "제주": "제주",
}


def tags_for(title: str, type_text: str = "") -> list[str]:
    text = f"{title} {type_text}"
    tags: list[str] = []
    if "장기전세" in text:
        tags.append("장기전세")
    if "무순위" in text or "잔여세대" in text:
        tags.append("무순위")
    if "분양" in text:
        tags.append("분양")
    if re.search(r"임대|행복주택|전세", text) and "장기전세" not in tags:
        tags.append("임대")
    # '예비입주자 모집공고'는 지금 신청받는 모집이라 결과성이 아니다(당첨자 발표·입주안내문 등만 결과성).
    result_words = [w for w in RESULT_WORDS if not (w == "예비입주자" and "모집" in title)]
    if any(w in text for w in result_words):
        tags.append("결과")
    if "정정" in text:
        tags.append("정정")
    return tags or ["기타"]


def sido_for(region_text: str) -> str:
    region_text = (region_text or "").strip()
    for prefix, name in SIDO_PREFIX.items():
        if region_text.startswith(prefix):
            return name
    return region_text[:2]


# 신청자와 무관한 글: 공급자 대상 매입공고, 휴무·교육 안내, 기존 입주자 안내 등
NOISE_RE = re.compile(
    r"매입\s*공고|휴무|교육|재계약|입주\s*안내|입주자\s*안내|어린이집|상가|용역|입찰|"
    r"설문|채용|지연\s*안내|점검|이전\s*안내|개정|사전점검"
)


def is_relevant(title: str, tags: list[str]) -> bool:
    """앱에 보여줄 공고인가: 분류된 태그가 있고 잡글이 아니어야 한다.
    '결과' 태그는 앱이 숨기므로 여기선 걸러내지 않는다(결과 조회 기능용)."""
    if tags == ["기타"]:
        return False
    if "결과" in tags:
        return True
    return not NOISE_RE.search(title)


def pushable(tags: list[str]) -> bool:
    """신규 공고 푸시 대상 여부: 결과성 공고는 제외, 핵심 카테고리만."""
    if "결과" in tags:
        return False
    return bool(set(tags) & {"분양", "무순위", "장기전세", "임대"})
