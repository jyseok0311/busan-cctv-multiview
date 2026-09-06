// 앱 껍데기만 캐시한다. CCTV 목록·영상은 항상 실시간이어야 하므로 절대 캐시하지 않는다.
const CACHE = 'busan-cctv-shell-v2';
const SHELL = ['./', './index.html', './manifest.json', './icon-192.png', './icon-512.png'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  // 같은 출처의 앱 파일만 다룬다 (부산시 API·영상·CDN 은 건드리지 않음)
  if (url.origin !== self.location.origin) return;

  // 네트워크 우선 — 새 버전이 바로 반영되고, 오프라인일 때만 캐시로 떨어진다
  e.respondWith(
    fetch(req)
      .then(res => {
        // 실패 응답(404/500)을 캐시에 넣으면 오프라인에서 그 오류가 영구히 재생된다
        if (res.ok){
          const copy = res.clone();
          caches.open(CACHE).then(c => c.put(req, copy)).catch(() => {});
        }
        return res;
      })
      .catch(() => caches.match(req).then(r => {
        if (r) return r;
        // 페이지 이동일 때만 index.html 로 대체한다. data/*.json 요청에 HTML 을 돌려주면
        // 앱이 "데이터 파일이 없습니다"라고 잘못 안내하게 된다.
        if (req.mode === 'navigate') return caches.match('./index.html');
        return new Response('', {status:503, statusText:'offline'});
      }))
  );
});
