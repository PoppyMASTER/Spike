// SkySpike social server — Cloudflare Worker + D1.
// Accounts (anonymous, token based), profiles, friends, private messages, public/club chat,
// direct match invites, clubs, leaderboards, ranked matchmaking with Elo, activity feed,
// blocking and reports. Clients poll /v1/ping every few seconds for notifications.

const ONLINE_S = 45;            // seen within this many seconds = online
const MSG_MAX = 300;
const NAME_RE = /^[\p{L}\p{N} _.\-]{3,16}$/u;
const AVATAR_RE = /^[a-z]{2,12}$/;
const COLOR_RE = /^#[0-9a-fA-F]{6}$/;

const BAD = ["connard", "connasse", "salope", "pute", "putain", "encule", "enculé", "fdp", "ntm", "nique",
  "batard", "bâtard", "pd", "tapette", "negro", "nègre", "negre", "bougnoule", "youpin", "fuck", "shit",
  "bitch", "nigger", "nigga", "retard", "cunt", "whore", "slut", "faggot"];

const now = () => Math.floor(Date.now() / 1000);
const json = (o, s = 200) => new Response(JSON.stringify(o), {
  status: s, headers: { "content-type": "application/json; charset=utf-8", "access-control-allow-origin": "*" },
});
const fail = (msg, s = 400) => json({ error: msg }, s);

async function sha256(t) {
  const b = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(t));
  return [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, "0")).join("");
}
function newToken() {
  const a = new Uint8Array(24);
  crypto.getRandomValues(a);
  return [...a].map((x) => x.toString(16).padStart(2, "0")).join("");
}
function clean(t, max = MSG_MAX) {
  t = String(t ?? "").replace(/[\u0000-\u001f\u007f]/g, " ").replace(/\s+/g, " ").trim().slice(0, max);
  for (const w of BAD) {
    const re = new RegExp(`(^|[^\\p{L}])(${w})(?=$|[^\\p{L}])`, "giu");
    t = t.replace(re, (m, a, b) => a + "*".repeat(b.length));
  }
  return t;
}
const level = (xp) => Math.floor(Math.sqrt(Math.max(0, xp) / 50)) + 1;
function tier(elo) {
  if (elo < 900) return "Bronze";
  if (elo < 1100) return "Argent";
  if (elo < 1300) return "Or";
  if (elo < 1500) return "Platine";
  if (elo < 1700) return "Diamant";
  return "Légende";
}
function pub(u, club) {
  if (!u) return null;
  const t = now();
  let team = [], trophies = {};
  try { team = JSON.parse(u.team); } catch {}
  try { trophies = JSON.parse(u.trophies); } catch {}
  return {
    id: u.id, name: u.name, tag: u.tag, avatar: u.avatar, color: u.color, bio: u.bio, team, trophies,
    ovr: u.ovr, codex: u.codex, solo_w: u.solo_w, solo_l: u.solo_l, xp: u.xp, level: level(u.xp),
    elo: u.elo, tier: tier(u.elo), ranked_w: u.ranked_w, ranked_l: u.ranked_l,
    online_w: u.online_w, online_l: u.online_l,
    online: t - u.last_seen < ONLINE_S, status: u.status, last_seen: u.last_seen, created: u.created,
    club_id: u.club_id, club: club ? { id: club.id, name: club.name, tag: club.tag, color: club.color } : null,
  };
}
// light author card for chat lines / lists
const card = (r) => ({ id: r.id, name: r.name, tag: r.tag, avatar: r.avatar, color: r.color,
  online: now() - r.last_seen < ONLINE_S, status: r.status, elo: r.elo, tier: tier(r.elo), level: level(r.xp),
  club_tag: r.club_tag ?? null });
const CARD_COLS = "u.id, u.name, u.tag, u.avatar, u.color, u.last_seen, u.status, u.elo, u.xp, c.tag AS club_tag";

class Api {
  constructor(env, req) { this.db = env.DB; this.req = req; this.me = null; }
  q(sql, ...p) { return this.db.prepare(sql).bind(...p); }
  async one(sql, ...p) { return await this.q(sql, ...p).first(); }
  async all(sql, ...p) { return (await this.q(sql, ...p).all()).results; }
  async run(sql, ...p) { return await this.q(sql, ...p).run(); }

