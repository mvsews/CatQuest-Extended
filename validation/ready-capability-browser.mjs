import {createServer} from 'node:http';
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {chromium} from '../.tmp/browser-tests/node_modules/playwright-core/index.mjs';
const server=createServer((req,res)=>{
 if(req.url?.startsWith('/vendor/catquest-ready.')){
  const path=req.url.slice(1);
  res.setHeader('Content-Type',path.endsWith('.json')?'application/json':'font/ttf');
  res.end(readFileSync(new URL('../lasthavens-addon-manager/'+path,import.meta.url)));return;
 }
 res.setHeader('Content-Type','text/html');res.end('<!doctype html><body></body>');
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));let browser;
try{
 browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});
 const page=await browser.newPage(),errors=[];page.on('pageerror',e=>errors.push(String(e)));
 await page.goto(`http://127.0.0.1:${server.address().port}/play`);
 await page.evaluate(()=>{
  addEventListener('message',e=>{if(e.data?.kind==='payload')globalThis.cqPayload=e.data.payload});
  globalThis.chrome={storage:{local:{get:async()=>({telemetryOff:true,voiceLocale:'ruRU',library:{revision:'test',addons:[{
   folder:'CatQuest',enabled:true,version:'0.10.94',files:{'CatQuest.toc':btoa('## Interface: 30300\nCore.lua'),'Core.lua':btoa('')}}]}}),set:async()=>{}},onChanged:{addListener(){}}},
   runtime:{getManifest:()=>({version:'0.6.60'}),getURL:p=>'/'+p,sendMessage:async m=>{
    if(m.kind==='voice-index')return {ok:true,tracks:{ruRU:[[11960,'DETAIL',287002]]},placeholderSize:1572864,demand:[]};
    return {ok:true};
   }}};
 });
 await page.addScriptTag({content:readFileSync(new URL('../lasthavens-addon-manager/bridge.js',import.meta.url),'utf8')});
 await page.waitForFunction(()=>globalThis.cqPayload?.addons?.[0]?.files?.['Bridge.lua']);
 const payload=await page.evaluate(()=>cqPayload);
 const lua=Buffer.from(payload.addons[0].files['Bridge.lua'],'base64').toString('utf8');
 assert(lua.includes('readyMetrics = 2'));assert(lua.includes('waitingFont = 1'));assert(lua.includes('fontReady = 1'));
 assert.equal(payload.readinessFont.metrics_version,2);assert.equal(payload.extensionVersion,'0.6.60');
 assert.equal(payload.addonVersion,'0.10.94');assert.equal(errors.length,0,errors.join('\n'));
 console.log('Real bridge: validated v2 font metadata is advertised as readyMetrics=2 in injected Lua');
}finally{if(browser)await browser.close();await new Promise(r=>server.close(r))}
