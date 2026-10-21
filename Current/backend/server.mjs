import http from 'node:http';
import { randomBytes } from 'node:crypto';
import { readFile, writeFile, mkdir, rename } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createBridge, encrypt, decrypt } from './bridge.mjs';
import { configFromEnv } from './config.mjs';
export { cents, normalizeAccounts, encrypt, decrypt } from './bridge.mjs';

export async function createServer(config, request = fetch) {
  const handler = await createBridge(config, {
    async load() {
      try { return decrypt(await readFile(config.dataFile, 'utf8'), config.key); }
      catch (error) { if (error.code === 'ENOENT') return null; throw new Error('Cannot unlock bank storage. Preserve the existing file and verify the encryption key.'); }
    },
    async save(state) {
      await mkdir(path.dirname(config.dataFile), { recursive: true, mode: 0o700 });
      const temp = `${config.dataFile}.${randomBytes(8).toString('hex')}.tmp`;
      await writeFile(temp, encrypt(state, config.key), { mode: 0o600 });
      await rename(temp, config.dataFile);
    },
  }, request);
  const server = http.createServer(async (req, res) => {
    try {
      const chunks = []; let length = 0;
      for await (const chunk of req) {
        length += chunk.length;
        if (length > 32768) { res.writeHead(413); res.end(); return; }
        chunks.push(chunk);
      }
      const response = await handler(new Request(new URL(req.url, 'http://localhost'), {
        method: req.method, headers: req.headers,
        ...(['GET', 'HEAD'].includes(req.method) ? {} : { body: Buffer.concat(chunks) }),
      }));
      res.writeHead(response.status, Object.fromEntries(response.headers));
      res.end(Buffer.from(await response.arrayBuffer()));
    } catch { res.writeHead(503); res.end('Bank bridge unavailable'); }
  });
  server.requestTimeout = 35000;
  server.headersTimeout = 10000;
  return server;
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const server = await createServer(configFromEnv());
    server.listen(Number(process.env.PORT ?? 8787), process.env.TENDER_HOST ?? '127.0.0.1', () => console.log('Tender bank bridge ready. Personal-use authenticated API; place behind HTTPS for an iPhone.'));
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
