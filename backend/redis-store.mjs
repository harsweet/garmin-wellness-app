import { randomUUID } from 'node:crypto';

// REST works on Vercel without maintaining a Redis TCP connection.
export class RedisStateStore {
  constructor({ url, token, key = 'momo:state', fetchImpl = globalThis.fetch }) {
    if (!url || !token || new URL(url).protocol !== 'https:') throw new Error('Configure Upstash Redis environment variables.');
    this.url = url.replace(/\/$/, '');
    this.token = token;
    this.key = key;
    this.fetchImpl = fetchImpl;
  }

  async command(...args) {
    const response = await this.fetchImpl(this.url, {
      method: 'POST', headers: { Authorization: `Bearer ${this.token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(args), signal: AbortSignal.timeout(3000)
    });
    if (!response.ok) throw new Error('Calendar storage is unavailable.');
    const data = await response.json();
    if (data.error) throw new Error('Calendar storage request failed.');
    return data.result;
  }

  async withLock(callback) {
    const lockKey = `${this.key}:lock`;
    const owner = randomUUID();
    let acquired = false;
    for (let attempt = 0; attempt < 6; attempt += 1) {
      if (await this.command('SET', lockKey, owner, 'NX', 'PX', '45000') === 'OK') { acquired = true; break; }
      await new Promise(resolve => setTimeout(resolve, 100 + attempt * 100));
    }
    if (!acquired) throw new Error('Calendar is busy. Try again shortly.');
    const lease = {
      load: async () => {
        const value = await this.command('GET', this.key);
        return value ? JSON.parse(value) : null;
      },
      save: async state => {
        const saved = await this.command('EVAL', "if redis.call('get',KEYS[1]) == ARGV[1] then redis.call('set',KEYS[2],ARGV[2]); return 1 else return 0 end", '2', lockKey, this.key, owner, JSON.stringify(state));
        if (saved !== 1) throw new Error('Calendar update expired. Try again.');
      }
    };
    try { return await callback(lease); }
    finally {
      // An expired request cannot release a newer request's lock.
      await this.command('EVAL', "if redis.call('get',KEYS[1]) == ARGV[1] then return redis.call('del',KEYS[1]) else return 0 end", '1', lockKey, owner).catch(() => {});
    }
  }
}
