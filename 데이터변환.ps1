# data.go.kr 에서 받은 CSV 를 앱이 읽는 JSON 으로 바꾼다.
#
# 사용법: 이 폴더(또는 하위 폴더)에 CSV 를 넣고 우클릭 → "PowerShell에서 실행"
#   파일명에 '주차장'          이 들어간 CSV 전부 → data/parking.json
#   파일명에 '단속' 또는 '카메라' 가 들어간 CSV 전부 → data/cameras.json
#   데이터 기준일자 요약        → data/meta.json  (앱이 "○○ 기준" 으로 표시)
#
# 부산 자료만 걸러서 크기를 줄인다. 출력 필드는 index.html 이 읽는 스키마와 같아야 한다:
#   parking : n a t c f free bt bf o tel lat lon [note]
#   cameras : p s g k lat lon
# 스키마를 바꾸면 index.html 의 drawParkLayer / toggleCamLayer / parkPopup / camPopup 도 함께 고칠 것.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$out  = Join-Path $root 'data'
if (-not (Test-Path $out)) { New-Item -ItemType Directory $out | Out-Null }
$utf8 = New-Object System.Text.UTF8Encoding($false)      # BOM 없는 UTF-8 (fetch 로 읽을 때 안전)

function Read-CsvAny([string]$path) {
  # 공공데이터포털 CSV 는 UTF-8(BOM) 또는 CP949. UTF-8 로 읽어 깨지면 CP949 로 다시 읽는다.
  $head = Get-Content -Path $path -Encoding UTF8 -TotalCount 1
  if ($head -match '�') { return Import-Csv -Path $path -Encoding Default }
  return Import-Csv -Path $path -Encoding UTF8
}
function Col($row, [string[]]$names) {
  foreach ($n in $names) {
    $p = $row.PSObject.Properties | Where-Object { ($_.Name -replace '\s','') -eq ($n -replace '\s','') }
    if ($p -and "$($p.Value)".Trim()) { return "$($p.Value)".Trim() }
  }
  return ''
}
# 시도명·주소·관리기관 같은 '위치' 열에서만 부산을 찾는다.
# (모든 열을 뒤지면 도로명이나 상호에 '부산'이 든 타지역 행까지 들어온다)
function IsBusan($row) {
  $t = Col $row @('시도명','소재지도로명주소','소재지지번주소','관리기관명')
  return ($t -match '부산')
}
function InBusanBox([double]$la, [double]$lo) {
  return ($la -ge 34.8 -and $la -le 35.45 -and $lo -ge 128.7 -and $lo -le 129.35)
}
function Write-Json($obj, [string]$path) {
  # -InputObject @() 로 넘겨야 1건일 때 객체가, 0건일 때 [] 가 아닌 '빈 문자열'이 되는 문제를 피한다
  $json = ConvertTo-Json -InputObject @($obj) -Depth 4 -Compress
  if (-not $json) { $json = '[]' }
  [IO.File]::WriteAllText($path, $json, $utf8)
}
function DateSummary($dates) {
  $d = @($dates | Where-Object { $_ -match '^\d{4}-\d{2}-\d{2}$' } | Sort-Object)
  if (-not $d.Count) { return $null }
  $mode = ($d | Group-Object | Sort-Object Count -Descending | Select-Object -First 1).Name
  return [ordered]@{ asOf = $mode; from = $d[0]; to = $d[-1] }
}

$meta = [ordered]@{ generated = (Get-Date -Format 'yyyy-MM-dd') }

# ---------- 주차장 ----------
$pFiles = @(Get-ChildItem $root -Filter '*.csv' -Recurse |
            Where-Object { $_.Name -match '주차장' -and $_.Name -notmatch '교통량' })
