import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { syncItem, normalizeTransaction, safeDiagnostic } from './transactions.mjs';
import { createBridge, encrypt } from './bridge.mjs';
import { vaultStorage } from './vault-storage.mjs';
const transaction = (id, more = {}) => ({ transaction_id: id, account_id: 'checking', amount: 3.29, iso_currency_code: 'USD', date: '2026-10-21', name: 'Coffee', pending: false, personal_finance_category: { primary: 'FOOD_AND_DRINK' }, ...more });
const page = (added = [], more = {}) => ({ added, modified: [], removed: [], has_more: false, next_cursor: 'next', ...more });

test('sync replaces pending, applies modifications/removals, preserves refund signs and transfers', async () => {
 const item = { id: 'bank', token: 'secret', transactionCursor: 'start', transactions: ['pending','removed','modified'].map(id => normalizeTransaction(transaction(id), 'bank', 'production')) };
 const result = await syncItem(item, 'production', async (_, input) => {
  if (input.cursor === 'start') return page([transaction('posted', { pending_transaction_id: 'pending' })], { has_more: true, next_cursor: 'page2' });
  return page([transaction('refund', { amount: -2 }), transaction('transfer', {personal_finance_category: {primary: 'TRANSFER_OUT'}})], { modified: [transaction('modified', { amount: 7 })], removed: [{ transaction_id: 'removed' }] });
 });
 assert.deepEqual(result.transactions.map(t => t.id).sort(), ['modified','posted','refund','transfer'].map(id => 'production:bank:'+id));
 assert.equal(result.transactions.find(t => t.id.endsWith('modified')).amountCents, 700);
 assert.equal(result.transactions.find(t => t.id.endsWith('refund')).amountCents, -200);
 assert.equal(result.transactions.find(t => t.id.endsWith('transfer')).isTransfer, true);
 assert.equal(item.transactionCursor, 'start');
});
test('mutation restarts from original cursor and discards the unsuccessful window', async () => {
 const cursors = []; let count = 0;
 const item = { id:'bank', token:'secret', transactionCursor:'original' };
 const result = await syncItem(item, 'production', async (_, input) => {
  cursors.push(input.cursor); count++;
  if (count === 1) return page([transaction('discard')], { has_more:true, next_cursor:'second' });
  if (count === 2) throw Object.assign(new Error('mutation'), { providerCode:'TRANSACTIONS_SYNC_MUTATION_DURING_PAGINATION' });
  return page([transaction('keep')]);
 });
 assert.deepEqual(cursors, ['original','second','original']);
 assert.equal(result.transactions.length, 1); assert.ok(result.transactions[0].id.endsWith('keep'));
});
test('page failure never mutates the stored cursor or history', async () => {
 const item = {id:'bank', token:'secret', transactionCursor:'original', transactions:[]};
 await assert.rejects(syncItem(item, 'production', async (_, input) => {
  if (input.cursor === 'original') return page([transaction('discard')], { has_more:true, next_cursor:'second' });
  throw new Error('offline');
 }));
 assert.deepEqual(item.transactions, []); assert.equal(item.transactionCursor, 'original');
});
test('diagnostic supports current/legacy exit and allowlists identifiers only', () => {
 for (const field of ['exit','on_exit']) {
  const diagnostic = safeDiagnostic({ link_session_id:'session-1', [field]:{error:{error_code:'INSTITUTION_DOWN',error_type:'INSTITUTION_ERROR',request_id:'request-1',error_message:'secret credentials'}} });
  assert.equal(diagnostic.code, 'INSTITUTION_DOWN');
  assert.ok(!JSON.stringify(diagnostic).includes('credentials'));
 }
 assert.equal(safeDiagnostic({exit:{error:{request_id:'https://secret?token=private'}}}).requestID, null);
});
test('bank sync is authenticated, retains failed banks, and throttles across restart', async () => {
 const config = { env:'production', apiToken:'a'.repeat(40), clientID:'client', secret:'secret' };
 let state = { environment:'production', items:[{id:'good',token:'good'}, {id:'bad',token:'bad',transactionCursor:'old',transactions:[normalizeTransaction(transaction('old'), 'bad','production')]}], sessions:[] };
 const storage = {load:async()=>state,save:async value=>{state=structuredClone(value);}};
 let calls=0;
 const provider = async (_, options) => { calls++; const input=JSON.parse(options.body); return Response.json(input.access_token==='bad' ? {error_code:'ITEM_LOGIN_REQUIRED'} : page([transaction('new')]), {status:input.access_token==='bad'?400:200}); };
 let handler=await createBridge(config,storage,provider);
 const req=token=>new Request('https://example.com/v1/transactions/sync',{method:'POST',headers:{authorization:'Bearer '+token}});
 assert.equal((await handler(req('wrong'))).status,401); assert.equal(calls,0);
 const result=await (await handler(req(config.apiToken))).json();
 assert.equal(result.errors.length,1); assert.equal(state.items[1].transactionCursor,'old');
 assert.ok(!JSON.stringify(result).includes('"token"'));
 handler=await createBridge(config,storage,provider); await handler(req(config.apiToken)); assert.equal(calls,2);
});
function fakeStorage(initial = new Map()) {
 let data=initial;
 const methods = map => ({get:async key=>Array.isArray(key)?new Map(key.filter(k=>map.has(k)).map(k=>[k,map.get(k)])):map.get(key),put:async(k,v)=>map.set(k,v),delete:async k=>map.delete(k)});
 return {get:async key=>methods(data).get(key), transaction:async fn=>{ const next=new Map(data); await fn(methods(next)); data=next; }, read:()=>data};
}
test('vault migrates legacy ciphertext, handles large history, and removes stale chunks', async () => {
 const key=randomBytes(32); const original={items:[{token:'private'}]};
 const storage=fakeStorage(new Map([['vault',encrypt(original,key)]])); const vault=vaultStorage(storage,key);
 assert.deepEqual(await vault.load(),original);
 const large={...original, history:'financial-data'.repeat(30000)};
 await vault.save(large); assert.deepEqual(await vault.load(),large); assert.equal(storage.read().has('vault'),false);
 assert.ok([...storage.read().values()].filter(x=>typeof x==='string').every(x=>Buffer.byteLength(x)<=60000 && !x.includes('financial-data')));
 await vault.save(original); assert.deepEqual(await vault.load(),original); assert.equal(storage.read().size,2);
});
test('incomplete encrypted vault fails closed', async () => {
 const key=randomBytes(32), storage=fakeStorage(new Map([['vault-chunk-count',2],['vault-chunk-0','incomplete']]));
 await assert.rejects(vaultStorage(storage,key).load(),/Missing vault chunk/);
});
test('deletion removes transaction caches with revoked items and retains failures for retry', async () => {
 const config={env:'production',apiToken:'a'.repeat(40)};
 let state={environment:'production',items:[{id:'good',token:'good',transactions:[{id:'private-history'}]},{id:'bad',token:'bad',transactions:[{id:'retry-history'}]}],sessions:[]};
 const storage={load:async()=>state,save:async next=>{state=next;}};
 const handler=await createBridge(config,storage,async(_,options)=>{
  const bad=JSON.parse(options.body).access_token==='bad';
  return Response.json(bad?{error_code:'SERVER_ERROR'}:{},{status:bad?500:200});
 });
 const response=await handler(new Request('https://example.com/v1/connections',{method:'DELETE',headers:{authorization:'Bearer '+config.apiToken}}));
 assert.equal(response.status,502); assert.deepEqual(state.items.map(i=>i.id),['bad']);
 assert.ok(!JSON.stringify(state).includes('private-history')); assert.ok(JSON.stringify(state).includes('retry-history'));
});
test('failed chunk transaction leaves the previous encrypted vault readable', async () => {
 const key=randomBytes(32), storage=fakeStorage(); const vault=vaultStorage(storage,key);
 const original={items:[{token:'retain-me'}]}; await vault.save(original);
 const oldTransaction=storage.transaction; let writes=0;
 storage.transaction=fn=>oldTransaction(txn=>fn({...txn,put:async(k,v)=>{if(++writes===2)throw new Error('disk full');await txn.put(k,v);}}));
 await assert.rejects(vault.save({large:'x'.repeat(100000)}),/disk full/);
 assert.deepEqual(await vault.load(),original);
});