  async auth() {
    const h = this.req.headers.get("authorization") || "";
    const tok = h.replace(/^Bearer\s+/i, "").trim();
    if (!tok) return false;
    this.me = await this.one("SELECT * FROM users WHERE token_hash = ?", await sha256(tok));
    return !!this.me && !this.me.banned;
  }
  async club(id) { return id ? await this.one("SELECT * FROM clubs WHERE id = ?", id) : null; }
  async user(id) { return await this.one("SELECT * FROM users WHERE id = ?", id); }
  async blocked(a, b) {
    return !!(await this.one("SELECT 1 FROM blocks WHERE (a = ? AND b = ?) OR (a = ? AND b = ?)", a, b, b, a));
  }
  async friends(a, b) { return !!(await this.one("SELECT 1 FROM friends WHERE a = ? AND b = ? AND status = 'friend'", a, b)); }
  // parse event data and resolve friend names ("est maintenant ami avec X")
  async withNames(rows) {
    const out = rows.map((r) => ({ ...r, data: typeof r.data === "string" ? JSON.parse(r.data) : r.data }));
    for (const e of out) {
      if (e.kind === "friend" && e.data.with) {
        const u = await this.one("SELECT name, tag FROM users WHERE id = ?", e.data.with);
        e.data.name = u ? `${u.name}#${u.tag}` : "?";
      }
    }
    return out;
  }
  async event(uid, kind, data = {}) {
    await this.run("INSERT INTO events (uid, kind, data, created) VALUES (?, ?, ?, ?)", uid, kind, JSON.stringify(data), now());
  }
  async spam(uid) {   // max 5 lines per 10 s across messages and chat
    const t = now() - 10;
    const a = await this.one("SELECT (SELECT COUNT(*) FROM messages WHERE src = ? AND created > ?) + (SELECT COUNT(*) FROM chat WHERE src = ? AND created > ?) AS n", uid, t, uid, t);
    return a.n >= 5;
  }
  async gainXp(uid, xp) {
    const before = await this.one("SELECT xp FROM users WHERE id = ?", uid);
    await this.run("UPDATE users SET xp = xp + ? WHERE id = ?", xp, uid);
    const l0 = level(before.xp), l1 = level(before.xp + xp);
    if (l1 > l0 && l1 % 5 === 0) await this.event(uid, "level", { level: l1 });
  }

  // ------------------------------------------------------------------ accounts
  async register(b) {
    const ip = this.req.headers.get("cf-connecting-ip") || "";
    const recent = await this.one("SELECT COUNT(*) AS n FROM users WHERE ip = ? AND created > ?", ip, now() - 3600);
    if (ip && recent.n >= 8) return fail("Trop de comptes créés depuis ce réseau, réessaie plus tard", 429);
    const name = clean(b.name, 16);
    if (!NAME_RE.test(name)) return fail("Pseudo : 3 à 16 lettres, chiffres, espaces, . _ -");
    const avatar = AVATAR_RE.test(b.avatar || "") ? b.avatar : "vex";
    const token = newToken();
    for (let i = 0; i < 12; i++) {
      const tag = 1000 + Math.floor(Math.random() * 9000);
      try {
        const t = now();
        await this.run("INSERT INTO users (name, tag, token_hash, avatar, created, last_seen, ip) VALUES (?, ?, ?, ?, ?, ?, ?)",
          name, tag, await sha256(token), avatar, t, t, ip);
        const u = await this.one("SELECT * FROM users WHERE token_hash = ?", await sha256(token));
        return json({ token, me: pub(u, null) });
      } catch (e) { /* tag taken, retry */ }
    }
    return fail("Pseudo trop demandé, essaie une variante");
  }
  async getMe() { return json({ me: pub(this.me, await this.club(this.me.club_id)) }); }
  async setMe(b) {
    const u = this.me;
    let name = u.name, tag = u.tag;
    if (b.name !== undefined && clean(b.name, 16) !== u.name) {
      name = clean(b.name, 16);
      if (!NAME_RE.test(name)) return fail("Pseudo : 3 à 16 lettres, chiffres, espaces, . _ -");
      if (await this.one("SELECT 1 FROM users WHERE name = ? COLLATE NOCASE AND tag = ? AND id != ?", name, tag, u.id))
        tag = 1000 + Math.floor(Math.random() * 9000);
    }
    const avatar = AVATAR_RE.test(b.avatar || "") ? b.avatar : u.avatar;
    const color = COLOR_RE.test(b.color || "") ? b.color : u.color;
    const bio = b.bio !== undefined ? clean(b.bio, 120) : u.bio;
    const team = Array.isArray(b.team) ? JSON.stringify(b.team.slice(0, 3).map((x) => [String(x[0]).slice(0, 12), x[1] | 0, x[2] | 0])) : u.team;
    const ovr = Number.isFinite(b.ovr) ? Math.max(0, Math.min(5000, b.ovr | 0)) : u.ovr;
    const codex = Number.isFinite(b.codex) ? Math.max(0, Math.min(500, b.codex | 0)) : u.codex;
    const sw = Number.isFinite(b.solo_w) ? Math.max(u.solo_w, b.solo_w | 0) : u.solo_w;
    const sl = Number.isFinite(b.solo_l) ? Math.max(u.solo_l, b.solo_l | 0) : u.solo_l;
    const trophies = b.trophies && typeof b.trophies === "object" ? JSON.stringify(b.trophies).slice(0, 300) : u.trophies;
    // XP for solo play: +10 per new win, +3 per new loss (capped per sync)
    const gain = Math.min(400, (sw - u.solo_w) * 10 + (sl - u.solo_l) * 3);
    await this.run("UPDATE users SET name = ?, tag = ?, avatar = ?, color = ?, bio = ?, team = ?, ovr = ?, codex = ?, solo_w = ?, solo_l = ?, trophies = ? WHERE id = ?",
      name, tag, avatar, color, bio, team, ovr, codex, sw, sl, trophies, u.id);
    if (gain > 0) await this.gainXp(u.id, gain);
    this.me = await this.user(u.id);
    return this.getMe();
  }
  async ping(b) {
    const u = this.me, t = now();
    const st = ["menu", "match", "queue", "online"].includes(b.status) ? b.status : "menu";
    await this.run("UPDATE users SET last_seen = ?, status = ? WHERE id = ?", t, st, u.id);
    const [req, unread, inv, fon] = await Promise.all([
      this.one("SELECT COUNT(*) AS n FROM friends WHERE b = ? AND status = 'pending'", u.id),
      this.one("SELECT COUNT(*) AS n FROM messages WHERE dst = ? AND seen = 0", u.id),
      this.all(`SELECT i.id AS iid, i.code, i.created AS icreated, ${CARD_COLS} FROM invites i JOIN users u ON u.id = i.src
                LEFT JOIN clubs c ON c.id = u.club_id WHERE i.dst = ? AND i.status = 'open' AND i.created > ?`, u.id, t - 120),
      this.one(`SELECT COUNT(*) AS n FROM friends f JOIN users u ON u.id = f.b WHERE f.a = ? AND f.status = 'friend' AND u.last_seen > ?`, u.id, t - ONLINE_S),
    ]);
    const lastGlobal = await this.one("SELECT MAX(id) AS id FROM chat WHERE room = 'global'");
    const lastClub = u.club_id ? await this.one("SELECT MAX(id) AS id FROM chat WHERE room = ?", "club:" + u.club_id) : null;
    return json({
      requests: req.n, unread: unread.n, friends_online: fon.n,
      invites: inv.map((r) => ({ id: r.iid, code: r.code, created: r.icreated, from: card(r) })),
      chat_global: lastGlobal?.id ?? 0, chat_club: lastClub?.id ?? 0, server_time: t,
    });
  }

