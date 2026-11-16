import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';

const source=readFileSync(new URL('../lasthavens-addon-manager/bridge.js',import.meta.url),'utf8');
const start=source.indexOf('  const decodeMessage =');
const end=source.indexOf('  const onCharacter =',start);
assert(start>0 && end>start);
const context=vm.createContext({TextDecoder});
vm.runInContext(`const WHO_NIBBLES=512;const VOICE_LOCALES=['ruRU'];
  const whoNibbles=new Map();
  const utf8=bytes=>new TextDecoder('utf-8',{fatal:true}).decode(new Uint8Array(bytes));
  ${source.slice(start,end)}
  globalThis.read=bytes=>{whoNibbles.set(1,bytes.flatMap(b=>[b>>4,b&15]));return decodeMessage(1)};`,context);
for(const [target,id] of [[1,9851],[2,9851],[3,0x1234abcd],[4,18411]]) {
  const bytes=[3,7,target,(id>>>24)&255,(id>>>16)&255,(id>>>8)&255,id&255,6,1];
  bytes.push(bytes.reduce((a,b)=>a+b,0)%256);
  const result=context.read(bytes);
  assert.equal(result.target,['quest','turnin','book','npc'][target-1]);
  assert.equal(result.id,target===3?'1234abcd':id);
  assert.equal(result.locale,'ruRU');
}
console.log('Feedback bridge: quest, completion, place and world-boss frames decode correctly');
for(const vote of [1,2]) {
  const bytes=[6,6,0,0,38,123,vote,1];
  bytes.push(bytes.reduce((a,b)=>a+b,0)%256);
  const result=context.read(bytes);
  assert.equal(result.kind,'quest-vote');assert.equal(result.quest,9851);
  assert.equal(result.vote,vote===1?1:-1);
}
console.log('Quest vote bridge: thumbs up/down frames preserve quest, direction and locale');
const actor=[...new TextEncoder().encode('Длинное имя сервера для проверки\tПервыйгерой\t'),0,0,0,0,0,0,0,42];
const extended=[6,18+actor.length,0,0,38,123,1,1,0x12,0x34,0x56,0x78,0x90,0xab,0xcd,0xef,0x6a,0xf5,0xa8,0x00,...actor];
extended.push(extended.reduce((a,b)=>a+b,0)%256);
const attributed=context.read(extended);
assert.equal(attributed.character.name,'Первыйгерой');assert.equal(attributed.character.guid,'0x000000000000002A');
assert.equal(attributed.event_id,'1234567890abcdef');assert(attributed.submitted_at>0);
console.log('Extended vote bridge: long Cyrillic realm/name, event nonce, GUID and submit time preserved');
const preference=[...new TextEncoder().encode('questRatings=0')];
const preferenceFrame=[5,preference.length,...preference];
preferenceFrame.push(preferenceFrame.reduce((a,b)=>a+b,0)%256);
assert.equal(context.read(preferenceFrame).settings.questRatings,false);
console.log('Quest rating preference survives the settings marker decoder');
