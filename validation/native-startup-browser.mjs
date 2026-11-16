import {createServer} from 'node:http';
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {chromium} from '../.tmp/browser-tests/node_modules/playwright-core/index.mjs';
const original=readFileSync(new URL('../.tmp/borean-alliance/Wow-public.js',import.meta.url),'utf8');
const native=original.slice(original.indexOf('function WebVfsFetchManifest'),original.indexOf('function WebVfsStoreOpen'))
 .replace('catch(e){return 0}', 'catch(e){return {caught:String(e.stack)}}');
const manifest='2443545900\tData/common-2.MPQ\n2239593705\tData/common.MPQ\n100\tData/ruRU/locale-ruRU.MPQ\n';
const font={...JSON.parse(readFileSync(new URL('../lasthavens-addon-manager/vendor/catquest-ready.json',import.meta.url))),body64:readFileSync(new URL('../lasthavens-addon-manager/vendor/catquest-ready.ttf',import.meta.url)).toString('base64')};
const worker=`var HEAPU8=new Uint8Array(131072);function growMemViews(){}function UTF8ToString(p){return p}function stringToNewUTF8(s){return s}var wasmImports;function assignWasmImports(){wasmImports={WebVfsStoreIo(){return 0}}}${native};onmessage=e=>{if(e.data.cmd!=='test')return;try{assignWasmImports();const text=WebVfsFetchManifest();const block=WebVfsFetchBlock('Data/common-2.MPQ',2443545900,0,64,65536,0);const range=WebVfsFetchRange('Data/common.MPQ',0,128,65536);postMessage({text,block,range,first:HEAPU8[0],rangeFirst:HEAPU8[65536]})}catch(error){postMessage({error:String(error.stack)})}}`;
const server=createServer((req,res)=>{
 res.setHeader('Cross-Origin-Opener-Policy','same-origin');res.setHeader('Cross-Origin-Embedder-Policy','require-corp');
 if(req.url==='/play'){res.setHeader('Content-Type','text/html');res.end('<!doctype html><script src="/runtime.js"></script><script src="/loader.js"></script>');return}
 if(req.url==='/runtime.js'||req.url==='/loader.js'){res.setHeader('Content-Type','text/javascript');res.end(readFileSync(new URL('../lasthavens-addon-manager/'+(req.url==='/runtime.js'?'runtime-core.js':'loader.js'),import.meta.url)));return}
 if(req.url==='/native-worker.js'){res.setHeader('Content-Type','text/javascript');res.end(worker);return}
 if(req.url==='/game-manifest.txt'){res.end(manifest);return}
 if(req.url.startsWith('/blocks/Data/')||req.url.startsWith('/game/Data/')){const n=req.headers.range?128:65536;res.setHeader('Content-Type','application/octet-stream');res.end(Buffer.alloc(n,122));return}
 res.writeHead(404);res.end();
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
let browser;
try{
 browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});
 for(const enabled of [0,1,2]){
  const page=await browser.newPage();const errors=[];page.on('pageerror',e=>errors.push(String(e)));
  await page.goto(`http://127.0.0.1:${server.address().port}/play`);
  const result=await page.evaluate(async({enabled,font})=>{
   const payload={revision:'test',addons:enabled?[{folder:'CatQuest',files:{'CatQuest.toc':btoa('## Interface: 30300\nCore.lua\n'),'Core.lua':btoa('local n=...')}}]:[],
    readinessFont:enabled===2?font:null,remoteTracks:enabled===2?{ruRU:[[11451,'DETAIL',200]]}:{},remoteDemand:enabled===2?{locale:'ruRU',size:1572864,tracks:[[11452,'DETAIL']]}:null};
   const worker=new Worker('/native-worker.js',{name:'em-pthread'});
   const answer=new Promise((resolve,reject)=>{worker.onmessage=e=>resolve(e.data);worker.onerror=e=>reject(Error(e.message));setTimeout(()=>reject(Error('Worker bootstrap timed out')),15000)});
   worker.postMessage({cmd:'test'});window.postMessage({channel:'lh-local-addons-v1',kind:'payload',payload},location.origin);
   return await answer;
  },{enabled,font});
  assert.equal(errors.length,0,errors.join('\n'));assert(!result.error,result.error);assert.equal(result.block,65536);assert.equal(result.range,128);assert.equal(result.first,122);assert.equal(result.rangeFirst,122);
  if(enabled){assert.equal(typeof result.text,'string',JSON.stringify(result));assert(result.text.startsWith(manifest));assert(result.text.includes('Interface/AddOns/CatQuest/Core.lua'));assert.equal(result.text.includes('/prefetch/512/21/f.ogg'),enabled===2)}else assert.equal(result.text,manifest);
  console.log(`Chrome native VFS + real loader (${['all addons disabled','local addon only','CatQuest with server voices'][enabled]}): manifest ${result.text.length} chars; base MPQ block/range unchanged`);
  await page.close();
 }
}finally{if(browser)await browser.close();await new Promise(r=>server.close(r))}
