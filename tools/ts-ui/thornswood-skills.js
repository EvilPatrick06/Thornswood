'use strict';
/*
  Your character: class, profession, skill tree, and while you are new, your
  home. The panel behind K, and the whole of character creation.

  Same rule as the emote wheel next door: nothing calls loadUrl. There is one
  browser and one page, so a page of its own would replace the chat, the names
  above heads and the whole front. This mounts itself at the end of the body,
  where React is not looking, and hides rather than unmounts.

  THE SECOND LOOK, 20 September. The first cut drew Patrick's wireframe as it
  was drawn: three round tabs, a list, a line across to a sub-list. He said
  the wireframe was a rough draft and not the thing, so this is the thing: a
  menu in the shape of the game's own, a framed panel over a darkened screen,
  a section list down the left with what you already are under each name, the
  section itself on the right, and one Confirm at the bottom. Plain sentences
  in it, not labels in capitals.

  CREATION IS THE SAME PANEL. A new character stands in the hall and the
  server opens this with a fourth section, Home. Pick a class, a profession
  and a home, in any order, each confirmed on its own, and the third one sends
  you to your inn. The panel closes itself when the server says creation is
  over.

  NOTHING HERE DECIDES ANYTHING. It reads what the server says this character
  is and sends what was picked. Every rule in the rulebook, one class only,
  one profession, novice in your sister half, two secondary professions at
  most, ranks, spell points, is the server's to enforce. A client that decided
  any of it would be a client anybody could edit. What the server refuses
  comes back as a note under the panel, and as a line in the chat.

  THE CONTRACT with thornswood-front.js, unchanged from the first cut:
    window.thornswoodSkills = { open, close, toggle, isOpen, setData }
    page -> plugin  'skills:ready' | 'skills:opened' | 'skills:closed' |
                    'skills:refresh' | 'skills:pick <words>'
    the plugin turns 'skills:pick X' into the chat line '/pick X'
*/