  // ------------------------------------------------------------------ people
  async getUser(id) {
    const u = await this.user(id);
    if (!u || u.banned) return fail("Joueur introuvable", 404);
    const me = this.me.id;
    let rel = "none";
    if (id === me) rel = "me";
    else if (await this.one("SELECT 1 FROM blocks WHERE a = ? AND b = ?", me, id)) rel = "blocked";
    else {
      const f = await this.one("SELECT status FROM friends WHERE a = ? AND b = ?", me, id);
      const g = await this.one("SELECT status FROM friends WHERE a = ? AND b = ?", id, me);
      if (f?.status === "friend") rel = "friend";
      else if (f) rel = "sent";
      else if (g) rel = "received";
    }
    const ev = await this.withNames(await this.all("SELECT id, kind, data, created, likes FROM events WHERE uid = ? ORDER BY id DESC LIMIT 10", id));
    const rank = await this.one("SELECT COUNT(*) + 1 AS r FROM users WHERE elo > ? AND banned = 0 AND (ranked_w + ranked_l) > 0", u.elo);
    return json({ user: pub(u, await this.club(u.club_id)), relation: rel, rank: u.ranked_w + u.ranked_l > 0 ? rank.r : null,
      events: ev });
  }
  async search(q) {
    q = String(q || "").trim().slice(0, 24);
    if (q.length < 2) return json({ users: [] });
    let rows;
    const m = q.match(/^(.+?)\s*#\s*(\d{4})$/);
    if (m) rows = await this.all(`SELECT ${CARD_COLS} FROM users u LEFT JOIN clubs c ON c.id = u.club_id WHERE u.name = ? COLLATE NOCASE AND u.tag = ? AND u.banned = 0`, m[1], +m[2]);
    else rows = await this.all(`SELECT ${CARD_COLS} FROM users u LEFT JOIN clubs c ON c.id = u.club_id WHERE u.name LIKE ? AND u.banned = 0 ORDER BY u.last_seen DESC LIMIT 25`, q.replace(/[%_]/g, "") + "%");
    return json({ users: rows.filter((r) => r.id !== this.me.id).map(card) });
  }
  async friendList() {
    const me = this.me.id;
    const friends = (await this.all(`SELECT ${CARD_COLS} FROM friends f JOIN users u ON u.id = f.b LEFT JOIN clubs c ON c.id = u.club_id WHERE f.a = ? AND f.status = 'friend' ORDER BY u.last_seen DESC`, me)).map(card);
    const incoming = (await this.all(`SELECT ${CARD_COLS} FROM friends f JOIN users u ON u.id = f.a LEFT JOIN clubs c ON c.id = u.club_id WHERE f.b = ? AND f.status = 'pending' ORDER BY f.created DESC`, me)).map(card);
    const outgoing = (await this.all(`SELECT ${CARD_COLS} FROM friends f JOIN users u ON u.id = f.b LEFT JOIN clubs c ON c.id = u.club_id WHERE f.a = ? AND f.status = 'pending' ORDER BY f.created DESC`, me)).map(card);
    const blocked = (await this.all(`SELECT ${CARD_COLS} FROM blocks k JOIN users u ON u.id = k.b LEFT JOIN clubs c ON c.id = u.club_id WHERE k.a = ?`, me)).map(card);
    return json({ friends, incoming, outgoing, blocked });
  }
  async addFriend(b) {
    const me = this.me.id;
    let id = b.id | 0;
    if (!id && b.name && b.tag) {
      const u = await this.one("SELECT id FROM users WHERE name = ? COLLATE NOCASE AND tag = ?", String(b.name), b.tag | 0);
      id = u?.id | 0;
    }
    if (!id || id === me || !(await this.user(id))) return fail("Joueur introuvable", 404);
    if (await this.blocked(me, id)) return fail("Impossible d'ajouter ce joueur");
    if (await this.friends(me, id)) return json({ ok: true, status: "friend" });
    const n = await this.one("SELECT COUNT(*) AS n FROM friends WHERE a = ?", me);
    if (n.n >= 200) return fail("Liste d'amis pleine (200)");
    const t = now();
    if (await this.one("SELECT 1 FROM friends WHERE a = ? AND b = ? AND status = 'pending'", id, me)) {
      await this.db.batch([
        this.q("UPDATE friends SET status = 'friend' WHERE a = ? AND b = ?", id, me),
        this.q("INSERT OR REPLACE INTO friends (a, b, status, created) VALUES (?, ?, 'friend', ?)", me, id, t),
      ]);
      await this.event(me, "friend", { with: id });
      return json({ ok: true, status: "friend" });
    }
    await this.run("INSERT OR IGNORE INTO friends (a, b, status, created) VALUES (?, ?, 'pending', ?)", me, id, t);
    return json({ ok: true, status: "sent" });
  }
  async answerFriend(b, accept) {
    const me = this.me.id, id = b.id | 0;
    if (!(await this.one("SELECT 1 FROM friends WHERE a = ? AND b = ? AND status = 'pending'", id, me))) return fail("Demande introuvable", 404);
    if (accept) {
      await this.db.batch([
        this.q("UPDATE friends SET status = 'friend' WHERE a = ? AND b = ?", id, me),
        this.q("INSERT OR REPLACE INTO friends (a, b, status, created) VALUES (?, ?, 'friend', ?)", me, id, now()),
      ]);
      await this.event(me, "friend", { with: id });
    } else await this.run("DELETE FROM friends WHERE a = ? AND b = ?", id, me);
    return json({ ok: true });
  }
  async removeFriend(b) {
    const me = this.me.id, id = b.id | 0;
    await this.run("DELETE FROM friends WHERE (a = ? AND b = ?) OR (a = ? AND b = ?)", me, id, id, me);
    return json({ ok: true });
  }
  async block(b, on) {
    const me = this.me.id, id = b.id | 0;
    if (!id || id === me) return fail("Joueur invalide");
    if (on) {
      await this.db.batch([
        this.q("INSERT OR IGNORE INTO blocks (a, b) VALUES (?, ?)", me, id),
        this.q("DELETE FROM friends WHERE (a = ? AND b = ?) OR (a = ? AND b = ?)", me, id, id, me),
      ]);
    } else await this.run("DELETE FROM blocks WHERE a = ? AND b = ?", me, id);
    return json({ ok: true });
  }
  async report(b) {
    const id = b.id | 0;
    if (!id) return fail("Joueur invalide");
    const n = await this.one("SELECT COUNT(*) AS n FROM reports WHERE src = ? AND created > ?", this.me.id, now() - 86400);
    if (n.n >= 20) return fail("Trop de signalements aujourd'hui", 429);
    await this.run("INSERT INTO reports (src, target, reason, context, created) VALUES (?, ?, ?, ?, ?)",
      this.me.id, id, clean(b.reason, 60), clean(b.context, 300), now());
    return json({ ok: true });
  }

  // ------------------------------------------------------------------ private messages
  async conversations() {
    const me = this.me.id;
    const rows = await this.all(
      `SELECT x.other, m.text, m.created AS mcreated, m.src, (SELECT COUNT(*) FROM messages WHERE src = x.other AND dst = ? AND seen = 0) AS unread,
              ${CARD_COLS}
       FROM (SELECT CASE WHEN src = ? THEN dst ELSE src END AS other, MAX(id) AS mid FROM messages WHERE src = ? OR dst = ? GROUP BY other) x
       JOIN messages m ON m.id = x.mid JOIN users u ON u.id = x.other LEFT JOIN clubs c ON c.id = u.club_id
       ORDER BY m.id DESC LIMIT 50`, me, me, me, me);
    return json({ conversations: rows.map((r) => ({ with: card(r), last: r.text, mine: r.src === me, created: r.mcreated, unread: r.unread })) });
  }
  async getMessages(p) {
    const me = this.me.id, other = +p.get("with") | 0, after = +p.get("after") | 0;
    const rows = await this.all(
      `SELECT id, src, text, created FROM messages WHERE ((src = ? AND dst = ?) OR (src = ? AND dst = ?)) AND id > ?
       ORDER BY id DESC LIMIT 80`, me, other, other, me, after);
    await this.run("UPDATE messages SET seen = 1 WHERE src = ? AND dst = ? AND seen = 0", other, me);
    return json({ messages: rows.reverse().map((r) => ({ ...r, mine: r.src === me })) });
  }
  async sendMessage(b) {
    const me = this.me.id, to = b.to | 0;
    if (!(await this.friends(me, to))) return fail("Tu ne peux écrire qu'à tes amis");
    if (await this.blocked(me, to)) return fail("Message impossible");
    if (await this.spam(me)) return fail("Doucement ! Attends quelques secondes", 429);
    const text = clean(b.text);
    if (!text) return fail("Message vide");
    const r = await this.run("INSERT INTO messages (src, dst, text, created) VALUES (?, ?, ?, ?)", me, to, text, now());
    return json({ ok: true, id: r.meta.last_row_id, text });
  }

  // ------------------------------------------------------------------ public chat (global / club)
  room(r) {
    if (r === "club") return this.me.club_id ? "club:" + this.me.club_id : null;
    return "global";
  }
  async getChat(p) {
    const room = this.room(p.get("room"));
    if (!room) return json({ messages: [] });
    const after = +p.get("after") | 0;
    const rows = await this.all(
      `SELECT ch.id AS cid, ch.text, ch.created AS ccreated, ch.src, ${CARD_COLS} FROM chat ch JOIN users u ON u.id = ch.src LEFT JOIN clubs c ON c.id = u.club_id
       WHERE ch.room = ? AND ch.id > ? AND u.banned = 0
         AND ch.src NOT IN (SELECT b FROM blocks WHERE a = ?)
       ORDER BY ch.id DESC LIMIT 60`, room, after, this.me.id);
    return json({ messages: rows.reverse().map((r) => ({ id: r.cid, text: r.text, created: r.ccreated, from: card(r), mine: r.src === this.me.id })) });
  }
  async postChat(b) {
    const room = this.room(b.room);
    if (!room) return fail("Tu n'es dans aucun club");
    if (await this.spam(this.me.id)) return fail("Doucement ! Attends quelques secondes", 429);
    const text = clean(b.text, 200);
    if (!text) return fail("Message vide");
    await this.run("INSERT INTO chat (room, src, text, created) VALUES (?, ?, ?, ?)", room, this.me.id, text, now());
    return json({ ok: true });
  }

  // ------------------------------------------------------------------ invites to an online match
  async invite(b) {
    const me = this.me.id, to = b.to | 0;
    if (!(await this.friends(me, to))) return fail("Tu ne peux inviter que tes amis");
    const code = String(b.code || "").toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, 8);
    if (code.length < 5) return fail("Code de partie invalide");
    await this.run("UPDATE invites SET status = 'old' WHERE src = ? AND dst = ? AND status = 'open'", me, to);
    await this.run("INSERT INTO invites (src, dst, code, created) VALUES (?, ?, ?, ?)", me, to, code, now());
    return json({ ok: true });
  }
  async answerInvite(b) {
    await this.run("UPDATE invites SET status = ? WHERE id = ? AND dst = ?", b.accept ? "accepted" : "declined", b.id | 0, this.me.id);
    return json({ ok: true });
  }

