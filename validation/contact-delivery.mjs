import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const read=(p)=>readFileSync(new URL(p,import.meta.url),'utf8');
const core=read('../lasthavens-addon-manager/runtime-core.js');
let tasks=new Map(),serial=0;
const messages=[];
const receiver=vm.createContext({post:m=>messages.push(structuredClone(m)),
  setTimeout:fn=>{tasks.set(++serial,fn);return serial},clearTimeout:id=>tasks.delete(id)});
vm.runInContext('const contactNibbles=new Map(),contactTimers=new Map();'+
  core.slice(core.indexOf('  const recordContactMarker ='),core.indexOf('  const markerFor ='))+
  '\nglobalThis.record=recordContactMarker;',receiver);
const markers=JSON.parse(read('../.tmp/contact-markers.json'));
for(const path of markers){
  const m=/contact\\(\d+)\\(\d+)\\([0-9a-f])\.ogg$/.exec(path);assert(m,path);
  receiver.record(+m[1],+m[2],parseInt(m[3],16));
}
function runTimers(){const batch=[...tasks.values()];tasks.clear();for(const fn of batch)fn()}
assert(messages.length>=69); // Complete frames arrive even without a timer tick.
const total=messages[0].total;
assert.equal(messages.length,total);
assert.equal(new Set(messages.map(m=>m.id)).size,1);
// Damaged and incomplete frames never become messages.
receiver.record(79,0,0);receiver.record(79,1,7);
runTimers();
assert.equal(messages.length,total);

const source=read('../lasthavens-addon-manager/contact.js').replace(/^import .*;$/gm,'').replaceAll('export ','');
const ratingSource=read('../lasthavens-addon-manager/quest-ratings.js').replace(/^import .*;$/gm,'').replaceAll('export ','');
const store={telemetryOff:true},requests=[];
let offline=true,serverStatus=200;
const storage={get:async(keys)=>Object.fromEntries((Array.isArray(keys)?keys:[keys]).map(k=>[k,structuredClone(store[k])])),
  set:async(values)=>Object.assign(store,structuredClone(values))};
function runtime(){
  const ctx=vm.createContext({chrome:{storage:{local:storage},runtime:{getManifest:()=>({version:'test'})}},
    TextDecoder,TextEncoder,Uint8Array,AbortController,setTimeout,clearTimeout,UPDATE_ORIGIN:'https://isolated.test',
    explicitMessageIdentity:async()=>({id:'anonymous-test-id',token:'anonymous-test-token'}),
    fetch:async(url,options)=>{if(offline)throw Error('offline');requests.push(JSON.parse(options.body));
      return {ok:serverStatus===200,json:async()=>({ok:serverStatus===200})}}});
  vm.runInContext('globalThis.helpers=(()=>{'+ratingSource+';return {captureAttribution,deliveryAttribution,cleanVoteCharacter}})();',ctx);
  Object.assign(ctx,ctx.helpers);
  vm.runInContext(source+'\nglobalThis.api={receiveContactPart,flushContactMessages};',ctx);return ctx.api;
}
let api=runtime();
for(const part of messages.slice(0,30).reverse())assert(await api.receiveContactPart(part));
assert.equal(Object.keys(store.contactOutbox||{}).length,0);
api=runtime(); // Restart while the large message is only partially received.
for(const part of messages.slice(30).reverse())assert(await api.receiveContactPart(part));
await api.flushContactMessages();
const [id,item]=Object.entries(store.contactOutbox)[0];
assert.equal(item.body,'Ж'.repeat(1997)+'\n🙂');assert.equal(item.category,'suggestion');
assert(store.contactReceived[id]);assert.equal(Object.keys(store.contactParts).length,0);
assert(!('name' in item)&&!('guid' in item)&&!('realm' in item));
offline=false;serverStatus=503;api=runtime();await api.flushContactMessages();
assert.equal(Object.keys(store.contactOutbox).length,1);
serverStatus=200;await api.flushContactMessages();assert.equal(Object.keys(store.contactOutbox).length,0);
const count=requests.length;
for(const part of messages)assert(await api.receiveContactPart(part));
await api.flushContactMessages();assert.equal(requests.length,count);
assert.equal(await api.receiveContactPart({...messages[0],category:9}),false);
assert.equal(await api.receiveContactPart({...messages[0],bytes:[256]}),false);
assert.equal(await api.receiveContactPart({...messages[0],total:79}),false);
console.log('Contact delivery: actual Lua frames -> runtime decoder -> durable partial receipt -> UTF-8 reconstruction -> offline outbox -> retries -> deduplicated submission passed');

function envelope(id,text){
  const bytes=[...new TextEncoder().encode(text)],total=Math.ceil(bytes.length/58);
  return Array.from({length:total},(_,i)=>({id,index:i+1,total,category:1,bytes:bytes.slice(i*58,(i+1)*58)}));
}
store.telemetryOff=false;offline=true;
const created=Math.floor(Date.now()/1000);
const extended=envelope('0123456789abcdef',`CQ2\t${created}\t0.10.68\tLastHavens\tПервый\t0x000000000000002A\nТест\nПредложение`);
for(const part of extended)assert(await api.receiveContactPart(part));
await api.flushContactMessages();
let queued=store.contactOutbox['0123456789abcdef'];
assert.equal(queued.body,'Тест\nПредложение');assert.equal(queued.character.name,'Первый');
assert.equal(queued.addon_version,'0.10.68');assert.equal(queued.submitted_at,created);
store.character={name:'Другой герой'};offline=false;await api.flushContactMessages();
assert.equal(requests.at(-1).character.name,'Первый');

// Privacy is captured on the first part, checked again on assembly and again
// before HTTP. A new current character must never fill missing attribution.
store.telemetryOff=true;offline=true;
const anonymous=envelope('fedcba9876543210',`CQ2\t${created}\t0.10.68\tLastHavens\tПервый\t0x000000000000002A\nАнонимный тест`);
await api.receiveContactPart(anonymous[0]);store.telemetryOff=false;
for(const part of anonymous.slice(1))assert(await api.receiveContactPart(part));
await api.flushContactMessages();
assert.equal(store.contactOutbox['fedcba9876543210'].character,null);
offline=false;await api.flushContactMessages();assert.equal(requests.at(-1).character,null);
console.log('Contact attribution: submit time, real addon version, original actor and opt-out during chunked delivery passed');
