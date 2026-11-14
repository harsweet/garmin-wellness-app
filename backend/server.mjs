import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DemoCalendar, CalendarError } from './demo-calendar.mjs';

const html = `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Momo demo calendar</title><style>
*{box-sizing:border-box}body{margin:0;background:#0d1020;color:#f4f3ec;font:16px system-ui,sans-serif}main{max-width:760px;margin:64px auto;padding:24px}small{color:#e7de8b;letter-spacing:.14em}h1{font-size:42px;letter-spacing:-.04em;margin-bottom:8px}p{color:#b2b7c8;line-height:1.6}article{border:1px solid #30364b;background:#171c2d;border-radius:18px;padding:24px;margin-top:28px}ul{list-style:none;padding:0}li{display:flex;gap:24px;justify-content:space-between;padding:17px 0;border-bottom:1px solid #30364b}li:last-child{border:0}time{color:#9bdec4;white-space:nowrap}code{background:#272d42;padding:3px 7px;border-radius:6px}footer{font-size:13px;color:#828ba3;margin-top:24px}</style><main><small>MOMO / DEMO CALENDAR</small><h1>A little room to escape.</h1><p>This is a local sample calendar. Accepted walks appear here; your Google Calendar stays untouched.</p><article><strong id="heading">Loading the demo day…</strong><ul id="events"></ul></article><p>In the fēnix simulator, <strong>hold UP</strong> to open Calendar. Choose a slot with UP / DOWN, press START, then confirm.</p><footer>Refreshes every 3 seconds. Times shown in <span id="zone"></span>. Restarting the service refreshes sample meetings; saved demo walks persist.</footer></main><script>
async function update(){try{const response=await fetch('/api/demo');if(!response.ok)throw Error();const data=await response.json();document.getElementById('zone').textContent=data.timeZone;document.getElementById('heading').textContent=data.activities+' demo walk'+(data.activities===1?'':'s')+' scheduled';const list=document.getElementById('events');list.replaceChildren();for(const event of data.events){const row=document.createElement('li');const title=document.createElement('span');title.textContent=event.title;const time=document.createElement('time');const options={timeZone:data.timeZone,hour:'numeric',minute:'2-digit'};time.textContent=new Date(event.start).toLocaleTimeString([],options)+' – '+new Date(event.end).toLocaleTimeString([],options);row.append(title,time);list.append(row)}}catch{document.getElementById('heading').textContent='Demo service is offline. Restart npm run calendar:demo.'}}update();setInterval(update,3000);
</script></html>`;

function json(response, data, status = 200) {
  response.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' });
  response.end(JSON.stringify(data));
}

async function readBody(request) {
  let body = '';
  for await (const chunk of request) {
    body += chunk;
    if (body.length > 16_384) throw new CalendarError(413, 'too_large', 'Request too large.');
  }
  try { return JSON.parse(body); } catch { throw new CalendarError(400, 'invalid_json', 'Invalid request.'); }
}

export function createDemoServer(calendar = new DemoCalendar()) {
  return http.createServer(async (request, response) => {
    try {
      const host = request.headers.host || '';
      if (!/^(127\.0\.0\.1|localhost):\d+$/.test(host)) return json(response, { error: 'invalid_host' }, 403);
      if (request.headers.origin && ![`http://${host}`].includes(request.headers.origin)) return json(response, { error: 'invalid_origin' }, 403);
      const pathname = new URL(request.url, `http://${host}`).pathname;
      if (request.method === 'GET' && pathname === '/') {
        response.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' });
        return response.end(html);
      }
      if (request.method === 'GET' && pathname === '/api/demo') {
        return json(response, { ...calendar.status(), activities: calendar.activities.length, events: calendar.allEvents().map(event => ({ ...event, start: new Date(event.start).toISOString(), end: new Date(event.end).toISOString() })) });
      }
      if (request.method !== 'POST' || !['/', '/api'].includes(pathname)) return json(response, { error: 'not_found' }, 404);
      const body = await readBody(request);
      if (!body || typeof body !== 'object' || Array.isArray(body)) throw new CalendarError(400, 'invalid_body', 'Invalid request.');
      if (body.action === 'pair') {
        if (body.code !== '000000') throw new CalendarError(401, 'invalid_code', 'Demo code is 000000.');
        return json(response, { token: 'momo-demo', mode: 'demo' });
      }
      if (body.token !== 'momo-demo') throw new CalendarError(401, 'unauthorized', 'Use the demo connection.');
      if (body.action === 'status') return json(response, calendar.status());
      if (body.action === 'availability') return json(response, calendar.availability());
      if (body.action === 'activities') {
        if (typeof body.slotId !== 'string') throw new CalendarError(400, 'invalid_slot', 'Choose a suggested slot.');
        return json(response, await calendar.book(body.slotId));
      }
      throw new CalendarError(400, 'invalid_action', 'Unknown calendar action.');
    } catch (error) {
      // Match Apps Script's JSON error contract, including HTTP 200 transport responses.
      json(response, { mode: 'demo', error: error.error || 'internal_error', message: error instanceof CalendarError ? error.message : 'Demo calendar unavailable.', httpStatus: error.httpStatus || 500 });
    }
  });
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const calendar = new DemoCalendar({ stateFile: fileURLToPath(new URL('../.local/demo-calendar.json', import.meta.url)), timeZone: process.env.MOMO_TIME_ZONE || 'America/Edmonton' });
  await calendar.load();
  const server = createDemoServer(calendar);
  server.on('error', error => { console.error(`Cannot start demo calendar: ${error.message}`); process.exitCode = 1; });
  server.listen(8787, '127.0.0.1', () => console.log('Momo DEMO calendar: http://127.0.0.1:8787 (no Google account connected)'));
}
