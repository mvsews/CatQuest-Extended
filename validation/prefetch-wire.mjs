import vm from 'node:vm';
import assert from 'node:assert/strict';
import {readFileSync,mkdtempSync,rmSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import path from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('..',import.meta.url));
const fixture=JSON.parse(execFileSync('python',['-c',
 `import sys,json;sys.path.insert(0,'.tmp/test-python');from lupa.lua51 import LuaRuntime;from pathlib import Path;l=LuaRuntime();l.globals().ROOT=Path.cwd().as_posix();r=l.execute(Path('validation/prefetch-wire.lua').read_text(encoding='utf-8'));print(json.dumps({k:list(r[k].values()) for k in ['paths','played','probes']}))`],{cwd:root,encoding:'utf8'}));
const font={...JSON.parse(readFileSync(new URL('../lasthavens-addon-manager/vendor/catquest-ready.json',import.meta.url))),body64:readFileSync(new URL('../lasthavens-addon-manager/vendor/catquest-ready.ttf',import.meta.url)).toString('base64')};
const temp=mkdtempSync(path.join(tmpdir(),'cq-prefetch-'));
try {
 const file=path.join(temp,'test.ogg');
 execFileSync('ffmpeg',['-v','error','-f','lavfi','-i','sine=frequency=440:sample_rate=24000:duration=4.25','-c:a','libvorbis',file]);
 const bytes=readFileSync(file),events=[],listeners=[];
 class Native{open(){}send(){throw Error('Unexpected network-backed sync read')}get status(){return 200}getResponseHeader(){return null}}
 class Channel{addEventListener(_,f){listeners.push(f)}postMessage(m){events.push(m)}}
 const ctx=vm.createContext({XMLHttpRequest:Native,URL,TextDecoder,TextEncoder,Uint8Array,DataView,atob,setTimeout:()=>1,clearTimeout(){},BroadcastChannel:Channel});
 vm.runInContext(readFileSync(new URL('../lasthavens-addon-manager/runtime-core.js',import.meta.url),'utf8'),ctx);
 ctx.LHInstallOverlay({},'https://game.test','https://api.test','3.3.5a',{}, {locale:'ruRU',size:bytes.length,tracks:[[11451,'DETAIL'],[11451,'COMPLETE']]},[],{locale:'ruRU',size:bytes.length},'',font);
 const read=p=>{const x=new ctx.XMLHttpRequest();x.open('GET','https://game.test/game/'+p.replaceAll('\\','/'),false);x.responseType='arraybuffer';x.send();return x};
 const greeting=[1,1,1,...Buffer.from('v2\t123\tmale\nNPC\nGreeting text')];
 const textFrame=[4,greeting.length,...greeting];textFrame.push(textFrame.reduce((a,b)=>a+b,0)%256);
 textFrame.flatMap(b=>[b>>4,b&15]).forEach((n,pos)=>read(`Interface/AddOns/CatQuest335_ServerVoices/gossip-msg/1/${pos}/${n.toString(16)}.ogg`));
 const markers=fixture.paths.filter(p=>p.includes('\\prefetch\\'));
 // Last byte never arrived: a partial command must not fetch or play.
 const first=markers.filter(p=>p.includes('\\prefetch\\1\\'));
 first.slice(0,-1).forEach(read);assert.equal(events.filter(e=>e.kind==='voice-fetch').length,0);
 markers.forEach(read);
 const requests=events.filter(e=>e.kind==='voice-fetch');
 assert.equal(requests.length,51,'DETAIL, COMPLETE, 3 place variants, NPC greeting and 45 later quests');
 assert(requests.some(e=>e.url.includes('/11451/DETAIL?')));
 assert(requests.some(e=>e.url.includes('/11451/COMPLETE?')));
 assert.equal(requests.filter(e=>e.url.includes('/book/a1b2c3d4?')).length,3);
 assert(requests.some(e=>e.url.includes('/gossip?')&&e.url.includes('npc_id=123')));
 assert.equal(read('Interface/AddOns/CatQuest335_ServerVoices/ready-signal/2/1.ttf').status,200,'Waiting signal uses a local zero-duration font');
 for(const request of requests)for(const fn of listeners)fn({data:{kind:'voice-response',id:request.id,status:200,contentType:'audio/ogg',body64:bytes.toString('base64')}});
 for(let i=0;i<8;i++)await Promise.resolve();
 const answer=read('Interface/AddOns/CatQuest335_ServerVoices/ready-signal/2/2.ttf');
 assert.equal(answer.status,200);assert.equal(Buffer.from(answer.response).length,font.bytes);
 assert.equal(read('Interface/AddOns/CatQuest335_ServerVoices/ready-signal/2/2.ttf/2188-0-64k.bin').status,200);
 const before=events.filter(e=>e.kind==='voice-fetch').length;
 const audio=read(fixture.played[0]);assert.equal(audio.status,200);assert.equal(Buffer.from(audio.response).toString('ascii',0,4),'OggS');
 assert.equal(events.filter(e=>e.kind==='voice-fetch').length,before,'Playback uses warmed cache');
 markers.forEach(read);
 assert.equal(read('Interface/AddOns/CatQuest335_ServerVoices/ready-signal/2/3.ttf').status,200,'Repeated block reads must not clear a ready signal');
 assert.equal(events.filter(e=>e.kind==='poll-pick').length,0,'Prefetch never plays background COMPLETE');
 // Legacy gossip-msg dispatch must retain the first nibble, too.
 const f=[8,8,0,0,44,187,1,1,1,244];f.push(f.reduce((a,b)=>a+b,0)%256);
 f.flatMap(b=>[b>>4,b&15]).forEach((n,pos)=>read(`Interface/AddOns/CatQuest335_ServerVoices/gossip-msg/16/${pos}/${n.toString(16)}.ogg`));
 for(let i=0;i<8;i++)await Promise.resolve();
 assert.equal(read('Interface/AddOns/CatQuest335_ServerVoices/ready-signal/500.ttf').status,200,'Legacy frame is complete');
 // Page-side VFS fetches must see the worker's acknowledgement, too.
 const pageListeners=[];
 const page=vm.createContext({XMLHttpRequest:Native,URL,TextDecoder,TextEncoder,Uint8Array,DataView,atob,Headers,Response,
  fetch:()=>{throw Error('Unexpected page network read')},setTimeout:()=>1,clearTimeout(){},BroadcastChannel:class{addEventListener(_,fn){pageListeners.push(fn)}},location:{origin:'https://game.test'}});
 vm.runInContext('window=globalThis;addEventListener=()=>{};postMessage=()=>{}',page);
 vm.runInContext(readFileSync(new URL('../lasthavens-addon-manager/runtime-core.js',import.meta.url),'utf8'),page);
 page.LHInstallOverlay({},'https://game.test','https://api.test','3.3.5a',{},null,[],{locale:'ruRU',size:bytes.length},'',font);
 for(const event of events.filter(e=>e.kind==='ready-signal'))for(const fn of pageListeners)fn({data:event});
 const pageFont=await page.fetch('https://game.test/game/Interface/AddOns/CatQuest335_ServerVoices/ready-signal/2/2.ttf');
 assert.equal(pageFont.status,200);assert.equal((await pageFont.arrayBuffer()).byteLength,font.bytes);
 const unknown=await page.fetch('https://game.test/game/Interface/AddOns/CatQuest335_ServerVoices/ready-signal/499/1.ttf');
 assert.equal(unknown.status,200,'Any v2 slot can be answered locally while its audio is pending');
 console.log('Real Lua -> frames -> async response -> fresh ready alias -> cached OGG: passed; dedup/Stop/duration, page bridge and >32 requests with LRU eviction passed');
} finally {rmSync(temp,{recursive:true,force:true})}