  // ------------------------------------------------------------------ clubs
  async clubInfo(c) {
    const m = await this.one("SELECT COUNT(*) AS n, CAST(AVG(elo) AS INTEGER) AS elo, SUM(ranked_w + online_w) AS wins FROM users WHERE club_id = ?", c.id);
    return { id: c.id, name: c.name, tag: c.tag, descr: c.descr, color: c.color, owner: c.owner, open: !!c.open, created: c.created,
      members: m.n, elo: m.elo ?? 1000, wins: m.wins ?? 0 };
  }
  async createClub(b) {
    if (this.me.club_id) return fail("Quitte d'abord ton club actuel");
    const name = clean(b.name, 24), tag = String(b.tag || "").toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, 4);
    if (name.length < 3) return fail("Nom du club : 3 caractères minimum");
    if (tag.length < 2) return fail("Sigle : 2 à 4 lettres ou chiffres");
    const color = COLOR_RE.test(b.color || "") ? b.color : "#4fc3ff";
    try {
      const r = await this.run("INSERT INTO clubs (name, tag, descr, color, owner, open, created) VALUES (?, ?, ?, ?, ?, ?, ?)",
        name, tag, clean(b.descr, 160), color, this.me.id, b.open === false ? 0 : 1, now());
      await this.run("UPDATE users SET club_id = ? WHERE id = ?", r.meta.last_row_id, this.me.id);
      await this.event(this.me.id, "club_new", { club: name, tag });
      return json({ ok: true, id: r.meta.last_row_id });
    } catch { return fail("Ce nom de club est déjà pris"); }
  }
  async listClubs(p) {
    const q = String(p.get("q") || "").replace(/[%_]/g, "").slice(0, 24);
    const rows = await this.all(
      `SELECT c.*, COUNT(u.id) AS members, CAST(AVG(u.elo) AS INTEGER) AS elo FROM clubs c LEFT JOIN users u ON u.club_id = c.id
       WHERE c.name LIKE ? OR c.tag LIKE ? GROUP BY c.id ORDER BY members DESC, c.id DESC LIMIT 40`, q + "%", q + "%");
    return json({ clubs: rows.map((c) => ({ id: c.id, name: c.name, tag: c.tag, descr: c.descr, color: c.color, open: !!c.open, members: c.members, elo: c.elo ?? 1000 })) });
  }
  async getClub(id) {
    const c = await this.club(id);
    if (!c) return fail("Club introuvable", 404);
    const members = await this.all(`SELECT ${CARD_COLS}, u.ranked_w, u.online_w FROM users u LEFT JOIN clubs c ON c.id = u.club_id WHERE u.club_id = ? ORDER BY u.elo DESC`, id);
    return json({ club: await this.clubInfo(c), members: members.map((m) => ({ ...card(m), owner: m.id === c.owner, wins: m.ranked_w + m.online_w })) });
  }
  async joinClub(b) {
    if (this.me.club_id) return fail("Quitte d'abord ton club actuel");
    const c = await this.club(b.id | 0);
    if (!c) return fail("Club introuvable", 404);
    if (!c.open) return fail("Ce club est fermé aux nouveaux membres");
    const n = await this.one("SELECT COUNT(*) AS n FROM users WHERE club_id = ?", c.id);
    if (n.n >= 30) return fail("Club complet (30 membres)");
    await this.run("UPDATE users SET club_id = ? WHERE id = ?", c.id, this.me.id);
    await this.event(this.me.id, "club_join", { club: c.name, tag: c.tag });
    return json({ ok: true });
  }
  async leaveClub() {
    const c = await this.club(this.me.club_id);
    if (!c) return json({ ok: true });
    await this.run("UPDATE users SET club_id = NULL WHERE id = ?", this.me.id);
    if (c.owner === this.me.id) {
      const next = await this.one("SELECT id FROM users WHERE club_id = ? ORDER BY elo DESC LIMIT 1", c.id);
      if (next) await this.run("UPDATE clubs SET owner = ? WHERE id = ?", next.id, c.id);
      else await this.db.batch([this.q("DELETE FROM clubs WHERE id = ?", c.id), this.q("DELETE FROM chat WHERE room = ?", "club:" + c.id)]);
    }
    return json({ ok: true });
  }
  async kick(b) {
    const c = await this.club(this.me.club_id);
    if (!c || c.owner !== this.me.id) return fail("Seul le chef du club peut exclure");
    if ((b.id | 0) === this.me.id) return fail("Utilise « Quitter »");
    await this.run("UPDATE users SET club_id = NULL WHERE id = ? AND club_id = ?", b.id | 0, c.id);
    return json({ ok: true });
  }
  async editClub(b) {
    const c = await this.club(this.me.club_id);
    if (!c || c.owner !== this.me.id) return fail("Seul le chef du club peut modifier");
    const color = COLOR_RE.test(b.color || "") ? b.color : c.color;
    await this.run("UPDATE clubs SET descr = ?, color = ?, open = ? WHERE id = ?",
      b.descr !== undefined ? clean(b.descr, 160) : c.descr, color, b.open === undefined ? c.open : (b.open ? 1 : 0), c.id);
    return json({ ok: true });
  }

  // ------------------------------------------------------------------ leaderboards
  async leaderboard(p) {
    const scope = p.get("scope") || "elo";
    const me = this.me.id;
    if (scope === "clubs") {
      const rows = await this.all(
        `SELECT c.id, c.name, c.tag, c.color, COUNT(u.id) AS members, CAST(AVG(u.elo) AS INTEGER) AS elo, SUM(u.ranked_w + u.online_w) AS wins
         FROM clubs c JOIN users u ON u.club_id = c.id GROUP BY c.id ORDER BY wins DESC, elo DESC LIMIT 50`);
      return json({ scope, rows });
    }
    const order = scope === "xp" ? "u.xp DESC" : "u.elo DESC, u.ranked_w DESC";
    let where = "u.banned = 0";
    if (scope === "elo") where += " AND (u.ranked_w + u.ranked_l) > 0";
    if (scope === "friends") where += ` AND (u.id = ${me} OR u.id IN (SELECT b FROM friends WHERE a = ${me} AND status = 'friend'))`;
    const rows = await this.all(`SELECT ${CARD_COLS}, u.ranked_w, u.ranked_l FROM users u LEFT JOIN clubs c ON c.id = u.club_id WHERE ${where} ORDER BY ${order} LIMIT 50`);
    const myRank = await this.one(
      scope === "xp" ? "SELECT COUNT(*) + 1 AS r FROM users WHERE xp > ? AND banned = 0" : "SELECT COUNT(*) + 1 AS r FROM users WHERE elo > ? AND banned = 0 AND (ranked_w + ranked_l) > 0",
      scope === "xp" ? this.me.xp : this.me.elo);
    return json({ scope, rows: rows.map((r) => ({ ...card(r), ranked_w: r.ranked_w, ranked_l: r.ranked_l, xp: r.xp })), my_rank: myRank.r });
  }

  // ------------------------------------------------------------------ activity feed
  async feed() {
    const me = this.me.id;
    const rows = await this.all(
      `SELECT e.id AS eid, e.kind, e.data, e.created AS ecreated, e.likes, (SELECT 1 FROM likes WHERE event = e.id AND uid = ?) AS liked, ${CARD_COLS}
       FROM events e JOIN users u ON u.id = e.uid LEFT JOIN clubs c ON c.id = u.club_id
       WHERE e.uid = ? OR e.uid IN (SELECT b FROM friends WHERE a = ? AND status = 'friend')
          OR (u.club_id IS NOT NULL AND u.club_id = ?)
       ORDER BY e.id DESC LIMIT 60`, me, me, me, this.me.club_id ?? -1);
    // names for "friend" events
    const ids = [...new Set(rows.filter((r) => r.kind === "friend").map((r) => JSON.parse(r.data).with))];
    const names = {};
    for (const id of ids) { const u = await this.one("SELECT name, tag FROM users WHERE id = ?", id); if (u) names[id] = `${u.name}#${u.tag}`; }
    return json({ events: rows.map((r) => {
      const data = JSON.parse(r.data);
      if (r.kind === "friend") data.name = names[data.with] ?? "?";
      return { id: r.eid, kind: r.kind, data, created: r.ecreated, likes: r.likes, liked: !!r.liked, from: card(r) };
    }) });
  }
  async postEvent(b) {
    const kinds = ["splus", "cup", "codex", "streak"];
    if (!kinds.includes(b.kind)) return fail("Type inconnu");
    const n = await this.one("SELECT COUNT(*) AS n FROM events WHERE uid = ? AND created > ?", this.me.id, now() - 86400);
    if (n.n >= 30) return json({ ok: true, skipped: true });
    const data = {};
    for (const [k, v] of Object.entries(b.data || {}).slice(0, 6)) data[String(k).slice(0, 12)] = typeof v === "number" ? v : clean(v, 40);
    await this.event(this.me.id, b.kind, data);
    return json({ ok: true });
  }
  async like(b) {
    const id = b.id | 0;
    const r = await this.run("INSERT OR IGNORE INTO likes (event, uid) VALUES (?, ?)", id, this.me.id);
    if (r.meta.changes) await this.run("UPDATE events SET likes = likes + 1 WHERE id = ?", id);
    return json({ ok: true });
  }

  // ------------------------------------------------------------------ ranked matchmaking
  async tryMatch() {
    const me = this.me, t = now();
    const mine = await this.one("SELECT * FROM queue WHERE uid = ?", me.id);
    if (!mine || mine.match_id) return;
    const waited = t - mine.joined;
    const win = 120 + 25 * waited;   // Elo window widens while waiting
    const other = await this.one(
      `SELECT * FROM queue WHERE uid != ? AND match_id IS NULL AND seen > ? AND ABS(elo - ?) <= ?
         AND uid NOT IN (SELECT b FROM blocks WHERE a = ?) AND uid NOT IN (SELECT a FROM blocks WHERE b = ?)
       ORDER BY joined LIMIT 1`, me.id, t - 8, me.elo, win, me.id, me.id);
    if (!other) return;
    // the one who waited longest hosts
    const r = await this.run("INSERT INTO matches (host, guest, ranked, created) VALUES (?, ?, 1, ?)", other.uid, me.id, t);
    const mid = r.meta.last_row_id;
    const upd = await this.run("UPDATE queue SET match_id = ? WHERE uid IN (?, ?) AND match_id IS NULL", mid, other.uid, me.id);
    if (upd.meta.changes < 2) {   // raced with someone else: undo
      await this.db.batch([this.q("UPDATE queue SET match_id = NULL WHERE match_id = ?", mid), this.q("DELETE FROM matches WHERE id = ?", mid)]);
    }
  }
  async queueState() {
    const me = this.me.id;
    const q = await this.one("SELECT * FROM queue WHERE uid = ?", me);
    if (!q) return json({ state: "idle" });
    if (!q.match_id) return json({ state: "waiting", waited: now() - q.joined });
    const m = await this.one("SELECT * FROM matches WHERE id = ?", q.match_id);
    const opp = await this.one(`SELECT ${CARD_COLS} FROM users u LEFT JOIN clubs c ON c.id = u.club_id WHERE u.id = ?`, m.host === me ? m.guest : m.host);
    return json({ state: "matched", match: { id: m.id, role: m.host === me ? "host" : "guest", code: m.code, opponent: card(opp) } });
  }
  async queueJoin() {
    const t = now();
    await this.run("INSERT OR REPLACE INTO queue (uid, elo, joined, seen, match_id) VALUES (?, ?, ?, ?, NULL)", this.me.id, this.me.elo, t, t);
    await this.run("UPDATE users SET status = 'queue', last_seen = ? WHERE id = ?", t, this.me.id);
    await this.tryMatch();
    return this.queueState();
  }
  async queuePoll() {
    await this.run("UPDATE queue SET seen = ? WHERE uid = ?", now(), this.me.id);
    await this.tryMatch();
    return this.queueState();
  }
  async queueLeave() {
    await this.run("DELETE FROM queue WHERE uid = ?", this.me.id);
    await this.run("UPDATE users SET status = 'menu' WHERE id = ?", this.me.id);
    return json({ ok: true });
  }
  async matchCode(b) {
    const m = await this.one("SELECT * FROM matches WHERE id = ? AND host = ?", b.id | 0, this.me.id);
    if (!m) return fail("Match introuvable", 404);
    await this.run("UPDATE matches SET code = ? WHERE id = ?", String(b.code || "").toUpperCase().slice(0, 8), m.id);
    return json({ ok: true });
  }
  // result of an online match. Ranked: {id, winner: "host"|"guest", score}; friendly: {opponent, won}
  async matchResult(b) {
    const me = this.me.id;
    if (b.id) {
      const m = await this.one("SELECT * FROM matches WHERE id = ? AND (host = ? OR guest = ?)", b.id | 0, me, me);
      if (!m) return fail("Match introuvable", 404);
      await this.run("DELETE FROM queue WHERE uid IN (?, ?)", m.host, m.guest);
      await this.run("UPDATE users SET status = 'menu' WHERE id IN (?, ?) AND status = 'queue'", m.host, m.guest);
      if (m.done) return json({ ok: true, delta: m.host === me ? m.delta : -m.delta, already: true });
      const hw = b.winner === "host";
      const H = await this.user(m.host), G = await this.user(m.guest);
      const exp = 1 / (1 + Math.pow(10, (G.elo - H.elo) / 400));
      const k = 32;
      const d = Math.round(k * ((hw ? 1 : 0) - exp));   // host's change
      await this.db.batch([
        this.q("UPDATE matches SET done = 1, winner = ?, score = ?, delta = ? WHERE id = ? AND done = 0", hw ? m.host : m.guest, clean(b.score, 40), d, m.id),
        this.q(`UPDATE users SET elo = MAX(0, elo + ?), ranked_w = ranked_w + ?, ranked_l = ranked_l + ? WHERE id = ?`, d, hw ? 1 : 0, hw ? 0 : 1, m.host),
        this.q(`UPDATE users SET elo = MAX(0, elo - ?), ranked_w = ranked_w + ?, ranked_l = ranked_l + ? WHERE id = ?`, d, hw ? 0 : 1, hw ? 1 : 0, m.guest),
      ]);
      await this.gainXp(m.host, hw ? 60 : 20);
      await this.gainXp(m.guest, hw ? 20 : 60);
      for (const [u, nd] of [[H, H.elo + d], [G, G.elo - d]]) {
        if (tier(nd) !== tier(u.elo) && nd > u.elo) await this.event(u.id, "tier", { tier: tier(nd), elo: nd });
      }
      return json({ ok: true, delta: m.host === me ? d : -d });
    }
    // friendly online match: each side reports its own result
    const won = !!b.won;
    await this.run(`UPDATE users SET online_w = online_w + ?, online_l = online_l + ? WHERE id = ?`, won ? 1 : 0, won ? 0 : 1, me);
    await this.gainXp(me, won ? 40 : 15);
    return json({ ok: true });
  }
  async matchHistory() {
    const me = this.me.id;
    const rows = await this.all(
      `SELECT m.id AS mid, m.host, m.guest, m.winner, m.score, m.created AS mcreated, m.delta, ${CARD_COLS} FROM matches m
       JOIN users u ON u.id = (CASE WHEN m.host = ? THEN m.guest ELSE m.host END) LEFT JOIN clubs c ON c.id = u.club_id
       WHERE (m.host = ? OR m.guest = ?) AND m.done = 1 ORDER BY m.id DESC LIMIT 20`, me, me, me);
    return json({ matches: rows.map((r) => ({ id: r.mid, won: r.winner === me, score: r.score, created: r.mcreated,
      delta: r.host === me ? r.delta : -r.delta, opponent: card(r) })) });
  }
}

