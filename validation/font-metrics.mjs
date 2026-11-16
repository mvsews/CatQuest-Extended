import vm from 'node:vm';
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {execFileSync} from 'node:child_process';
const root=new URL('..',import.meta.url);
const font={...JSON.parse(readFileSync(new URL('lasthavens-addon-manager/vendor/catquest-ready.json',root))),
 body64:readFileSync(new URL('lasthavens-addon-manager/vendor/catquest-ready.ttf',root)).toString('base64')};
assert.equal(font.metrics_version,2);
const listeners=[];
const ctx=vm.createContext({XMLHttpRequest:class{open(){}send(){throw Error('No network allowed')}},
 URL,TextEncoder,TextDecoder,Uint8Array,DataView,Int32Array,SharedArrayBuffer,Atomics,atob,Headers,Response,
 setTimeout:()=>1,clearTimeout(){},location:{origin:'https://game.test'},fetch(){throw Error('No network allowed')},
 BroadcastChannel:class{addEventListener(_,fn){listeners.push(fn)}}});
vm.runInContext('window=globalThis;addEventListener=()=>{};postMessage=()=>{}',ctx);
vm.runInContext(readFileSync(new URL('lasthavens-addon-manager/runtime-core.js',root),'utf8'),ctx);
ctx.LHInstallOverlay({},'https://game.test','https://api.test','3.3.5a',{}, {locale:'ruRU',size:200,tracks:[]},[],null,'',font);
const temp=mkdtempSync(join(tmpdir(),'cq-native-metrics-'));
try{
 const samples=[];
 for(const seconds of [.1,4.3,13.3,36.8,99.9,123.4,999.9]){
  for(const fn of listeners)fn({data:{kind:'ready-signal',slot:1,seconds}});
  const response=await ctx.fetch('https://game.test/game/Interface/AddOns/CatQuest335_ServerVoices/ready-signal/1/1.ttf');
  assert.equal(response.status,200);
  const file=join(temp,seconds+'.ttf');writeFileSync(file,new Uint8Array(await response.arrayBuffer()));
  samples.push({seconds,file});
 }
 const manifest=join(temp,'samples.json');writeFileSync(manifest,JSON.stringify(samples));
 console.log(execFileSync('python',['validation/run_font_metrics_tests.py',manifest],{encoding:'utf8'}).trim());
}finally{rmSync(temp,{recursive:true,force:true})}
