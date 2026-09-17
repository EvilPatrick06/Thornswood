<#
  Check-Site.ps1

  Asks the site, on the VPS, whether everything it depends on is actually
  answering. Reads nothing secret back and prints no secrets.

      .\Check-Site.ps1

  Run it when somebody says they cannot get in. It tells you in ten seconds
  which of the four possible reasons it is, rather than guessing from what the
  person in front of you can see.
#>
[CmdletBinding()]
param(
  [string]$Vps  = '192.135.112.23',
  [string]$User = 'Administrator',
  [string]$Root = 'C:/Thornswood-Docs',
  # Check one person: their Discord id. Right click them, Copy User ID.
  [string]$Who,
  [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$ssh = @('-o','BatchMode=yes','-o','StrictHostKeyChecking=no')
$rootWin = $Root.Replace('/','\')

function Remote($script) {
  $e = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
  & ssh @ssh "$User@$Vps" "powershell -NoProfile -EncodedCommand $e" 2>&1
}

if ($Who -and $Who -notmatch '^[0-9]{17,20}$') {
  Write-Host ''
  Write-Host "  -Who has to be a Discord id: 17 to 20 digits. You gave: $Who" -ForegroundColor Red
  exit 1
}

Write-Host ''
Write-Host '  THORNSWOOD  -  is the site actually working' -ForegroundColor White

# All of this runs up there in node, because node is what the site uses and a
# thing that works in PowerShell but not in node is not an answer.
$js = @'
const https=require('https'),fs=require('fs');
const cfg=JSON.parse(fs.readFileSync('ROOTWIN\\config.json','utf8').replace(/^\uFEFF/,''));
const who=process.argv[2]||'';
const get=(p)=>new Promise(r=>{
  const q=https.get({hostname:'discord.com',path:'/api/v10'+p,
    headers:{Authorization:'Bot '+cfg.discord.botToken}},(s)=>{
    let o='';s.on('data',d=>o+=d);
    s.on('end',()=>{let b=null;try{b=JSON.parse(o)}catch(e){}r({c:s.statusCode,b})});
  });
  q.setTimeout(10000,()=>{try{q.destroy()}catch(e){}});
  q.on('error',e=>r({c:0,b:null,e:e.message}));
});
// A bot token is three parts with dots between them and the first part is the
// application id in base64. A client secret is 32 characters with no dots. The
// two get pasted into each other's box, and afterwards Discord only ever says
// 401, which does not tell you which one is wrong. This does. It prints no
// secret, only a length and an application id.
const appIdIn=(v)=>{
  const p=String(v||'').split('.');
  if(p.length!==3)return '';
  let id='';
  try{id=Buffer.from(p[0].replace(/-/g,'+').replace(/_/g,'/'),'base64').toString('utf8')}catch(e){}
  return /^[0-9]{17,20}$/.test(id)?id:'';
};
const secretLooks=(v)=>{
  if(!v)return 'MISSING';
  if(appIdIn(v))return 'THIS IS A BOT TOKEN, NOT A CLIENT SECRET. Sign in is broken.';
  if(String(v).length<25||String(v).length>45)
    return 'set, but it is '+String(v).length+' characters and a client secret is 32';
  return 'set';
};
const tokenLooks=(v,cid)=>{
  if(!v)return 'MISSING';
  const a=appIdIn(v);
  if(!a)return 'NOT A BOT TOKEN. It is '+String(v).length+' characters in '+
    String(v).split('.').length+' part(s); a bot token is 3 parts.';
  if(cid&&a!==cid)return 'set, but it belongs to application '+a+', NOT '+cid;
  return 'set, and it belongs to this application';
};
(async()=>{
  console.log('client id     ' + (cfg.discord.clientId||'MISSING'));
  console.log('client secret ' + secretLooks(cfg.discord.clientSecret));
  console.log('bot token     ' + tokenLooks(cfg.discord.botToken, cfg.discord.clientId));
  console.log('guild id      ' + (cfg.discord.guildId||'MISSING'));
  console.log('invite        ' + (cfg.discord.invite||'not set'));
  console.log('patreon       ' + (cfg.patreon||'not set'));
  console.log('admin ids     ' + (cfg.admins||[]).join(', '));
  console.log('lets into the game: ' + ((cfg.access&&cfg.access.play)||[]).join(', '));
  console.log('');
  if(!cfg.discord.botToken||!cfg.discord.guildId){
    console.log('NO BOT. Only the admin ids above can get in.');return;}
  const g=await get('/guilds/'+cfg.discord.guildId);
  if(g.c!==200){
    console.log('THE BOT CANNOT READ THE SERVER. Discord answered '+g.c+
      (g.c===401?(appIdIn(cfg.discord.botToken)
        ?'  (this IS a real bot token for the right application, so it has been '+
         'reset since. Get a fresh one: developer portal, Bot, Reset Token.)'
        :'  (what is stored is not a bot token at all, see the line above)'):
       g.c===403?'  (the bot is not allowed to read this server)':
       g.c===404?'  (wrong guild id, or the bot is not in that server)':''));
    console.log('While this is true, everybody except the admin ids is turned away.');
    return;}
  console.log('bot reads "'+g.b.name+'"');
  const r=await get('/guilds/'+cfg.discord.guildId+'/roles');
  if(r.c!==200){console.log('but it cannot read the roles: '+r.c);return;}
  console.log(r.b.length+' roles visible');
  const want=((cfg.access&&cfg.access.play)||[]).concat((cfg.access&&cfg.access.admin)||[]);
  const have=r.b.map(x=>x.name);
  const missing=want.filter(n=>have.indexOf(n)<0);
  if(missing.length)console.log('NAMED IN config BUT NOT IN THE SERVER: '+missing.join(', '));
  else console.log('every role the config names exists in the server');
  if(who){
    console.log('');
    const m=await get('/guilds/'+cfg.discord.guildId+'/members/'+who);
    if(m.c===404){console.log(who+' is NOT in the server.');return;}
    if(m.c!==200){console.log('could not look '+who+' up: '+m.c);return;}
    const byId={};r.b.forEach(x=>byId[x.id]=x.name);
    const mine=(m.b.roles||[]).map(i=>byId[i]).filter(Boolean);
    const name=m.b.nick||(m.b.user&&(m.b.user.global_name||m.b.user.username))||who;
    console.log(name+' is in the server');
    console.log('  roles:  '+(mine.join(', ')||'none'));
    const hit=(l)=>(l||[]).filter(n=>mine.indexOf(n)>=0);
    const banned=hit((cfg.access||{}).banned);
    console.log('  banned: '+(banned.length?'YES, '+banned.join(', '):'no'));
    console.log('  game:   '+(hit((cfg.access||{}).play).join(', ')||'NO, none of the play roles'));
    console.log('  admin:  '+(hit((cfg.access||{}).admin).join(', ')||'no'));
    if((cfg.admins||[]).indexOf(String(who))>=0)console.log('  also on the hand written admin list');
  }
})();
'@
$js = $js.Replace('ROOTWIN', $rootWin.Replace('\','\\'))
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($js))

Write-Host ''
Remote @"
`$ErrorActionPreference = 'Continue'
`$f = Join-Path `$env:TEMP 'tw-check.js'
[IO.File]::WriteAllText(`$f, [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$b64')))
& node `$f '$Who'
Remove-Item `$f -Force -EA SilentlyContinue
"@ | ForEach-Object { "  $_" }

Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
