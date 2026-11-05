# 분양 알리미 (housing_alert)

SH·LH·청약홈의 분양·무순위·장기전세 공고를 모아 보여주는 모바일 앱.
**상시 서버 없이** 동작한다: 예약 실행이 공고를 모아 정적 JSON 으로 만들고, 앱은 그 파일만 읽는다.

```
[예약 실행 30분마다]  python -m app.export
   LH·SH 게시판 + 청약홈 API ──▶ public/notices.json, meta.json ──▶ GitHub Pages
                                                                        │
[앱] 받아서 기기에 캐시 ◀──────────────────────────────────────────────┘
     지역·유형 필터, 캘린더, 비교, 내 일정은 모두 기기 안에서 계산
     내 정보(관심 조건·저장한 공고)는 기기의 JSON 파일 한 개에만 저장 → 설정에서 내보내기/가져오기
```

## 폴더
| 폴더 | 내용 |
|---|---|
| `server/` | 수집기. 실제로 쓰는 것은 `app/collectors/`, `app/classify.py`, `app/export.py` |
| `mobile/` | Flutter 앱 |
| `.github/workflows/collect.yml` | 30분마다 수집해 GitHub Pages 에 배포하는 예약 실행 (아직 실행해 보지 않은 초안) |
| `prototype/` | 처음 만든 텔레그램 알림 스크립트 |

## 지금 쓰지 않는 코드
`server/app/{api,db,models,ingest,matching,push,run_ingest}.py`는 정적 JSON 으로 바꾸기 전의 FastAPI·DB 버전이다.
푸시를 붙일 때 `matching.py`·`push.py`의 규칙을 참고할 수 있어 남겨 두었고, 테스트도 계속 통과한다.
필요 없다고 정해지면 지워도 된다.

## 로컬에서 돌려 보기
```powershell
# 1) 수집 → server/public/ (청약홈 키가 없으면 LH·SH 만 나온다)
$env:DATA_GO_KR_KEY = [Environment]::GetEnvironmentVariable('DATA_GO_KR_KEY','User')
cd D:\TaskCore\apps\housing_alert\server
python -m app.export --out public

# 2) 정적 파일 서빙
python -m http.server 8000 --directory public

# 3) 앱 (다른 터미널). 에뮬레이터는 10.0.2.2, 실기기는 PC 의 IP
cd ..\mobile
flutter run --dart-define=DATA_BASE=http://10.0.2.2:8000
```

## 테스트
```powershell
cd server ; python -m pytest -q     # 수집기·분류·export·(옛 API)
cd ..\mobile ; flutter analyze ; flutter test
```
`flutter test` 중 "실제 notices.json" 테스트는 `server/public/notices.json` 이 있을 때만 실행된다.

## 아직 안 한 것
- 공개 저장소 생성, Pages 설정, 예약 실행 실제 가동
- LH·SH 상세(접수 시작일·당첨 발표일 등) 수집, SH·LH 분양 게시판
- 푸시(FCM 주제 방식), 공고 요약, 지도, 자격·가점·가능성 등급, 경쟁률
