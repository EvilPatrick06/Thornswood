'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const source=fs.readFileSync(path.join(__dirname,'../game/plugins/thornswood-emotes.js'),'utf8');
const serverAddress=JSON.parse(fs.readFileSync(path.join(__dirname,'../scripts/vps/vps.json'),'utf8')).address;
function fixture() {
  const handlers={},hooks=[],sent=[],labels=[],pins=[],nativeTasks=[];
  let drawn=true,accepted=true,focused=false,delay=0,waiting=false,inUpdate=false,resetInterrupts=false,ack=true,time=Date.now();
  class Clock extends Date { static now(){return time;} }
  function native(fn){if(!inUpdate)throw new Error('native outside update');return fn();}
  const actor={getFormID:()=>0x14,isWeaponDrawn:()=>drawn,sheatheWeapon:()=>{waiting=true;if(!delay)drawn=false;},getParentCell:()=>null};
  actor.getItemCount=()=>native(()=>1);
  const io={readFileSync(file){
    if(file.endsWith('skymp5-client-settings.txt'))return JSON.stringify({'server-ip':serverAddress});
    if(file.endsWith('thornswood-session.txt'))return String(Date.now());
    throw new Error('absent');
  },appendFileSync(){},writeFileSync(){}};
  const T={ready:true,isTyping:()=>false,hasFocus:()=>false,claimFocus(){},js(text){labels.push(text);return true;}};
  const sp={on(name,fn){(handlers[name]||(handlers[name]=[])).push(fn);},printConsole(){},
    Game:{getPlayer:()=>native(()=>actor),getFormFromFile:(id)=>native(()=>id===0x19bad4?null:{id})},Utility:{isInMenuMode:()=>native(()=>false)},browser:{isFocused:()=>focused},
    TESModPlatform:{setWeaponDrawnMode:(pc,mode)=>pins.push(mode)},
    hooks:{sendAnimationEvent:{add:hook=>hooks.push(hook)}},
    Debug:{notification(){},sendAnimationEvent(pc,event){nativeTasks.push(()=>{
      const ctx={selfId:pc.getFormID(),animEventName:event,animationSucceeded:accepted,storage:new Map()};
      hooks.forEach(h=>h.enter(ctx));sent.push(ctx.animEventName);
      if(resetInterrupts && event==='IdleForceDefaultState' && waiting){waiting=false; drawn=true;}
      if(ack)hooks.forEach(h=>h.leave(ctx));
    });}}};
  const ctx={skyrimPlatform:sp,Thornswood:T,require:()=>io,Date:Clock,JSON,Math,Number};
  vm.createContext(ctx);vm.runInContext(source,ctx);
  function emit(name,event){inUpdate=name==='update'||name==='buttonEvent';if(name==='update'&&waiting&&delay>0&&!--delay){drawn=false;waiting=false;}for(const fn of handlers[name]||[])fn(event);if(name==='update')while(nativeTasks.length)nativeTasks.shift()();inUpdate=false;}
  return {sent,pins,labels,emit,reject(){accepted=false;},
    focus(){focused=true;},delaySheathe(){delay=5;},interruptSheatheOnReset(){resetInterrupts=true;delay=5;},noAcknowledgement(){ack=false;},elapse(ms){time+=ms;},
    labelsOnly:()=>labels.filter(s=>s.includes('t:"emote"')),
    // The eighth slot (Drink) chosen on the wheel: G opens it, the page sends __slot 8.
    pick8(){emit('buttonEvent',{device:0,code:34,isDown:true,isUp:false,isRepeating:false,heldDuration:0});
      emit('browserMessage',{arguments:['thornswood-emote','__slot 8']});}};
}
const mouse=fixture();
mouse.emit('buttonEvent',{device:1,code:9,isDown:true,isUp:false});
mouse.emit('update');mouse.emit('update');
assert.equal(mouse.labelsOnly().length,0,'a mouse wheel event cannot select Drink');
assert.equal(mouse.sent.length,0,'mouse input cannot queue an emote');
const held=fixture();
held.emit('buttonEvent',{device:0,code:9,isDown:true,isUp:false,isRepeating:true,heldDuration:1});
assert.equal(held.labelsOnly().length,0,'held repeats cannot select a new emote');
held.emit('update');assert.equal(held.sent.length,0);
// With the wheel shut, 8 is Skyrim's favourites hotkey and plays no slot (Djinn, 6 Oct).
const shutKey=fixture();
shutKey.emit('buttonEvent',{device:0,code:9,isDown:true,isUp:false,isRepeating:false,heldDuration:0});
for(let i=0;i<4;i++)shutKey.emit('update');
assert.equal(shutKey.sent.length,0,'with the wheel shut, the number keys are the game\'s favourites hotkeys and play no emote');
assert.equal(shutKey.labelsOnly().length,0);
const explicit=fixture();
explicit.pick8();
assert.equal(explicit.labelsOnly().length,0,'the label waits for an accepted animation');
for(let i=0;i<4;i++)explicit.emit('update');
assert.ok(explicit.pins.includes(-1),'clear the persistent weapon stance override');
assert.ok(explicit.sent.includes('idleDrinkingStandingStart'),'a drawn stance must not loop forever on Stop');
assert.equal(explicit.labelsOnly().length,1,'one accepted explicit selection produces one label');
const rejected=fixture();rejected.reject();
rejected.pick8();
for(let i=0;i<4;i++)rejected.emit('update');
assert(rejected.sent.includes('idleDrinkingStandingStart'),'exercise rejection of the requested idle itself');
assert.equal(rejected.labelsOnly().length,0,'a rejected animation cannot claim the emote happened');
const panel=fixture();panel.focus();
panel.emit('buttonEvent',{device:0,code:9,isDown:true,isUp:false});panel.emit('update');
assert.equal(panel.sent.length,0,'numbers typed into another panel cannot select emotes');
const slow=fixture();slow.delaySheathe();
slow.pick8();
slow.emit('update');slow.emit('update');
assert.equal(slow.labelsOnly().length,0,'wait until the sheathing animation has finished');
for(let i=0;i<6;i++)slow.emit('update');
assert.equal(slow.labelsOnly().length,1,'a delayed sheathe still plays the chosen gesture once');
const stopMouse=fixture();stopMouse.emit('buttonEvent',{device:1,code:49,isDown:true,isUp:false});stopMouse.emit('update');
assert.equal(stopMouse.sent.length,0,'Stop also belongs only to the keyboard');
const wheel=fixture();wheel.emit('buttonEvent',{device:0,code:34,isDown:true,isUp:false});
wheel.emit('browserMessage',{arguments:['thornswood-emote','__play Lute']});
for(let i=0;i<4;i++)wheel.emit('update');
assert.ok(wheel.sent.includes('IdleLuteStart'),'owned instruments selected on the wheel are checked inside update');
assert.equal(wheel.labelsOnly().length,1);
wheel.emit('buttonEvent',{device:0,code:34,isDown:true,isUp:false});
wheel.emit('browserMessage',{arguments:['thornswood-emote','__stand']});
const previous=wheel.sent.length;wheel.emit('update');wheel.emit('update');
assert.equal(wheel.sent[previous],'IdleForceDefaultState','wheel Stop also reaches the update queue');
const interrupted=fixture();interrupted.interruptSheatheOnReset();
interrupted.pick8();
for(let i=0;i<10;i++)interrupted.emit('update');
assert.equal(interrupted.labelsOnly().length,1,'resetting the graph must not interrupt the requested sheathe');
const unacknowledged=fixture();unacknowledged.noAcknowledgement();
unacknowledged.pick8();
for(let i=0;i<4;i++)unacknowledged.emit('update');
unacknowledged.elapse(2100);unacknowledged.emit('update');
assert.equal(unacknowledged.labelsOnly().length,0,'an unacknowledged gesture cannot produce a label');
console.log('PASS keyboard-only emotes, repeat refusal, staged sheathing and accepted-animation labels');
