// Actual overlay, with a synchronous API and an asynchronous bridge.
import vm from 'node:vm';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const source=readFileSync(new URL('../lasthavens-addon-manager/runtime-core.js',import.meta.url),'utf8');
const track=new Uint8Array(200);
track.set([79,103,103,83]);track[26]=1;track[28]=1;
new DataView(track.buffer).setUint32(40,48000,true);
track.set([79,103,103,83],100);new DataView(track.buffer).setUint32(106,60*48000,true);
function runtime(){
  const ready=new Set(),emitted=[],listeners=[];
  let now=1000000,failures=0,requests=0;
  class Clock extends Date {static now(){return now}}
  class Native {
    open(_,url){this.url=url}send(){requests++;if(failures){failures--;throw new Error('temporary network failure')};this.quest=Number(/\/voice\/(\d+)/.exec(this.url)?.[1]);}
    get status(){return ready.has(this.quest)?200:202}
    get response(){return track.buffer}get responseText(){return ''}get readyState(){return 4}
    getResponseHeader(){return 'audio/ogg'}setRequestHeader(){}dispatchEvent(){}
  }
  class Channel {
    addEventListener(_,fn){listeners.push(fn)}
    postMessage(m){
      emitted.push(m);
      if(m.kind==='voice-fetch')queueMicrotask(()=>{
        requests++;
        const failed=failures>0;if(failed)failures--;
        const quest=Number(/\/voice\/(\d+)/.exec(m.url)?.[1]);
        for(const fn of listeners)fn({data:{kind:'voice-response',id:m.id,status:failed?502:ready.has(quest)?200:202,contentType:'audio/ogg',
          body64:Buffer.from(track).toString('base64')}});
      });
    }
  }
  const ctx=vm.createContext({XMLHttpRequest:Native,URL,TextDecoder,Uint8Array,DataView,atob,
    BroadcastChannel:Channel,Event,Date:Clock, setTimeout:()=>1,clearTimeout:()=>{}});
  vm.runInContext(source,ctx);
  ctx.LHInstallOverlay({},'https://game.test','https://api.test','3.3.5a',{},
    {locale:'ruRU',size:200,tracks:[[111,'DETAIL'],[222,'DETAIL']]});
  function read(path,async=false){const x=new ctx.XMLHttpRequest();x.open('GET','https://game.test/game/Interface/AddOns/CatQuest335_ServerVoices/'+path,async);x.send();return x}
  return {ready,emitted,read,advance:seconds=>{now+=seconds*1000},failNext:()=>{failures++},requests:()=>requests};
}

// A request abandoned before it was generated must not be handed to a later
// quest's poll. Its file may be ready, but it no longer owns playback.
{
  const r=runtime();
  assert.equal(r.read('ruRU/Sounds/q/111.ogg').status,404);
  assert.equal(r.read('ruRU/Sounds/q/222.ogg').status,404);
  for(let i=0;i<8;i++)await Promise.resolve();
  r.ready.add(111);
  r.advance(11);
  assert.equal(r.read('poll/1.ogg').status,404,'A poll for quest 222 must not start abandoned quest 111');
  r.ready.add(222);
  r.advance(11);
  assert.equal(r.read('poll/2.ogg').status,404,'First poll starts async fetch');
  for(let i=0;i<8;i++)await Promise.resolve();
  assert.equal(r.read('poll/5.ogg').status,200);
  assert.equal(r.emitted.find(m=>m.kind==='poll-pick').path.includes('/222.ogg'),true);
  assert.equal(r.read('poll/5.ogg').status,200); // Whole/block reads of one play share bytes.
  assert.equal(r.emitted.filter(m=>m.kind==='poll-pick').length,1);
  assert.equal(r.read('poll/3.ogg').status,404); // A new poll cannot repeat the sound.
  r.advance(65);
  assert.equal(r.read('poll/4.ogg').status,404); // Nor revive abandoned quest 111 after the busy period.
}

// An async fetch can fill the cache after a synchronous miss. Once the
// original file was delivered, it must leave the poll queue as well.
{
  const r=runtime();
  r.ready.add(111);
  assert.equal(r.read('ruRU/Sounds/q/111.ogg').status,404);
  r.read('ruRU/Sounds/q/111.ogg',true);
  for(let i=0;i<8;i++)await Promise.resolve();
  assert.equal(r.read('ruRU/Sounds/q/111.ogg').status,200);
  assert.equal(r.read('poll/1.ogg').status,404,'A cached track already delivered directly must not be replayed by a poll');
}
// Temporary fetch failure recovers asynchronously, without blocking reads.
{
  const r=runtime();r.failNext();
  assert.equal(r.read('ruRU/Sounds/q/111.ogg').status,404);
  for(let i=0;i<8;i++)await Promise.resolve();
  const attempted=r.requests();
  assert.equal(r.read('poll/10.ogg').status,404);
  assert.equal(r.requests(),attempted,'Transient failures need a retry backoff');
  r.ready.add(111);r.advance(11);
  assert.equal(r.read('poll/11.ogg').status,404,'Recovery starts a background request');
  for(let i=0;i<8;i++)await Promise.resolve();
  assert.equal(r.read('poll/13.ogg').status,200,'A failed fetch must recover through a fresh poll');
  assert.equal(r.requests(),attempted+1);
  assert.equal(r.read('poll/12.ogg').status,404,'Recovery must not replay the same voice');
}
console.log('Playback polls: current ownership, cached delivery and transient network recovery passed');
