// Amud sync mailbox: stores one opaque, end-to-end-encrypted blob per mailbox.
// The Worker never sees keys or content, only a random mailbox id, a hash of a
// bearer token and ciphertext. Protocol: see README.md.

export interface Env {
  MAILBOX: DurableObjectNamespace;
  REPORTS: DurableObjectNamespace;
  ADMIN_TOKEN?: string; // secret: lets you read reports with GET /v1/report
}

const MAX_BLOB = 256 * 1024; // bytes of base64 text
const IDLE_DAYS = 180; // an untouched mailbox deletes itself
const ID = /^[0-9a-f]{32}$/;

const CORS = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET, PUT, POST, DELETE, OPTIONS',
  'access-control-allow-headers': 'authorization, content-type, if-match',
  'access-control-max-age': '86400',
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json', 'cache-control': 'no-store', ...CORS },
  });

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
    const path = new URL(req.url).pathname.replace(/\/+$/, '');
    if (path === '/v1/health') return json({ ok: true, app: 'amud-sync', v: 1 });
    if (path === '/v1/report') {
      if (req.method === 'GET') {
        const t = /^Bearer (.+)$/.exec(req.headers.get('authorization') ?? '')?.[1];
        if (!env.ADMIN_TOKEN || !t || !same(t, env.ADMIN_TOKEN)) return json({ error: 'forbidden' }, 403);
      } else if (req.method !== 'POST') return json({ error: 'method not allowed' }, 405);
      return env.REPORTS.get(env.REPORTS.idFromName('all')).fetch(req);
    }
    const m = /^\/v1\/([^/]+)$/.exec(path);
    if (!m || !ID.test(m[1])) return json({ error: 'not found' }, 404);
    const stub = env.MAILBOX.get(env.MAILBOX.idFromName(m[1]));
    return stub.fetch(req);
  },
};

async function sha256Hex(s: string): Promise<string> {
  const d = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

function same(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}

/** One mailbox. Storage: `auth` (sha-256 of the bearer token), `rev`, `blob`. */
export class Mailbox implements DurableObject {
  constructor(private state: DurableObjectState) {}

  async fetch(req: Request): Promise<Response> {
    const token = /^Bearer (.{16,200})$/.exec(req.headers.get('authorization') ?? '')?.[1];
    if (!token) return json({ error: 'missing token' }, 401);
    const hash = await sha256Hex(token);
    const stored = await this.state.storage.get<string>('auth');
    // First write claims the mailbox; after that the token must match.
    if (stored && !same(stored, hash)) return json({ error: 'wrong token' }, 403);

    if (req.method === 'GET') {
      if (!stored) return json({ error: 'empty' }, 404);
      const blob = await this.state.storage.get<string>('blob');
      if (blob === undefined) return json({ rev: 0 });
      await this.touch();
      return json({ rev: (await this.state.storage.get<number>('rev')) ?? 0, blob });
    }

    if (req.method === 'DELETE') {
      if (!stored) return json({ error: 'empty' }, 404);
      await this.state.storage.deleteAll();
      await this.state.storage.deleteAlarm();
      return json({ ok: true });
    }

    if (req.method === 'PUT') {
      let body: { blob?: unknown };
      try {
        body = await req.json();
      } catch {
        return json({ error: 'bad json' }, 400);
      }
      if (typeof body.blob !== 'string' || body.blob.length === 0) return json({ error: 'blob required' }, 400);
      if (body.blob.length > MAX_BLOB) return json({ error: 'too large' }, 413);
      const expect = Number(req.headers.get('if-match') ?? 'NaN');
      if (!Number.isInteger(expect) || expect < 0) return json({ error: 'if-match required' }, 428);
      const rev = (await this.state.storage.get<number>('rev')) ?? 0;
      if (expect !== rev) {
        // Someone else wrote first: hand back the current copy to merge.
        const blob = await this.state.storage.get<string>('blob');
        return json({ error: 'conflict', rev, blob }, 409);
      }
      await this.state.storage.put({ auth: hash, rev: rev + 1, blob: body.blob });
      await this.touch();
      return json({ rev: rev + 1 });
    }

    return json({ error: 'method not allowed' }, 405);
  }

  private touch() {
    return this.state.storage.setAlarm(Date.now() + IDLE_DAYS * 86400_000);
  }

  async alarm() {
    await this.state.storage.deleteAll();
  }
}

const UID = /^[0-9a-f]{32}$/;
const REPORT_LIMITS = { location: 300, type: 60, text: 4000, details: 2000, correction: 1000, app: 40 };
const PER_USER_PER_DAY = 20;

/** All text reports, one row each, tied only to a random per-install user id. */
export class Reports implements DurableObject {
  constructor(private state: DurableObjectState) {
    state.storage.sql.exec(`CREATE TABLE IF NOT EXISTS reports (
      id INTEGER PRIMARY KEY AUTOINCREMENT, ts INTEGER NOT NULL, uid TEXT NOT NULL,
      location TEXT, type TEXT, text TEXT, details TEXT, correction TEXT, app TEXT)`);
  }

  async fetch(req: Request): Promise<Response> {
    if (req.method === 'GET') {
      const rows = this.state.storage.sql.exec('SELECT * FROM reports ORDER BY id DESC LIMIT 500').toArray();
      return json({ reports: rows });
    }
    let b: Record<string, unknown>;
    try {
      b = await req.json();
    } catch {
      return json({ error: 'bad json' }, 400);
    }
    if (typeof b.uid !== 'string' || !UID.test(b.uid)) return json({ error: 'uid required' }, 400);
    const f = (k: keyof typeof REPORT_LIMITS) => {
      const v = b[k];
      return typeof v === 'string' ? v.slice(0, REPORT_LIMITS[k]) : '';
    };
    if (!f('details').trim()) return json({ error: 'details required' }, 400);
    const now = Date.now();
    const recent = this.state.storage.sql
      .exec('SELECT COUNT(*) AS n FROM reports WHERE uid = ? AND ts > ?', b.uid, now - 86400_000)
      .one().n as number;
    if (recent >= PER_USER_PER_DAY) return json({ error: 'too many reports today' }, 429);
    this.state.storage.sql.exec(
      'INSERT INTO reports (ts, uid, location, type, text, details, correction, app) VALUES (?,?,?,?,?,?,?,?)',
      now, b.uid, f('location'), f('type'), f('text'), f('details'), f('correction'), f('app'),
    );
    return json({ ok: true });
  }
}
