import vm from 'node:vm';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {diagnosticLabel,exportDiagnostics} from '../lasthavens-addon-manager/diagnostics-format.js';
const source=readFileSync(new URL('../lasthavens-addon-manager/background.js',import.meta.url),'utf8').replace(/^import[\s\S]*?;\r?\n/gm,'');
const stored={},timers=[];let handler,writes=0,mode='ready';
const listener={addListener(){}};
const context=vm.createContext({URL,Uint8Array,AbortSignal,btoa,console,setTimeout:f=>(timers.push(f),timers.length),
 self:{addEventListener(){}},chrome:{action:{onClicked:listener},alarms:{onAlarm:listener},
 runtime:{getManifest:()=>({version:'0.6.58'}),onInstalled:listener,onStartup:listener,onMessage:{addListener:f=>handler=f}},
 storage:{session:{get:async()=>stored,set:async change=>{Object.assign(stored,change);writes++}}}},
 countProbe(){},errorOf:()=>null,recordError(){},reportOrder(){},
 fetch:async()=>{
  if(mode==='offline')throw Error('offline test');
  const ready=mode==='ready';return {status:ready?200:429,headers:new Headers({'Content-Type':ready?'audio/ogg':'application/json'}),
   arrayBuffer:async()=>new Uint8Array([79,103,103,83]).buffer,json:async()=>({error:'budget_exhausted',reason:'try later'})};
 }});
vm.runInContext(source,context);
async function request(){return await new Promise(resolve=>handler({kind:'voice-fetch',request:'req-test',run:'run-test',
 url:'https://quester.mvse.ws/api/v1/voice/12009/COMPLETE?locale=ruRU&p=secret'},
 {tab:{url:'https://lasthavens.com/play'}},resolve));}
assert.equal((await request()).ok,true);mode='limited';assert.equal((await request()).status,429);
mode='offline';assert.equal((await request()).ok,false);
assert.equal(writes,0,'Diagnostics storage writes are batched');
timers.shift()();for(let i=0;i<12;i++)await Promise.resolve();
assert.equal(writes,1);const log=stored.probeLog;
assert(log.some(e=>e.type==='backend-headers'&&e.status===200));
assert(log.some(e=>e.type==='backend-body'&&e.status===429&&e.detail.includes('budget_exhausted')));
assert(log.some(e=>e.type==='backend-error'&&e.error.includes('offline')));
assert(log.every(e=>e.quest===12009&&e.kind==='COMPLETE'&&e.run==='run-test'));
for(let i=0;i<1200;i++)handler({kind:'probe',event:{type:'sample',at:Date.now()}},{tab:{url:'https://lasthavens.com/play'}},()=>{});
timers.shift()();for(let i=0;i<12;i++)await Promise.resolve();assert.equal(stored.probeLog.length,300);
const report=exportDiagnostics([...log,{type:'client-stage',run:'run-test',slot:42,quest:12009,kind:'COMPLETE',stage:'font-missing (client)',at:Date.now(),body64:'secret'}],'0.6.58');
assert(report.includes('font-missing'));assert(report.includes('clientFont=not observed'));assert(!report.includes('secret'));
assert(diagnosticLabel(log[0]).includes('req=req-test'));
console.log('Extension diagnostics: correlated backend stages, HTTP errors, batching, bounded history and export passed');
