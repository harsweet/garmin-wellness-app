import { createHash } from 'node:crypto';
import { MomoWorkspace } from '../backend/workspace.mjs';
import { GrokSuggestions } from '../backend/grok.mjs';
import { RedisStateStore } from '../backend/redis-store.mjs';

function failure(response, message, code = 503) {
  if (response.writableEnded) return;
  response.writeHead(code, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
  response.end(JSON.stringify({ error: 'service_unavailable', message, httpStatus: code }));
}

// A new calendar/service is hydrated for each request: cold starts cannot erase
// onboarding, feedback, or demo bookings. All writes use an owner-checked lease.
export function createVercelHandler({ env = process.env, store: injectedStore, provider: injectedProvider } = {}) {
  return async function handler(request, response) {
    try {
      const token = env.MOMO_DEVICE_TOKEN || '';
      if (!/^[A-Za-z0-9_-]{43}$/.test(token)) return failure(response, 'Set MOMO_DEVICE_TOKEN before using this deployment.');
      const publicValue = env.MOMO_PUBLIC_URL || (env.VERCEL_PROJECT_PRODUCTION_URL ? `https://${env.VERCEL_PROJECT_PRODUCTION_URL}` : env.VERCEL_URL ? `https://${env.VERCEL_URL}` : '');
      const publicUrl = new URL(publicValue);
      if (publicUrl.protocol !== 'https:') return failure(response, 'Configure the HTTPS public app URL.');
      const publicOrigin = publicUrl.origin;
      const query = new URL(request.url, publicOrigin);
      const originalPath = query.searchParams.get('momoPath');
      if (originalPath) {
        if (!originalPath.startsWith('/') || originalPath.startsWith('//')) return failure(response, 'Invalid request path.', 400);
        request.url = originalPath;
      }
      const namespace = createHash('sha256').update(token).digest('hex').slice(0, 20);
      const store = injectedStore || new RedisStateStore({ url: env.UPSTASH_REDIS_REST_URL || env.KV_REST_API_URL, token: env.UPSTASH_REDIS_REST_TOKEN || env.KV_REST_API_TOKEN, key: `momo:${namespace}:state` });
      await store.withLock(async lease => {
        const saved = await lease.load();
        const provider = injectedProvider || new GrokSuggestions({ apiKey: env.XAI_API_KEY || env.GROK_API_KEY || '', model: env.XAI_MODEL || 'grok-4.7' });
        const workspace = new MomoWorkspace({ initialState: saved, deviceToken: token, adminToken: env.MOMO_ADMIN_TOKEN || '', publicOrigin, provider, allowLocalSetup: false, timeZone: env.MOMO_TIME_ZONE || 'America/Edmonton', save: state => lease.save(state) });
        await workspace.initialize();
        await workspace.handle(request, response);
      });
    } catch {
      failure(response, 'Momo needs its storage or deployment settings checked. Please try again shortly.');
    }
  };
}

export default createVercelHandler();
