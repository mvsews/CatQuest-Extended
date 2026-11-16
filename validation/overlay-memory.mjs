import vm from 'node:vm';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('..',import.meta.url));
if(!process.argv.includes('--measure')) {
 const measure=mode=>JSON.parse(execFileSync(process.execPath,['--expose-gc','--max-old-space-size=384',fileURLToPath(import.meta.url),'--measure',mode],{cwd:root,encoding:'utf8'}));
 const before=measure('baseline'),after=measure('shared');
 console.log(JSON.stringify({before_one_worker:before,after_32_workers:after},null,2));
 assert(after.heapBytes < before.heapBytes*3,'32 workers must not each retain a copy of the large directory');
 assert(after.heapBytes < 160*1024*1024,'Overlay JS heap across 32 workers must remain bounded');
 console.log('32-worker manifest memory and unchanged manifest delivery passed');
} else {
 const baseline=process.argv.at(-1)==='baseline';
 const source=baseline?execFileSync('python',['-c',"import zipfile;print(zipfile.ZipFile('dist/release/CatQuest-Lasthavens-0.6.53.zip').read('lasthavens-addon-manager/runtime-core.js').decode('utf-8'))"],{encoding:'utf8',maxBuffer:1024*1024}):readFileSync('lasthavens-addon-manager/runtime-core.js','utf8');
 const font={...JSON.parse(readFileSync('lasthavens-addon-manager/vendor/catquest-ready.json')),body64:readFileSync('lasthavens-addon-manager/vendor/catquest-ready.ttf').toString('base64')};
 class Native{open(){}send(){}get status(){return 200}get responseText(){return '1\tbase-file'}getResponseHeader(){return null}}
 const tracks={ruRU:Array.from({length:5165},(_,i)=>[i+10000,'DETAIL',200])};
 const demand={locale:'ruRU',size:1572864,tracks:Array.from({length:7042},(_,i)=>[i+20000,i%2?'DETAIL':'COMPLETE'])};
 global.gc();const start=process.memoryUsage().heapUsed;
 const contexts=[];let shared;
 for(let i=0;i<(baseline?1:32);i++) {
  const ctx=vm.createContext({XMLHttpRequest:Native,URL,TextEncoder,TextDecoder,Uint8Array,DataView,Int32Array,SharedArrayBuffer,Atomics,atob,crossOriginIsolated:true,setTimeout:()=>1,clearTimeout(){}});
  vm.runInContext(source,ctx);
  const installed=ctx.LHInstallOverlay({},'https://game.test','https://api.test','3.3.5a',structuredClone(tracks),structuredClone(demand),[],null,'',font,null,shared);
  if(!baseline){if(shared)assert.equal(installed.sharedManifest.buffer,shared.buffer);shared=installed.sharedManifest}
  contexts.push(ctx);
 }
 const ctx=contexts.at(-1),x=new ctx.XMLHttpRequest();x.open('GET','https://game.test/game-manifest.txt',false);x.send();
 const text=x.responseText;
 assert(text.includes('1\tbase-file\n'));assert(text.includes('/prefetch/512/21/f.ogg'));assert(text.includes('/ready-signal/512/16.ttf'));assert(text.includes('/contact/80/143/f.ogg'));
 // Ignore this intentionally requested transient decoded text in retained measurements.
 x.answer=null;
 global.gc();
 console.log(JSON.stringify({workers:contexts.length,heapBytes:process.memoryUsage().heapUsed-start,sharedManifestBytes:shared?.buffer.byteLength||0,manifestCharacters:text.length}));
}
