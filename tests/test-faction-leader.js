// test-faction-leader.js
//
// Apply: Faction Leader replaced Apply: Trading Company on the Discord
// ticket panel. The Free Skyrim Trading Company is one of the seats.
//
// Djinn, 11-12 Oct 2026: the form, the pick list, the staff flag, the
// confirmed panel sentence, and Faction Leader routing to upper staff
// by role ID. This file holds the source to those decisions so a
// pull request that puts the company form back, drops factions.json from
// Install-Bot, grants a faction lead Discord role, or matches Lead
// roles by a name prefix goes red here.
// bot/test-faction-leader.py runs the form and the routing.
//
// Read only.
'use strict';
const fs = require('fs');
const path = require('path');
const REPO = path.join(__dirname, '..');
const CR = String.fromCharCode(13);
const read = function (p) { return fs.readFileSync(path.join(REPO, p), 'utf8').split(CR).join(''); };

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

const bot = read('bot/bot.py');
const req = read('bot/requirements.txt');
const install = read('scripts/deploy/Install-Bot.ps1');
const build = read('bot/Build-Discord.py');
const names = JSON.parse(read('bot/factions.json'));
const site = read('site/server.js');
const page = read('docs/systems/trading-company.md');
const factions = read('docs/systems/factions.md');
const STAFF_RULE = 'No GM or staff member (Loremaster, Discord Moderator, or any other staff role) may hold an in-game RP role with faction leadership, such as a Jarl or a faction lead.';

yes('F1 discord.py is pinned at 2.7.1, which has Select inside a modal since 2.6.0',
    req.indexOf('discord.py==2.7.1') !== -1 &&
    bot.indexOf('discord.ui.Label(') !== -1 &&
    bot.indexOf('discord.ui.Select(') !== -1 &&
    bot.indexOf('required=True') !== -1);

yes('F2 factions.json is names only, in this order, and Other is not in it',
    Array.isArray(names) &&
    names.join('|') === [
      'Imperial Embassy',
      'Thalmor Remnant',
      'Dark Brotherhood',
      'The Companions',
      'Free Skyrim Trading Company'
    ].join('|') &&
    names.indexOf('Other') === -1 &&
    !JSON.stringify(names).includes('token') &&
    !JSON.stringify(names).includes('secret'));

yes('F3 the panel offers Apply: Faction Leader and not Apply: Trading Company',
    /\('faction',\s+'Apply: Faction Leader'/.test(bot) &&
    !/\('company',\s+'Apply: Trading Company'/.test(bot) &&
    /'faction':\s+'Faction Lead of the faction named below'/.test(bot) &&
    !/'company':\s+'Trading Company'/.test(bot));

yes('F4 the three copied questions stay optional (long), and only the pick is required',
    /'What would they do with the faction\?'/.test(bot) &&
    /'Who is your character\?'/.test(bot) &&
    /'How much time can you give it\?'/.test(bot) &&
    !/'What would they do for the company\?'/.test(bot) &&
    /required=not long/.test(bot) &&
    /FACTION_OTHER_Q = 'If Other, which faction\?'/.test(bot) &&
    /max_length=200/.test(bot));

yes('F5 Install-Bot sends factions.json on the artifact list and in the copy loop',
    install.indexOf("'bot/factions.json'") !== -1 &&
    install.indexOf("foreach ($f in 'bot.py', 'card.py', 'dev-channel.txt', 'requirements.txt', 'factions.json')") !== -1);

yes('F6 Build-Discord still makes Trading Company and does not make a faction lead role',
    build.indexOf("ROLES.append(('Trading Company'") !== -1 &&
    !/Faction Lead/.test(build) && !/Faction Leader/.test(build));

yes('F7 is_staff still leaves Lead and Trial Gamemaster out, and the flag list includes them',
    /Lead Gamemaster and Trial Gamemaster carry Manage Threads/.test(bot) &&
    /LEADERSHIP_EXTRA = \('Lead Gamemaster', 'Trial Gamemaster'\)/.test(bot) &&
    /LEADERSHIP_KINDS = \('jarl', 'faction'\)/.test(bot) &&
    /def is_staff\(who\):/.test(bot) &&
    /The one gate on \/close, the Close ticket button/.test(bot));

yes('F8 Faction Leader tickets go to UPPER_STAFF_ROLES plus Owner, never a Lead name prefix',
    /UPPER_STAFF_ROLES/.test(bot) &&
    /UPPER_STAFF_NAMES\.add\('owner'\)/.test(bot) &&
    /def ticket_pull_roles\(/.test(bot) &&
    /kind == 'faction'/.test(bot) &&
    !/startswith\(['"]Lead/.test(bot) &&
    bot.indexOf("name='faction-seat'") === -1 &&
    install.indexOf('UPPER_STAFF_ROLES') !== -1);

yes('F9 submit re-checks a known name; Other is not flagged; there is no seat file',
    /faction_pick_is_known\(picked\)/.test(bot) &&
    /Other is a normal option/.test(bot) &&
    bot.indexOf('FACTION_SEATS') === -1 &&
    bot.indexOf('_seats_write') === -1);

yes('F10 the pick and the Other text stay out of the pinging head and Asking for',
    /head = '%s opened this\. %s'/.test(bot) &&
    /'faction':\s+'Faction Lead of the faction named below'/.test(bot) &&
    /The pick and the Other box stay out of the opening line/.test(bot));

yes('F11 the panel uses Djinn\'s confirmed staff-rule sentence and does not say apply for the Trading Company',
    bot.indexOf(STAFF_RULE) !== -1 &&
    /STAFF_LEADERSHIP_RULE/.test(bot) &&
    !/Applying for the Trading Company/.test(bot) &&
    !/Apply: Trading Company/.test(bot) &&
    bot.indexOf('Staff cannot hold a Jarl seat or a faction lead.') === -1);

yes('F12 the site inbox still stores any ticket kind as a free string',
    /ticket: String\(o\.kind \|\| ''\)\.slice\(0, 20\)/.test(site));

yes('F13 the trading company page no longer says Apply: Trading Company',
    page.indexOf('Apply: Trading Company') === -1 &&
    /Apply:\s*\nFaction Leader|Apply: Faction Leader/.test(page) &&
    /Trading Company/.test(page) &&
    page.indexOf('/faction-seat') === -1);

yes('F14 the factions page names the lead seats and the confirmed staff rule, with no seat command',
    /Apply: Faction Leader/.test(factions) &&
    factions.indexOf(STAFF_RULE) !== -1 &&
    factions.indexOf('/faction-seat') === -1 &&
    /does not make a new Discord role/.test(factions));

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
