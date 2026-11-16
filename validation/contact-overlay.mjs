// Run the complete page/worker overlay, including manifest and virtual XHR.
import vm from 'node:vm';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const source=readFileSync(new URL('../lasthavens-addon-manager/runtime-core.js',import.meta.url),'utf8');
const markers=JSON.parse(readFileSync(new URL('../.tmp/contact-markers.json',import.meta.url),'utf8'));
for(const mode of ['page','worker']){
  const emitted=[],timers=new Map();let serial=0;
  class NativeXHR {
    open(){}send(){}addEventListener(){}setRequestHeader(){}getResponseHeader(){return null}
    get status(){return 200}get readyState(){return 4}get responseText(){return '# original manifest'}
  }
  class Channel {addEventListener(){}postMessage(m){emitted.push(m)}}
  const ctx=vm.createContext({XMLHttpRequest:NativeXHR,URL,TextDecoder,TextEncoder,Uint8Array,atob,
    setTimeout:fn=>{timers.set(++serial,fn);return serial},clearTimeout:id=>timers.delete(id),
    location:{origin:'https://lasthavens.com'},BroadcastChannel:Channel,
    postMessage:m=>emitted.push(m),addEventListener:()=>{}});
  if(mode==='page')vm.runInContext('window=globalThis',ctx);
  vm.runInContext(source,ctx);
const started=performance.now();ctx.LHInstallOverlay({},'https://lasthavens.com','https://isolated.test','3.3.5a',{},null,[],{locale:'ruRU',size:1572864});
  const elapsed=performance.now()-started;
  let xhr=new ctx.XMLHttpRequest();xhr.open('GET','https://lasthavens.com/game-manifest.txt',false);xhr.send();
  assert.equal(xhr.status,200);
  assert(xhr.responseText.includes('/contact/1/0/0.ogg'));
  assert(xhr.responseText.includes('/contact/80/143/f.ogg'));
  for(const path of markers){
    xhr=new ctx.XMLHttpRequest();xhr.open('GET','https://lasthavens.com/game/'+path.replaceAll('\\','/'),false);xhr.send();
    assert.equal(xhr.status,200);assert.equal(xhr.getResponseHeader('content-type'),'audio/ogg');
  }
  // No worker timers run: the real game can keep that event loop blocked.
  const parts=emitted.filter(m=>m.kind==='contact-part');assert(parts.length>=69);
  assert.equal(parts.length,parts[0].total);
  assert.equal(parts[0].bytes.length,58);
  assert.equal(emitted.filter(m=>m.kind==='gossip-text'||m.kind==='voice-request').length,0);
  console.log(`Contact overlay (${mode}): ${markers.length} reads, ${parts.length} frames delivered without timers; build ${Math.round(elapsed)}ms`);
}
