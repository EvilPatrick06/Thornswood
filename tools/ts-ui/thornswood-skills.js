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
  server opens this with two more sections, Home and Review. While creating
  every card is a soft choice: a click marks it on the page and sends
  nothing, another click replaces it, and the section list reads the choice
  in gold. Review, last in the list, shows every choice on one page and has
  the one button, Begin, lit once a home is chosen. Confirm sends them all,
  one pick each, profession, class, and the town last, because the town is
  the pick that ends creation on the server. A home is the one choice that
  has to be made before leaving the hall; class and profession can be left
  for later with the last card in each of those sections and picked in the
  world from this same panel, one Confirm at a time. There is no Close
  button while creating (Escape and K still shut it, and the server's
  reminder opens it again). The panel closes itself on the home's answer.

  NOTHING HERE DECIDES ANYTHING. It reads what the server says this character
  is and sends what was picked. Every rule in the rulebook, one class only,
  one profession, novice in your sister half, two secondary professions at
  most, ranks, spell points, is the server's to enforce. A client that decided
  any of it would be a client anybody could edit. What the server refuses
  comes back as a note under the panel, and as a line in the chat. "Choose
  later", a soft choice and a marked spell are marks on this page until
  Confirm in Review sends the choices; "later" and the spells are never
  sent, "later" is a mark on this
  page and nothing else, because leaving a choice unmade changes nothing.

  NOTHING REDRAWS FOR NOTHING, 20 September. The server writes the property
  on every answer, on every refresh and on every reminder while somebody is
  still choosing, so the same panel arrives again and again. The first cut
  tore the section list and the body down and rebuilt them on each arrival,
  and every click did the same, with 90 millisecond colour transitions on the
  rebuilt cards: the boxes flashed. Now draw() compares what it would draw
  with what it drew last, as JSON, and does nothing when they match; the
  status line is its own smaller redraw; and there are no transitions and no
  hover rules, for the same reason the character choice page has none (see
  thornswood-select.js: its first three cuts died the moment the mouse moved
  over them). The cursor still turns into a hand over anything clickable; a
  cursor rule restyles nothing.

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
      later: 'You can pick your class in the world, from this panel. One class, for good, when you do.',
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
      later: 'You can pick your profession in the world, from this panel.',
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
    /*
      The spell book. The names are Skyrim's own spells, sorted into the
      mage's four ranks (the game's Apprentice and Adept tiers both sit
      under Advanced). Not wired to the server yet, on Patrick's word of
      20 September: this is the shape of the page. The server does not know
      spells or spell points, so what is drawn comes from here, every spell
      reads as one you could take, and nothing is sent.
    */
    spells: {
      title: 'Spell book',
      lead: 'The spells of your two schools, by rank. A spell costs one point; points come with each rank.',
      ranks: [{ key: 'novice', name: 'Novice' }, { key: 'advanced', name: 'Advanced' },
              { key: 'expert', name: 'Expert' }, { key: 'master', name: 'Master' }],
      schools: {
        destruction: { novice: ['Flames', 'Frostbite', 'Sparks'],
                       advanced: ['Firebolt', 'Ice Spike', 'Lightning Bolt', 'Fireball', 'Ice Storm', 'Chain Lightning', 'Flame Cloak', 'Frost Cloak', 'Lightning Cloak'],
                       expert: ['Incinerate', 'Icy Spear', 'Thunderbolt', 'Wall of Flames', 'Wall of Frost', 'Wall of Storms'],
                       master: ['Fire Storm', 'Blizzard', 'Lightning Storm'] },
        restoration: { novice: ['Healing', 'Lesser Ward'],
                       advanced: ['Healing Hands', 'Fast Healing', 'Steadfast Ward', 'Turn Undead', 'Close Wounds', 'Heal Other', 'Greater Ward', 'Repel Lesser Undead'],
                       expert: ['Grand Healing', 'Circle of Protection', 'Repel Undead', 'Turn Greater Undead'],
                       master: ['Guardian Circle', 'Bane of the Undead'] },
        alteration:  { novice: ['Candlelight', 'Oakflesh'],
                       advanced: ['Magelight', 'Stoneflesh', 'Detect Life', 'Ironflesh', 'Telekinesis', 'Waterbreathing'],
                       expert: ['Ebonyflesh', 'Paralyze', 'Detect Dead'],
                       master: ['Dragonhide', 'Mass Paralysis'] },
        conjuration: { novice: ['Conjure Familiar', 'Raise Zombie', 'Bound Sword'],
                       advanced: ['Conjure Flame Atronach', 'Reanimate Corpse', 'Bound Battleaxe', 'Soul Trap', 'Conjure Frost Atronach', 'Banish Daedra', 'Revenant', 'Bound Bow'],
                       expert: ['Conjure Storm Atronach', 'Dread Zombie', 'Conjure Dremora Lord', 'Expel Daedra', 'Command Daedra'],
                       master: ['Dead Thrall', 'Flame Thrall', 'Frost Thrall', 'Storm Thrall'] },
        illusion:    { novice: ['Courage', 'Clairvoyance', 'Fury'],
                       advanced: ['Calm', 'Fear', 'Muffle', 'Frenzy', 'Rally', 'Invisibility'],
                       expert: ['Pacify', 'Rout', 'Call to Arms'],
                       master: ['Harmony', 'Hysteria', 'Mayhem'] }
      }
    },
    home: {
      title: 'Home',
      lead: 'Where you wake up. The inn keeps a room for you, and it is where you come back to.',
      rows: []   // the server sends the towns while you are new
    },
    review: {
      title: 'Review',
      lead: 'What you have chosen. Confirm sends all of it to the server and takes you to your inn. A profession without its half, or a mage short of two schools, is not sent; it can be picked in the world.',
      rows: []   // drawn from the choices, not from a table
    }
  };
  var REVIEW = DATA.review;   // kept beside a table the server might send without it

  /* The inn in each town, by the server's town key. Display only. */
  var INNS = {
    whiterun: 'The Bannered Mare', riften: 'The Bee and Barb', solitude: 'The Winking Skeever',
    windhelm: 'Candlehearth Hall', markarth: 'The Silver-Blood Inn', falkreath: 'Dead Man’s Drink',
    morthal: 'Moorside Inn', dawnstar: 'The Windpeak Inn', winterhold: 'The Frozen Hearth'
  };

  var RANK_NAMES = { novice: 'Novice', advanced: 'Advanced', expert: 'Expert', master: 'Master' };
  var CAP = 5;             // points that fill a skill; the server's LIMITS.skillCap, mirrored for the pips

  // ---------------------------------------------------------------- state --
  // Profession first, then class, then the tree, and the home last while
  // creating: Patrick's order, 20 September. The home is the last thing
  // because confirming it is what ends creation.
  var sections = ['profession', 'class', 'tree'];   // 'home' and 'review' are added while creating
  var section = 'profession';
  var rowAt = 0;
  var mine = null;         // what the server says this character is: the panel view
  var picked = {};         // section -> { row: key, subs: [keys] } chosen in the panel, not yet sent
  var later = {};          // section -> true when "Choose later" was clicked; this page's mark only
  var marked = {};         // spell name -> true, marked in the spell book; this page's mark only, nothing is sent
  var pending = [];        // picks sent and not yet answered, oldest first: [{ section, words, at }]
  var status = '';         // the line under the panel
  var statusKind = '';     // '' | 'ok' | 'no'
  var wasCreating = false;
  var closing = false;     // creation is over and the panel is on its way shut
  var tableGen = 0;        // bumped when a table arrives from the server, so a redraw is forced
  var drawnKey = '';       // JSON of what head, nav and body were last drawn from
  var footKey = '';        // the same for the foot

  // ------------------------------------------------------------------ css --
  /*
    No transitions and no :hover, on purpose; see the head of the file. The
    lit card is lit by a click or a key and nothing else.

    The panel is a fixed 1120 by 700 box for a 1920 by 1080 screen, scaled up
    by fit() on a bigger one, and never wider than the viewport less 24px a
    side on a smaller one. The flexible grid column is minmax(0,1fr) and every
    row spanning it has min-width:0, so nothing inside can push the foot past
    the panel's edge: the buttons sit inside the panel's padding whatever the
    status line says.
  */
  var css = [
    '#ts-skills{position:fixed;inset:0;z-index:2147483000;display:flex;align-items:center;justify-content:center;',
    'background:radial-gradient(ellipse at center,rgba(0,0,0,.50) 0%,rgba(0,0,0,.72) 100%);',
    'font-family:"Palatino Linotype",Palatino,Georgia,serif;color:#d9cfb4;user-select:none;pointer-events:auto}',
    '#ts-skills.gone{display:none}',
    '#ts-skills *{box-sizing:border-box}',
    '#ts-skills .panel{width:1120px;max-width:calc(100vw - 48px);height:700px;max-height:calc(100vh - 48px);display:grid;',
    'grid-template-columns:250px minmax(0,1fr);grid-template-rows:auto minmax(0,1fr) auto;',
    'background:rgba(11,10,8,.94);border:1px solid rgba(198,170,109,.42);outline:1px solid rgba(198,170,109,.14);outline-offset:4px;',
    'box-shadow:0 24px 80px rgba(0,0,0,.7);position:relative}',
    // head
    '#ts-skills .head{grid-column:1/3;min-width:0;display:flex;align-items:flex-end;justify-content:space-between;gap:32px;',
    'padding:22px 32px 16px;border-bottom:1px solid rgba(198,170,109,.22)}',
    '#ts-skills .eyebrow{font-size:11px;letter-spacing:.3em;text-transform:uppercase;color:rgba(198,170,109,.75);margin-bottom:6px}',
    '#ts-skills .title{font-size:26px;color:#f6e9c8;line-height:1.1;white-space:nowrap}',
    '#ts-skills .who{flex:0 1 560px;min-width:0;text-align:right;font-size:13.5px;color:#d9cfb4;line-height:1.5}',
    '#ts-skills .who .dim{color:rgba(217,207,180,.6);font-style:italic}',
    '#ts-skills .who .pts{color:#e9d19b}',
    // nav: the first row's text sits 22px under the head line, level with the body's lead,
    // and 32px in from the panel's edge, level with the head and the body
    '#ts-skills .nav{grid-column:1;min-width:0;border-right:1px solid rgba(198,170,109,.22);padding:8px 0;overflow:auto}',
    '#ts-skills .navrow{padding:14px 20px 13px 29px;border-left:3px solid transparent;cursor:pointer}',
    '#ts-skills .navrow.on{border-left-color:#e9d19b;background:rgba(120,94,44,.24)}',
    '#ts-skills .navrow .k{font-size:16px;color:#d9cfb4;letter-spacing:.02em}',
    '#ts-skills .navrow.on .k{color:#f6e9c8}',
    '#ts-skills .navrow .v{font-size:12.5px;color:rgba(217,207,180,.58);font-style:italic;margin-top:3px}',
    '#ts-skills .navrow .v.set{color:#9fcf92;font-style:normal}',
    '#ts-skills .navrow .v.need{color:#e9d19b}',
    '#ts-skills .navrow .v.chosen{color:#e9d19b;font-style:normal}',   // a soft choice while creating, gold like .tag.gold
    // body
    '#ts-skills .body{grid-column:2;min-width:0;padding:22px 32px 18px;overflow:auto}',
    '#ts-skills .lead{font-size:13.5px;line-height:1.55;color:rgba(217,207,180,.66);font-style:italic;margin:0 0 16px;max-width:680px}',
    '#ts-skills .cards{display:grid;grid-template-columns:1fr;gap:9px}',
    '#ts-skills .cards.three{grid-template-columns:repeat(3,1fr)}',
    '#ts-skills .card{border:1px solid rgba(198,170,109,.30);background:rgba(0,0,0,.20);padding:13px 18px 12px;position:relative;cursor:pointer}',
    '#ts-skills .card.at{border-color:rgba(233,209,155,.95);background:rgba(120,94,44,.34)}',
    '#ts-skills .card.mine{border-color:rgba(160,205,150,.8)}',
    '#ts-skills .card.off{opacity:.42}',
    '#ts-skills .card.later{border-style:dashed}',
    '#ts-skills .card .name{font-size:16.5px;color:#f6e9c8;display:flex;align-items:baseline;gap:12px}',
    '#ts-skills .card .desc{font-size:13px;line-height:1.5;color:rgba(217,207,180,.78);margin-top:4px}',
    '#ts-skills .card .inn{font-size:12.5px;color:rgba(217,207,180,.6);font-style:italic;margin-top:3px}',
    '#ts-skills .tag{margin-left:auto;font-size:10.5px;letter-spacing:.2em;text-transform:uppercase;color:#9fcf92;white-space:nowrap}',
    '#ts-skills .tag.gold{color:#e9d19b}',
    '#ts-skills .tag.dim{color:rgba(217,207,180,.5)}',
    // halves and schools inside an open profession card
    '#ts-skills .halves{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:11px}',
    '#ts-skills .halves.five{grid-template-columns:repeat(5,1fr)}',
    '#ts-skills .half{border:1px solid rgba(198,170,109,.32);padding:9px 12px;background:rgba(0,0,0,.22);cursor:pointer}',
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
    'padding:9px 6px 8px;border:1px solid transparent}',
    '#ts-skills .skill.at{border-color:rgba(233,209,155,.6);background:rgba(120,94,44,.18)}',
    '#ts-skills .skill .sn{font-size:15px;color:#f6e9c8}',
    '#ts-skills .skill .sd{grid-column:1/4;font-size:12px;color:rgba(217,207,180,.6);line-height:1.45;margin-top:3px}',
    '#ts-skills .skill .sd.lit{color:#e9d19b}',
    '#ts-skills .pips{display:flex;gap:4px}',
    '#ts-skills .pip{width:10px;height:10px;border:1px solid rgba(198,170,109,.55);background:rgba(0,0,0,.2)}',
    '#ts-skills .pip.lit{background:#c6aa6d;border-color:#e9d19b}',
    '#ts-skills .plus{width:26px;height:26px;border:1px solid rgba(198,170,109,.55);color:#e9d19b;display:grid;place-items:center;',
    'font-size:18px;line-height:1;background:rgba(0,0,0,.25);cursor:pointer}',
    '#ts-skills .plus.off{opacity:.25;pointer-events:none}',
    // foot: the hint on the left takes what is left and wraps; the buttons never shrink
    '#ts-skills .foot{grid-column:1/3;min-width:0;display:flex;align-items:center;justify-content:space-between;gap:24px;',
    'padding:14px 32px;border-top:1px solid rgba(198,170,109,.22)}',
    '#ts-skills .status{flex:1 1 auto;min-width:0;font-size:13.5px;line-height:1.4;color:rgba(217,207,180,.7);font-style:italic;min-height:1.4em}',
    '#ts-skills .status.ok{color:#9fcf92;font-style:normal}',
    '#ts-skills .status.no{color:#d9a27a;font-style:normal}',
    '#ts-skills .btns{flex:0 0 auto;display:flex;gap:10px;align-items:stretch}',
    '#ts-skills .tsbtn{display:inline-flex;align-items:center;justify-content:center;gap:10px;height:40px;padding:0 24px;',
    'border:1px solid rgba(198,170,109,.55);font-size:13px;letter-spacing:.14em;text-transform:uppercase;white-space:nowrap;',
    'color:#e9d19b;background:rgba(0,0,0,.25);font-family:inherit;cursor:pointer}',
    '#ts-skills .tsbtn.primary{background:#c6aa6d;border-color:#e9d19b;color:#1b1205}',
    '#ts-skills .tsbtn.primary.off{opacity:.35;pointer-events:none}',
    // The buttons are .tsbtn, not .btn, and the name matters: the front's own
    // stylesheet (build.js, in this same document) carries an unscoped .btn
    // rule with width 50px, height 50px and margin 20px. Our rules are scoped
    // under #ts-skills and win on every property they set, but a property
    // they do not set comes through from theirs, and on 20 September that
    // gave Confirm a 50px box with five letters showing. A class name nobody
    // else uses is the only rule that holds against a stylesheet we do not
    // write.
    // review, while creating: one row per choice, the key on the left
    '#ts-skills .review{max-width:680px;margin:2px 0 18px}',
    '#ts-skills .rrow{display:flex;align-items:baseline;gap:24px;padding:11px 0;border-bottom:1px solid rgba(198,170,109,.18)}',
    '#ts-skills .rrow .rk{flex:0 0 150px;font-size:11.5px;letter-spacing:.24em;text-transform:uppercase;color:rgba(198,170,109,.85)}',
    '#ts-skills .rrow .rv{flex:1 1 auto;min-width:0;font-size:16px;color:#f6e9c8}',
    '#ts-skills .rrow .rv.chosen{color:#e9d19b}',
    '#ts-skills .rrow .rv.set{color:#9fcf92}',
    '#ts-skills .rrow .rv.dim{color:rgba(217,207,180,.58);font-style:italic}',
    '#ts-skills .rrow .rv.need{color:#e9d19b;font-style:italic}',
    // the spell book
    '#ts-skills .spellbar{display:flex;justify-content:space-between;align-items:baseline;gap:16px;margin:0 0 12px}',
    '#ts-skills .spellpts{font-size:14px;color:#e9d19b}',
    '#ts-skills .spellnote{font-size:12px;font-style:italic;color:rgba(217,207,180,.55)}',
    '#ts-skills .spellcols{grid-template-columns:repeat(2,minmax(0,1fr))}',
    '#ts-skills .rankhead{font-size:11px;letter-spacing:.16em;text-transform:uppercase;color:rgba(217,207,180,.5);margin:10px 0 4px}',
    '#ts-skills .spell{display:flex;justify-content:space-between;align-items:center;gap:10px;padding:6px 10px;',
    'border:1px solid transparent;cursor:pointer}',
    '#ts-skills .spell.at{border-color:rgba(233,209,155,.7);background:rgba(120,94,44,.16)}',
    '#ts-skills .spell.on .spellname{color:#f6e9c8}',
    '#ts-skills .spell.mine .spellname{color:#9fcf92}',
    '#ts-skills .spellname{font-size:14px}',
    // the K, drawn as a key cap beside Close
    '#ts-skills .key{display:inline-flex;align-items:center;justify-content:center;min-width:22px;height:22px;padding:0 6px;',
    'border:1px solid rgba(233,209,155,.55);border-bottom-width:2px;border-radius:3px;background:rgba(0,0,0,.35);',
    'font-size:11px;letter-spacing:0;line-height:1;color:#e9d19b}'
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
        '<div class="tsbtn ghost" data-act="close"><span>Close</span><span class="key">K</span></div>' +
        '<div class="tsbtn primary" data-act="confirm">Confirm</div>' +
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

  /*
    Laid out for 1920x1080 and scaled up from there: at 3440x1440 the first
    cut was a postage stamp. The scale is the smaller of the two ratios, so
    the scaled box is at most 1120/1920 of the width and 700/1080 of the
    height, and never meets the edge: 1920x1080 and 2560x1080 draw it as is,
    3440x1440 draws it at 1.333 (1493 by 933), 2000x837 is below 1 and draws
    it as is, 700 tall in 837.
  */
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
  function isMage() {
    if (mine && mine.profession) return mine.profession === 'mage';
    // Nothing confirmed yet: the Mage card lit while creating counts, so the
    // book is there to read before the profession is sent.
    var p = picked.profession;
    return !!(creating() && p && p.row === 'mage');
  }
  /* The schools the spell book shows: the server's, or the ones lit on the Mage card. */
  function bookSchools() {
    if (mine && mine.profession) return mine.profession === 'mage' ? (mine.schools || []).slice() : [];
    var p = picked.profession;
    return (creating() && p && p.row === 'mage') ? (p.subs || []).slice() : [];
  }
  /*
    Spell points. The server's number when it sends one; until it does, a
    mage starts with two (Patrick, 20 September: "it should be 2"). A mark
    costs one, so no more can be marked than there are points, and the bar
    counts down. The real rule, points by rank and spells granted, is the
    server's and is still to come.
  */
  var STARTING_SPELL_POINTS = 2;
  function spellPoints() {
    if (mine && mine.spellPoints !== undefined && mine.spellPoints !== null) return Number(mine.spellPoints) || 0;
    return STARTING_SPELL_POINTS;
  }
  function markedCount() { var n = 0; for (var k in marked) if (marked[k]) n++; return n; }
  function pointsLeft() { return Math.max(0, spellPoints() - markedCount()); }
  /* Mark or unmark a spell; a mark needs a point. True when something changed. */
  function toggleMark(name) {
    if (marked[name]) { marked[name] = false; return true; }
    if (pointsLeft() <= 0) { status = 'No spell points left. Unmark one to mark another.'; statusKind = 'no'; return false; }
    marked[name] = true;
    return true;
  }
  function rows() { return DATA[section] ? DATA[section].rows : []; }
  function titleOf(sec) { return DATA[sec] ? DATA[sec].title : cap(sec); }
  function rowOf(sec, key) {
    var rs = DATA[sec] ? DATA[sec].rows : [];
    for (var i = 0; i < rs.length; i++) if (rs[i].key === key) return rs[i];
    return null;
  }

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

  /*
    "Choose later" is offered while creating, in Class and Profession, and
    only while that one is still unset. Home never has it: a home is the one
    choice that has to be made before leaving the hall. In the world there is
    no later to choose; the cards are there and they send as they always did.
  */
  function laterOffered(sec) {
    if (!creating()) return false;
    if (sec === 'class') return !haveClass();
    if (sec === 'profession') return !haveProf();
    return false;
  }
  /*
    Soft choices, while creating. A click marks a card on this page and
    sends nothing; Begin, in Review, sends them all. These read the marks,
    for the section list and for Review, and say whether a profession is
    whole: its half picked, or both schools for a mage.
  */
  function choose(sec, row, subs) { picked[sec] = { row: row, subs: subs || [] }; later[sec] = false; }
  function chooseLater(sec) { later[sec] = true; picked[sec] = null; }
  function softProf() {
    var p = picked.profession;
    var r = (p && p.row) ? rowOf('profession', p.row) : null;
    if (!r) return null;
    var want = r.pick || 1;
    var subs = (p.subs || []).map(function (h) { return nameOf('profession', h); });
    if (subs.length >= want) return { t: r.name + ', ' + subs.join(' and '), c: 'chosen', whole: true };
    return { t: r.name + ', ' + (want > 1 ? subs.length + ' of ' + want + ' schools' : 'no half yet'), c: 'need', whole: false };
  }
  function softClass() {
    var p = picked['class'];
    var r = (p && p.row) ? rowOf('class', p.row) : null;
    return r ? { t: r.name, c: 'chosen' } : null;
  }
  function softHome() {
    var p = picked.home;
    var towns = (mine && mine.towns) || [];
    for (var i = 0; i < towns.length; i++) {
      if (p && towns[i].key === p.row) return { t: towns[i].name, inn: INNS[p.row] || '', c: 'chosen' };
    }
    return null;
  }
  function countRows() {
    if (section === 'home') return ((mine && mine.towns) || []).length;
    if (section === 'tree') return 15;
    if (section === 'spells') return bookRows().length;
    return rows().length + (laterOffered(section) ? 1 : 0);
  }
  /* Another section: the top row, and the status line back to the hint. */
  function goTo(sec) { section = sec; rowAt = 0; status = ''; statusKind = ''; }

  // ------------------------------------------------------------------ draw --
  /*
    Everything head, nav and body are drawn from, as one string. The note is
    left out: it only ever reaches the status line, and a refusal must not
    tear the cards down. When the string is the one drawn last, nothing is
    touched, which is what makes the server's repeated writes invisible.
  */
  function viewKey() {
    var v = null;
    if (mine) { v = {}; for (var k in mine) if (k !== 'note') v[k] = mine[k]; }
    return JSON.stringify([tableGen, sections, section, rowAt, picked, later, marked, v]);
  }

  function draw() {
    // A mage gets the spell book, between Profession and Class, the moment
    // Mage is the profession: confirmed by the server, or still lit on the
    // Profession card while creating. Home and Review are creation's own.
    sections = creating() ? ['profession', 'class', 'tree', 'home', 'review'] : ['profession', 'class', 'tree'];
    if (isMage()) sections.splice(1, 0, 'spells');
    if (sections.indexOf(section) < 0) section = sections[0];
    var n = countRows();
    if (rowAt >= n) rowAt = n ? n - 1 : 0;
    if (rowAt < 0) rowAt = 0;
    var key = viewKey();
    if (key !== drawnKey) {
      drawnKey = key;
      drawHead();
      drawNav();
      drawBody();
    }
    drawFoot();
  }

  function drawHead() {
    if (creating()) {
      elTitle.textContent = 'Begin your life in Thornswood';
      elWho.textContent = '';
      elWho.appendChild(el('div', '', 'Choose a home. Your class and profession can be chosen here too, or later in the world. Nothing is sent until you press Confirm in Review.'));
      return;
    }
    elTitle.textContent = DATA[section] ? DATA[section].title : '';
    elWho.textContent = '';
    var s = summary();
    elWho.appendChild(el('div', s ? '' : 'dim', s || 'Nothing chosen yet. Class and profession are picked once, here, and never changed.'));
    var rk = topRank();
    var pts = mine ? Number(mine.points) || 0 : 0;
    var line2 = el('div', 'dim');
    if (rk) line2.appendChild(document.createTextNode(RANK_NAMES[rk] || cap(rk)));
    if (rk && pts) line2.appendChild(document.createTextNode(' · '));
    if (pts) { var p = el('span', 'pts', pts + (pts === 1 ? ' point to spend' : ' points to spend')); line2.appendChild(p); }
    if (rk || pts) elWho.appendChild(line2);
  }

  /*
    The line under each section's name: what the server says you are (green),
    or while creating the soft choice (gold), or later, or choose one.
  */
  function navValue(sec) {
    var soft = null;
    if (sec === 'class') {
      if (haveClass()) return { t: nameOf('class', mine['class']), c: 'set' };
      soft = creating() ? softClass() : null;
      if (soft) return soft;
      return later[sec] ? { t: 'later', c: '' } : { t: 'choose one', c: 'need' };
    }
    if (sec === 'profession') {
      if (!haveProf()) {
        soft = creating() ? softProf() : null;
        if (soft) return { t: soft.t, c: soft.c };
        return later[sec] ? { t: 'later', c: '' } : { t: 'choose one', c: 'need' };
      }
      var halves = ownHalves().map(function (h) { return nameOf('profession', h); });
      return { t: nameOf('profession', mine.profession) + (halves.length ? ', ' + halves.join(' and ') : ''), c: 'set' };
    }
    if (sec === 'home') {
      if (haveHome()) return { t: cap(mine.home), c: 'set' };
      soft = softHome();
      return soft ? { t: soft.t, c: 'chosen' } : { t: 'choose one', c: 'need' };
    }
    if (sec === 'review') return (haveHome() || softHome()) ? { t: 'ready to begin', c: 'chosen' } : { t: 'needs a home', c: 'need' };
    if (sec === 'spells') {
      var sp = pointsLeft();
      var m = markedCount();
      return { t: sp ? sp + ' to spend' : (m ? m + ' marked' : 'nothing yet'), c: sp ? 'need' : '' };
    }
    var pts = mine ? Number(mine.points) || 0 : 0;
    var spent = 0;
    if (mine && mine.tree) for (var k in mine.tree) spent += Number(mine.tree[k]) || 0;
    return { t: pts ? pts + ' to spend' : (spent ? spent + ' spent' : 'nothing yet'), c: pts ? 'need' : '' };
  }

  function drawNav() {
    elNav.textContent = '';
    sections.forEach(function (sec) {
      var row = el('div', 'navrow' + (sec === section ? ' on' : ''));
      row.appendChild(el('div', 'k', titleOf(sec)));
      var v = navValue(sec);
      row.appendChild(el('div', 'v ' + v.c, v.t));
      row.onclick = function () { goTo(sec); draw(); };
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
    else if (section === 'spells') drawSpells();
    else if (section === 'review') drawReview();
    else drawTree();
  }

  /* Every spell the book shows, flat, for the keyboard: [{school, rank, name}]. */
  function bookRows() {
    var out = [];
    var schools = bookSchools();
    var book = DATA.spells;
    if (!book) return out;
    schools.forEach(function (sc) {
      var byRank = book.schools[sc];
      if (!byRank) return;
      book.ranks.forEach(function (r) {
        (byRank[r.key] || []).forEach(function (name) { out.push({ school: sc, rank: r.key, name: name }); });
      });
    });
    return out;
  }

  /*
    The spell book: one column per school, the spells under their rank,
    each with a mark that says have, marked, or could take. Have comes from
    the server once it sends spells (mine.spells); until then everything
    reads as one you could take, and a click marks it on this page only.
  */
  function drawSpells() {
    var schools = bookSchools();
    var book = DATA.spells;
    if (!schools.length) {
      elBody.appendChild(el('p', 'lead', 'Pick your two schools on the Profession card first. The book fills with their spells.'));
      return;
    }
    var pts = spellPoints();
    var have = (mine && mine.spells) || {};
    var n = markedCount();
    var leftPts = pointsLeft();
    var top = el('div', 'spellbar');
    top.appendChild(el('div', 'spellpts', leftPts + ' of ' + pts + (pts === 1 ? ' spell point' : ' spell points') + ' left' + (n ? ', ' + n + ' marked' : '')));
    top.appendChild(el('div', 'spellnote', 'Not sent to the server yet. What you mark here stays on this page.'));
    elBody.appendChild(top);
    var cols = el('div', 'cols spellcols');
    var idx = 0;
    schools.forEach(function (sc) {
      var col = el('div', 'col');
      col.appendChild(el('div', 'colhead', cap(sc)));
      var byRank = book.schools[sc] || {};
      book.ranks.forEach(function (r) {
        var names = byRank[r.key] || [];
        if (!names.length) return;
        col.appendChild(el('div', 'rankhead', r.name));
        names.forEach(function (name) {
          var i = idx++;
          var got = !!have[name];
          var row = el('div', 'spell' + (i === rowAt ? ' at' : '') + (got ? ' mine' : '') + (marked[name] ? ' on' : ''));
          row.appendChild(el('span', 'spellname', name));
          row.appendChild(el('span', 'tag' + (got ? '' : (marked[name] ? ' gold' : ' dim')), got ? 'yours' : (marked[name] ? 'marked' : 'could take')));
          row.onclick = function () {
            rowAt = i;
            if (!got) toggleMark(name);
            draw();
          };
          col.appendChild(row);
        });
      });
      cols.appendChild(col);
    });
    elBody.appendChild(cols);
  }

  /* The last card of Class and of Profession while creating. A click is the mark; nothing is sent. */
  function laterCard(wrap, sec, i) {
    var card = el('div', 'card later' + (i === rowAt ? ' at' : ''));
    var name = el('div', 'name', 'Choose later');
    if (later[sec]) name.appendChild(el('span', 'tag dim', 'left for later'));
    card.appendChild(name);
    card.appendChild(el('div', 'desc', DATA[sec].later || ''));
    card.onclick = function () { rowAt = i; chooseLater(sec); draw(); };
    wrap.appendChild(card);
  }
  /* The tag on a card you have picked: while creating the click is the choice, in the world Confirm sends it. */
  function chosenTag() { return el('span', 'tag gold', creating() ? 'chosen' : 'chosen, confirm below'); }

  function drawClass() {
    var wrap = el('div', 'cards');
    var have = haveClass();
    var p = picked['class'] || {};
    rows().forEach(function (r, i) {
      var isMine = have && mine['class'] === r.key;
      var card = el('div', 'card' + (i === rowAt ? ' at' : '') + (isMine ? ' mine' : '') + (have && !isMine ? ' off' : ''));
      var name = el('div', 'name', r.name);
      if (isMine) name.appendChild(el('span', 'tag', 'yours'));
      else if (p.row === r.key) name.appendChild(chosenTag());
      card.appendChild(name);
      card.appendChild(el('div', 'desc', r.desc));
      card.onclick = function () {
        rowAt = i;
        if (!have) choose('class', r.key, []);
        draw();
      };
      wrap.appendChild(card);
    });
    if (laterOffered('class')) laterCard(wrap, 'class', rows().length);
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
      else if (p.row === r.key && p.subs && p.subs.length) name.appendChild(chosenTag());
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
              choose('profession', r.key, cur);
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
        // A click on another card starts that card fresh: the half picked on
        // the last one, or the "later" mark, must not ride under this one and
        // go out when it is sent.
        var fresh = p.row !== r.key;
        if (fresh) choose('profession', r.key, []);
        if (rowAt !== i || fresh) { rowAt = i; draw(); }
      };
      wrap.appendChild(card);
    });
    if (laterOffered('profession')) laterCard(wrap, 'profession', rows().length);
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
      card.onclick = function () { rowAt = i; if (!haveHome()) choose('home', t.key, []); draw(); };
      wrap.appendChild(card);
    });
    if (!towns.length) elBody.appendChild(el('p', 'lead', 'The server has not sent the town list yet. Give it a moment.'));
    elBody.appendChild(wrap);
  }

  /*
    Review, the last section while creating: one row per choice, read from
    the same marks the section list reads, so the two never disagree. What
    the server already has (a class accepted before the home was refused,
    say) reads in green, a soft choice in gold, a later mark or nothing yet
    dim, and the home stands out until it is chosen.
  */
  function reviewRows() {
    var out = [];
    var soft = null;
    if (haveProf()) out.push({ k: 'Profession', v: navValue('profession').t, c: 'set' });
    else if ((soft = softProf())) out.push({ k: 'Profession', v: soft.t, c: soft.c });
    else out.push({ k: 'Profession', v: later.profession ? 'later' : 'not chosen yet', c: 'dim' });
    if (isMage()) {
      var m = 0; for (var mk in marked) if (marked[mk]) m++;
      out.push({ k: 'Spell book', v: m ? m + ' marked, not sent yet' : 'nothing marked yet', c: m ? 'chosen' : 'dim' });
    }
    if (haveClass()) out.push({ k: 'Class', v: nameOf('class', mine['class']), c: 'set' });
    else if ((soft = softClass())) out.push({ k: 'Class', v: soft.t, c: 'chosen' });
    else out.push({ k: 'Class', v: later['class'] ? 'later' : 'not chosen yet', c: 'dim' });
    if (haveHome()) out.push({ k: 'Home', v: cap(mine.home) + (INNS[mine.home] ? ', ' + INNS[mine.home] : ''), c: 'set' });
    else if ((soft = softHome())) out.push({ k: 'Home', v: soft.t + (soft.inn ? ', ' + soft.inn : ''), c: 'chosen' });
    else out.push({ k: 'Home', v: 'not chosen yet', c: 'need' });
    return out;
  }
  function drawReview() {
    var wrap = el('div', 'review');
    reviewRows().forEach(function (r) {
      var row = el('div', 'rrow');
      row.appendChild(el('div', 'rk', r.k));
      row.appendChild(el('div', 'rv' + (r.c ? ' ' + r.c : ''), r.v));
      wrap.appendChild(row);
    });
    elBody.appendChild(wrap);
    elBody.appendChild(el('p', 'lead', 'A home is the one thing that has to be chosen. The rest can wait for the world.'));
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

  /*
    The status line and the two buttons: three elements, set in place, never
    rebuilt. While creating the one button is Begin, under Review only, and
    there is no Close: Escape and K still shut the panel and the server's
    reminder brings it back. In the world Confirm sits under every section
    that sends, and Close is back.
  */
  function drawFoot() {
    var cr = creating();
    var can = canConfirm();
    var line = status || hint();
    var label = 'Confirm';
    var showConfirm = cr ? section === 'review' : (section !== 'tree' && section !== 'spells');
    var key = JSON.stringify([line, statusKind, can, label, showConfirm, cr]);
    if (key === footKey) return;
    footKey = key;
    elStatus.className = 'status' + (statusKind ? ' ' + statusKind : '');
    elStatus.textContent = line;
    elConfirm.className = 'tsbtn primary' + (can ? '' : ' off');
    elConfirm.textContent = label;
    elConfirm.style.display = showConfirm ? '' : 'none';
    elClose.style.display = cr ? 'none' : '';
  }

  function hint() {
    if (section === 'tree') return 'Press + on a skill to put a point in it.';
    if (section === 'spells') {
      if (!bookSchools().length) return 'The book needs your two schools.';
      return 'Click a spell to mark it. Spells are not sent to the server yet.';
    }
    if (section === 'review') {
      if (!(haveHome() || softHome())) return 'Pick a home first. Confirm sends everything you chose to the server.';
      return 'Confirm sends everything you chose to the server and takes you to your inn.';
    }
    // The later lines are creation's: the mark is only ever set there.
    if (section === 'class') {
      if (haveClass()) return 'Your class is set for good.';
      if (later['class']) return 'Class left for later. Pick one now if you would rather, or move on.';
      if (creating()) return 'Pick a class and move on, or choose later and pick it in the world. Nothing is sent until Confirm.';
      return 'Pick a class, then confirm. One class, for good.';
    }
    if (section === 'profession') {
      if (haveProf()) return 'Your profession is set. Ranks come from doing the work.';
      if (later.profession) return 'Profession left for later. Pick one and its half now if you would rather, or move on.';
      if (creating()) return 'Pick a profession and its half and move on, or choose later and pick it in the world. Nothing is sent until Confirm.';
      return 'Pick a profession and its half, then confirm.';
    }
    if (section === 'home') return haveHome() ? 'Home is set.' : 'Pick the town you will wake up in and move on to Review. A home is the one thing you must choose before you leave the hall.';
    return '';
  }

  // --------------------------------------------------------------- picks --
  /*
    While creating the one button is Begin, in Review, lit once a home is
    chosen. In the world Confirm sends the section's own pick: a class, or a
    profession with its half or both schools.
  */
  function canConfirm() {
    if (creating()) return section === 'review' && !!softHome();
    var p = picked[section];
    if (!p || !p.row) return false;
    if (section === 'class') return !haveClass();
    if (section === 'profession') {
      if (haveProf()) return false;
      var r = rowOf('profession', p.row);
      if (!r) return false;
      return (p.subs || []).length === (r.pick || 1);
    }
    return false;
  }

  /* One pick to the server, remembered until its answer or a refusal comes back. */
  function send(sec, words) {
    pending.push({ section: sec, words: words, at: Date.now() });
    tell('pick', words);
  }

  function confirm() {
    if (!canConfirm()) return;
    if (creating()) { begin(); return; }
    var p = picked[section];
    send(section, section === 'class' ? 'class ' + p.row : 'profession ' + p.row + ' ' + p.subs.join(','));
    status = 'Sent. The server is checking.'; statusKind = '';
    draw();
  }

  /*
    Begin, from Review while creating: every soft choice goes to the server
    now, one pick each, in the order profession, class, town. The town is
    last because the town is the pick that ends creation on the server, and
    anything sent after it would land in the world. Later marks and marked
    spells send nothing; the server never hears of them. What the server
    already has is not sent again, which is what a second Begin after a
    refused home relies on.
  */
  function begin() {
    var pf = softProf();
    if (pf && pf.whole && !haveProf()) send('profession', 'profession ' + picked.profession.row + ' ' + picked.profession.subs.join(','));
    if (softClass() && !haveClass()) send('class', 'class ' + picked['class'].row);
    send('home', 'town ' + picked.home.row);
    status = 'Sent. The server is checking.'; statusKind = '';
    draw();
  }

  function spend(skill) {
    if (!mine || !(Number(mine.points) > 0)) return;
    send('tree', 'spend ' + skill);
    status = 'Sent.'; statusKind = '';
    draw();
  }

  /* Creation is over: the panel shuts and forgets its marks. */
  function leave() { closing = false; status = ''; statusKind = ''; later = {}; api.close(); }

  /*
    The server answered by rewriting the property. Each pick in flight is
    cleared by its own answer, the thing it asked for now set, and says so;
    a refusal clears one by note (see refused). Confirm sends up to three at
    once and the server answers each with its own write, so the picks are
    read one at a time: a refused class must not swallow the home's answer,
    and only the home's own answer ends creation. A pick nothing answers in
    thirty seconds is dropped, so the list cannot grow for ever.
  */
  var PENDING_MS = 30000;
  function answered(before, after) {
    if (!pending.length) return;
    var keep = [];
    var now = Date.now();
    pending.forEach(function (p) {
      var done = true;
      if (p.section === 'class' && after['class'] && !(before && before['class'])) { status = nameOf('class', after['class']) + ' it is.'; statusKind = 'ok'; later['class'] = false; }
      else if (p.section === 'profession' && after.profession && !(before && before.profession)) { status = 'You are a ' + nameOf('profession', after.profession).toLowerCase() + ' now.'; statusKind = 'ok'; later.profession = false; }
      else if (p.section === 'home' && after.home && !(before && before.home)) {
        status = cap(after.home) + '. See you there.'; statusKind = 'ok';
        // The home is the pick that ends creation, so the panel goes now, on
        // the answer. It used to wait for the server's creating flag, which
        // is written after the move and reached the page halfway through the
        // loading screen, with the panel still up over it.
        if (creating() && !closing) { later = {}; closing = true; setTimeout(leave, 700); }
      }
      else if (p.section === 'tree') { status = 'Spent.'; statusKind = 'ok'; }
      else done = false;
      if (done) picked[p.section] = null;
      else if (now - p.at < PENDING_MS) keep.push(p);
    });
    pending = keep;
  }

  /*
    A refusal. The server writes one note per refused pick, in the order the
    picks arrived, so the oldest pick still in flight is the one it answers.
    The card stays as it was picked, so it can be sent again or replaced.
  */
  function refused(text) {
    status = 'No: ' + text + '.'; statusKind = 'no';
    if (pending.length) pending.shift();
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
    var n = countRows();
    if (e.key === 'Escape') { api.close(); e.preventDefault(); return; }
    if (e.key === 'Enter') {
      if (section === 'tree') {
        var flat = [];
        rows().forEach(function (a) { (a.subs || []).forEach(function (s) { flat.push(s.key); }); });
        if (flat[rowAt]) spend(flat[rowAt]);
      } else if (canConfirm()) { confirm(); }
      else {
        // Enter on a row picks it. While creating that is the choice, and
        // Enter in Review is Begin; in the world the second Enter confirms.
        if (section === 'spells') {
          var sr = bookRows()[rowAt];
          if (sr && !((mine && mine.spells) || {})[sr.name]) { toggleMark(sr.name); draw(); }
          e.preventDefault(); return;
        }
        var r = section === 'home' ? ((mine && mine.towns) || [])[rowAt] : rows()[rowAt];
        var pp = picked.profession;
        if (!r && rowAt === rows().length && laterOffered(section)) { chooseLater(section); draw(); }
        else if (r && section === 'class' && !haveClass()) { choose('class', r.key, []); draw(); }
        else if (r && section === 'home' && !haveHome()) { choose('home', r.key, []); draw(); }
        else if (r && section === 'profession' && creating() && !haveProf() && !(pp && pp.row === r.key)) { choose('profession', r.key, []); draw(); }
      }
      e.preventDefault(); return;
    }
    if (e.key === 'ArrowDown') { rowAt = n ? (rowAt + 1) % n : 0; draw(); e.preventDefault(); }
    else if (e.key === 'ArrowUp') { rowAt = n ? (rowAt + n - 1) % n : 0; draw(); e.preventDefault(); }
    else if (e.key === 'ArrowRight' || e.key === 'ArrowLeft') {
      var i = sections.indexOf(section);
      goTo(sections[(i + (e.key === 'ArrowRight' ? 1 : sections.length - 1)) % sections.length]);
      draw(); e.preventDefault();
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
      if (table && typeof table === 'object') { DATA = table; if (!DATA.review) DATA.review = REVIEW; tableGen++; }
      if (got && typeof got === 'object') {
        var before = mine;
        mine = (got.panel && typeof got.panel === 'object') ? got.panel : got;
        answered(before, mine);
        // A note is new when its time or its words changed: two refusals
        // from one Confirm can carry the same millisecond.
        if (mine.note && mine.note.text && (!before || !before.note || before.note.at !== mine.note.at || before.note.text !== mine.note.text)) refused(mine.note.text);
        // Creation just ended: the home was confirmed and the server moved
        // you. The panel keeps what it shows, says so, and shuts itself; the
        // marks for later are cleared, since in the world there is no later.
        if (wasCreating && !mine.creating && !closing) {
          status = 'Off you go.'; statusKind = 'ok';
          closing = true;
          setTimeout(leave, 700);
        }
        wasCreating = !!mine.creating;
      }
      if (root.className !== 'gone') {
        if (closing) { drawFoot(); } else { draw(); }
      }
    }
  };

  window.thornswoodSkills = api;
  draw();
  tell('ready');
})();
