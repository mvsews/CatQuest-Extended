// No incoming callback is ever delivered to the game worker. This models a
// native pthread loop that never yields to its JS event loop.
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const source=readFileSync(new URL('../lasthavens-addon-manager/runtime-core.js',import.meta.url),'utf8');
const font={...JSON.parse(readFileSync(new URL('../lasthavens-addon-manager/vendor/catquest-ready.json',import.meta.url))),body64:readFileSync(new URL('../lasthavens-addon-manager/vendor/catquest-ready.ttf',import.meta.url)).toString('base64')};
const audio=new Uint8Array(200);audio.set([79,103,103,83]);audio[26]=1;audio[28]=1;
new DataView(audio.buffer).setUint32(40,48000,true);audio.set([79,103,103,83],100);new DataView(audio.buffer).setUint32(106,60*48000,true);
const shared={header:new SharedArrayBuffer(513*16),audio:new SharedArrayBuffer(2*1024),laneBytes:1024,lanes:2,runId:'diagnostic-test',extensionVersion:'0.6.58',addonVersion:'0.10.92'};
const pageListeners=[],outgoing=[],pageEvents=[],workerIncoming=[];
class Native{open(){}send(){throw Error('Synchronous network request is forbidden')}getResponseHeader(){return null}}
const common={XMLHttpRequest:Native,URL,TextDecoder,TextEncoder,Uint8Array,DataView,Int32Array,SharedArrayBuffer,Atomics,atob,Headers,Response,setTimeout:()=>1,clearTimeout(){}};
const page=vm.createContext({...common,crossOriginIsolated:true,queueMicrotask,body64:Buffer.from(audio).toString('base64'),location:{origin:'https://game.test'},fetch:()=>{throw Error('Unexpected network read')},
 BroadcastChannel:class{addEventListener(_,f){pageListeners.push(f)}},record:m=>pageEvents.push(m)});
vm.runInContext(`window=globalThis;const windowListeners=[];addEventListener=(_,f)=>windowListeners.push(f);postMessage=m=>{record(m);if(m.kind==='voice-fetch')queueMicrotask(()=>windowListeners.forEach(f=>f({source:window,origin:location.origin,data:{channel:m.channel,kind:'voice-response',id:m.id,status:200,contentType:'audio/ogg',body64}})))}`,page);
const worker=vm.createContext({...common,BroadcastChannel:class{addEventListener(_,f){workerIncoming.push(f)}postMessage(m){outgoing.push(m);queueMicrotask(()=>pageListeners.forEach(f=>f({data:m})))}}});
let directory;
for(const ctx of [page,worker]){vm.runInContext(source,ctx);const installed=ctx.LHInstallOverlay({},'https://game.test','https://api.test','3.3.5a',{}, {locale:'ruRU',size:200,tracks:[[11451,'DETAIL']]},[],null,'',font,shared,directory);directory=installed.sharedManifest}
assert(directory?.buffer instanceof SharedArrayBuffer,'Page and worker use one shared manifest');
const read=(p)=>{const x=new worker.XMLHttpRequest();x.open('GET','https://game.test/game/Interface/AddOns/CatQuest335_ServerVoices/'+p,false);x.responseType='arraybuffer';x.send();return x};
function request(signal,quest=11451){
 const f=[8,8,0,0,quest>>8,quest&255,1,1,signal>>8,signal&255];f.push(f.reduce((a,b)=>a+b,0)%256);
 f.flatMap(b=>[b>>4,b&15]).forEach((v,p)=>read(`prefetch/${signal}/${p}/${v.toString(16)}.ogg`));
}
request(5);
read('trace/5/17.ogg');read('trace/5/17.ogg');
const clientEvents=outgoing.filter(m=>m.kind==='probe' && m.event.type==='client-stage');
assert.equal(clientEvents.length,1,'Repeated range/cache reads do not multiply client stages');
assert.equal(clientEvents[0].event.quest,11451);assert.equal(clientEvents[0].event.slot,5);
assert.equal(clientEvents[0].event.stage,'font-probe');assert.equal(clientEvents[0].event.attempt,1);
assert.equal(clientEvents[0].event.run,'diagnostic-test');
assert.equal(read('ready-signal/5/1.ttf').status,200,'A v2 slot exposes a local zero-duration waiting font immediately');
for(let i=0;i<20;i++)await Promise.resolve();
assert.equal(pageEvents.filter(m=>m.kind==='voice-fetch').length,1,'Page owns the fetch');
assert.equal(outgoing.filter(m=>m.kind==='voice-fetch').length,0,'Worker does not wait on a Promise response');
assert.equal(read('ready-signal/5/2.ttf').status,200,'Worker sees page acknowledgement without any incoming JS event');
assert.equal(read('ruRU/Sounds/q/11451.ogg').status,200,'Worker has actual audio bytes, not just readiness');
read('trace/5/11.ogg');read('trace/5/4.ogg');
assert(outgoing.some(m=>m.event?.type==='audio-delivered' && m.event.quest===11451));
assert(outgoing.some(m=>m.event?.type==='client-stage' && m.event.stage.startsWith('playing')));
assert(outgoing.some(m=>m.kind==='probe'&&m.event.type==='read'&&m.event.quest===11451&&m.event.cached),
 'Read diagnostic must acknowledge shared/pinned audio so the browser panel can leave loading');
const pageFont=await page.fetch('https://game.test/game/Interface/AddOns/CatQuest335_ServerVoices/ready-signal/5/2.ttf');assert.equal(pageFont.status,200);
request(6,11452);request(7,11453);
for(let i=0;i<20;i++)await Promise.resolve();
assert.equal(read('ready-signal/6/1.ttf').status,200);assert.equal(read('ready-signal/7/1.ttf').status,200);
assert.equal(read('ruRU/Sounds/q/11451.ogg').status,200,'Already acknowledged bytes remain pinned after shared-lane reuse');
assert.equal(pageEvents.filter(m=>m.kind==='voice-fetch').length,3);
request(8,11454);request(9,11455);request(10,11456);
for(let i=0;i<20;i++)await Promise.resolve();
assert.equal(read('ready-signal/8/1.ttf').status,200,'An evicted result falls back to a local waiting font');
for(let i=0;i<20;i++)await Promise.resolve();
assert.equal(read('ready-signal/8/2.ttf').status,200,'Page republishes a cached result without waiting for worker callbacks');
assert.equal(pageEvents.filter(m=>m.kind==='voice-fetch').length,6,'Republishing must not download again');
console.log('Blocked native worker: page fetch -> shared memory -> signal -> cached audio passed with zero incoming worker callbacks');
