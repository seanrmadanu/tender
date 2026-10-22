// Durable Object values have a size limit. Store the encrypted vault in chunks,
// replacing chunks and the count in one storage transaction. Legacy vaults migrate
// on the first successful write; no encryption key or vault identity is changed.
import { encrypt, decrypt } from './bridge.mjs';
export function vaultStorage(storage, key) {
  return {
    async load() {
      const count = await storage.get('vault-chunk-count');
      if (count === undefined) {
        const legacy = await storage.get('vault');
        return legacy ? decrypt(legacy, key) : null;
      }
      if (!Number.isInteger(count) || count < 1 || count > 2000) throw new Error('Invalid vault chunks');
      const keys = Array.from({length: count}, (_, i) => `vault-chunk-${i}`);
      const values = new Map();
      for (let i = 0; i < keys.length; i += 100) for (const [k,v] of await storage.get(keys.slice(i,i+100))) values.set(k,v);
      if (keys.some(k => typeof values.get(k) !== 'string')) throw new Error('Missing vault chunk');
      return decrypt(keys.map(k => values.get(k)).join(''), key);
    },
    async save(state) {
      const encrypted = encrypt(state, key);
      const chunks = encrypted.match(/.{1,60000}/g);
      if (!chunks || chunks.length > 2000) throw new Error('Vault too large');
      await storage.transaction(async txn => {
        const oldCount = await txn.get('vault-chunk-count') ?? 0;
        for (let i = 0; i < chunks.length; i++) await txn.put(`vault-chunk-${i}`, chunks[i]);
        for (let i = chunks.length; i < oldCount; i++) await txn.delete(`vault-chunk-${i}`);
        await txn.put('vault-chunk-count', chunks.length);
        await txn.delete('vault');
      });
    },
  };
}
