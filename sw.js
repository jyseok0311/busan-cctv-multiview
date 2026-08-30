// 앱 껍데기만 캐시한다. CCTV 목록·영상은 항상 실시간이어야 하므로 절대 캐시하지 않는다.
const CACHE = 'busan-cctv-shell-v1';
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
        const copy = res.clone();
        caches.open(CACHE).then(c => c.put(req, copy)).catch(() => {});
        return res;
      })
      .catch(() => caches.match(req).then(r => r || caches.match('./index.html')))
  );
});
