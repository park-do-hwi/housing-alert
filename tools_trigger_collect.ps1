# GitHub 예약 실행이 몇 시간씩 밀려서, 이 PC가 30분마다 collect 워크플로를 직접 깨운다.
# 토큰: D:\TaskCore\secrets\housing_alert\gh_token.txt (저장소 밖, 한 줄). 권한: 이 저장소 Actions 읽기·쓰기.
$f = 'D:\TaskCore\secrets\housing_alert\gh_token.txt'
if (-not (Test-Path $f)) { exit 2 }
$t = (Get-Content $f -Raw).Trim()
$h = @{ Authorization = "Bearer $t"; Accept = 'application/vnd.github+json' }
$u = 'https://api.github.com/repos/park-do-hwi/housing-alert/actions'
try {
  # 이미 돌고 있거나 대기 중이면 또 깨우지 않는다.
  $r = Invoke-RestMethod -Headers $h -Uri "$u/workflows/collect.yml/runs?per_page=3"
  if ($r.workflow_runs | Where-Object { $_.status -in 'queued','in_progress' }) { exit 0 }
  Invoke-RestMethod -Method Post -Headers $h -Uri "$u/workflows/collect.yml/dispatches" -Body '{"ref":"main"}' | Out-Null
} catch { exit 1 }