(function () {
  if (window.thornswoodSkills) return;

  // ------------------------------------------------------------ the table --
  /*
    From the rulebook of 20 September. The names and the rules are the
    server's; the sentences are this file's, because the server sends keys and
    a person reads sentences. If the server ever sends a table it replaces
    this one wholesale.
  */
  var DATA = {
    'class': {
      title: 'Class',
      lead: 'One class, for good. It is the one kind of work only you can do. Everything else you buy, trade for, or ask a friend to do.',
      rows: [
        { key: 'hunter', name: 'Hunter', desc: 'The only ones who can loot an animal they have brought down. Hides, meat and horn come from a hunter or from nobody.' },
        { key: 'fisher', name: 'Fisher', desc: 'The only ones who can take fish from the water. Every fish on every table was caught by one of you.' },
        { key: 'gatherer', name: 'Gatherer', desc: 'The only ones who can harvest flora and loose materials out of the world. Herbs, mushrooms, moss, the makings of every potion.' },
        { key: 'miner', name: 'Miner', desc: 'The only ones who can work an ore vein. Every ingot in Skyrim starts with a miner and a pickaxe.' },
        { key: 'farmer', name: 'Farmer', desc: 'The only ones who can plant and harvest crops. Grain, vegetables and the bread that comes of them.' }
      ]
    },
    profession: {
      title: 'Profession',
      lead: 'One profession, and one half of it to make your own. You know the novice work of the other half from the start. A Master of another profession can teach you their basics, and you may take that up twice.',
      rows: [
        { key: 'warrior', name: 'Warrior', desc: 'Arms, and the people who carry them.',
          subs: [{ key: 'bulwark', name: 'Bulwark', desc: 'Shields, heavy armour, holding the line' },
                 { key: 'berserker', name: 'Berserker', desc: 'Two handed, dual wield, ending the fight' }],
          perk: 'At Master, Warlord: teach novice combat to non-warriors, and the master-tier manoeuvres.' },
        { key: 'mage', name: 'Mage', desc: 'Two schools of magic, and spells learned by the point.', pick: 2,
          subs: [{ key: 'destruction', name: 'Destruction' }, { key: 'restoration', name: 'Restoration' },
                 { key: 'alteration', name: 'Alteration' }, { key: 'conjuration', name: 'Conjuration' },
                 { key: 'illusion', name: 'Illusion' }],
          perk: 'At Master, Archmage: a third school, and the authority to take on apprentices who are not mages.' },
        { key: 'alchemist', name: 'Alchemist', desc: 'What goes into a bottle, and what it does to whoever drinks it.',
          subs: [{ key: 'blightbrewer', name: 'Blightbrewer', desc: 'Poisons and harm' },
                 { key: 'physicker', name: 'Physicker', desc: 'Medicine and restoration' }],
          perk: 'At Master, Master Chemist: two potions from every batch.' },
        { key: 'cook', name: 'Cook', desc: 'The hearth, and everything that comes off it.',
          subs: [{ key: 'hearthcook', name: 'Hearthcook', desc: 'Dinners, meats, stews' },
                 { key: 'confectioner', name: 'Confectioner', desc: 'Desserts, breads, sweets' }],
          perk: 'At Master, Grand Chef: two dishes from every batch.' },
        { key: 'smith', name: 'Smith', desc: 'Iron and steel, and the forge that shapes them.',
          subs: [{ key: 'platewright', name: 'Platewright', desc: 'Armour' },
                 { key: 'edgewright', name: 'Edgewright', desc: 'Weapons' }],
          perk: 'At Master, Mastercraft: temper to Legendary, past the ordinary limit.' },
        { key: 'enchanter', name: 'Enchanter', desc: 'Souls, and what they are bound into.',
          subs: [{ key: 'bladebinder', name: 'Bladebinder', desc: 'Weapon enchantments' },
                 { key: 'wardweaver', name: 'Wardweaver', desc: 'Armour and apparel' }],
          perk: 'At Master, Twin Souls: two enchantments on one item.' },
        { key: 'tailor', name: 'Tailor', desc: 'Cloth, thread and the people who wear them.',
          subs: [{ key: 'liverywright', name: 'Liverywright', desc: 'Robes, uniforms, faction dress' },
                 { key: 'haberdasher', name: 'Haberdasher', desc: 'Common and fine clothing' }],
          perk: 'At Master, Master Weaver: clothing that hides armour or turns the weather, without the weight.' },
        { key: 'woodworker', name: 'Woodworker', desc: 'Timber, from the felling to the finished thing.',
          subs: [{ key: 'charburner', name: 'Charburner', desc: 'Firewood, coke, campfires' },
                 { key: 'woodwright', name: 'Woodwright', desc: 'Bows, arrows, instruments' }],
          perk: 'At Master, Master Carver: campfires and kilns give their full warmth.' }
      ]
    },
    tree: {
      title: 'Skill tree',
      lead: 'Fifteen skills across health, magicka and stamina. A point goes in one at a time, and filling one grants its perk.',
      rows: [
        { key: 'health', name: 'Health', subs: [
            { key: 'vitality', name: 'Vitality', desc: 'Most health', perk: 'Cheat Death: once a day a killing blow leaves you at one point of health.' },
            { key: 'fortitude', name: 'Fortitude', desc: 'Regeneration', perk: 'Troll’s Blood: regeneration carries on in combat.' },
            { key: 'might', name: 'Might', desc: 'Melee damage', perk: 'Devastating Blow: power attacks often stagger or knock down.' },
            { key: 'resilience', name: 'Resilience', desc: 'Armour', perk: 'Unshakeable: no stagger while blocking.' },
            { key: 'toughness', name: 'Toughness', desc: 'Poison and disease', perk: 'Purified Blood: no disease, and three quarters of poison shrugged off.' }] },
        { key: 'magicka', name: 'Magicka', subs: [
            { key: 'capacity', name: 'Capacity', desc: 'Most magicka', perk: 'Archmage’s Vessel: a burst of regeneration when nearly empty.' },
            { key: 'clarity', name: 'Clarity', desc: 'Regeneration', perk: 'Leyline Attunement: full regeneration while casting.' },
            { key: 'potency', name: 'Potency', desc: 'Spell effect', perk: 'Overcharge: one spell in seven lands double.' },
            { key: 'ward', name: 'Ward', desc: 'Magic resistance', perk: 'Spellbreaker: one spell in four is absorbed and refills you.' },
            { key: 'efficiency', name: 'Efficiency', desc: 'Cost', perk: 'Font of Magic: once a day, fifteen seconds of free casting.' }] },
        { key: 'stamina', name: 'Stamina', subs: [
            { key: 'endurance', name: 'Endurance', desc: 'Most stamina', perk: 'Tireless: sprinting and power attacks cost half.' },
            { key: 'vigor', name: 'Vigor', desc: 'Regeneration', perk: 'Second Wind: full stamina the instant it empties, once in five minutes.' },
            { key: 'agility', name: 'Agility', desc: 'Speed', perk: 'Windwalker: a tenth faster, and no fall damage.' },
            { key: 'burden', name: 'Burden', desc: 'Carry weight', perk: 'Pack Mule: no slowing until fifty pounds over.' },
            { key: 'precision', name: 'Precision', desc: 'Critical and ranged', perk: 'Lethal Aim: ranged attacks ignore half of physical armour.' }] }
      ]
    },
    home: {
      title: 'Home',
      lead: 'Where you wake up. The inn keeps a room for you, and it is where you come back to.',
      rows: []   // the server sends the towns while you are new
    }
  };

  /* The inn in each town, by the server's town key. Display only. */
  var INNS = {
    whiterun: 'The Bannered Mare', riften: 'The Bee and Barb', solitude: 'The Winking Skeever',
    windhelm: 'Candlehearth Hall', markarth: 'The Silver-Blood Inn', falkreath: 'Dead Man’s Drink',
    morthal: 'Moorside Inn', dawnstar: 'The Windpeak Inn', winterhold: 'The Frozen Hearth'
  };

  var RANK_NAMES = { novice: 'Novice', advanced: 'Advanced', expert: 'Expert', master: 'Master' };
  var CAP = 5;             // points that fill a skill; the server's LIMITS.skillCap, mirrored for the pips

  // ---------------------------------------------------------------- state --
  var sections = ['class', 'profession', 'tree'];   // 'home' is added while creating
  var section = 'class';
  var rowAt = 0;
  var mine = null;         // what the server says this character is: the panel view
  var picked = {};         // section -> { row: key, subs: [keys] } chosen in the panel, not yet confirmed
  var pending = null;      // the last pick sent and not yet answered, for the status line
  var status = '';         // the line under the panel
  var statusKind = '';     // '' | 'ok' | 'no'
  var wasCreating = false;

  // ------------------------------------------------------------------ css --
  var css = [
    '#ts-skills{position:fixed;inset:0;z-index:2147483000;display:flex;align-items:center;justify-content:center;',
    'background:radial-gradient(ellipse at center,rgba(0,0,0,.50) 0%,rgba(0,0,0,.72) 100%);',
    'font-family:"Palatino Linotype",Palatino,Georgia,serif;color:#d9cfb4;user-select:none;pointer-events:auto}',
    '#ts-skills.gone{display:none}',
    '#ts-skills *{box-sizing:border-box}',
    '#ts-skills .panel{width:min(1120px,94vw);height:min(700px,90vh);display:grid;',
    'grid-template-columns:250px 1fr;grid-template-rows:auto 1fr auto;',
    'background:rgba(11,10,8,.94);border:1px solid rgba(198,170,109,.42);outline:1px solid rgba(198,170,109,.14);outline-offset:4px;',
    'box-shadow:0 24px 80px rgba(0,0,0,.7);position:relative}',
    // head
    '#ts-skills .head{grid-column:1/3;display:flex;align-items:flex-end;justify-content:space-between;',
    'padding:22px 32px 16px;border-bottom:1px solid rgba(198,170,109,.22)}',
    '#ts-skills .eyebrow{font-size:11px;letter-spacing:.3em;text-transform:uppercase;color:rgba(198,170,109,.75);margin-bottom:6px}',
    '#ts-skills .title{font-size:26px;color:#f6e9c8;line-height:1.1}',
    '#ts-skills .who{text-align:right;font-size:13.5px;color:#d9cfb4;line-height:1.5}',
    '#ts-skills .who .dim{color:rgba(217,207,180,.6);font-style:italic}',
    '#ts-skills .who .pts{color:#e9d19b}',
    // nav
    '#ts-skills .nav{grid-column:1;border-right:1px solid rgba(198,170,109,.22);padding:14px 0;overflow:auto}',
    '#ts-skills .navrow{padding:14px 26px 13px 23px;border-left:3px solid transparent;cursor:pointer;transition:background 90ms linear}',
    '#ts-skills .navrow:hover{background:rgba(120,94,44,.14)}',
    '#ts-skills .navrow.on{border-left-color:#e9d19b;background:rgba(120,94,44,.24)}',
    '#ts-skills .navrow .k{font-size:16px;color:#d9cfb4;letter-spacing:.02em}',
    '#ts-skills .navrow.on .k{color:#f6e9c8}',
    '#ts-skills .navrow .v{font-size:12.5px;color:rgba(217,207,180,.58);font-style:italic;margin-top:3px}',
    '#ts-skills .navrow .v.set{color:#9fcf92;font-style:normal}',
    '#ts-skills .navrow .v.need{color:#e9d19b}',
    // body
    '#ts-skills .body{grid-column:2;padding:22px 32px 18px;overflow:auto}',
    '#ts-skills .lead{font-size:13.5px;line-height:1.55;color:rgba(217,207,180,.66);font-style:italic;margin:0 0 16px;max-width:680px}',
    '#ts-skills .cards{display:grid;grid-template-columns:1fr;gap:9px}',
    '#ts-skills .cards.three{grid-template-columns:repeat(3,1fr)}',
    '#ts-skills .card{border:1px solid rgba(198,170,109,.30);background:rgba(0,0,0,.20);padding:13px 18px 12px;cursor:pointer;',
    'transition:all 90ms linear;position:relative}',
    '#ts-skills .card:hover{border-color:rgba(233,209,155,.7);background:rgba(120,94,44,.16)}',
    '#ts-skills .card.at{border-color:rgba(233,209,155,.95);background:rgba(120,94,44,.34)}',
    '#ts-skills .card.mine{border-color:rgba(160,205,150,.8)}',
    '#ts-skills .card.off{opacity:.42}',
    '#ts-skills .card.off:hover{border-color:rgba(198,170,109,.30);background:rgba(0,0,0,.20)}',
    '#ts-skills .card .name{font-size:16.5px;color:#f6e9c8;display:flex;align-items:baseline;gap:12px}',
    '#ts-skills .card .desc{font-size:13px;line-height:1.5;color:rgba(217,207,180,.78);margin-top:4px}',
    '#ts-skills .card .inn{font-size:12.5px;color:rgba(217,207,180,.6);font-style:italic;margin-top:3px}',
    '#ts-skills .tag{margin-left:auto;font-size:10.5px;letter-spacing:.2em;text-transform:uppercase;color:#9fcf92;white-space:nowrap}',
    '#ts-skills .tag.gold{color:#e9d19b}',
    '#ts-skills .tag.dim{color:rgba(217,207,180,.5)}',
    // halves and schools inside an open profession card
    '#ts-skills .halves{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:11px}',
    '#ts-skills .halves.five{grid-template-columns:repeat(5,1fr)}',
    '#ts-skills .half{border:1px solid rgba(198,170,109,.32);padding:9px 12px;background:rgba(0,0,0,.22);cursor:pointer;transition:all 90ms linear}',
    '#ts-skills .half:hover{border-color:rgba(233,209,155,.75)}',
    '#ts-skills .half.on{border-color:rgba(233,209,155,.95);background:rgba(120,94,44,.42)}',
    '#ts-skills .half.mine{border-color:rgba(160,205,150,.8)}',
    '#ts-skills .half .hn{font-size:14.5px;color:#f6e9c8}',
    '#ts-skills .half .hd{font-size:12px;color:rgba(217,207,180,.66);margin-top:2px}',
    '#ts-skills .half .hr{font-size:11px;color:#9fcf92;letter-spacing:.12em;text-transform:uppercase;margin-top:4px}',
    '#ts-skills .perk{font-size:12.5px;line-height:1.5;color:rgba(198,170,109,.85);margin-top:10px;padding-top:8px;border-top:1px solid rgba(198,170,109,.18)}',
    // the tree
    '#ts-skills .cols{display:grid;grid-template-columns:repeat(3,1fr);gap:22px}',
    '#ts-skills .colhead{font-size:11.5px;letter-spacing:.24em;text-transform:uppercase;color:rgba(198,170,109,.85);',
    'padding-bottom:8px;border-bottom:1px solid rgba(198,170,109,.22);margin-bottom:6px}',
    '#ts-skills .skill{display:grid;grid-template-columns:1fr auto auto;grid-template-rows:auto auto;column-gap:10px;align-items:center;',
    'padding:9px 6px 8px;border:1px solid transparent;cursor:default}',
    '#ts-skills .skill.at{border-color:rgba(233,209,155,.6);background:rgba(120,94,44,.18)}',
    '#ts-skills .skill .sn{font-size:15px;color:#f6e9c8}',
    '#ts-skills .skill .sd{grid-column:1/4;font-size:12px;color:rgba(217,207,180,.6);line-height:1.45;margin-top:3px}',
    '#ts-skills .skill .sd.lit{color:#e9d19b}',
    '#ts-skills .pips{display:flex;gap:4px}',
    '#ts-skills .pip{width:10px;height:10px;border:1px solid rgba(198,170,109,.55);background:rgba(0,0,0,.2)}',
    '#ts-skills .pip.lit{background:#c6aa6d;border-color:#e9d19b}',
    '#ts-skills .plus{width:26px;height:26px;border:1px solid rgba(198,170,109,.55);color:#e9d19b;display:grid;place-items:center;',
    'font-size:18px;line-height:1;cursor:pointer;background:rgba(0,0,0,.25)}',
    '#ts-skills .plus:hover{background:rgba(120,94,44,.5);border-color:rgba(233,209,155,.95)}',
    '#ts-skills .plus.off{opacity:.25;pointer-events:none}',
    // foot
    '#ts-skills .foot{grid-column:1/3;display:flex;align-items:center;justify-content:space-between;gap:20px;',
    'padding:13px 32px;border-top:1px solid rgba(198,170,109,.22)}',
    '#ts-skills .status{font-size:13.5px;color:rgba(217,207,180,.7);font-style:italic;min-height:1.4em}',
    '#ts-skills .status.ok{color:#9fcf92;font-style:normal}',
    '#ts-skills .status.no{color:#d9a27a;font-style:normal}',
    '#ts-skills .btns{display:flex;gap:10px;align-items:center}',
    '#ts-skills .btn{border:1px solid rgba(198,170,109,.55);padding:10px 26px;font-size:13px;letter-spacing:.14em;text-transform:uppercase;',
    'cursor:pointer;color:#e9d19b;background:rgba(0,0,0,.25);transition:all 90ms linear;font-family:inherit}',
    '#ts-skills .btn:hover{background:rgba(120,94,44,.45);border-color:rgba(233,209,155,.95);color:#f6e9c8}',
    '#ts-skills .btn kbd{font-family:inherit;font-size:11px;opacity:.7;margin-left:8px;letter-spacing:0}',
    '#ts-skills .btn.primary{background:#c6aa6d;border-color:#e9d19b;color:#1b1205}',
    '#ts-skills .btn.primary:hover{background:#e9d19b;color:#1b1205}',
    '#ts-skills .btn.primary.off{opacity:.35;pointer-events:none}',
    '#ts-skills .steps{display:flex;gap:14px;font-size:12px;letter-spacing:.14em;text-transform:uppercase;color:rgba(217,207,180,.5);margin-top:4px;justify-content:flex-end}',
    '#ts-skills .steps .done{color:#9fcf92}'
  ].join('');

  var style = document.createElement('style');
  style.id = 'ts-skills-css';
  style.textContent = css;
  document.head.appendChild(style);

  // ----------------------------------------------------------------- dom --
  var root = document.createElement('div');
  root.id = 'ts-skills';
  root.className = 'gone';
  root.innerHTML =
    '<div class="panel">' +
      '<div class="head"><div><div class="eyebrow">Thornswood</div><div class="title"></div></div><div class="who"></div></div>' +
      '<div class="nav"></div>' +
      '<div class="body"></div>' +
      '<div class="foot"><div class="status"></div><div class="btns">' +
        '<div class="btn ghost" data-act="close">Close<kbd>K</kbd></div>' +
        '<div class="btn primary" data-act="confirm">Confirm</div>' +
      '</div></div>' +
    '</div>';
  document.body.appendChild(root);

  var elTitle = root.querySelector('.title');
  var elWho = root.querySelector('.who');
  var elNav = root.querySelector('.nav');
  var elBody = root.querySelector('.body');
  var elStatus = root.querySelector('.status');
  var elConfirm = root.querySelector('[data-act="confirm"]');
  var elClose = root.querySelector('[data-act="close"]');
  var elPanel = root.querySelector('.panel');

  /* Laid out for 1920x1080 and scaled up from there: at 3440x1440 the first
     cut was a postage stamp. */
  function fit() {
    try {
      var s = Math.min(window.innerWidth / 1920, window.innerHeight / 1080);
      if (!isFinite(s) || s < 1) s = 1;
      elPanel.style.transformOrigin = 'center center';
      elPanel.style.transform = 'scale(' + Math.min(s, 2.4).toFixed(3) + ')';
    } catch (e) { }
  }
  window.addEventListener('resize', fit);

  function tell(what, extra) {
    try {
      window.skyrimPlatform.sendMessage('thornswood-front', 'skills:' + what + (extra ? ' ' + extra : ''));
    } catch (e) { }
  }

  function el(tag, cls, text) {
    var d = document.createElement(tag);
    if (cls) d.className = cls;
    if (text !== undefined && text !== null) d.textContent = text;
    return d;
  }
  function cap(s) { s = String(s || ''); return s ? s.charAt(0).toUpperCase() + s.slice(1) : ''; }
  function nameOf(sec, key) {
    var rows = DATA[sec] ? DATA[sec].rows : [];
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].key === key) return rows[i].name;
      var subs = rows[i].subs || [];
      for (var j = 0; j < subs.length; j++) if (subs[j].key === key) return subs[j].name;
    }
    return cap(key);
  }
  function creating() { return !!(mine && mine.creating); }
  function rows() { return DATA[section] ? DATA[section].rows : []; }

  // ----------------------------------------------------- what you already are --
  function haveClass() { return !!(mine && mine['class']); }
  function haveProf() { return !!(mine && mine.profession); }
  function haveHome() { return !!(mine && mine.home); }
  function rankOf(key) { return (mine && mine.ranks && mine.ranks[key]) || ''; }
  function ownHalves() {
    if (!mine) return [];
    if (mine.half) return [mine.half];
    return (mine.schools || []).slice();
  }
  function summary() {
    var bits = [];
    if (haveClass()) bits.push(nameOf('class', mine['class']));
    if (haveProf()) {
      var halves = ownHalves().map(function (h) { return nameOf('profession', h); });
      bits.push(nameOf('profession', mine.profession) + (halves.length ? ', ' + halves.join(' and ') : ''));
    }
    return bits.join(' · ');
  }
  function topRank() {
    var best = '';
    var own = ownHalves();
    for (var i = 0; i < own.length; i++) {
      var r = rankOf(own[i]);
      if (!best || ['novice', 'advanced', 'expert', 'master'].indexOf(r) > ['novice', 'advanced', 'expert', 'master'].indexOf(best)) best = r;
    }
    return best;
  }

  // ------------------------------------------------------------------ draw --
  function draw() {
    sections = creating() ? ['class', 'profession', 'home', 'tree'] : ['class', 'profession', 'tree'];
    if (sections.indexOf(section) < 0) section = sections[0];
    drawHead();
    drawNav();
    drawBody();
    drawFoot();
  }

  function drawHead() {
    if (creating()) {
      elTitle.textContent = 'Begin your life in Thornswood';
      elWho.textContent = '';
      elWho.appendChild(el('div', '', 'Choose a class, a profession and a home. Each one is yours the moment you confirm it.'));
      var steps = el('div', 'steps');
      steps.appendChild(el('span', haveClass() ? 'done' : '', (haveClass() ? '✓ ' : '') + 'Class'));
      steps.appendChild(el('span', haveProf() ? 'done' : '', (haveProf() ? '✓ ' : '') + 'Profession'));
      steps.appendChild(el('span', haveHome() ? 'done' : '', (haveHome() ? '✓ ' : '') + 'Home'));
      elWho.appendChild(steps);
      return;
    }
    elTitle.textContent = DATA[section] ? DATA[section].title : '';
    elWho.textContent = '';
    var s = summary();
    elWho.appendChild(el('div', s ? '' : 'dim', s || 'Nothing chosen yet. Class and profession are picked once, in the creation hall.'));
    var rk = topRank();
    var pts = mine ? Number(mine.points) || 0 : 0;
    var line2 = el('div', 'dim');
    if (rk) line2.appendChild(document.createTextNode(RANK_NAMES[rk] || cap(rk)));
    if (rk && pts) line2.appendChild(document.createTextNode(' · '));
    if (pts) { var p = el('span', 'pts', pts + (pts === 1 ? ' point to spend' : ' points to spend')); line2.appendChild(p); }
    if (rk || pts) elWho.appendChild(line2);
  }

  function navValue(sec) {
    if (sec === 'class') return haveClass() ? { t: nameOf('class', mine['class']), c: 'set' } : { t: creating() ? 'choose one' : 'not chosen', c: creating() ? 'need' : '' };
    if (sec === 'profession') {
      if (!haveProf()) return { t: creating() ? 'choose one' : 'not chosen', c: creating() ? 'need' : '' };
      var halves = ownHalves().map(function (h) { return nameOf('profession', h); });
      return { t: nameOf('profession', mine.profession) + (halves.length ? ', ' + halves.join(' and ') : ''), c: 'set' };
    }
    if (sec === 'home') return haveHome() ? { t: cap(mine.home), c: 'set' } : { t: 'choose one', c: 'need' };
    var pts = mine ? Number(mine.points) || 0 : 0;
    var spent = 0;
    if (mine && mine.tree) for (var k in mine.tree) spent += Number(mine.tree[k]) || 0;
    return { t: pts ? pts + ' to spend' : (spent ? spent + ' spent' : 'nothing yet'), c: pts ? 'need' : '' };
  }

  function drawNav() {
    elNav.textContent = '';
    sections.forEach(function (sec) {
      var row = el('div', 'navrow' + (sec === section ? ' on' : ''));
      row.appendChild(el('div', 'k', DATA[sec].title));
      var v = navValue(sec);
      row.appendChild(el('div', 'v ' + v.c, v.t));
      row.onclick = function () { section = sec; rowAt = 0; draw(); };
      elNav.appendChild(row);
    });
  }

  function drawBody() {
    elBody.textContent = '';
    var lead = DATA[section] ? DATA[section].lead : '';
    if (section === 'tree') {
      var pts = mine ? Number(mine.points) || 0 : 0;
      lead += ' ' + (pts ? 'You have ' + pts + (pts === 1 ? ' point' : ' points') + ' to spend.' : 'No points to spend right now.');
    }
    if (lead) elBody.appendChild(el('p', 'lead', lead));
    if (section === 'class') drawClass();
    else if (section === 'profession') drawProfession();
    else if (section === 'home') drawHome();
    else drawTree();
  }

  function drawClass() {
    var wrap = el('div', 'cards');
    var have = haveClass();
    var p = picked['class'] || {};
    rows().forEach(function (r, i) {
      var isMine = have && mine['class'] === r.key;
      var card = el('div', 'card' + (i === rowAt ? ' at' : '') + (isMine ? ' mine' : '') + (have && !isMine ? ' off' : ''));
      var name = el('div', 'name', r.name);
      if (isMine) name.appendChild(el('span', 'tag', 'yours'));
      else if (p.row === r.key) name.appendChild(el('span', 'tag gold', 'chosen, confirm below'));
      card.appendChild(name);
      card.appendChild(el('div', 'desc', r.desc));
      card.onclick = function () {
        rowAt = i;
        if (!have) picked['class'] = { row: r.key, subs: [] };
        draw();
      };
      wrap.appendChild(card);
    });
    elBody.appendChild(wrap);
  }

  function drawProfession() {
    var wrap = el('div', 'cards');
    var have = haveProf();
    var p = picked.profession || {};
    rows().forEach(function (r, i) {
      var isMine = have && mine.profession === r.key;
      var open = i === rowAt && !have;
      var card = el('div', 'card' + (i === rowAt ? ' at' : '') + (isMine ? ' mine' : '') + (have && !isMine ? ' off' : ''));
      var name = el('div', 'name', r.name);
      if (isMine) name.appendChild(el('span', 'tag', 'yours'));
      else if (p.row === r.key && p.subs && p.subs.length) name.appendChild(el('span', 'tag gold', 'chosen, confirm below'));
      card.appendChild(name);
      card.appendChild(el('div', 'desc', r.desc));

      if (open || isMine) {
        var want = r.pick || 1;
        var halves = el('div', 'halves' + ((r.subs || []).length > 2 ? ' five' : ''));
        (r.subs || []).forEach(function (s) {
          var on = !isMine && p.row === r.key && (p.subs || []).indexOf(s.key) >= 0;
          var mineHalf = isMine && ownHalves().indexOf(s.key) >= 0;
          var h = el('div', 'half' + (on ? ' on' : '') + (mineHalf ? ' mine' : ''));
          h.appendChild(el('div', 'hn', s.name));
          if (s.desc) h.appendChild(el('div', 'hd', s.desc));
          var rk = rankOf(s.key);
          if (isMine && rk) h.appendChild(el('div', 'hr', (RANK_NAMES[rk] || cap(rk)) + (mineHalf ? '' : ', your sister half')));
          if (!isMine) {
            h.onclick = function (ev) {
              ev.stopPropagation();
              var cur = (picked.profession && picked.profession.row === r.key) ? picked.profession.subs.slice() : [];
              var at = cur.indexOf(s.key);
              if (at >= 0) cur.splice(at, 1); else cur.push(s.key);
              while (cur.length > want) cur.shift();
              picked.profession = { row: r.key, subs: cur };
              draw();
            };
          }
          halves.appendChild(h);
        });
        card.appendChild(halves);
        if (!isMine && want > 1) {
          var n = (p.row === r.key && p.subs) ? p.subs.length : 0;
          card.appendChild(el('div', 'inn', 'Pick ' + want + ' schools. ' + n + ' of ' + want + ' picked.'));
        } else if (!isMine) {
          card.appendChild(el('div', 'inn', 'Pick the half you will make your own. The other is yours at novice from the start.'));
        }
        if (r.perk) card.appendChild(el('div', 'perk', r.perk));
      }
      card.onclick = function () {
        if (have) { rowAt = i; draw(); return; }
        if (rowAt !== i) { rowAt = i; draw(); }
      };
      wrap.appendChild(card);
    });
    elBody.appendChild(wrap);
  }

  function drawHome() {
    var towns = (mine && mine.towns) || [];
    var wrap = el('div', 'cards three');
    var p = picked.home || {};
    towns.forEach(function (t, i) {
      var card = el('div', 'card' + (i === rowAt ? ' at' : '') + (haveHome() && mine.home === t.key ? ' mine' : ''));
      var name = el('div', 'name', t.name);
      if (haveHome() && mine.home === t.key) name.appendChild(el('span', 'tag', 'yours'));
      else if (p.row === t.key) name.appendChild(el('span', 'tag gold', 'chosen'));
      card.appendChild(name);
      if (INNS[t.key]) card.appendChild(el('div', 'inn', INNS[t.key]));
      card.onclick = function () { rowAt = i; if (!haveHome()) picked.home = { row: t.key, subs: [] }; draw(); };
      wrap.appendChild(card);
    });
    if (!towns.length) elBody.appendChild(el('p', 'lead', 'The server has not sent the town list yet. Give it a moment.'));
    elBody.appendChild(wrap);
  }

  function drawTree() {
    var cols = el('div', 'cols');
    var pts = mine ? Number(mine.points) || 0 : 0;
    var tree = (mine && mine.tree) || {};
    var flat = [];
    rows().forEach(function (attr) {
      var col = el('div', 'col');
      col.appendChild(el('div', 'colhead', attr.name));
      (attr.subs || []).forEach(function (s) {
        var idx = flat.length; flat.push(s.key);
        var have = Number(tree[s.key]) || 0;
        var full = have >= CAP;
        var row = el('div', 'skill' + (idx === rowAt ? ' at' : ''));
        row.appendChild(el('div', 'sn', s.name));
        var pips = el('div', 'pips');
        for (var i = 0; i < CAP; i++) pips.appendChild(el('span', 'pip' + (i < have ? ' lit' : '')));
        row.appendChild(pips);
        var plus = el('div', 'plus' + ((pts > 0 && !full) ? '' : ' off'), '+');
        plus.title = 'Put a point in ' + s.name;
        plus.onclick = function (ev) { ev.stopPropagation(); spend(s.key); };
        row.appendChild(plus);
        row.appendChild(el('div', 'sd' + (full ? ' lit' : ''), full ? s.perk : s.desc + '. ' + s.perk));
        row.onclick = function () { rowAt = idx; draw(); };
        col.appendChild(row);
      });
      cols.appendChild(col);
    });
    elBody.appendChild(cols);
  }

  function drawFoot() {
    elStatus.className = 'status' + (statusKind ? ' ' + statusKind : '');
    elStatus.textContent = status || hint();
    var can = canConfirm();
    elConfirm.className = 'btn primary' + (can ? '' : ' off');
    elConfirm.textContent = section === 'home' ? 'Make it home' : 'Confirm';
    elConfirm.style.display = section === 'tree' ? 'none' : '';
  }

  function hint() {
    if (section === 'tree') return 'Press + on a skill to put a point in it.';
    if (section === 'class') return haveClass() ? 'Your class is set for good.' : 'Pick a class, then confirm.';
    if (section === 'profession') return haveProf() ? 'Your profession is set. Ranks come from doing the work.' : 'Pick a profession and its half, then confirm.';
    if (section === 'home') return haveHome() ? 'Home is set.' : 'Pick the town you will wake up in.';
    return '';
  }

  // --------------------------------------------------------------- picks --
  function canConfirm() {
    var p = picked[section];
    if (!p || !p.row) return false;
    if (section === 'class') return !haveClass();
    if (section === 'home') return !haveHome() && creating();
    if (section === 'profession') {
      if (haveProf()) return false;
      var r = null;
      rows().forEach(function (x) { if (x.key === p.row) r = x; });
      if (!r) return false;
      return (p.subs || []).length === (r.pick || 1);
    }
    return false;
  }

  function confirm() {
    if (!canConfirm()) return;
    var p = picked[section];
    var words;
    if (section === 'class') words = 'class ' + p.row;
    else if (section === 'home') words = 'town ' + p.row;
    else words = 'profession ' + p.row + ' ' + p.subs.join(',');
    pending = { section: section, words: words, at: Date.now() };
    status = 'Sent. The server is checking.'; statusKind = '';
    tell('pick', words);
    draw();
  }

  function spend(skill) {
    if (!mine || !(Number(mine.points) > 0)) return;
    pending = { section: 'tree', words: 'spend ' + skill, at: Date.now() };
    status = 'Sent.'; statusKind = '';
    tell('pick', 'spend ' + skill);
    draw();
  }

  /* The server answered by rewriting the property. Say what changed. */
  function answered(before, after) {
    if (!pending) return;
    var p = pending; pending = null;
    if (p.section === 'class' && after['class'] && !(before && before['class'])) { status = nameOf('class', after['class']) + ' it is.'; statusKind = 'ok'; }
    else if (p.section === 'profession' && after.profession && !(before && before.profession)) { status = 'You are a ' + nameOf('profession', after.profession).toLowerCase() + ' now.'; statusKind = 'ok'; }
    else if (p.section === 'home' && after.home && !(before && before.home)) { status = cap(after.home) + '. See you there.'; statusKind = 'ok'; }
    else if (p.section === 'tree') { status = 'Spent.'; statusKind = 'ok'; }
    else { status = ''; statusKind = ''; }
    picked[p.section] = null;
  }

  // ---------------------------------------------------------------- keys --
  /*
    Arrow keys and Enter, because the mouse is not always where somebody left
    it and the panel is a list. Escape closes. Everything else is left alone:
    this page is shared with the chat, and swallowing keys it does not own is
    how the chat box lost the keyboard before.
  */
  function onKey(e) {
    if (root.className === 'gone') return;
    var n = section === 'home' ? ((mine && mine.towns) || []).length
          : section === 'tree' ? 15 : rows().length;
    if (e.key === 'Escape') { api.close(); e.preventDefault(); return; }
    if (e.key === 'Enter') {
      if (section === 'tree') {
        var flat = [];
        rows().forEach(function (a) { (a.subs || []).forEach(function (s) { flat.push(s.key); }); });
        if (flat[rowAt]) spend(flat[rowAt]);
      } else if (canConfirm()) { confirm(); }
      else {
        // Enter on a row picks it, the second Enter confirms.
        var r = section === 'home' ? ((mine && mine.towns) || [])[rowAt] : rows()[rowAt];
        if (r && section === 'class' && !haveClass()) { picked['class'] = { row: r.key, subs: [] }; draw(); }
        else if (r && section === 'home' && !haveHome()) { picked.home = { row: r.key, subs: [] }; draw(); }
      }
      e.preventDefault(); return;
    }
    if (e.key === 'ArrowDown') { rowAt = n ? (rowAt + 1) % n : 0; draw(); e.preventDefault(); }
    else if (e.key === 'ArrowUp') { rowAt = n ? (rowAt + n - 1) % n : 0; draw(); e.preventDefault(); }
    else if (e.key === 'ArrowRight' || e.key === 'ArrowLeft') {
      var i = sections.indexOf(section);
      section = sections[(i + (e.key === 'ArrowRight' ? 1 : sections.length - 1)) % sections.length];
      rowAt = 0; draw(); e.preventDefault();
    }
  }
  window.addEventListener('keydown', onKey, true);
  elConfirm.onclick = confirm;
  elClose.onclick = function () { api.close(); };

  // ---------------------------------------------------------------- api --
  var api = {
    open: function () {
      if (root.className !== 'gone') return;
      root.className = '';
      fit();
      draw();
      tell('opened');
      tell('refresh');   // the server says again what this character is
    },
    close: function () {
      if (root.className === 'gone') return;
      root.className = 'gone';
      tell('closed');
    },
    toggle: function () {
      if (root.className === 'gone') { api.open(); } else { api.close(); }
    },
    isOpen: function () { return root.className !== 'gone'; },
    /*
      What the server sent. The property carries the whole stored state with
      the view for this panel nested under .panel; the first cut read the top
      level and so never saw its own class or profession. A table, if one ever
      comes, replaces the one here wholesale.
    */
    setData: function (table, got) {
      if (table && typeof table === 'object') { DATA = table; }
      if (got && typeof got === 'object') {
        var before = mine;
        mine = (got.panel && typeof got.panel === 'object') ? got.panel : got;
        answered(before, mine);
        if (mine.note && mine.note.text && (!before || !before.note || before.note.at !== mine.note.at)) {
          status = 'No: ' + mine.note.text + '.'; statusKind = 'no'; pending = null;
        }
        // Creation just ended: the third pick landed and the server moved you.
        if (wasCreating && !mine.creating) {
          status = 'Off you go.'; statusKind = 'ok';
          setTimeout(function () { api.close(); }, 1200);
        }
        wasCreating = !!mine.creating;
      }
      if (root.className !== 'gone') { draw(); }
    }
  };

  window.thornswoodSkills = api;
  draw();
  tell('ready');
})();
