'use strict';
// Local browser fixture for the actual CEF trader panel. No game/server writes.
const http=require('node:http'),fs=require('node:fs'),path=require('node:path');
const base={open:true,transfer:true,trader:'Guild trader',place:'Whiterun',purse:250,
  offers:[{name:'Iron Ingot',buy:3,sell:5,stock:4}],supply:[],quests:[
    {id:'ebony',name:'The ebony',who:'Miner, master',ask:4,holds:12,hours:24,state:'available',drawn:0,
      gems:[],locations:'Raven Rock Mine',canTake:true,canReturn:false,canAbandon:false},
    {id:'gem',name:'A gem',who:'Miner, master',ask:2,holds:6,hours:24,state:'available',drawn:0,
      gems:['Ruby','Sapphire','Emerald','Amethyst'],locations:{Ruby:'White Ridge Sanctum',Sapphire:'Highpoint Tower',Emerald:'Kolbjorn Barrow',Amethyst:'Highpoint Tower'},
      canTake:true,canReturn:false,canAbandon:false},
    {id:'stalhrim',name:'The stalhrim',who:'Miner, master',ask:3,holds:8,hours:24,state:'locked',drawn:0,
      gems:[],locations:'Kolbjorn Barrow',canTake:false,canReturn:false,canAbandon:false},
    {id:'heartstone',name:'The heart stone',who:'Miner, master',ask:3,holds:8,hours:24,state:'cooldown',drawn:0,waitMinutes:80,
      gems:[],locations:'Coldcinder Cave',canTake:false,canReturn:false,canAbandon:false}
  ]};
const panel=path.join(__dirname,'../../game/ui/thornswood-merchant.js');
http.createServer((req,res)=>{
  if(req.url==='/merchant.js'){res.setHeader('Content-Type','text/javascript');res.end(fs.readFileSync(panel));return;}
  const data=JSON.parse(JSON.stringify(base));
  if(new URL(req.url,'http://localhost').searchParams.get('scenario')==='open') {
    Object.assign(data.quests[0],{state:'open',drawn:6,canTake:false,canReturn:true,canAbandon:true});
    Object.assign(data.quests[1],{state:'open',drawn:1,gem:'Ruby',canTake:false,canReturn:false,canAbandon:true});
  }
  res.setHeader('Content-Type','text/html');
  res.end('<!doctype html><html lang="en"><meta charset="utf-8"><title>Merchant panel fixture</title>'+ 
    '<body style="margin:0;background:#302820"><output id="commands" style="position:fixed;top:0;left:0;color:white;z-index:2147483500"></output>'+ 
    '<script>window.skyrimPlatform={sendMessage:function(){}};window.thornswoodNet={say:function(line){document.getElementById("commands").textContent=line;}};</script>'+ 
    '<script src="/merchant.js"></script><script>window.thornswoodMerchant.setData('+JSON.stringify(data)+');</script></body></html>');
}).listen(0,'127.0.0.1',function(){console.log('Merchant fixture http://127.0.0.1:'+this.address().port);});
