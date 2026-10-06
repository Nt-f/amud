// Shared text is captured before Flutter starts, and consumed once by Dart.
(() => {
  const base = new URL('./', document.baseURI);
  const query = new URL(location.href).searchParams;
  if (query.has('share-text') || query.has('share-url') || query.has('share-title')) {
    const text = [query.get('share-text'), query.get('share-url')].filter(Boolean).join('\n').slice(0, 16000);
    sessionStorage.setItem('amud-shared-note', JSON.stringify({title: (query.get('share-title') || '').slice(0, 160), text}));
    history.replaceState(null, '', base.href + location.hash);
  }
  // HTTPS links use paths so app-link verification can match them. Preserve
  // existing hash links and normalize path links into Flutter's hash router.
  if (!location.hash && location.pathname.startsWith(base.pathname) && location.pathname !== base.pathname) {
    const route = '/' + location.pathname.slice(base.pathname.length);
    history.replaceState(null, '', base.href + '#' + route + location.search);
  }
  const api = new URL('api/push/', base);
  const key = 'amud-push';
  let savedPlan = [];
  const stored = () => { try { return JSON.parse(localStorage.getItem(key) || 'null'); } catch (_) { return null; } };
  const config = async () => {
    try { const r = await fetch(new URL('config', api), {cache: 'no-store'}); return r.ok ? await r.json() : null; }
    catch (_) { return null; }
  };
  const request = async (path, method, body, token) => {
    const r = await fetch(new URL(path, api), {method, headers: {'Content-Type': 'application/json', ...(token ? {Authorization: 'Bearer ' + token} : {})},
      ...(body ? {body: JSON.stringify(body)} : {})});
    if (!r.ok) throw new Error('Web push server returned ' + r.status);
    return r.status === 204 ? null : r.json();
  };
  const registration = async () => {
    let reg = await navigator.serviceWorker.getRegistration(base.href);
    if (!reg) reg = await navigator.serviceWorker.register(new URL('sw.js', base), {scope: base.pathname});
    return navigator.serviceWorker.ready;
  };
  window.amudWeb = {
    takeSharedNote() { const value = sessionStorage.getItem('amud-shared-note'); sessionStorage.removeItem('amud-shared-note'); return value; },
    async badge(count) {
      try {
        if (count > 0 && navigator.setAppBadge) await navigator.setAppBadge(count);
        else if (navigator.clearAppBadge) await navigator.clearAppBadge();
      } catch (_) { /* Badging is optional on browsers without an installed PWA. */ }
    },
    async pushAvailable() { return 'PushManager' in window && 'serviceWorker' in navigator && !!(await config())?.publicKey; },
    async pushEnabled() {
      if (!stored() || !('serviceWorker' in navigator)) return false;
      const reg = await navigator.serviceWorker.getRegistration(base.href);
      return !!(await reg?.pushManager.getSubscription());
    },
    async enablePush() {
      const cfg = await config();
      if (!cfg?.publicKey || !('PushManager' in window)) return false;
      if (await Notification.requestPermission() !== 'granted') return false;
      const reg = await registration();
      const padded = cfg.publicKey.replace(/-/g, '+').replace(/_/g, '/');
      const bytes = Uint8Array.from(atob(padded + '='.repeat((4 - padded.length % 4) % 4)), c => c.charCodeAt(0));
      const subscription = await reg.pushManager.getSubscription() || await reg.pushManager.subscribe({userVisibleOnly: true, applicationServerKey: bytes});
      const existing = stored();
      const record = await request('subscriptions', 'POST', {subscription: subscription.toJSON(), plan: savedPlan}, existing?.token);
      localStorage.setItem(key, JSON.stringify(record));
      return true;
    },
    async disablePush() {
      const current = stored();
      // Cancel on the server before discarding the capability token.
      if (current) await request('subscriptions/' + current.id, 'DELETE', null, current.token);
      const reg = await navigator.serviceWorker.getRegistration(base.href);
      await (await reg?.pushManager.getSubscription())?.unsubscribe();
      localStorage.removeItem(key);
    },
    async submitPlan(serialized) {
      savedPlan = JSON.parse(serialized);
      const current = stored();
      if (!current || !await this.pushEnabled()) return false;
      try { await request('subscriptions/' + current.id, 'PUT', {plan: savedPlan}, current.token); return true; }
      catch (_) { return false; } // Open-tab notifications remain a fallback.
    },
  };
})();