async function route(req, env) {
  const url = new URL(req.url);
  const p = url.pathname.replace(/\/+$/, "");
  if (req.method === "OPTIONS") return new Response(null, { headers: { "access-control-allow-origin": "*", "access-control-allow-headers": "authorization, content-type", "access-control-allow-methods": "GET, POST" } });
  if (p === "" || p === "/v1") return json({ ok: true, service: "skyspike-social", time: now() });
  const api = new Api(env, req);
  let body = {};
  if (req.method === "POST") {
    try { body = await req.json(); } catch { body = {}; }
  }
  if (p === "/v1/register" && req.method === "POST") return api.register(body);
  if (p === "/v1/login" && req.method === "POST") {
    const u = await api.one("SELECT * FROM users WHERE token_hash = ?", await sha256(String(body.token || "").trim()));
    if (!u || u.banned) return fail("Code de transfert inconnu", 404);
    return json({ token: String(body.token).trim(), me: pub(u, await api.club(u.club_id)) });
  }
  if (!(await api.auth())) return fail("Session invalide", 401);
  const P = url.searchParams;
  const G = req.method === "GET";
  switch (p) {
    case "/v1/me": return G ? api.getMe() : api.setMe(body);
    case "/v1/ping": return api.ping(body);
    case "/v1/user": return api.getUser(+P.get("id") | 0);
    case "/v1/search": return api.search(P.get("q"));
    case "/v1/friends": return api.friendList();
    case "/v1/friends/add": return api.addFriend(body);
    case "/v1/friends/accept": return api.answerFriend(body, true);
    case "/v1/friends/decline": return api.answerFriend(body, false);
    case "/v1/friends/remove": return api.removeFriend(body);
    case "/v1/block": return api.block(body, true);
    case "/v1/unblock": return api.block(body, false);
    case "/v1/report": return api.report(body);
    case "/v1/conversations": return api.conversations();
    case "/v1/messages": return G ? api.getMessages(P) : api.sendMessage(body);
    case "/v1/chat": return G ? api.getChat(P) : api.postChat(body);
    case "/v1/invite": return api.invite(body);
    case "/v1/invite/answer": return api.answerInvite(body);
    case "/v1/clubs": return G ? api.listClubs(P) : api.createClub(body);
    case "/v1/club": return api.getClub(+P.get("id") | 0);
    case "/v1/club/join": return api.joinClub(body);
    case "/v1/club/leave": return api.leaveClub();
    case "/v1/club/kick": return api.kick(body);
    case "/v1/club/edit": return api.editClub(body);
    case "/v1/leaderboard": return api.leaderboard(P);
    case "/v1/feed": return api.feed();
    case "/v1/event": return api.postEvent(body);
    case "/v1/like": return api.like(body);
    case "/v1/queue/join": return api.queueJoin();
    case "/v1/queue/poll": return api.queuePoll();
    case "/v1/queue/leave": return api.queueLeave();
    case "/v1/match/code": return api.matchCode(body);
    case "/v1/match/result": return api.matchResult(body);
    case "/v1/matches": return api.matchHistory();
  }
  return fail("Route inconnue", 404);
}

export default {
  async fetch(req, env) {
    try { return await route(req, env); }
    catch (e) { return fail("Erreur serveur : " + (e && e.message ? e.message : e), 500); }
  },
  // housekeeping every hour: old chat, stale queue entries, expired invites
  async scheduled(_ev, env) {
    const t = now();
    await env.DB.batch([
      env.DB.prepare("DELETE FROM chat WHERE created < ?").bind(t - 3 * 86400),
      env.DB.prepare("DELETE FROM queue WHERE seen < ?").bind(t - 60),
      env.DB.prepare("DELETE FROM invites WHERE created < ?").bind(t - 86400),
      env.DB.prepare("DELETE FROM messages WHERE created < ?").bind(t - 60 * 86400),
    ]);
  },
};