if ($pFiles.Count) {
  Write-Host "주차장 CSV $($pFiles.Count)개"
  $rows = @(); foreach ($f in $pFiles) { $rows += Read-CsvAny $f.FullName }
  $list = New-Object System.Collections.ArrayList
  $dates = @(); $dropped = 0
  foreach ($r in $rows) {
    if (-not (IsBusan $r)) { continue }
    $lat = Col $r @('위도'); $lon = Col $r @('경도')
    if (-not ($lat -as [double]) -or -not ($lon -as [double])) { $dropped++; continue }
    $la = [double]$lat; $lo = [double]$lon
    if (-not (InBusanBox $la $lo)) { $dropped++; continue }
    $dates += (Col $r @('데이터기준일자'))
    # 도로명주소가 비면 지번주소로, '부산광역시' 접두어는 화면에서 군더더기라 제거
    $addr = Col $r @('소재지도로명주소'); if (-not $addr) { $addr = Col $r @('소재지지번주소') }
    $addr = $addr -replace '^부산광역시\s*',''
    $fee  = Col $r @('요금정보')
    $note = Col $r @('특기사항')
    $o = [ordered]@{
      n    = Col $r @('주차장명')
      a    = $addr
      t    = (Col $r @('주차장구분')) + '·' + (Col $r @('주차장유형'))
      c    = [int](((Col $r @('주차구획수')) -replace '[^0-9]','') -as [int])
      f    = $fee
      free = [bool]($fee -eq '무료')
      bt   = Col $r @('주차기본시간')
      bf   = Col $r @('주차기본요금')
      o    = (((Col $r @('운영요일')) + ' ' + (Col $r @('평일운영시작시각')) + '~' + (Col $r @('평일운영종료시각'))).Trim())
      tel  = Col $r @('전화번호')
      lat  = [math]::Round($la, 6)
      lon  = [math]::Round($lo, 6)
    }
    if ($note -and $note.Length -le 120) { $o.note = $note }
    [void]$list.Add($o)
  }
  Write-Json $list (Join-Path $out 'parking.json')
  $free = @($list | Where-Object { $_['free'] }).Count
  $meta.parking = [ordered]@{ count = $list.Count; free = $free; date = (DateSummary $dates) }
  Write-Host ("  → parking.json  {0}곳 (무료 {1}곳) · 제외 {2}건" -f $list.Count, $free, $dropped) -ForegroundColor Green
} else { Write-Host "주차장 CSV 없음 (파일명에 '주차장' 포함 필요)" -ForegroundColor Yellow }

# ---------- 단속카메라 ----------
$cFiles = @(Get-ChildItem $root -Filter '*.csv' -Recurse | Where-Object { $_.Name -match '단속|카메라' })
if ($cFiles.Count) {
  Write-Host "단속카메라 CSV $($cFiles.Count)개"
  $rows = @(); foreach ($f in $cFiles) { $rows += Read-CsvAny $f.FullName }
  $list = New-Object System.Collections.ArrayList
  $seen = @{}; $dates = @(); $dropped = 0; $dup = 0
  foreach ($r in $rows) {
    if (-not (IsBusan $r)) { continue }
    $lat = Col $r @('위도'); $lon = Col $r @('경도')
    if (-not ($lat -as [double]) -or -not ($lon -as [double])) { $dropped++; continue }
    $la = [double]$lat; $lo = [double]$lon
    if (-not (InBusanBox $la $lo)) { $dropped++; continue }
    $place = Col $r @('설치장소'); if (-not $place) { $place = Col $r @('도로노선명') }
    $key = '{0:F5}|{1:F5}|{2}' -f $la, $lo, $place
    if ($seen.ContainsKey($key)) { $dup++; continue }
    $seen[$key] = $true
    $dates += (Col $r @('데이터기준일자'))
    [void]$list.Add([ordered]@{
      p   = $place
      s   = [int](((Col $r @('제한속도')) -replace '[^0-9]','') -as [int])
      g   = ((Col $r @('시군구명')) -replace '청$','')
      k   = Col $r @('단속구분')     # 코드값(3·4…). 공식 코드표 미확인 — 앱은 종류를 표기하지 않고 제한속도만 쓴다
      lat = [math]::Round($la, 6)
      lon = [math]::Round($lo, 6)
    })
  }
  Write-Json $list (Join-Path $out 'cameras.json')
  $withSpeed = @($list | Where-Object { $_['s'] -gt 0 }).Count
  $gus = @($list | ForEach-Object { $_['g'] } | Where-Object { $_ } | Sort-Object -Unique)
  $meta.cameras = [ordered]@{ count = $list.Count; withSpeed = $withSpeed; districts = $gus; date = (DateSummary $dates) }
  Write-Host ("  → cameras.json  {0}개 (제한속도 표기 {1}) · 중복 {2} · 제외 {3} · 구·군 {4}개" -f $list.Count, $withSpeed, $dup, $dropped, $gus.Count) -ForegroundColor Green
} else { Write-Host "단속카메라 CSV 없음 (파일명에 '단속' 또는 '카메라' 포함 필요)" -ForegroundColor Yellow }

[IO.File]::WriteAllText((Join-Path $out 'meta.json'), (ConvertTo-Json -InputObject $meta -Depth 4 -Compress), $utf8)
Write-Host ""
Write-Host "끝. data 폴더의 parking.json / cameras.json / meta.json 을 확인하세요." -ForegroundColor Cyan
