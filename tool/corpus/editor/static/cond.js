'use strict';
// The corpus condition language (packages/siddur_engine condition.dart),
// evaluated against the preview's simulated day.

const NUMERIC = new Set(['dow', 'hDay', 'hMonth', 'hYear', 'roshChodeshDay', 'chanukahDay', 'omerDay', 'hoshanaDay', 'yomTovDay']);

const PRESETS = {
  'Ordinary weekday (Shacharit)': { dow: 2, shacharit: true, weekday: true, diaspora: true, minyan: true, tachanun: true, tachanunShacharit: true, torahReading: false, talUmatar: true, mashivHaruach: true },
  'Monday / Thursday': { dow: 1, monThu: true, shacharit: true, weekday: true, diaspora: true, minyan: true, tachanun: true, tachanunShacharit: true, torahReading: true },
  'Shabbat Shacharit': { dow: 6, shacharit: true, shabbat: true, diaspora: true, minyan: true, torahReading: true, mashivHaruach: true },
  'Shabbat Mincha': { dow: 6, mincha: true, shabbat: true, diaspora: true, minyan: true, torahReading: true, tzidkatcha: true },
  'Friday night': { dow: 5, maariv: true, erevShabbat: true, diaspora: true, minyan: true },
  'Rosh Chodesh': { dow: 3, shacharit: true, roshChodesh: true, roshChodeshDay: 1, weekday: true, diaspora: true, minyan: true, hallel: true, halfHallel: true, torahReading: true },
  'Chol HaMoed Pesach': { dow: 2, shacharit: true, cholHamoed: true, cholHamoedPesach: true, pesach: true, hallel: true, halfHallel: true, torahReading: true, diaspora: true, minyan: true },
  'Yom Tov': { dow: 2, shacharit: true, yomTov: true, yomTovDay: 1, hallel: true, wholeHallel: true, torahReading: true, diaspora: true, minyan: true },
  'Aseret Yemei Teshuva': { dow: 2, shacharit: true, weekday: true, aseretYemeiTeshuva: true, avinuMalkeinu: true, diaspora: true, minyan: true, tachanun: true, tachanunShacharit: true },
  'Public fast': { dow: 2, shacharit: true, weekday: true, publicFast: true, fastDay: true, avinuMalkeinu: true, diaspora: true, minyan: true, torahReading: true },
  'Chanukah': { dow: 2, shacharit: true, chanukah: true, chanukahDay: 3, hallel: true, wholeHallel: true, torahReading: true, diaspora: true, minyan: true },
  'Israel, ordinary weekday': { dow: 2, shacharit: true, weekday: true, il: true, minyan: true, tachanun: true, tachanunShacharit: true },
};

function parseCondition(expr) {
  const toks = [];
  const re = /\s*(?:(\|\||&&|==|!=|<=|>=|[!<>()\[\],])|([A-Za-z_]\w*)|(\d+(?:\.\d+)?))/y;
  let pos = 0; expr = expr.trim();
  while (pos < expr.length) {
    re.lastIndex = pos;
    const m = re.exec(expr);
    if (!m) throw new Error('bad character: ' + expr.slice(pos, pos + 8));
    pos = re.lastIndex;
    toks.push(m[1] ? { t: 'op', v: m[1] } : m[2] ? { t: 'id', v: m[2] } : { t: 'num', v: +m[3] });
  }
  let i = 0;
  const peek = () => toks[i] || {};
  const take = v => { const t = toks[i++]; if (!t) throw new Error('unexpected end of condition'); if (v && t.v !== v) throw new Error(`expected ${v}, got ${t.v}`); return t; };
  const prim = () => {
    const t = take();
    if (t.t === 'num') return () => t.v;
    if (t.t === 'id') return ctx => resolve(t.v, ctx);
    if (t.v === '(') { const e = or(); take(')'); return e; }
    throw new Error('unexpected ' + t.v);
  };
  const cmp = () => {
    const a = prim(), t = peek();
    if (['==', '!=', '<', '<=', '>', '>='].includes(t.v)) {
      take(); const b = prim();
      return c => { const x = a(c), y = b(c); return { '==': x == y, '!=': x != y, '<': x < y, '<=': x <= y, '>': x > y, '>=': x >= y }[t.v]; };
    }
    if (t.t === 'id' && t.v === 'in') {
      take(); take('[');
      const items = [];
      if (peek().v !== ']') { items.push(prim()); while (peek().v === ',') { take(); items.push(prim()); } }
      take(']');
      return c => { const x = a(c); return items.some(f => f(c) == x); };
    }
    return a;
  };
  const un = () => { if (peek().v === '!') { take(); const e = un(); return c => !e(c); } return cmp(); };
  const and = () => { let e = un(); while (peek().v === '&&') { take(); const r = un(), l = e; e = c => !!l(c) && !!r(c); } return e; };
  const or = () => { let e = and(); while (peek().v === '||') { take(); const r = and(), l = e; e = c => !!l(c) || !!r(c); } return e; };
  const f = or();
  if (i !== toks.length) throw new Error('trailing ' + toks[i].v);
  return f;
}

function resolve(id, ctx) {
  if (id === 'true') return true;
  if (id === 'false') return false;
  if (id.startsWith('if_')) return true; // personal circumstance: shown, marked "If: …"
  const v = ctx[id];
  if (v === undefined) return NUMERIC.has(id) ? 0 : false;
  return v;
}

const _condCache = new Map();
// true / false, or null when the condition doesn't parse
function evalCond(expr, ctx = S.ctx) {
  if (!expr) return true;
  let f = _condCache.get(expr);
  if (f === undefined) { try { f = parseCondition(expr); } catch { f = null; } _condCache.set(expr, f); }
  if (!f) return null;
  return !!f(ctx);
}
function condError(expr) { try { parseCondition(expr); return null; } catch (e) { return e.message; } }
function condIds(expr) { return [...new Set((expr.match(/[A-Za-z_]\w*/g) || []).filter(x => !['true', 'false', 'in'].includes(x)))]; }
