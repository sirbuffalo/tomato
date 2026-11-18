// Mac mini host for the Tomato page and private chat.
// Runs the Worker's fetch handler on node:http with a file-backed SQLite D1 stand-in.
// Config (secrets) lives outside the repo in a 0600 file; nothing secret is printed.
import {createServer} from 'node:http';
import {readFile, chmod} from 'node:fs/promises';
import {homedir} from 'node:os';
import {join} from 'node:path';
import {database} from '../scripts/local-d1.mjs';
import worker from '../worker/index.js';

const dir = join(homedir(), 'Library/Application Support/byre/tomato-chat-server');
const config = JSON.parse(await readFile(join(dir, 'server.json'), 'utf8'));
for (const key of ['origin', 'port', 'formPassword', 'relayKey', 'feedbackOpenedAt', 'feedbackClosesAt'])
  if (!config[key]) throw Error('server.json missing ' + key);
await chmod(dir, 0o700);

const DB = database(join(dir, 'chat.db'));
DB.raw.exec('PRAGMA journal_mode=WAL;CREATE TABLE IF NOT EXISTS _migrations(name TEXT PRIMARY KEY)');
for (const name of ['0000_feedback', '0001_chat', '0002_bridge', '0003_password_attempts', '0004_transcript_retention']) {
  if (DB.raw.prepare('SELECT 1 FROM _migrations WHERE name=?').get(name)) continue;
  DB.raw.exec(await readFile(new URL('../drizzle/' + name + '.sql', import.meta.url), 'utf8'));
  DB.raw.prepare('INSERT INTO _migrations(name) VALUES(?)').run(name);
}
const env = {DB, FORM_PASSWORD: config.formPassword, RELAY_KEY: config.relayKey,
  FEEDBACK_OPENED_AT: config.feedbackOpenedAt, FEEDBACK_CLOSES_AT: config.feedbackClosesAt};

const origin = new URL(config.origin).origin;
let loggedForwarded = false;
const server = createServer(async (req, res) => {
  try {
    const headers = new Headers();
    for (const [key, value] of Object.entries(req.headers))
      if (value !== undefined && key !== 'cf-connecting-ip') headers.set(key, Array.isArray(value) ? value.join(', ') : value);
    // The Worker keys password throttles on cf-connecting-ip; derive it from the proxy, never the client.
    const forwarded = String(req.headers['x-forwarded-for'] || '').split(',').map(v => v.trim()).filter(Boolean).at(-1);
    if (!loggedForwarded) { loggedForwarded = true; console.log('X-Forwarded-For header ' + (forwarded ? 'present' : 'absent') + ' on first request'); }
    headers.set('cf-connecting-ip', forwarded || req.socket.remoteAddress || '');
    const hasBody = !['GET', 'HEAD'].includes(req.method);
    const request = new Request(origin + req.url, {method: req.method, headers, ...(hasBody ? {body: req, duplex: 'half'} : {})});
    const response = await worker.fetch(request, env, {waitUntil(p) { p.catch(e => console.error(e.message)); }});
    response.headers.forEach((value, key) => { if (key !== 'set-cookie') res.setHeader(key, value); });
    const cookies = response.headers.getSetCookie?.() || [];
    if (cookies.length) res.setHeader('set-cookie', cookies);
    res.statusCode = response.status;
    if (!response.body) return res.end();
    const reader = response.body.getReader();
    while (true) { const {value, done} = await reader.read(); if (done) break; res.write(value); }
    res.end();
  } catch (error) {
    console.error(error.message);
    res.statusCode = 500; res.end('Server error');
  }
});
server.listen(config.port, '127.0.0.1', () => console.log('Tomato site on 127.0.0.1:' + config.port + ' origin ' + origin));
