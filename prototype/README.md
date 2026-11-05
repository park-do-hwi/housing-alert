# SH/LH 공고 알림

1. `config.example.json` → `config.json` 복사 후 텔레그램 봇 토큰/chat_id 입력
2. `python housing_alert.py --init` (현재 공고를 기준선으로 저장)
3. `python housing_alert.py --dry-run` 으로 매칭 확인
4. 스케줄 등록 (30분마다):
   schtasks /Create /SC MINUTE /MO 30 /TN HousingAlert /TR "python D:\TaskCore\housing_alert\housing_alert.py"

키워드/제외어/지역은 config.json에서 조정. 중복 방지는 seen.json.
