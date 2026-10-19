'use strict';

// Promise existing NPC gold before asking for goods. This state belongs to
// the same private ledger entry as the purse, never a character projection.
const WAIT=6*60*60*1000,MAX_GOLD=2147483647,MAX_HELD=100,MAX_COOL=1024;
const owns=(value,key)=>Object.prototype.hasOwnProperty.call(value,key);
const integer=(value,min,max=Number.MAX_SAFE_INTEGER)=>Number.isSafeInteger(value)&&value>=min&&value<=max;
const object=value=>value&&typeof value==='object'&&!Array.isArray(value);
const fields=(value,keys)=>object(value)&&Object.keys(value).length===keys.length&&keys.every(key=>owns(value,key));
const copy=value=>JSON.parse(JSON.stringify(value));
const job=id=>typeof id==='string'&&/^q-[a-z0-9-]{1,46}$/.test(id);
function owner(human) {
 if(!human||!integer(human.profileId,1,MAX_GOLD)||typeof human.desc!=='string')return '';
 const match=/^([0-9a-f]{1,6})(?::([^:/\\\x00-\x1f\x7f]+\.(?:esm|esp|esl)))?$/i.exec(human.desc);
 return match&&parseInt(match[1],16)>0?JSON.stringify([parseInt(match[1],16),(match[2]||'').toLowerCase(),human.profileId]):'';
}
function ownerString(value) {
 if(typeof value!=='string')return false;
 try {
  const row=JSON.parse(value);
  return Array.isArray(row)&&row.length===3&&integer(row[0],1,0xffffff)&&typeof row[1]==='string'&&
   (!row[1]||/^[^:/\\\x00-\x1f\x7f]+\.(?:esm|esp|esl)$/.test(row[1]))&&row[1]===row[1].toLowerCase()&&
   integer(row[2],1,MAX_GOLD)&&JSON.stringify(row)===value;
 }catch(error){return false;}
}
function key(human,id) {const who=owner(human);return who&&job(id)?JSON.stringify([who,id]):'';}
function keyParts(value) {
 try {const row=JSON.parse(value);return Array.isArray(row)&&row.length===2&&ownerString(row[0])&&job(row[1])&&
  JSON.stringify(row)===value?row:null;}catch(error){return null;}
}
function empty(){return {v:1,serial:0,held:{},cool:{}};}
function read(raw) {
 if(raw===undefined)return empty();
 function bad(){throw Error('Saved commission promises cannot be verified.');}
 if(!fields(raw,['v','serial','held','cool'])||raw.v!==1||!integer(raw.serial,0)||!object(raw.held)||!object(raw.cool)||
   Object.keys(raw.held).length>MAX_HELD||Object.keys(raw.cool).length+Object.keys(raw.held).length>MAX_COOL)bad();
 const tokens=new Set();
 for(const name of Object.keys(raw.held)) {
  const parts=keyParts(name),row=raw.held[name];
  if(!parts||!fields(row,['token','owner','job','hash','item','count','unit','gold','at'])||
    !integer(row.token,1,raw.serial)||tokens.has(row.token)||row.owner!==parts[0]||row.job!==parts[1]||
    typeof row.hash!=='string'||!/^[0-9a-f]{64}$/.test(row.hash)||
    !fields(row.item,['baseId','name'])||!integer(row.item.baseId,1,0xffffffff)||row.item.baseId===15||
    typeof row.item.name!=='string'||!row.item.name.trim()||row.item.name.length>160||/[\x00-\x1f\x7f]/.test(row.item.name)||
    !integer(row.count,1,100000)||!integer(row.unit,0,MAX_GOLD)||!integer(row.gold,0,MAX_GOLD)||
    row.gold!==row.count*row.unit||!integer(row.at,1)||owns(raw.cool,name))bad();
  tokens.add(row.token);
 }
 for(const name of Object.keys(raw.cool))if(!keyParts(name)||!integer(raw.cool[name],1))bad();
 return copy(raw);
}
function reserved(raw){return Object.values(read(raw).held).reduce((sum,row)=>sum+row.gold,0);}
function spendable(state) {
 const promised=reserved(state.commissions);
 if(!integer(state.purse,0,MAX_GOLD)||promised>state.purse)throw Error('Commission promises exceed the merchant purse.');
 return state.purse-promised;
}
function openCount(states,human) {
 const who=owner(human);if(!who)throw Error('Commission owner cannot be verified.');
 return states.reduce((sum,state)=>{if(state===null)return sum;spendable(state);return sum+Object.values(read(state.commissions).held).filter(row=>row.owner===who).length;},0);
}
function prepare(raw,at) {
 if(!integer(at,1))throw Error('Commission time cannot be verified.');
 const next=read(raw);
 for(const name of Object.keys(next.cool))if(at-next.cool[name]>=WAIT)delete next.cool[name];
 return next;
}
function reserve(raw,human,id,terms,at,purse) {
 const next=prepare(raw,at),name=key(human,id);
 if(!name)return {ok:false,why:'session'};
 if(!terms||!integer(terms.unit,0,MAX_GOLD)||!integer(terms.count,1,100000)||
   !integer(terms.unit*terms.count,0,MAX_GOLD))return {ok:false,why:'price'};
 if(owns(next.held,name))return {ok:false,why:'open'};
 if(owns(next.cool,name))return {ok:false,why:'cooldown'};
 if(Object.keys(next.held).length>=MAX_HELD||Object.keys(next.cool).length+Object.keys(next.held).length>=MAX_COOL)return {ok:false,why:'capacity'};
 if(next.serial===Number.MAX_SAFE_INTEGER)return {ok:false,why:'counter'};
 if(spendable({purse,commissions:next})<terms.unit*terms.count)return {ok:false,why:'purse'};
 const token=++next.serial;
 next.held[name]={token,owner:owner(human),job:id,hash:terms.hash,item:copy(terms.item),count:terms.count,
   unit:terms.unit,gold:terms.unit*terms.count,at};
 read(next);
 return {ok:true,next,token};
}
function close(raw,human,id,token,at,pay) {
 const next=prepare(raw,at),name=key(human,id),row=name&&next.held[name];
 if(!row||!integer(token,1)||row.token!==token)return {ok:false,why:'session'};
 if(pay&&Object.keys(next.cool).length>=MAX_COOL)return {ok:false,why:'capacity'};
 delete next.held[name];
 if(pay)next.cool[name]=at;
 return {ok:true,next,gold:pay?row.gold:0,terms:row};
}
module.exports={WAIT,MAX_HELD,MAX_COOL,empty,read,owner,key,reserved,spendable,openCount,reserve,
 cancel:(raw,human,id,token,at)=>close(raw,human,id,token,at,false),
 finish:(raw,human,id,token,at)=>close(raw,human,id,token,at,true)};
