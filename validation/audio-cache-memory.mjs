import vm from 'node:vm';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
assert(global.gc,'Run with node --expose-gc');
const source=readFileSync(new URL('../lasthavens-addon-manager/runtime-core.js',import.meta.url),'utf8');
const font={...JSON.parse(readFileSync(new URL('../lasthavens-addon-manager/vendor/catquest-ready.json',import.meta.url))),body64:readFileSync(new URL('../lasthavens-addon-manager/vendor/catquest-ready.ttf',import.meta.url)).toString('base64')};
const track=new Uint8Array(256*1024);track.set([79,103,103,83]);track[26]=1;track[28]=1;new DataView(track.buffer).setUint32(40,48000,true);track.set([79,103,103,83],100);new DataView(track.buffer).setUint32(106,60*48000,true);
const listeners=[];let requests=0;
class Native{open(){}send(){throw Error('Unexpected sync network request')}getResponseHeader(){return null}}
const ctx=vm.createContext({XMLHttpRequest:Native,URL,TextEncoder,TextDecoder,Uint8Array,DataView,Int32Array,SharedArrayBuffer,Atomics,atob,Headers,Response,queueMicrotask,crossOriginIsolated:true,
 body64:Buffer.from(track).toString('base64'),location:{origin:'https://game.test'},setTimeout:()=>1,clearTimeout(){},BroadcastChannel:class{addEventListener(_,f){listeners.push(f)}},note:()=>requests++});
vm.runInContext(`window=globalThis;const handlers=[];addEventListener=(_,f)=>handlers.push(f);postMessage=m=>{if(m.kind==='voice-fetch'){note();queueMicrotask(()=>handlers.forEach(f=>f({source:window,origin:location.origin,data:{channel:m.channel,kind:'voice-response',id:m.id,status:200,contentType:'audio/ogg',body64}})))}}`,ctx);
const shared={header:new SharedArrayBuffer(513*16),audio:new SharedArrayBuffer(1024*1024),laneBytes:512*1024,lanes:2};
vm.runInContext(source,ctx);ctx.LHInstallOverlay({},'https://game.test','https://api.test','3.3.5a',{},null,[],{locale:'ruRU',size:track.length},'',font,shared);
global.gc();const before=process.memoryUsage().arrayBuffers;
const request=slot=>listeners.forEach(f=>f({data:{kind:'prefetch-start',slot,path:`Interface/AddOns/CatQuest335_ServerVoices/ruRU/Sounds/q/${20000+slot}.ogg`}}));
for(let slot=1;slot<=200;slot++){request(slot);for(let i=0;i<10;i++)await Promise.resolve()}
await new Promise(setImmediate);global.gc();await new Promise(setImmediate);global.gc();
const growth=process.memoryUsage().arrayBuffers-before;
assert.equal(requests,200);
assert(growth<22*1024*1024,`200 tracks must stay within bounded audio caches, got ${growth} bytes`);
// An evicted result is fetched again on demand, not falsely acknowledged.
request(1);for(let i=0;i<10;i++)await Promise.resolve();assert.equal(requests,201);
const x=new ctx.XMLHttpRequest();x.open('GET','https://game.test/game/Interface/AddOns/CatQuest335_ServerVoices/ready-signal/1/2.ttf',false);x.responseType='arraybuffer';x.send();assert.equal(x.status,200);
console.log(`200-track audio retention: ${(growth/1024/1024).toFixed(1)} MiB; evicted track reload and readiness passed`);
