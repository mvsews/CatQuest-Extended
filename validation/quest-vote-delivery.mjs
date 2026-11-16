import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';

const source=readFileSync(new URL('../lasthavens-addon-manager/quest-ratings.js',import.meta.url),'utf8')
  .replace(/^import .*;$/m,'').replaceAll('export ','');
const store={telemetryOff:true,telemetry:{id:'must-not-send',token:'must-not-send'}};
const requests=[];
let offline=false,hold=null;
const storage={
  get:async(keys)=>Object.fromEntries((Array.isArray(keys)?keys:[keys]).map(key=>[key,structuredClone(store[key])])),
  set:async(values)=>{Object.assign(store,structuredClone(values));},
};
const server=async(url,options)=>{
  if(offline)throw new Error('offline');
  const body=JSON.parse(options.body);requests.push({url,body});
  if(url.endsWith('/quest-voters'))return {ok:true,status:200,json:async()=>({ok:true,token:'isolated-test-token-1234567890'})};
  if(hold){const wait=hold;hold=null;await wait;}
  return {ok:true,status:200,json:async()=>({ok:true})};
};
function runtime() {
  const context=vm.createContext({chrome:{storage:{local:storage}},crypto:{randomUUID},
    fetch:server,AbortController,setTimeout,clearTimeout,UPDATE_ORIGIN:'https://isolated.test'});
  vm.runInContext(source+'\nglobalThis.api={reportQuestVote,flushQuestVotes};',context);
  return context.api;
}
let api=runtime();
assert(await api.reportQuestVote({quest:9851,vote:1,locale:'ruRU'}));
await api.flushQuestVotes();
assert.equal(Object.keys(store.questVoteOutbox).length,0);
assert.equal(store.questVoteCache[9851].vote,1);
assert(store.questVoteIdentity.token);
assert(!requests.some(row=>JSON.stringify(row.body).includes('must-not-send')));
assert(!requests.some(row=>'guid' in row.body || 'realm' in row.body || 'name' in row.body));

// Explicit votes persist with telemetry off and survive worker restarts/offline.
offline=true;
await api.reportQuestVote({quest:9852,vote:-1,locale:'ruRU'});await api.flushQuestVotes();
assert.equal(Object.keys(store.questVoteOutbox).length,1);
api=runtime();offline=false;await api.flushQuestVotes();
assert.equal(Object.keys(store.questVoteOutbox).length,0);
assert.equal(requests.filter(row=>row.url.endsWith('/quest-voters')).length,1);

// A new choice while an old network request awaits acknowledgment must not
// be deleted by that old request's success.
let release;
hold=new Promise(resolve=>{release=resolve;});
await api.reportQuestVote({quest:9853,vote:1,locale:'ruRU'});
for(let i=0;i<20 && !requests.some(row=>row.body.quest===9853);i++)await new Promise(resolve=>setTimeout(resolve,0));
await api.reportQuestVote({quest:9853,vote:-1,locale:'ruRU'});
release();await api.flushQuestVotes();
assert.equal(store.questVoteCache[9853].vote,-1);
assert.equal(Object.keys(store.questVoteOutbox).length,0);
assert.deepEqual(requests.filter(row=>row.body.quest===9853).map(row=>row.body.vote),[1,-1]);
const count=requests.length;
assert.equal(await api.reportQuestVote({quest:0,vote:1}),false);
assert.equal(await api.reportQuestVote({quest:9851,vote:0}),false);
assert.equal(requests.length,count);
console.log('Quest vote delivery: explicit consent, anonymous identity, durable offline outbox, worker restart, changed-vote race and validation passed');

// The user's opt-out marker beats an old SavedVariables snapshot after F5.
const telemetry=readFileSync(new URL('../lasthavens-addon-manager/telemetry.js',import.meta.url),'utf8')
  .replace(/^import .*;$/gm,'').replaceAll('export ','');
const preferences=vm.createContext({chrome:{storage:{local:storage}},crypto:{randomUUID},
  fetch:server,UPDATE_ORIGIN:'https://isolated.test',readLibrary:async()=>({addons:[]})});
vm.runInContext(telemetry+'\nglobalThis.save=saveAddonSettings;',preferences);
await preferences.save({questRatings:false});
await preferences.save({questRatings:true},{fromSnapshot:true});
assert.equal(store.addonSettings.questRatings,false);
console.log('Quest rating preference: opt-out survives stale game snapshots with telemetry disabled');

const heroA={realm:'LastHavens',name:'Первый',guid:'0x000000000000002A'};
const heroB={realm:'LastHavens',name:'Второй',guid:'0x000000000000002B'};
store.telemetryOff=false;offline=true;
await api.reportQuestVote({quest:9986,vote:1,locale:'ruRU',character:heroA,event_id:'1234567890abcdef',submitted_at:Date.now()/1000});
await api.flushQuestVotes();
assert.equal(store.questVoteOutbox['3.3.5a|9986'].character.name,'Первый');
store.character=heroB;api=runtime();offline=false;await api.flushQuestVotes();
let delivered=requests.filter(r=>r.body.quest===9986).at(-1).body;
assert.equal(delivered.character.name,'Первый');assert.equal(delivered.share_character,true);
assert.equal(delivered.event_id,'1234567890abcdef');

// Opting out before retry sends the original action anonymously, even though
// it was captured while metrics were enabled. Opting in cannot deanonymize
// actions captured during opt-out.
offline=true;store.telemetryOff=false;
await api.reportQuestVote({quest:9987,vote:1,character:heroA});await api.flushQuestVotes();
store.telemetryOff=true;offline=false;await api.flushQuestVotes();
delivered=requests.filter(r=>r.body.quest===9987).at(-1).body;
assert.equal(delivered.share_character,false);assert.equal(delivered.character,null);
offline=true;await api.reportQuestVote({quest:9988,vote:1,character:heroA});await api.flushQuestVotes();
store.telemetryOff=false;offline=false;await api.flushQuestVotes();
assert.equal(requests.filter(r=>r.body.quest===9988).at(-1).body.character,null);
store.identityOff=true;
await api.reportQuestVote({quest:9989,vote:-1,character:heroA});await api.flushQuestVotes();
assert.equal(requests.filter(r=>r.body.quest===9989).at(-1).body.character,null);
console.log('Vote attribution: actor snapshot survives character changes/restarts; opt-out at capture or delivery remains anonymous');
