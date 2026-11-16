import {createServer} from 'node:http';
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {chromium} from '../.tmp/browser-tests/node_modules/playwright-core/index.mjs';
const server=createServer((req,res)=>{res.setHeader('Content-Type','text/html');res.end('<!doctype html><body><canvas id="canvas"></canvas></body>')});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
let browser;
try {
 browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});
 for(const type of ['prefetch-sent','fetch-start']) {
  const page=await browser.newPage({locale:'ru-RU'}),errors=[];page.on('pageerror',e=>errors.push(String(e)));
  await page.goto(`http://127.0.0.1:${server.address().port}/play`);
  await page.evaluate(()=>{
   globalThis.statusReplies=[];
   globalThis.chrome={storage:{local:{get:async()=>({library:{revision:'test',addons:[]},telemetryOff:true,panelPosition:{left:100000,top:100000}}),set:async()=>{},remove:async()=>{}},onChanged:{addListener(){}}},runtime:{getManifest:()=>({version:'0.6.58'}),getURL:p=>'/'+p,sendMessage:async m=>{
    if(m.kind==='voice-status')return new Promise(r=>statusReplies.push(r));
    if(m.kind==='voice-capacity')return new Promise(()=>{});
    return {ok:true};
   }}};
   globalThis.testVoiceChannel=new BroadcastChannel('lh-catquest-voice-v1');
   globalThis.sendVoiceProbe=event=>testVoiceChannel.postMessage({kind:'probe',event});
  });
  await page.addScriptTag({content:readFileSync(new URL('../lasthavens-addon-manager/bridge.js',import.meta.url),'utf8')});
  await page.evaluate(type=>sendVoiceProbe({type,quest:12034,kind:'DETAIL',locale:'ruRU',slot:7,ok:false}),type);
  const panel=page.locator('#catquest-voice-panel');await panel.waitFor({state:'visible',timeout:2000});
  assert((await panel.innerText()).includes('#12034'),'Pending status cannot delay initial display');
  const box=await panel.boundingBox();assert(box.x>=0&&box.y>=0&&box.x+box.width<=1281&&box.y+box.height<=721,'Saved off-screen position is clamped');
  await page.evaluate(()=>sendVoiceProbe({type:'fetch-done',quest:12034,kind:'DETAIL',locale:'ruRU',ok:true}));
  await page.waitForFunction(()=>document.querySelector('#catquest-voice-panel')?.textContent.includes('ожидаю запуска'));
  await page.evaluate(()=>statusReplies.forEach(reply=>reply({status:'queued',position:9,eta_seconds:50})));
  assert((await panel.innerText()).includes('ожидаю запуска'),'Old status cannot overwrite the downloaded state');
  await page.evaluate(()=>sendVoiceProbe({type:'read',quest:12034,kind:'DETAIL',locale:'ruRU',cached:true}));
  await page.waitForFunction(()=>document.querySelector('#catquest-voice-panel')?.textContent.includes('файл передан игре'));
  await page.evaluate(()=>document.querySelector('#catquest-voice-panel').remove());
  await page.evaluate(()=>sendVoiceProbe({type:'prefetch-sent',quest:12035,kind:'COMPLETE',locale:'ruRU',slot:8}));
  await panel.waitFor({state:'visible'});assert((await panel.innerText()).includes('#12035'));
  await panel.locator('button').click();await panel.waitFor({state:'hidden'});
  await page.evaluate(()=>sendVoiceProbe({type:'prefetch-sent',quest:12036,kind:'DETAIL',locale:'ruRU',slot:9}));
  await panel.waitFor({state:'visible'});assert((await panel.innerText()).includes('#12036'));
  assert.equal(errors.length,0,errors.join('\n'));
  console.log(`Voice panel (${type}): immediate display with stalled server, honest loading/read states, stale response, close/reopen and reattach passed`);
  await page.close();
 }
} finally {if(browser)await browser.close();await new Promise(r=>server.close(r))}
