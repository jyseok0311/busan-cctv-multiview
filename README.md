# 부산 실시간 CCTV 멀티뷰

부산 지역 공개 CCTV 스트림을 지도와 함께 격자 형태로 동시에 볼 수 있는 단일 HTML 페이지입니다.

## 사용법

- 웹에서 바로 보기: https://jyseok0311.github.io/busan-cctv-multiview/
- 로컬에서 보기: `index.html` 파일을 브라우저로 열면 됩니다.

## 구성

- `index.html` — 전체 앱 (HTML/CSS/JS 단일 파일)

외부 라이브러리는 CDN에서 불러옵니다.

- [Leaflet](https://leafletjs.com/) 1.9.4 — 지도
- [hls.js](https://github.com/video-dev/hls.js/) 1.5.17 — HLS 영상 재생
