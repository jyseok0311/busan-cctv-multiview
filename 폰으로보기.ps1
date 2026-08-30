# 설치 없이 이 폴더를 같은 와이파이의 다른 기기에 열어주는 간단한 웹서버.
# 사용법: 이 파일을 마우스 오른쪽 클릭 → "PowerShell에서 실행"
# 멈추려면 창에서 Ctrl+C.

$port = 8000
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

$ip = (Get-NetIPAddress -AddressFamily IPv4 |
       Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
       Select-Object -First 1).IPAddress

$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $port)
$listener.Start()

Write-Host ""
Write-Host "  폰에서 아래 주소를 여세요 (같은 와이파이여야 합니다)" -ForegroundColor Cyan
Write-Host ""
Write-Host "      http://${ip}:${port}/" -ForegroundColor Yellow
Write-Host ""
Write-Host "  멈추려면 Ctrl+C" -ForegroundColor DarkGray
Write-Host ""

$types = @{
  '.html'='text/html; charset=utf-8'; '.htm'='text/html; charset=utf-8';
  '.js'='text/javascript; charset=utf-8'; '.css'='text/css; charset=utf-8';
  '.csv'='text/csv; charset=utf-8'; '.json'='application/json; charset=utf-8';
  '.png'='image/png'; '.jpg'='image/jpeg'; '.gif'='image/gif'; '.svg'='image/svg+xml';
  '.webm'='video/webm'; '.mp4'='video/mp4'; '.ico'='image/x-icon'
}

try {
  while ($true) {
    $client = $listener.AcceptTcpClient()
    try {
      $stream = $client.GetStream()
      $buf = New-Object byte[] 8192
      $n = $stream.Read($buf, 0, $buf.Length)
      if ($n -le 0) { $client.Close(); continue }
      $req = [Text.Encoding]::UTF8.GetString($buf, 0, $n)
      $line = ($req -split "`r`n")[0]
      $path = ($line -split ' ')[1]
      if (-not $path) { $path = '/' }
      $path = [Uri]::UnescapeDataString(($path -split '\?')[0])

      $body = $null; $ctype = 'text/html; charset=utf-8'; $status = '200 OK'

      if ($path -eq '/') {
        $rows = ''
        Get-ChildItem -Path $root -File | Sort-Object Name | ForEach-Object {
          $href = [Uri]::EscapeDataString($_.Name)
          $kb = [math]::Round($_.Length / 1KB, 1)
          $rows += "<li><a href=""/$href"">$($_.Name)</a> <span>$kb KB</span></li>"
        }
        $html = @"
<!DOCTYPE html><html lang="ko"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>부산 CCTV</title><style>
body{background:#14161a;color:#e8ebf0;font:16px/1.6 system-ui,sans-serif;margin:0;padding:24px}
h1{font-size:18px;margin:0 0 16px}ul{list-style:none;padding:0;margin:0}
li{border-bottom:1px solid #2c313b;padding:14px 4px;display:flex;gap:10px;align-items:center}
a{color:#4da3ff;text-decoration:none;flex:1;word-break:break-all}span{color:#9aa4b2;font-size:12px}
</style></head><body><h1>부산 실시간 CCTV</h1><ul>$rows</ul></body></html>
"@
        $body = [Text.Encoding]::UTF8.GetBytes($html)
      } else {
        $file = Join-Path $root ($path.TrimStart('/') -replace '/', '\')
        $full = [IO.Path]::GetFullPath($file)
        if ($full.StartsWith([IO.Path]::GetFullPath($root)) -and (Test-Path $full -PathType Leaf)) {
          $body = [IO.File]::ReadAllBytes($full)
          $ext = [IO.Path]::GetExtension($full).ToLower()
          if ($types.ContainsKey($ext)) { $ctype = $types[$ext] } else { $ctype = 'application/octet-stream' }
        } else {
          $status = '404 Not Found'
          $body = [Text.Encoding]::UTF8.GetBytes('<h1>404</h1>')
        }
      }

      $head = "HTTP/1.1 $status`r`nContent-Type: $ctype`r`nContent-Length: $($body.Length)`r`nCache-Control: no-store`r`nConnection: close`r`n`r`n"
      $hb = [Text.Encoding]::ASCII.GetBytes($head)
      $stream.Write($hb, 0, $hb.Length)
      $stream.Write($body, 0, $body.Length)
      $stream.Flush()
    } catch {} finally { $client.Close() }
  }
} finally { $listener.Stop() }
