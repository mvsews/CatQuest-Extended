import vm from 'node:vm';
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdtempSync,rmSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import path from 'node:path';
import {tmpdir} from 'node:os';
const temp=mkdtempSync(path.join(tmpdir(),'catquest-ready-'));
try {
  const original=path.join(temp,'source.ogg');
  execFileSync('ffmpeg',['-v','error','-f','lavfi','-i','sine=frequency=440:sample_rate=24000:duration=4.25','-c:a','libvorbis',original]);
  const audio=readFileSync(original),events=[];
  let now=1000000,status=202,requests=0;
  class Clock extends Date {static now(){return now}}
  class Native {
    open(_,url){this.url=url} send(){requests++}
    get status(){return status}get response(){return audio.buffer.slice(audio.byteOffset,audio.byteOffset+audio.length)}
    getResponseHeader(){return status===200?'audio/ogg':'application/json'}
  }
  const font={...JSON.parse(readFileSync(new URL('../lasthavens-addon-manager/vendor/catquest-ready.json',import.meta.url),'utf8')),
    body64:readFileSync(new URL('../lasthavens-addon-manager/vendor/catquest-ready.ttf',import.meta.url)).toString('base64')};
  const ctx=vm.createContext({XMLHttpRequest:Native,URL,TextDecoder,TextEncoder,Uint8Array,DataView,atob,Date:Clock,
    setTimeout:()=>1,clearTimeout:()=>{},BroadcastChannel:class {addEventListener(){}postMessage(m){events.push(m)}}});
  vm.runInContext(readFileSync(new URL('../lasthavens-addon-manager/runtime-core.js',import.meta.url),'utf8'),ctx);
  ctx.LHInstallOverlay({},'https://game.test','https://api.test','3.3.5a',{},
    {locale:'ruRU',size:1572864,tracks:[[11710,'DETAIL'],[11710,'COMPLETE']]},[],null,'',font);
  function read(p){const x=new ctx.XMLHttpRequest();x.open('GET','https://game.test/game/Interface/AddOns/CatQuest335_ServerVoices/'+p,false);x.responseType='arraybuffer';x.send();return x}
  assert.equal(read('ready/ruRU/q/11710_DETAIL/1.ttf').status,404,'202 is not playback readiness');
  assert.equal(requests,1);
  now+=11000;status=429;
  assert.equal(read('ready/poll/1.ttf').status,404,'429 must never become a ready font or audio');
  now+=11000;status=200;
  const answer=read('ready/poll/2.ttf');assert.equal(answer.status,200);
  assert.equal(answer.getResponseHeader('Content-Type'),'font/ttf');
  const bytes=Buffer.from(answer.response);assert.equal(bytes.length,font.bytes);
  const block=read(`ready/poll/2.ttf/${font.bytes}-0-64k.bin`);
  assert.equal(block.status,200,'Readiness block paths must stay inside the virtual font route');
  assert.equal(Buffer.from(block.response).length,font.bytes);
  let checksum=0;for(let at=0;at<bytes.length;at+=4)checksum=(checksum+bytes.readUInt32BE(at))>>>0;
  assert.equal(checksum,0xb1b0afba,'Patched font must retain a valid global TrueType checksum');
  const f=path.join(temp,'ready.ttf');writeFileSync(f,bytes);
  const measured=JSON.parse(execFileSync('python',['-c',
    'import json,sys;from PIL import ImageFont;from fontTools.ttLib import TTFont;t=TTFont(sys.argv[1],checkChecksums=2);f=ImageFont.truetype(sys.argv[1],12);print(json.dumps({c:f.getlength(c) for c in "ABCDM"}))',f],{encoding:'utf8'}));
  const digits='ABCD'.split('').map(c=>Math.round(measured[c]/measured.M)-1);
  assert.equal(digits.reduce((n,d)=>n*10+d,0)/10,4.3,'Lua receives rounded-up actual Ogg duration through real font metrics');
  const before=requests;
  const played=read('ruRU/Sounds/q/11710.ogg');assert.equal(played.status,200);
  assert.equal(Buffer.from(played.response).toString('ascii',0,4),'OggS');
  assert.equal(requests,before,'Audio is warmed by the acknowledgement; playback must not start another request');
  assert.equal(events.filter(e=>e.kind==='poll-pick').length,0,'Readiness checking itself must not play anything');
  console.log('Readiness font: 202/429 wait, 200 acknowledgement, valid TTF, actual duration and warmed single playback passed');
} finally {rmSync(temp,{recursive:true,force:true})}
