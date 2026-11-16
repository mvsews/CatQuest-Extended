import {createServer} from 'node:http';
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {chromium} from '../.tmp/browser-tests/node_modules/playwright-core/index.mjs';
const track=(process.argv[2] || '12009-COMPLETE').match(/^(\d{1,7})-(DETAIL|COMPLETE)$/);
assert(track,'Expected questID-DETAIL or questID-COMPLETE');
const quest=Number(track[1]),kind=track[2],stem=quest+(kind==='COMPLETE'?'_t':'');
const audio=readFileSync(new URL(`../.tmp/${track[0]}.ogg`,import.meta.url));
const runtime=readFileSync(new URL('../lasthavens-addon-manager/runtime-core.js',import.meta.url),'utf8');
const loader=readFileSync(new URL('../lasthavens-addon-manager/loader.js',import.meta.url),'utf8');
const font={...JSON.parse(readFileSync(new URL('../lasthavens-addon-manager/vendor/catquest-ready.json',import.meta.url))),body64:readFileSync(new URL('../lasthavens-addon-manager/vendor/catquest-ready.ttf',import.meta.url)).toString('base64')};
const worker=`var wasmImports;function assignWasmImports(){wasmImports={WebVfsStoreIo(){return 0}}}
var FS={files:new Map([['Fonts/FRIZQT__.TTF',new Uint8Array([1,2,3])]]),mkdirTree(){},
 createDataFile(parent,name,bytes){this.files.set(parent==='.'?name:parent+'/'+name,bytes)},
 unlink(path){this.files.delete(path)},lookupPath(path){if(!this.files.has(path))throw Error('Missing font '+path);return {bytes:this.files.get(path)}},open(path){return this.lookupPath(path)}};
onmessage=e=>{if(e.data.cmd!=='test')return;try{
 const read=path=>{const x=new XMLHttpRequest();x.open('GET','/game/Interface/AddOns/CatQuest335_ServerVoices/'+path,false);x.responseType='arraybuffer';x.send();return x};
 const f=[8,8,${quest>>>24},${quest>>>16&255},${quest>>>8&255},${quest&255},${kind==='COMPLETE'?2:1},1,0,12];f.push(f.reduce((a,b)=>a+b,0)%256);
 f.flatMap(b=>[b>>4,b&15]).forEach((v,p)=>read('prefetch/12/'+p+'/'+v.toString(16)+'.ogg'));
 const pathFor=alias=>['Interface','AddOns','CatQuest','r','12',alias+'.ttf'].join(String.fromCharCode(92));
 const probeFont=alias=>{const path=pathFor(alias);return e.data.mode==='libc'?FS.open(path,'r').bytes:e.data.mode==='stat'?FS.lookupPath(path).bytes:new Uint8Array(read('../CatQuest/r/12/'+alias+'.ttf').response)};
 const offsets=${JSON.stringify(font.glyph_offsets)},units=${font.units_per_em};
 const isReady=bytes=>{if(!bytes?.length)return false;const d=new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength);return offsets.some(o=>o+2<=bytes.length&&d.getUint16(o,false)>units)};
 let waiting;try{waiting=probeFont(1)}catch{waiting=null}
 if(!waiting?.length||isReady(waiting))throw Error('First signal alias must be a local zero-duration waiting font');
 const end=Date.now()+10000;let font;
 // Deliberately block incoming worker events, as the native game does.
 while(Date.now()<end){try{font=probeFont(2);if(isReady(font))break}catch{}}
 if(!font?.length||!isReady(font))throw Error('Shared ready font never arrived');
 if(FS.open('Fonts/FRIZQT__.TTF','r').bytes[0]!==1)throw Error('Regular game fonts were changed');
 const sound=read('ruRU/Sounds/q/${stem}.ogg');
 postMessage({before:waiting.length,font:Array.from(font),status:sound.status,audio:Array.from(new Uint8Array(sound.response))});
}catch(error){postMessage({error:String(error.stack)})}}`;
const server=createServer((req,res)=>{
 res.setHeader('Cross-Origin-Opener-Policy','same-origin');res.setHeader('Cross-Origin-Embedder-Policy','require-corp');
 if(req.url==='/play'){res.setHeader('Content-Type','text/html');res.end('<!doctype html><script src="/runtime.js"></script><script src="/loader.js"></script>');return}
 if(req.url==='/runtime.js'||req.url==='/loader.js'||req.url==='/native-worker.js'){res.setHeader('Content-Type','text/javascript');res.end(req.url==='/runtime.js'?runtime:req.url==='/loader.js'?loader:worker);return}
 if(req.url==='/audio'){res.setHeader('Content-Type','audio/ogg');res.end(audio);return}
 if(req.url==='/game-manifest.txt'){res.end('1\tData/test.MPQ\n');return}
 res.writeHead(404);res.end();
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));let browser;
try{
 browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});
 for(const mode of ['vfs','libc','stat']) {
 const page=await browser.newPage();const errors=[];page.on('pageerror',e=>errors.push(String(e)));
 await page.goto(`http://127.0.0.1:${server.address().port}/play`);
 const result=await page.evaluate(async({font,size,mode,quest,kind})=>{
  const events=[];const bridge=new BroadcastChannel('lh-catquest-voice-v1');
  // Page bridge only: no response is delivered to the blocked worker.
  window.addEventListener('message',async e=>{
   if(e.data?.kind!=='voice-fetch')return;
   const r=await fetch('/audio'),bytes=new Uint8Array(await r.arrayBuffer());
   let s='';for(const b of bytes)s+=String.fromCharCode(b);
   window.postMessage({channel:'lh-catquest-voice-v1',kind:'voice-response',id:e.data.id,status:200,contentType:'audio/ogg',body64:btoa(s)},location.origin);
  });
  bridge.onmessage=e=>events.push(e.data);
  const worker=new Worker('/native-worker.js',{name:'em-pthread'});
  const answer=new Promise((resolve,reject)=>{worker.onmessage=e=>resolve(e.data);worker.onerror=e=>reject(Error(e.message));setTimeout(()=>reject(Error('Worker timeout')),15000)});
  worker.postMessage({cmd:'test',mode});window.postMessage({channel:'lh-local-addons-v1',kind:'payload',payload:{revision:'audio',addons:[{folder:'CatQuest',files:{'CatQuest.toc':btoa('## Interface: 30300\nCore.lua'),'Core.lua':btoa('')}}],readinessFont:font,remoteTracks:{ruRU:[[quest,kind,size]]},remoteDemand:{locale:'ruRU',size:1572864,tracks:[]},sharedVoice:{header:new SharedArrayBuffer(513*16),audio:new SharedArrayBuffer(2*1024*1024*2),laneBytes:2*1024*1024,lanes:2,runId:'audio-test',extensionVersion:'test',addonVersion:'test'}}},location.origin);
  const result=await answer;if(result.error)return result;
  const loaded=await new FontFace('CQSignal',new Uint8Array(result.font)).load();document.fonts.add(loaded);
  const canvas=document.createElement('canvas'),c=canvas.getContext('2d');c.font='12px CQSignal';
  const texts=['M','MM','NM','AM','BM','CM','DM','A','B','C','D'];
  result.widths=Object.fromEntries(texts.map(ch=>[ch,c.measureText(ch).width]));
  result.inkWidths=Object.fromEntries(texts.map(ch=>[ch,c.measureText(ch).actualBoundingBoxRight]));
  const context=new AudioContext();const decoded=await context.decodeAudioData(new Uint8Array(result.audio).buffer);result.duration=decoded.duration;await context.close();
  result.events=events.filter(e=>e.kind==='probe').map(e=>e.event);
  return result;
 },{font,size:audio.length,mode,quest,kind});
 assert(!result.error,result.error);assert(result.before>0,'Waiting alias must be present before audio is ready');assert.equal(result.status,200);assert.deepEqual(Buffer.from(result.audio),audio);assert.equal(errors.length,0,errors.join('\n'));
 let duration;
 for(const widths of [result.widths,result.inkWidths]){
  const unit=(widths.NM-widths.MM)/9;
  duration=[...'ABCD'].reduce((n,c)=>n*10+Math.round((widths[c+'M']-widths.MM)/unit),0)/10;
  assert(Math.abs(duration-result.duration)<.11,JSON.stringify({duration,decoded:result.duration,widths}));
 }
 const oldDuration=[...'ABCD'].reduce((n,c)=>n*10+Math.round(result.inkWidths[c]/result.inkWidths.M)-1,0)/10;
 assert.equal(oldDuration,0,'Single-glyph ink measurements reproduce the original waiting bug');
 console.log(`Real q${quest} ${kind} (${mode} font reader): ${audio.length} bytes preserved; old glyph-ink duration ${oldDuration}s -> calibrated pair duration ${duration}s; native audio decode ${result.duration}s; blocked-worker handoff passed`);
 await page.close();
 }
}finally{if(browser)await browser.close();await new Promise(r=>server.close(r))}
