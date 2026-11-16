import vm from 'node:vm';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const fixture=JSON.parse(readFileSync(new URL('../.tmp/gossip-once-frames.json',import.meta.url),'utf8'));
const emitted=[];
class Native {open(){}send(){}get status(){return 200}getResponseHeader(){return null}}
const ctx=vm.createContext({XMLHttpRequest:Native,URL,TextDecoder,TextEncoder,Uint8Array,DataView,atob,
 setTimeout:()=>1,clearTimeout:()=>{},BroadcastChannel:class{addEventListener(){}postMessage(m){emitted.push(m)}}});
vm.runInContext(readFileSync(new URL('../lasthavens-addon-manager/runtime-core.js',import.meta.url),'utf8'),ctx);
ctx.LHInstallOverlay({},'https://game.test','https://api.test','3.3.5a',{},null,[],{size:1572864,locale:'ruRU'});
const open=(path)=>{const x=new ctx.XMLHttpRequest();x.open('GET','https://game.test/game/'+path.replaceAll('\\','/'),false);return x};
for(const p of fixture.paths.filter(p=>p.includes('gossip-msg'))){const x=open(p);x.send();assert.equal(x.status,200)}
assert.equal(emitted.filter(m=>m.kind==='gossip-heard').length,0,'Requesting or transferring text must not mark it heard');
open(fixture.audio); // Parse the real v2 header. Opening is not completion.
assert.equal(emitted.filter(m=>m.kind==='gossip-heard').length,0);
const finished=fixture.paths.filter(p=>p.includes('heard\\gossip'));
assert.equal(finished.length,1,'Real Core emits the acknowledgement only at natural completion');
open(finished[0]).send();
assert.equal(emitted.filter(m=>m.kind==='gossip-heard').length,1);
assert.equal(emitted.find(m=>m.kind==='gossip-heard').key,fixture.key);
open('Interface/AddOns/CatQuest335_ServerVoices/heard/gossip/254.ogg').send();
assert.equal(emitted.filter(m=>m.kind==='gossip-heard').length,1,'Unknown slots cannot acknowledge an unrelated paragraph');
console.log('Gossip wire: real Core frames, NPC/text key, completed-only acknowledgement and unknown-slot rejection passed');
