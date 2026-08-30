# data.go.kr 에서 받은 CSV 를 앱이 읽는 JSON 으로 바꾼다.
# 사용법: 이 폴더에 CSV 를 넣고 우클릭 → PowerShell에서 실행
#   - 전국주차장정보표준데이터        → data/parking.json
#   - 전국무인교통단속카메라표준데이터 → data/cameras.json
# 부산 자료만 걸러서 크기를 줄인다.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$out  = Join-Path $root 'data'
if (-not (Test-Path $out)) { New-Item -ItemType Directory $out | Out-Null }

function Read-Csv914([string]$path) {
  # 공공데이터포털 CSV 는 CP949 인 경우가 많다. UTF-8 로 먼저 읽어 깨지면 CP949 로 다시 읽는다.
  $utf = Get-Content -Path $path -Encoding UTF8 -TotalCount 1
  if ($utf -match '[\uFFFD]') {
    return Import-Csv -Path $path -Encoding Default
  }
  return Import-Csv -Path $path -Encoding UTF8
}
function Col($row, [string[]]$names) {
  foreach ($n in $names) {
    $p = $row.PSObject.Properties | Where-Object { $_.Name -replace '\s','' -eq ($n -replace '\s','') }
    if ($p -and "$($p.Value)".Trim()) { return "$($p.Value)".Trim() }
  }
  return ''
}
function IsBusan($row) {
  $t = (Col $row @('시도명','소재지도로명주소','소재지지번주소','관리기관명','주차장명'))
  $all = ($row.PSObject.Properties | ForEach-Object { "$($_.Value)" }) -join ' '
  return ($all -match '부산')
}

# ---------- 주차장 ----------
$pFiles = @(Get-ChildItem $root -Filter "*.csv" -Recurse | Where-Object { $_.Name -match "주차장" -and $_.Name -notmatch "교통량" })
if ($pFiles.Count) {
  Write-Host "주차장 CSV $($pFiles.Count)개"
  $rows = @(); foreach ($pf in $pFiles) { $rows += Read-Csv914 $pf.FullName }
  $list = @()
  foreach ($r in $rows) {
    if (-not (IsBusan $r)) { continue }
    $lat = Col $r @('위도'); $lon = Col $r @('경도')
    if (-not ($lat -as [double]) -or -not ($lon -as [double])) { continue }
    $fee = Col $r @('요금정보')
    $list += [ordered]@{
      n = Col $r @('주차장명')
      a = Col $r @('소재지도로명주소','소재지지번주소')
      t = Col $r @('주차장구분')          # 공영/민영
      c = [int](( Col $r @('주차구획수') ) -replace '[^0-9]','' -replace '^$','0')
      f = $fee                              # 무료 / 유료 / 혼합
      free = [bool]($fee -match '무료')
      o = (Col $r @('운영요일')) + ' ' + (Col $r @('평일운영시작시각')) + '~' + (Col $r @('평일운영종료시각'))
      bt = Col $r @('주차기본시간')
      bf = Col $r @('주차기본요금')
      lat = [math]::Round([double]$lat, 6)
      lon = [math]::Round([double]$lon, 6)
    }
  }
  $list | ConvertTo-Json -Depth 3 -Compress | Set-Content (Join-Path $out 'parking.json') -Encoding UTF8
  $freeN = ($list | Where-Object { $_.free }).Count
  Write-Host ("  → parking.json  {0}곳 (무료 {1}곳)" -f $list.Count, $freeN) -ForegroundColor Green
} else { Write-Host "주차장 CSV 없음 (파일명에 '주차장' 포함 필요)" -ForegroundColor Yellow }

# ---------- 단속카메라 ----------
$cFile = Get-ChildItem $root -Filter '*.csv' | Where-Object { $_.Name -match '단속|카메라' } | Select-Object -First 1
if ($cFile) {
  Write-Host "단속카메라 CSV: $($cFile.Name)"
  $rows = Read-Csv914 $cFile.FullName
  $list = @()
  foreach ($r in $rows) {
    if (-not (IsBusan $r)) { continue }
    $lat = Col $r @('위도'); $lon = Col $r @('경도')
    if (-not ($lat -as [double]) -or -not ($lon -as [double])) { continue }
    $list += [ordered]@{
      k = Col $r @('단속구분')                      # 과속/신호과속/주정차 등
      s = [int](( Col $r @('제한속도') ) -replace '[^0-9]','' -replace '^$','0')
      p = Col $r @('설치장소','도로노선명')
      z = Col $r @('보호구역구분')                   # 어린이보호구역 등
      lat = [math]::Round([double]$lat, 6)
      lon = [math]::Round([double]$lon, 6)
    }
  }
  $list | ConvertTo-Json -Depth 3 -Compress | Set-Content (Join-Path $out 'cameras.json') -Encoding UTF8
  Write-Host ("  → cameras.json  {0}개" -f $list.Count) -ForegroundColor Green
} else { Write-Host "단속카메라 CSV 없음 (파일명에 '단속' 또는 '카메라' 포함 필요)" -ForegroundColor Yellow }

Write-Host ""
Write-Host "끝났습니다. data 폴더의 json 파일을 확인하세요." -ForegroundColor Cyan
