import { randomBytes, createCipheriv, createDecipheriv } from 'node:crypto';

export function encryptedLedgerStorage(storage, key, owner) {
  const bytes = Buffer.from(key ?? '', 'base64');
  if (bytes.length !== 32) throw new Error('AI storage key is missing');
  return {
    async load() {
      const count = await storage.get('ledger-count');
      if (count === undefined) return null;
      if (!Number.isInteger(count) || count < 1 || count > 300) throw new Error('Invalid ledger chunks');
      const chunks = [];
      for (let start = 0; start < count; start += 100) {
        const keys = Array.from({ length: Math.min(100, count - start) }, (_, i) => 'ledger-' + (start + i));
        const values = await storage.get(keys);
        for (const k of keys) { if (typeof values.get(k) !== 'string') throw new Error('Missing ledger chunk'); chunks.push(values.get(k)); }
      }
      const data = Buffer.from(chunks.join(''), 'base64'), decipher = createDecipheriv('aes-256-gcm', bytes, data.subarray(0, 12));
      decipher.setAAD(Buffer.from(owner)); decipher.setAuthTag(data.subarray(12, 28));
      return JSON.parse(Buffer.concat([decipher.update(data.subarray(28)), decipher.final()]).toString());
    },
    async save(value) {
      const iv = randomBytes(12), cipher = createCipheriv('aes-256-gcm', bytes, iv); cipher.setAAD(Buffer.from(owner));
      const body = Buffer.concat([cipher.update(Buffer.from(JSON.stringify(value), 'utf8')), cipher.final()]);
      const chunks = Buffer.concat([iv, cipher.getAuthTag(), body]).toString('base64').match(/.{1,60000}/g);
      if (chunks.length > 300) throw new Error('Ledger storage limit');
      await storage.transaction(async txn => {
        const previous = await txn.get('ledger-count') ?? 0;
        for (let i = 0; i < chunks.length; i++) await txn.put('ledger-' + i, chunks[i]);
        for (let i = chunks.length; i < previous; i++) await txn.delete('ledger-' + i);
        await txn.put('ledger-count', chunks.length);
      });
    },
  };
}
