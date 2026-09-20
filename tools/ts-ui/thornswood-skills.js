'use strict';
/*
  Profession, Class and Skill Tree, as an overlay inside the front.

  Same rule as the emote wheel next door: nothing calls loadUrl. There is one
  browser and one page, so a page of its own would replace the chat, the names
  above heads and the whole front. This mounts itself at the end of the body,
  where React is not looking, and hides rather than unmounts.

  THE LAYOUT IS PATRICK'S, from the template of 20 September. Three columns:

    left    three round tabs, PROFESSION / CLASS / TREE
    middle  the list for whichever tab is up
    right   the sub-choice for whichever middle row is highlighted, with a
            line drawn from that row across to it, and Confirm at the bottom

  The template is a black on white wireframe. The colours here are the ones
  every other Thornswood overlay already uses, because a white panel in the
  middle of them would be the only thing on screen that does not belong.

  NOTHING HERE DECIDES ANYTHING. It reads a table and sends what was picked.
  Every rule in the rulebook, one class only, one profession, novice in your
  sister half, two secondary professions at most, ranks, spell points, is the
  server's to enforce and none of it exists yet. A client that decided any of
  it would be a client anybody could edit.
*/

(function () {
  if (window.thornswoodSkills) return;

  // ------------------------------------------------------------ the table --
  /*
    From the rulebook of 20 September. Shipped as a default so the menu draws
    something on a client that has not heard from the server yet; setData
    replaces it wholesale the moment the server says otherwise, because the
    server owns this and a hardcoded copy is a copy that goes stale.
  */
  var DATA = {
    profession: {
      title: 'Profession',
      note: 'One profession, and one half of it. You know novice work of your sister half and nothing of anybody else’s.',
      rows: [
        { key: 'warrior', name: 'Warrior', subs: [
            { key: 'bulwark', name: 'Bulwark', note: 'Tanks, shields, heavy armour' },
            { key: 'berserker', name: 'Berserker', note: 'Damage, two handed, dual wield' }],
          perk: 'Warlord: teach novice combat to non-warriors, and master-tier maneuvers.' },
        { key: 'mage', name: 'Mage', pick: 2, subs: [
            { key: 'destruction', name: 'Destruction' },
            { key: 'restoration', name: 'Restoration' },
            { key: 'alteration', name: 'Alteration' },
            { key: 'conjuration', name: 'Conjuration' },
            { key: 'illusion', name: 'Illusion' }],
          perk: 'Archmage: a third school, and the authority to apprentice non-mages.' },
        { key: 'alchemist', name: 'Alchemist', subs: [
            { key: 'blightbrewer', name: 'Blightbrewer', note: 'Poisons and harm' },
            { key: 'physicker', name: 'Physicker', note: 'Medicine and restoration' }],
          perk: 'Master Chemist: two potions per batch.' },
        { key: 'cook', name: 'Cook', subs: [
            { key: 'hearthcook', name: 'Hearthcook', note: 'Dinners, meats, stews' },
            { key: 'confectioner', name: 'Confectioner', note: 'Desserts, breads, sweets' }],
          perk: 'Grand Chef: two food per batch.' },
        { key: 'smith', name: 'Smith', subs: [
            { key: 'platewright', name: 'Platewright', note: 'Armour' },
            { key: 'edgewright', name: 'Edgewright', note: 'Weapons' }],
          perk: 'Mastercraft: temper to Legendary, past normal limits.' },
        { key: 'enchanter', name: 'Enchanter', subs: [
            { key: 'bladebinder', name: 'Bladebinder', note: 'Weapon enchantments' },
            { key: 'wardweaver', name: 'Wardweaver', note: 'Armour and apparel' }],
          perk: 'Twin Souls: two enchantments on one item.' },
        { key: 'tailor', name: 'Tailor', subs: [
            { key: 'liverywright', name: 'Liverywright', note: 'Robes, uniforms, faction dress' },
            { key: 'haberdasher', name: 'Haberdasher', note: 'Common and fine clothing' }],
          perk: 'Master Weaver: clothing gives hidden armour or weather protection, without the weight.' },
        { key: 'woodworker', name: 'Woodworker', subs: [
            { key: 'charburner', name: 'Charburner', note: 'Firewood, coke, campfires' },
            { key: 'woodwright', name: 'Woodwright', note: 'Bows, arrows, instruments' }],
          perk: 'Master Carver: campfires and kilns give maximum warmth.' }
      ]
    },
    'class': {
      title: 'Class',
      note: 'One class, and it is the only way its work enters the world. No perks, no teaching, no second one.',
      rows: [
        { key: 'hunter', name: 'Hunter', only: 'The only class that can loot an animal body.' },
        { key: 'fisher', name: 'Fisher', only: 'The only class that can catch fish.' },
        { key: 'gatherer', name: 'Gatherer', only: 'The only class that can harvest flora and materials out of the world.' },
        { key: 'miner', name: 'Miner', only: 'The only class that can mine ore veins.' },
        { key: 'farmer', name: 'Farmer', only: 'The only class that can plant and harvest crops.' }
      ]
    },
    tree: {
      title: 'Tree',
      note: 'Fifteen sub-skills. Maxing one grants its master perk.',
      rows: [
        { key: 'health', name: 'Health', subs: [
            { key: 'vitality', name: 'Vitality', note: 'Max health', perk: 'Cheat Death: once a day a fatal blow leaves you at 1 HP.' },
            { key: 'fortitude', name: 'Fortitude', note: 'Regeneration', perk: 'Troll’s Blood: regeneration is not stunted in combat.' },
            { key: 'might', name: 'Might', note: 'Melee damage', perk: 'Devastating Blow: power attacks often stagger or knock down.' },
            { key: 'resilience', name: 'Resilience', note: 'Armour rating', perk: 'Unshakeable: immune to stagger while blocking.' },
            { key: 'toughness', name: 'Toughness', note: 'Poison and disease', perk: 'Purified Blood: immune to disease, 75% poison resistance.' }] },
        { key: 'magicka', name: 'Magicka', subs: [
            { key: 'capacity', name: 'Capacity', note: 'Max magicka', perk: 'Archmage’s Vessel: a burst of regeneration below 10%.' },
            { key: 'clarity', name: 'Clarity', note: 'Regeneration', perk: 'Leyline Attunement: full regeneration while casting.' },
            { key: 'potency', name: 'Potency', note: 'Spell effect', perk: 'Overcharge: 15% chance of double damage or duration.' },
            { key: 'ward', name: 'Ward', note: 'Magic resistance', perk: 'Spellbreaker: 25% chance to absorb a spell and refill magicka.' },
            { key: 'efficiency', name: 'Efficiency', note: 'Cost', perk: 'Font of Magic: once a day, all spells free for 15 seconds.' }] },
        { key: 'stamina', name: 'Stamina', subs: [
            { key: 'endurance', name: 'Endurance', note: 'Max stamina', perk: 'Tireless: sprinting and power attacks drain half as much.' },
            { key: 'vigor', name: 'Vigor', note: 'Regeneration', perk: 'Second Wind: full stamina the instant it empties, five minute cooldown.' },
            { key: 'agility', name: 'Agility', note: 'Speed', perk: 'Windwalker: 10% faster, and no fall damage.' },
            { key: 'burden', name: 'Burden', note: 'Carry weight', perk: 'Pack Mule: no speed penalty up to 50 lbs over.' },
            { key: 'precision', name: 'Precision', note: 'Critical and ranged', perk: 'Lethal Aim: ranged attacks ignore half of physical armour.' }] }
      ]
    }
  };

  var TABS = ['profession', 'class', 'tree'];
  var tab = 'profession';
  var rowAt = 0;
  var chosen = {};        // what the server says this character already is
  var picked = {};        // what is selected in the panel right now

  // ------------------------------------------------------------------ css --
  var css = [
    '#ts-skills{position:fixed;inset:0;z-index:2147483000;display:flex;',
    'align-items:center;justify-content:center;pointer-events:none;',
    'font-family:"Palatino Linotype",Palatino,Georgia,serif;user-select:none}',
    '#ts-skills.gone{display:none}',
    '#ts-skills .panel{pointer-events:auto;width:min(1180px,92vw);height:min(660px,88vh);',
    'display:grid;grid-template-columns:186px 1fr 1fr;gap:0;',
    'background:rgba(14,13,11,.80);border:1px solid rgba(198,170,109,.45);',
    'box-shadow:0 18px 60px rgba(0,0,0,.55);position:relative}',
    '#ts-skills .rail{border-right:1px solid rgba(198,170,109,.28);display:flex;',
    'flex-direction:column;align-items:center;justify-content:space-around;padding:22px 0}',
    '#ts-skills .tab{width:118px;height:118px;border-radius:50%;display:grid;place-items:center;',
    'border:1.5px solid rgba(198,170,109,.42);color:#c6aa6d;font-size:15px;letter-spacing:.06em;',
    'cursor:pointer;text-align:center;padding:0 10px;transition:all 110ms linear;background:transparent}',
    '#ts-skills .tab:hover{border-color:rgba(233,209,155,.8);color:#e9d19b}',
    '#ts-skills .tab.on{background:rgba(120,94,44,.42);border-color:rgba(233,209,155,.95);color:#f6e9c8}',
    '#ts-skills .mid,#ts-skills .right{padding:20px 18px;overflow-y:auto;display:flex;',
    'flex-direction:column;gap:9px}',
    '#ts-skills .right{border-left:1px solid rgba(198,170,109,.28);position:relative}',
    '#ts-skills .note{color:rgba(217,207,180,.62);font-size:12.5px;line-height:1.45;',
    'margin:0 0 4px;font-style:italic}',
    '#ts-skills .item{border:1px solid rgba(198,170,109,.34);color:#d9cfb4;font-size:16px;',
    'padding:13px 16px;cursor:pointer;background:rgba(0,0,0,.18);transition:all 100ms linear;',
    'display:flex;align-items:baseline;gap:10px;flex:none}',
    '#ts-skills .item:hover{border-color:rgba(233,209,155,.75);background:rgba(120,94,44,.22)}',
    '#ts-skills .item.at{border-color:rgba(233,209,155,.95);background:rgba(120,94,44,.40);color:#f6e9c8}',
    '#ts-skills .item.picked{border-color:rgba(160,205,150,.85)}',
    '#ts-skills .item .sub{color:rgba(217,207,180,.55);font-size:12px;font-style:italic}',
    '#ts-skills .item .tick{color:#9fcf92;font-size:13px;margin-left:auto}',
    '#ts-skills .perk{color:rgba(198,170,109,.8);font-size:12.5px;line-height:1.5;',
    'border-top:1px solid rgba(198,170,109,.22);padding-top:10px;margin-top:2px}',
    '#ts-skills .confirm{margin-top:auto;align-self:flex-end;border:1px solid rgba(198,170,109,.6);',
    'color:#e9d19b;font-size:16px;padding:11px 34px;cursor:pointer;background:rgba(0,0,0,.25);',
    'transition:all 110ms linear;flex:none}',
    '#ts-skills .confirm:hover{background:rgba(120,94,44,.5);border-color:rgba(233,209,155,.95);color:#f6e9c8}',
    '#ts-skills .confirm.off{opacity:.35;cursor:default}',
    '#ts-skills .confirm.off:hover{background:rgba(0,0,0,.25);border-color:rgba(198,170,109,.6);color:#e9d19b}',
    '#ts-skills .link{position:absolute;height:1px;background:rgba(233,209,155,.75);',
    'pointer-events:none;transition:top 110ms linear}',
    '#ts-skills .hint{position:absolute;left:0;right:0;bottom:-26px;text-align:center;',
    'color:rgba(198,170,109,.55);font-size:12px}'
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
      '<div class="rail"></div>' +
      '<div class="mid"></div>' +
      '<div class="right"></div>' +
      '<div class="link" style="display:none"></div>' +
      '<div class="hint">K closes this</div>' +
    '</div>';
  document.body.appendChild(root);

  var elRail = root.querySelector('.rail');
  var elMid = root.querySelector('.mid');
  var elRight = root.querySelector('.right');
  var elLink = root.querySelector('.link');
  var elPanel = root.querySelector('.panel');

  function tell(what, extra) {
    try {
      window.skyrimPlatform.sendMessage('thornswood-front',
        'skills:' + what + (extra ? ' ' + extra : ''));
    } catch (e) { }
  }

  function el(tag, cls, text) {
    var d = document.createElement(tag);
    if (cls) d.className = cls;
    if (text !== undefined) d.textContent = text;
    return d;
  }

  // ---------------------------------------------------------------- draw --
  function drawRail() {
    elRail.textContent = '';
    TABS.forEach(function (t) {
      var d = el('div', 'tab' + (t === tab ? ' on' : ''),
                 t === 'profession' ? 'PROFESSION' : DATA[t].title);
      d.onclick = function () { tab = t; rowAt = 0; draw(); };
      elRail.appendChild(d);
    });
  }

  function rows() { return (DATA[tab] && DATA[tab].rows) || []; }

  function drawMid() {
    elMid.textContent = '';
    var note = DATA[tab] && DATA[tab].note;
    if (note) { elMid.appendChild(el('p', 'note', note)); }
    rows().forEach(function (r, i) {
      var d = el('div', 'item' + (i === rowAt ? ' at' : '') +
                        (chosen[tab] === r.key ? ' picked' : ''));
      d.appendChild(el('span', '', r.name));
      if (chosen[tab] === r.key) { d.appendChild(el('span', 'tick', 'yours')); }
      d.onclick = function () { rowAt = i; draw(); };
      elMid.appendChild(d);
    });
  }

  function drawRight() {
    elRight.textContent = '';
    var r = rows()[rowAt];
    if (!r) { elLink.style.display = 'none'; return; }

    if (r.only) {
      // A class has no halves. It has one sentence and it is the whole rule.
      elRight.appendChild(el('p', 'note', r.only));
    }

    var subs = r.subs || [];
    var want = r.pick || 1;
    subs.forEach(function (s) {
      var mine = (picked[tab + ':' + r.key] || []).indexOf(s.key) !== -1;
      var d = el('div', 'item' + (mine ? ' picked' : ''));
      d.appendChild(el('span', '', s.name));
      if (s.note) { d.appendChild(el('span', 'sub', s.note)); }
      if (mine) { d.appendChild(el('span', 'tick', '✓')); }
      d.onclick = function () { choose(r, s, want); };
      elRight.appendChild(d);
    });

    if (r.perk) { elRight.appendChild(el('div', 'perk', 'Master perk. ' + r.perk)); }
    var at = (picked[tab + ':' + r.key] || []);
    if (subs.length && want > 1) {
      elRight.appendChild(el('div', 'perk', 'Choose ' + want + '. ' + at.length + ' chosen.'));
    }
    if (r.subs && r.subs.length && r.subs[0].perk) {
      // The tree's right column is fifteen sub-skills, each with its own perk.
      elRight.textContent = '';
      subs.forEach(function (s) {
        var d = el('div', 'item');
        d.appendChild(el('span', '', s.name));
        if (s.note) { d.appendChild(el('span', 'sub', s.note)); }
        elRight.appendChild(d);
        elRight.appendChild(el('div', 'perk', s.perk));
      });
    }

    var ok = el('div', 'confirm' + (canConfirm(r, want) ? '' : ' off'), 'Confirm');
    ok.onclick = function () { confirm(r, want); };
    elRight.appendChild(ok);

    drawLink();
  }

  function canConfirm(r, want) {
    if (tab === 'tree') { return false; }           // nothing to spend yet
    if (!r.subs || !r.subs.length) { return true; } // a class is its own answer
    return (picked[tab + ':' + r.key] || []).length === want;
  }

  function choose(r, s, want) {
    var id = tab + ':' + r.key;
    var list = picked[id] || (picked[id] = []);
    var at = list.indexOf(s.key);
    if (at !== -1) { list.splice(at, 1); }
    else {
      if (list.length >= want) { list.shift(); }   // oldest out, newest in
      list.push(s.key);
    }
    draw();
  }

  function confirm(r, want) {
    if (!canConfirm(r, want)) { return; }
    var list = picked[tab + ':' + r.key] || [];
    tell('pick', tab + ' ' + r.key + (list.length ? ' ' + list.join(',') : ''));
    // Nothing is marked as yours here. The server says what somebody is, and
    // it says so by sending the table back. A client that ticked its own box
    // would be a client that disagrees with the server the moment one is
    // refused.
  }

  /* The line from the highlighted middle row across to the right column, which
     is the one piece of the template that is not a box. */
  function drawLink() {
    var at = elMid.querySelector('.item.at');
    if (!at) { elLink.style.display = 'none'; return; }
    var p = elPanel.getBoundingClientRect();
    var b = at.getBoundingClientRect();
    var r = elRight.getBoundingClientRect();
    elLink.style.display = '';
    elLink.style.top = Math.round(b.top - p.top + b.height / 2) + 'px';
    elLink.style.left = Math.round(b.right - p.left) + 'px';
    elLink.style.width = Math.max(0, Math.round(r.left - b.right)) + 'px';
  }

  function draw() { drawRail(); drawMid(); drawRight(); }

  // --------------------------------------------------------------- keys --
  /*
    Arrow keys and Enter, because the mouse is not always where somebody left
    it and the panel is a list. Escape closes. Everything else is left alone:
    this page is shared with the chat, and swallowing keys it does not own is
    how the chat box lost the keyboard before.
  */
  function onKey(e) {
    if (root.className === 'gone') { return; }
    var n = rows().length;
    if (e.key === 'Escape') { api.close(); e.preventDefault(); return; }
    if (e.key === 'ArrowDown') { rowAt = n ? (rowAt + 1) % n : 0; draw(); e.preventDefault(); }
    else if (e.key === 'ArrowUp') { rowAt = n ? (rowAt + n - 1) % n : 0; draw(); e.preventDefault(); }
    else if (e.key === 'ArrowRight' || e.key === 'ArrowLeft') {
      var i = TABS.indexOf(tab);
      tab = TABS[(i + (e.key === 'ArrowRight' ? 1 : TABS.length - 1)) % TABS.length];
      rowAt = 0; draw(); e.preventDefault();
    }
  }
  window.addEventListener('keydown', onKey, true);
  window.addEventListener('resize', function () { if (root.className !== 'gone') drawLink(); });

  // ---------------------------------------------------------------- api --
  var api = {
    open: function () {
      root.className = '';
      draw();
      // The link needs a layout pass before it can be measured.
      setTimeout(drawLink, 0);
      tell('opened');
    },
    close: function () {
      root.className = 'gone';
      tell('closed');
    },
    toggle: function () {
      if (root.className === 'gone') { api.open(); } else { api.close(); }
    },
    isOpen: function () { return root.className !== 'gone'; },
    /* The server's copy of the table, and what this character already is.
       Both replace what is here rather than merging, because a merge would
       keep a row the server has removed. */
    setData: function (table, mine) {
      if (table && typeof table === 'object') { DATA = table; }
      if (mine && typeof mine === 'object') { chosen = mine; }
      picked = {};
      if (root.className !== 'gone') { draw(); }
    }
  };

  window.thornswoodSkills = api;
  draw();
  tell('ready');
})();
