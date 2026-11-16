// Exercise the real overlay on a real Vorbis file, including large headers.
import vm from 'node:vm';
import {mkdtempSync,readFileSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import assert from 'node:assert/strict';

const folder=mkdtempSync(path.join(tmpdir(),'catquest-ogg-'));
try {
  const original=path.join(folder,'original.ogg');
  execFileSync('ffmpeg',['-v','error','-f','lavfi','-i','sine=frequency=440:sample_rate=24000:duration=1.2',
    '-c:a','libvorbis','-q:a','5',original]);
  const track=readFileSync(original),events=[],listeners=[];
  class Native {
    open(){} send(){} get status(){return 200}
    get response(){return track.buffer.slice(track.byteOffset,track.byteOffset+track.length)}
    getResponseHeader(){return 'audio/ogg'}
  }
  const context=vm.createContext({XMLHttpRequest:Native,URL,TextDecoder,TextEncoder,
    Uint8Array,DataView,atob,setTimeout:()=>1,clearTimeout:()=>{},
    BroadcastChannel:class {addEventListener(_,f){listeners.push(f)}postMessage(m){
      events.push(m);
      if(m.kind==='voice-fetch')queueMicrotask(()=>listeners.forEach(f=>f({data:{kind:'voice-response',id:m.id,status:200,contentType:'audio/ogg',body64:track.toString('base64')}})));
    }}});
  vm.runInContext(readFileSync(new URL('../lasthavens-addon-manager/runtime-core.js',import.meta.url),'utf8'),context);
  context.LHInstallOverlay({},'https://game.test','https://api.test','3.3.5a',{},
    {locale:'ruRU',size:1572864,tracks:[[11626,'DETAIL']]});
  const read=(suffix)=>{
    const x=new context.XMLHttpRequest();
    x.open('GET','https://game.test/'+suffix,false);x.responseType='arraybuffer';x.send();
    assert.equal(x.status,200);return Buffer.from(x.response);
  };
  const relative='Interface/AddOns/CatQuest335_ServerVoices/ruRU/Sounds/q/11626.ogg';
  const miss=new context.XMLHttpRequest();miss.open('GET','https://game.test/game/'+relative,false);miss.send();
  assert.equal(miss.status,404,'First read returns immediately while async fetch runs');
  for(let i=0;i<8;i++)await Promise.resolve();
  const padded=read('game/'+relative);assert.equal(padded.length,1572864);
  const pages=[];
  for(let at=0;at<padded.length;){
    assert.equal(padded.toString('ascii',at,at+4),'OggS');
    const lacing=padded.subarray(at+27,at+27+padded[at+26]);
    const end=at+27+lacing.length+lacing.reduce((a,b)=>a+b,0);
    pages.push({at,end,lacing,granule:padded.readBigInt64LE(at+6),flags:padded[at+5]});at=end;
  }
  const incomplete=pages.filter(p=>p.lacing.length && p.lacing.every(n=>n===255));
  assert(incomplete.length>10,'The fixture must exercise a multi-page padding packet');
  for(const p of incomplete)assert.equal(p.granule,-1n,
    'Ogg pages without a completed packet must carry granule -1, not zero');
  // A normal cache decoder can seek and fetch the file in 64 KiB blocks.
  const blocks=[];
  for(let index=0;index<padded.length/65536;index++)blocks.push(read(`blocks/${relative}/${padded.length}-${index}-64k.bin`));
  assert.deepEqual(Buffer.concat(blocks),padded);
  const target=path.join(folder,'padded.ogg');writeFileSync(target,padded);
  const decode=(file,decoder)=>execFileSync('ffmpeg',['-v','error','-c:a',decoder,'-i',file,'-f','s16le','-'],{maxBuffer:1024*1024});
  for(const decoder of ['vorbis','libvorbis'])assert.deepEqual(decode(target,decoder),decode(original,decoder),
    `${decoder}: changing the placeholder header must not change decoded PCM`);
  console.log('OGG placeholder: packet granules, real Vorbis, exact size, whole/block reads and unchanged PCM passed');
} finally {rmSync(folder,{recursive:true,force:true})}
