'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const gm=fs.readFileSync(path.join(__dirname,'../game/gamemode.js'),'utf8');
const start=gm.indexOf('function wearScript() {'),end=gm.indexOf('\n}',start)+2;
const script=new Function(gm.slice(start,end)+'; return wearScript();')();
function fixture(){
  let now=1000,loaded=false,menu=false,race=1;const items=new Map(),worn=new Set(),equips=[];
  const pc={is3DLoaded:()=>loaded,getItemCount:f=>items.get(f.id)||0,isEquipped:f=>worn.has(f.id),
    getRace:()=>({getFormID:()=>race}),
    equipItem(f){equips.push(f.id);worn.add(f.id);},queueNiNodeUpdate(){}};
  const ctx={value:{ids:[0x1be1a,0x1be1b],at:1000},state:{},sp:{Game:{getPlayer:()=>pc,getFormEx:id=>({id})},
    Form:{from:f=>f},Actor:{from:f=>f},Ui:{isMenuOpen:()=>menu}}};
  const sandbox={ctx,Date:{now:()=>now}};vm.createContext(sandbox);
  return{ctx,equips,worn,items,tick(){now+=250;vm.runInContext(script,sandbox);},load(){loaded=true;},menu(value){menu=value;},race(value){race=value;worn.clear();}};
}
const delayed=fixture();delayed.tick();
assert.equal(delayed.ctx.state.thornswoodWearAt,undefined,'do not consume the equip request before the body and inventory arrive');
delayed.load();delayed.items.set(0x1be1a,1);delayed.tick();
assert.deepEqual(delayed.equips,[0x1be1a],'equip only the requested item that has arrived');
delayed.items.set(0x1be1b,1);delayed.tick();
assert.deepEqual(delayed.equips,[0x1be1a,0x1be1b],'late boots are also equipped automatically');
assert.equal(delayed.ctx.state.thornswoodWearAt,1000,'consume the request only after both pieces are equipped');
delayed.worn.clear();delayed.tick();
assert.equal(delayed.equips.length,2,'a completed request must respect later deliberate unequipping');
const raceMenu=fixture();raceMenu.load();raceMenu.menu(true);
raceMenu.items.set(0x1be1a,1);raceMenu.items.set(0x1be1b,1);raceMenu.tick();
raceMenu.ctx.value.creation=true;raceMenu.tick();
assert.equal(raceMenu.equips.length,2,'the outfit must be worn while the face menu is open');
raceMenu.race(2);raceMenu.tick();
assert.equal(raceMenu.equips.length,4,'a race change must automatically put the same owned clothes back on');
const expired=fixture();for(let i=0;i<85;i++)expired.tick();expired.load();expired.items.set(0x1be1a,1);expired.tick();
assert.equal(expired.equips.length,0,'a stale request cannot dress somebody later');
const appearanceStart=gm.indexOf('function beginAppearance(actorId) {'),appearanceEnd=gm.indexOf('\n}',appearanceStart)+2;
const actions=[];
let savedStage;
const begin=new Function('mp','faceMark','firstSeen','HALL','setChargen','log','tellOnce','sendToHall','giveShift','chargenOf',
  gm.slice(appearanceStart,appearanceEnd)+';return beginAppearance;')(
  {get:()=>null},()=>'',new Map(),{desc:'hall'},(id,state)=>{savedStage=state;actions.push('stage');},()=>{},()=>{},()=>false,()=>actions.push('clothes'),()=>savedStage);
begin(1);assert.deepEqual(actions,['stage','clothes'],'persist the new creation stage, then dress before the face is chosen');
console.log('PASS delayed starting clothes, race-menu deferral, single equip and stale request refusal');
