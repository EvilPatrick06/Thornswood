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
  something sends them: Confirm in Review while creating, Learn in the spell
  book in the world. "later" is never sent and is a mark on this page and
  nothing else, because leaving a choice unmade changes nothing.

  THE SPELLS ARE REAL NOW, 20 September. A marked spell used to be a mark and
  no more. It is a pick like any other: Learn sends one 'skills:pick spell
  <name>' per mark and waits, and in creation the marks go out with Confirm
  in Review, after the profession, because a spell needs the profession that
  owns it. What is yours, how many points you hold and your rank in each
  school are read from what the server sent and are never worked out here.

  NOTHING REDRAWS FOR NOTHING, 20 September. The server writes the property
  on every answer, on every refresh and on every reminder while somebody is
  still choosing, so the same panel arrives again and again. The first cut
  tore the section list and the body down and rebuilt them on each arrival,
  and every click did the same, with 90 millisecond colour transitions on the
  rebuilt cards: the boxes flashed. Now draw() compares what it would draw
  with what it drew last, as JSON, and does nothing when they match; the
  status line and the work counters on the progress lines are each their own
  smaller redraw, written in place; and there are no transitions and no
  hover rules, for the same reason the character choice page has none (see
  thornswood-select.js: its first three cuts died the moment the mouse moved
  over them). The cursor still turns into a hand over anything clickable; a
  cursor rule restyles nothing.

  THE CONTRACT with thornswood-front.js, unchanged from the first cut:
    window.thornswoodSkills = { open, close, toggle, isOpen, setData }
    page -> plugin  'skills:ready' | 'skills:opened' | 'skills:closed' |
                    'skills:refresh' | 'skills:pick <words>'
    the plugin turns 'skills:pick X' into the chat line '/pick X'

  THE CONTRACT with the server, agreed 20 September, written down here
  because the two halves were written at the same time and did not match, so
  nothing drew. What setData is handed is the whole stored state with this
  panel's view nested under .panel, and these are the fields this page reads:

    progress: { '<key>': { next: '<the rank being climbed to>',
                           done: <number>, need: <number> } }
      One entry per half, school or class verb that can still climb, under
      the same keys as ranks. A key at master, or one that cannot climb, is
      left out entirely rather than sent with a null, and the whole field is
      left out when there is nothing to say.

    note: { text: '<the refusal, in plain words>', at: <ms>,
            about: '<class|profession|spell|town|spend>' }
      about says which pick the refusal answers, so the panel clears that
      pick and only that one. A note with no about is still shown.

    book: { halves: [ { key, name, how, rank, open, total,
                        families: [ { name, open, total } ], why } ],
            none: '<sentence>' }
      The recipe book, counted by the server out of its own recipe table. how
      is 'own', 'sister' or 'taught'. why replaces families when there is
      nothing open, and none replaces the halves when there are none. The
      field is left out entirely for a mage with no craft half taught to
      them, and while creating, and the section is not drawn without it.

    spells: { '<spell name>': true }     what the character actually holds
    spellPoints: <number>                what is left to spend
    tree: { '<sub-skill key>': <0..5> }  points in the tree, placed and spent
    points: <number>                     free tree points
    placed: { '<sub-skill key>': <0..5> } the part of tree that was placed at
                                          creation and cannot be moved
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
            { key: 'potency', name: 'Potency', desc: 'Spell effect, in the schools you hold', perk: 'Overcharge: one spell in seven lands double.' },
            { key: 'ward', name: 'Ward', desc: 'Magic resistance', perk: 'Spellbreaker: one spell in four is absorbed and refills you.' },
            { key: 'efficiency', name: 'Efficiency', desc: 'Cost, in the schools you hold', perk: 'Font of Magic: once a day, fifteen seconds of free casting.' }] },
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
      under Advanced). The list of names is this page's; everything about a
      person is the server's. Which spells are yours comes from mine.spells,
      how many points you hold from mine.spellPoints, and the rank in each
      school from mine.ranks. A spell the server lists is drawn as yours and
      cannot be unmarked; the rest are marks until they are sent.
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
    /*
      The recipe book. Everything in it is the server's: this table holds the
      title and the one sentence over the page and nothing else, because what
      a half can make is read out of the game's own records by
      tools\Build-RecipeTable.ps1 and counted by the server, and a list of
      families typed here would be a second opinion nobody asked for.

      It is counts and not a list on purpose. The server's table holds 1,728
      recipes and this page is a browser drawn over a running Skyrim, so what
      arrives is the families and how many of each are open. Patrick, 21
      September: "don't be very specific because for like tailor there are
      hundreds of clothing items".
    */
    recipes: {
      title: 'Recipe book',
      /*
        The lead names the rule and not a rank. It said "the novice work of
        your sister half" until 21 September, which is the same wrong copy
        howYouHoldIt was keeping: a sister half climbs when a Master of it
        takes somebody on, and the server sends the rank it actually holds
        them at. Each column says how far its own half goes, read off what
        arrived, so this line has no business naming a rung.
      */
      lead: 'What you can make right now, by the kind of thing it is. Your own half, your sister half, and anything a Master taught you, each as far as your rank in it reaches. Recipes Skyrim keeps behind a perk, a spell or something you have to be holding are not counted as open.',
      rows: []   // the server sends the halves and their families
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
  var progRows = [];       // the value half of each progress line on the page, in order
  var progKey = '';        // the same for those lines: their words, so a tick writes once

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
    '#ts-skills .card.at{border-color:rgba(198,170,109,.55);box-shadow:inset 3px 0 0 0 #c6aa6d}',
    '#ts-skills .card.mine{border-color:rgba(160,205,150,.85);background:rgba(120,170,115,.13)}',
    '#ts-skills .card.off{opacity:.42}',
    '#ts-skills .card.chosen{border-color:#e9d19b;background:rgba(201,162,75,.16)}',
    '#ts-skills .spell.on{background:rgba(201,162,75,.16)}',
    '#ts-skills .spell.mine{background:rgba(120,170,115,.11)}',
    '#ts-skills .skill.full{background:rgba(120,170,115,.11)}',
    '#ts-skills .skill.full .sn{color:#9fcf92}',
    '#ts-skills .skill.full .pip.lit{background:#7fb877;border-color:#9fcf92}',
    '#ts-skills .skill.some .pip.lit{background:#c6aa6d;border-color:#e9d19b}',
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
    '#ts-skills .half.on{border-color:#e9d19b;background:rgba(201,162,75,.20)}',
    '#ts-skills .half.mine{border-color:rgba(160,205,150,.85);background:rgba(120,170,115,.13)}',
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
    '#ts-skills .skill.at{border-color:transparent;box-shadow:inset 3px 0 0 0 rgba(198,170,109,.75)}',
    '#ts-skills .skill .sn{font-size:15px;color:#f6e9c8}',
    '#ts-skills .skill .sd{grid-column:1/4;font-size:12px;color:rgba(217,207,180,.6);line-height:1.45;margin-top:3px}',
    '#ts-skills .skill .sd.lit{color:#9fcf92}',
    '#ts-skills .pips{display:flex;gap:4px}',
    '#ts-skills .pip{width:10px;height:10px;border:1px solid rgba(198,170,109,.55);background:rgba(0,0,0,.2)}',
    '#ts-skills .pip.lit{background:#c6aa6d;border-color:#e9d19b}',
    // A point that came with your class or profession rather than one you
    // spent: green, which in this panel is what is already yours. Written at
    // the same weight as the .some and .full pip rules above and after them,
    // so it wins the tie whatever the rest of the row is.
    '#ts-skills .skill.some .pip.given,#ts-skills .skill.full .pip.given,#ts-skills .skill .pip.given{',
    'background:#7fb877;border-color:#9fcf92}',
    // how far off the next rank is, one line per half, above the tree. Words
    // and a number, never a bar: a bar with no number on it says nothing.
    '#ts-skills .progress{max-width:680px;margin:0 0 16px;padding-bottom:12px;border-bottom:1px solid rgba(198,170,109,.18)}',
    '#ts-skills .prow{display:flex;align-items:baseline;gap:18px;padding:4px 0}',
    '#ts-skills .prow .pk{flex:0 0 150px;font-size:11.5px;letter-spacing:.24em;text-transform:uppercase;color:rgba(198,170,109,.85)}',
    '#ts-skills .prow .pv{flex:1 1 auto;min-width:0;font-size:14px;color:#d9cfb4}',
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
    // Close Skyrim once it is armed, the colours of the character page's own
    // Close the game when it asks the second time (thornswood-select.js).
    '#ts-skills .tsbtn.danger{border-color:#e9a27a;color:#f6c9b0;background:rgba(120,40,30,.45)}',
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
    // the school's name on the left, the server's rank in it on the right
    '#ts-skills .spellcols .colhead{display:flex;align-items:baseline;justify-content:space-between;gap:10px}',
    '#ts-skills .rankhead{font-size:11px;letter-spacing:.16em;text-transform:uppercase;color:rgba(217,207,180,.5);margin:10px 0 4px}',
    '#ts-skills .spell{display:flex;justify-content:space-between;align-items:center;gap:10px;padding:6px 10px;',
    'border:1px solid transparent;cursor:pointer}',
    '#ts-skills .spell.at{border-color:transparent;box-shadow:inset 3px 0 0 0 rgba(198,170,109,.75)}',
    '#ts-skills .spell.on .spellname{color:#f6e9c8}',
    '#ts-skills .spell.mine .spellname{color:#9fcf92}',
    '#ts-skills .spellname{font-size:14px}',
    '#ts-skills .spell.shut .spellname{color:rgba(217,207,180,.38)}',
    '#ts-skills .spell.shut{cursor:default}',
    // the recipe book, written against the spell book's rules above so the two
    // sections read as one panel: the same two columns, the same column head
    // with a rank on the right, the same row height. Nothing here is
    // clickable, so no cursor rule and no lit row.
    '#ts-skills .bookcols{grid-template-columns:repeat(2,minmax(0,1fr))}',
    // Two halves is everybody; the third and fourth columns are a character a
    // Master has taught, which the rulebook allows twice, so four is the most
    // there can ever be and three across fits them without a second row.
    '#ts-skills .bookcols.wide{grid-template-columns:repeat(3,minmax(0,1fr))}',
    '#ts-skills .bookcols .colhead{display:flex;align-items:baseline;justify-content:space-between;gap:10px}',
    '#ts-skills .bookhow{font-size:12px;font-style:italic;color:rgba(217,207,180,.58);line-height:1.45;margin:8px 0 2px}',
    '#ts-skills .bookopen{font-size:13px;color:#e9d19b;margin:0 0 6px}',
    '#ts-skills .bookrow{display:flex;justify-content:space-between;align-items:center;gap:10px;padding:6px 10px}',
    '#ts-skills .bookrow .bn{font-size:14px;color:#f6e9c8}',
    '#ts-skills .bookrow .bv{font-size:12.5px;color:rgba(217,207,180,.66);white-space:nowrap}',
    '#ts-skills .bookwhy{font-size:12.5px;line-height:1.5;color:rgba(217,207,180,.7);margin:8px 0 0}',
    /*
      Scrollbars, here and everywhere else in this window.

      The browser's own is a white strip down the side of a dark panel, which
      in a dark room reads as a fault rather than as a control: Patrick called
      it a flash bang on 20 September, and said it is in all the menus rather
      than only this one. Every page in the game is drawn in one document, so
      these rules are written without a page in front of them and the whole
      window matches, the front's own pages included. They are the same rules
      the character choice at the main menu carries, because that page is up
      before this one is loaded.
    */
    '::-webkit-scrollbar{width:10px;height:10px}',
    '::-webkit-scrollbar-track{background:rgba(0,0,0,.25)}',
    '::-webkit-scrollbar-thumb{background:rgba(198,170,109,.35);border:2px solid transparent;',
    'background-clip:padding-box;border-radius:6px}',
    '::-webkit-scrollbar-thumb:active{background:rgba(233,209,155,.55);background-clip:padding-box}',
    '::-webkit-scrollbar-corner{background:transparent}',
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
  // The word inside the Close button, so drawFoot can say Close Skyrim while
  // creating without rebuilding the button or losing its key cap.
  var elCloseLabel = elClose.querySelector('span');
  // And its K key cap, which is hidden while creating: there the button
  // closes Skyrim, and K never does. See closeButton.
  var elCloseKey = elClose.querySelector('.key');
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
    THE RECIPE BOOK, WHICH IS THE SERVER'S ANSWER AND NOT THIS PAGE'S.

    The server sends it whole, under mine.book:

      book: { halves: [ { key, name, how, rank, open, total,
                          families: [ { name, open, total } ], why } ],
              none: '<the sentence for a character with no half at all>' }

    how is 'own', 'sister' or 'taught', which is the three ways classes.md
    lets somebody stand in a half. why is there instead of families when
    there is nothing open, and it is the server's sentence: five of the
    fourteen halves own no recipe in the whole game, and which five and why
    is a fact about the build rather than an opinion of this page's.

    The field is absent for a mage with no craft half taught to them, which
    is how the section knows not to draw itself at all. Anything else, a
    shape this page does not recognise included, reads as no book and the
    section stays away rather than drawing a wrong one.
  */
  function recipeBook() {
    var got = mine && mine.book;
    if (!got || typeof got !== 'object' || Array.isArray(got)) { return null; }
    if (!Array.isArray(got.halves)) { return null; }
    return got;
  }
  function recipeHalves() {
    var book = recipeBook();
    if (!book) { return []; }
    var out = [];
    for (var i = 0; i < book.halves.length; i++) {
      var h = book.halves[i];
      if (h && typeof h === 'object' && h.name) { out.push(h); }
    }
    return out;
  }
  /*
    The one line under a half's name saying why it is yours, and how far it
    goes. "24 of 302" under a sister half with no explanation reads as a page
    that is broken rather than a rule that is working, so the rule is said.

    IT READS THE RANK THE SERVER SENT AND NEVER A CEILING OF ITS OWN. Until
    21 September this said "Its novice work is yours for nothing, and no
    further" whatever the server sent, which was a second copy of a rule the
    server deliberately refused to keep. tools\gamemode.js bookView sends each
    half at P.rankOf, and the comment over that line says why in as many words:
    rankUp lets a sister half climb when a Master of it takes the person on, so
    writing novice into the reader would be wrong for the one character the
    rule was written for. The client kept the copy anyway.

    What it looked like: a Smith/Edgewright whose Master Platewright took them
    on has ranks.platewright advanced, and the server sends
    { how: 'sister', rank: 'advanced', open: 415, total: 771 }. The column drew
    the tag "Advanced", then "Its novice work is yours for nothing, and no
    further", then "415 of 771 open", three lines in a row that cannot all be
    true, and the middle one told somebody who had earned advanced sister work
    that they did not have it.
  */
  function howYouHoldIt(how, rank) {
    var at = RANK_NAMES[rank] || (rank ? cap(String(rank)) : 'Novice');
    if (how === 'sister') {
      if (rank && rank !== 'novice') {
        return 'Your sister half. A Master of it took you on, so it is yours up to ' + at + '.';
      }
      return 'Your sister half. Its novice work is yours for nothing, and it goes further only if a Master of it takes you on.';
    }
    if (how === 'taught') {
      if (rank && rank !== 'novice') {
        return 'Taught to you by a Master of another profession, and yours up to ' + at + '.';
      }
      return 'Taught to you by a Master of another profession. Novice work, and it never goes past it.';
    }
    return 'Your own half. It opens as your rank climbs.';
  }

  /*
    Which spells are open to you, and why one is not.

    Two rules, Patrick's, 20 September: a spell of a rank above Novice needs
    your rank in that school to have reached it, and it needs at least one
    spell of the rank below already in your book. So during creation, when
    nobody has a rank in anything, only Novice spells can be marked. The
    first cut let a Conjuration Advanced spell be marked with no Novice one
    under it, which is what he caught.

    A spell already marked on this page counts as one you have for the rank
    below, so marking Flames opens Advanced Destruction the moment the rank
    allows it. The server grants nothing from here yet; this is the shape of
    the rule, and the rules themselves stay the server's.
  */
  var RANK_ORDER = ['novice', 'advanced', 'expert', 'master'];
  function rankIndex(key) {
    var i = RANK_ORDER.indexOf(String(key || 'novice'));
    return i < 0 ? 0 : i;
  }
  /* The rank this character has reached in that school. The server's, or Novice. */
  function schoolRank(school) { return rankOf(school) || 'novice'; }
  /*
    The spells the server says are yours, by name.

    It sends them as { Flames: true }. A list of names, or the stored
    { points: 2, known: [...] } shape, reads the same way here: what arrives
    is the server's to name, and this page only reads it. A shape it does not
    know reads as no spells, which draws an empty book rather than a wrong one.
  */
  function knownOf(view) {
    var out = {};
    var got = view && view.spells;
    if (!got || typeof got !== 'object') return out;
    var list = null;
    if (Array.isArray(got)) list = got;
    else if (Array.isArray(got.known)) list = got.known;
    if (list) {
      for (var i = 0; i < list.length; i++) if (list[i]) out[String(list[i])] = true;
      return out;
    }
    for (var k in got) if (got[k] === true) out[k] = true;
    return out;
  }
  function knownSpells() { return knownOf(mine); }
  /* Does the book hold a spell of that rank in that school, granted or marked. */
  function holdsRank(school, rankKey) {
    var book = DATA.spells;
    if (!book || !book.schools[school]) return false;
    var have = knownSpells();
    var names = book.schools[school][rankKey] || [];
    for (var i = 0; i < names.length; i++) {
      if (have[names[i]] || marked[names[i]]) return true;
    }
    return false;
  }
  /*
    Empty when the spell is open, otherwise the short reason it is not, in
    the words a person would use.
  */
  function lockedBecause(school, rankKey) {
    var want = rankIndex(rankKey);
    if (want === 0) return '';
    if (want > rankIndex(schoolRank(school))) {
      return 'needs ' + (RANK_NAMES[rankKey] || cap(rankKey)) + ' ' + cap(school);
    }
    var below = RANK_ORDER[want - 1];
    if (!holdsRank(school, below)) {
      return 'needs a ' + (RANK_NAMES[below] || below).toLowerCase() + ' spell first';
    }
    return '';
  }

  /*
    Spell points: the server's number, or the rulebook's two while there is
    no character yet, or nothing at all.

    The server sends it as mine.spellPoints, or as the points on mine.spells
    when what arrives is the stored shape. While creating it has said
    nothing, because there is nobody to say it about, so the two the
    rulebook gives a new mage stand in: "A mage picks two schools, then two
    starting spells" (tools\docs-app\data\site\classes.md).

    In the world there is no standing in. A mage the server has sent no
    number for reads as no number: null, and every line that would print one
    checks for it and prints nothing instead. This used to fall back to two
    whatever the character was, so a Master with three spells read "2 of 2
    spell points left", which is the page inventing the one thing it must
    never invent. Nothing is spent here either; a mark holds a point on this
    page until a pick is answered.
  */
  var STARTING_SPELL_POINTS = 2;   // the rulebook's, classes.md: two starting spells
  function spellPoints() {
    /*
      WHILE CREATING, THE SERVER'S NUMBER IS ABOUT SOMEBODY WHO HAS NOT
      CHOSEN YET, AND THAT IS WHY IT HAD TO BE IGNORED HERE.

      Patrick, 22 September: mages "got their points after creation but had 0
      during creation". Exactly that. The server sends spellPoints on every
      panel, out of the rules, and the rules are right: a character with no
      profession is not a mage and has no points, so during creation it sends
      0. Nobody is a mage until Confirm.

      The fallback below was written for this and could never fire, because it
      only answers when the server has said NOTHING and the server always says
      something. So the book drew with no points, and a mage picked their two
      starting spells by not being able to.

      bookSchools right underneath already reads the lit Mage card while
      creating rather than the server's empty answer. This is the same
      question about the same card and now it is answered the same way. Once
      the profession is confirmed, mine.profession is set, isMage stops
      reading the card, and the server's number is the only one used: a Master
      with three spells must never be told they have two.
    */
    if (creating() && !(mine && mine.profession) && isMage()) return STARTING_SPELL_POINTS;
    if (mine && mine.spellPoints !== undefined && mine.spellPoints !== null) return Number(mine.spellPoints) || 0;
    var got = mine && mine.spells;
    if (got && typeof got === 'object' && !Array.isArray(got) && got.points !== undefined && got.points !== null) {
      return Number(got.points) || 0;
    }
    return creating() ? STARTING_SPELL_POINTS : null;
  }
  function markedCount() { return markedNames().length; }
  /*
    What is left after the marks, or null when there is no number to count
    down from. Every caller has to tell null from 0: null is the server
    saying nothing and a mark is still allowed, 0 is the server saying none
    and a mark is not.
  */
  function pointsLeft() {
    var p = spellPoints();
    if (p === null) return null;
    return Math.max(0, p - markedCount());
  }
  /*
    The marked spells, in the order the book draws them, which is the order
    they are sent in. Read off the book rather than off the marks, so a mark
    left behind by a school that is no longer yours counts for nothing and is
    never sent.
  */
  function markedNames() {
    var out = [];
    bookRows().forEach(function (r) { if (marked[r.name] && out.indexOf(r.name) < 0) out.push(r.name); });
    return out;
  }
  /*
    Mark or unmark a spell; a mark needs a point and an open rank. True when
    something changed.

    Unmarking can shut a rank above it, so anything that is no longer open
    loses its mark with it: marking Flames, then Firebolt, then unmarking
    Flames must not leave Firebolt marked under nothing.
  */
  function toggleMark(school, rankKey, name) {
    // A spell the server has granted is not a mark and never comes off.
    if (knownSpells()[name]) { status = name + ' is yours already.'; statusKind = 'no'; return false; }
    if (marked[name]) { marked[name] = false; tidyMarks(); return true; }
    var why = lockedBecause(school, rankKey);
    if (why) { status = cap(name) + ' ' + why + '.'; statusKind = 'no'; return false; }
    // null is the server saying nothing about points, and a mark it has not
    // ruled on goes on the page: the server is the one that refuses it.
    var left = pointsLeft();
    if (left !== null && left <= 0) { status = 'No spell points left. Unmark one to mark another.'; statusKind = 'no'; return false; }
    marked[name] = true;
    return true;
  }

  /* Drop any mark that is no longer open, until nothing more falls. */
  function tidyMarks() {
    var book = DATA.spells;
    if (!book) return;
    var again = true;
    while (again) {
      again = false;
      bookSchools().forEach(function (sc) {
        var byRank = book.schools[sc] || {};
        book.ranks.forEach(function (r) {
          (byRank[r.key] || []).forEach(function (nm) {
            if (marked[nm] && lockedBecause(sc, r.key)) { marked[nm] = false; again = true; }
          });
        });
      });
    }
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
  /*
    The points that were placed at creation, per the contract's mine.placed.
    They came with the class and profession that were chosen, they are part
    of mine.tree like any other point, and they are not yours to move.

    Read against the tree, so a number for a skill that holds fewer points
    than the server says were placed counts only as far as the pips go, and
    a number for a skill that is not in the tree counts for nothing.
  */
  function placedAt(key) {
    var got = mine && mine.placed;
    if (!got || typeof got !== 'object') return 0;
    var n = Number(got[key]);
    if (!isFinite(n) || n <= 0) return 0;
    var have = Number((mine.tree || {})[key]) || 0;
    return Math.min(Math.floor(n), have, CAP);
  }
  function placedTotal() {
    var total = 0;
    var attrs = (DATA.tree && DATA.tree.rows) || [];
    for (var i = 0; i < attrs.length; i++) {
      var subs = attrs[i].subs || [];
      for (var j = 0; j < subs.length; j++) total += placedAt(subs[j].key);
    }
    return total;
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
    How far off the next rank is, when the server sends it, and silence when
    it does not.

    The contract, at the head of this file:

      progress: { '<key>': { next: '<the rank being climbed to>',
                             done: <number>, need: <number> } }

    One entry per half, school or class verb that can still climb, under the
    same keys as ranks, so 'platewright' and 'hunter' and 'destruction' all
    read the same way. The remainder drawn is need less done. How much work a
    rank takes is the server's number and is nowhere on this page, and an
    entry without a next rank or without the numbers draws no line at all,
    because a line reading "Advanced in 0 more" would be this page inventing
    one. A field that is not an object draws nothing and throws nothing.

    left and unit are the shape this page asked for before the contract was
    agreed. They are still read, so a server that has not caught up draws a
    line rather than nothing; the contract does not send them.
  */
  function labelOf(key) {
    var n = nameOf('profession', key);
    return n !== cap(key) ? n : nameOf('class', key);
  }
  function progressLines() {
    var out = [];
    var got = mine && mine.progress;
    if (!got || typeof got !== 'object') return out;
    for (var k in got) {
      var p = got[k];
      if (!p || typeof p !== 'object') continue;
      var next = p.next ? (RANK_NAMES[p.next] || cap(p.next)) : '';
      if (!next) continue;
      var left = null;
      if (p.need !== undefined && p.need !== null) left = Number(p.need) - (Number(p.done) || 0);
      else if (p.left !== undefined && p.left !== null) left = Number(p.left);
      if (left === null || !isFinite(left)) continue;
      out.push({ k: labelOf(k),
                 t: left > 0 ? next + ' in ' + left + ' more' + (p.unit ? ' ' + p.unit : '') : next + ' earned' });
    }
    return out;
  }
  /*
    Which lines there are and in what order, and not a single one of their
    numbers. This is what decides a rebuild; the numbers are written into the
    lines in place (see drawProgress), because a work counter ticking every
    time somebody swings a hammer must not tear the panel down under
    somebody who is reading it.
  */
  function progressShape() {
    return progressLines().map(function (p) { return p.k; });
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
    // Nothing in the recipe book is picked, marked or sent, so there is no
    // row for the arrow keys to walk. Left and right still move sections.
    if (section === 'recipes') return 0;
    // Nothing on the property page is picked, marked or sent either. It is a
    // list of what is already true.
    if (section === 'property') return 0;
    return rows().length + (laterOffered(section) ? 1 : 0);
  }
  /* Another section: the top row, and the status line back to the hint. */
  function goTo(sec) { section = sec; rowAt = 0; status = ''; statusKind = ''; }

  // ------------------------------------------------------------------ draw --
  /*
    Everything head, nav and body are drawn from, as one string. When the
    string is the one drawn last, nothing is touched, which is what makes the
    server's repeated writes invisible.

    Three fields are left out of it on purpose:

      note      only ever reaches the status line, and a refusal must not
                tear the cards down.
      progress  its counters tick every time somebody picks a flower, and a
                panel that rebuilt its head, its nav and its body on each
                one would be rebuilding itself under a person who is reading
                it. What is in the key instead is progressShape(), the lines
                and their order and none of their numbers; the numbers are
                written in place by drawProgress, the way the foot is
                written in place by drawFoot.
      work      the same counters said the other way round, and this page
                draws nothing at all from it. Leaving it in would undo all
                of the above the first time a caught-up count arrived.
  */
  var NOT_DRAWN = { note: true, progress: true, work: true };
  function viewKey() {
    var v = null;
    if (mine) { v = {}; for (var k in mine) if (!NOT_DRAWN[k]) v[k] = mine[k]; }
    return JSON.stringify([tableGen, sections, section, rowAt, picked, later, marked, v, progressShape()]);
  }

  function draw() {
    // A mage gets the spell book, between Profession and Class, the moment
    // Mage is the profession: confirmed by the server, or still lit on the
    // Profession card while creating. Home and Review are creation's own.
    sections = creating() ? ['profession', 'class', 'tree', 'home', 'review'] : ['profession', 'class', 'tree'];
    if (isMage()) sections.splice(1, 0, 'spells');
    /*
      The recipe book sits where the spell book sits, right after Profession,
      and after the spell book when there is one. A mage gets the spell book;
      everybody else gets this; and a mage a Master taught a craft half gets
      both, because the server sends the book to them as well and the section
      is drawn from whether the book arrived rather than from the profession.
      The server sends nothing while creating, so the section is the world's.
    */
    if (recipeBook()) sections.splice(isMage() ? 2 : 1, 0, 'recipes');
    /*
      Property, last, and only once there is something on it. Patrick,
      21 September: "once they claim a house or have a key to a house a property
      button should appear in the K menu that lists the Properties and wether
      they own them or not". The server leaves the page off entirely when
      somebody holds nothing and carries no key, so the button appearing IS the
      server having something to say. Nothing here decides it.
    */
    if (propertyRows().length) sections.push('property');
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
    drawProgress();
    drawFoot();
  }

  /*
    The counters, written into the lines that are already on the page. The
    shape is viewKey's and a change to it has already rebuilt the body by the
    time this runs; this is the numbers and nothing else, so a tick of work
    changes one string and leaves every card, every section name and the
    place the reader had got to exactly where they were.
  */
  function drawProgress() {
    if (!progRows.length) return;
    var prog = progressLines();
    if (prog.length !== progRows.length) return;   // the shape moved; the rebuild has it
    var key = JSON.stringify(prog.map(function (p) { return p.t; }));
    if (key === progKey) return;
    progKey = key;
    for (var i = 0; i < prog.length; i++) progRows[i].textContent = prog[i].t;
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
    if (sec === 'property') {
      // Named pRows and pHeld rather than rows and mine on purpose: both of
      // those are the module's own, var is hoisted to the top of the function,
      // and a local of either name blanks out the line above that reads
      // mine['class'] for every other section as well.
      var pRows = propertyRows();
      var pHeld = 0;
      for (var pi = 0; pi < pRows.length; pi++) if (pRows[pi].mine) pHeld++;
      var pKeys = pRows.length - pHeld;
      if (!pRows.length) return { t: 'nothing yet', c: '' };
      return { t: pHeld ? pHeld + ' held' + (pKeys ? ', ' + pKeys + ' keyed' : '')
                        : pKeys + (pKeys === 1 ? ' key' : ' keys'),
               c: pHeld ? 'set' : '' };
    }
    if (sec === 'recipes') {
      // How many things you can make, added up over every half you stand in.
      // One number, because the section list is one line per section and the
      // page behind it is where the halves are.
      var halves = recipeHalves();
      var open = 0;
      for (var i = 0; i < halves.length; i++) open += Number(halves[i].open) || 0;
      if (!halves.length) return { t: 'nothing yet', c: '' };
      return { t: open ? open + (open === 1 ? ' thing to make' : ' things to make') : 'nothing open yet', c: open ? 'set' : '' };
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
    progRows = [];   // whatever was on the page is gone with it
    progKey = '';
    var lead = DATA[section] ? DATA[section].lead : '';
    if (section === 'tree') {
      var pts = mine ? Number(mine.points) || 0 : 0;
      lead += ' ' + (pts ? 'You have ' + pts + (pts === 1 ? ' point' : ' points') + ' to spend.' : 'No points to spend right now.');
      // The one line about the placed points, so the green pips below are
      // not a colour nobody explained.
      var gv = placedTotal();
      if (gv) {
        lead += ' ' + (gv === 1 ? 'One point came' : gv + ' points came') + ' with what you chose, ' +
                'in green, and ' + (gv === 1 ? 'it does' : 'they do') + ' not move.';
      }
    }
    if (lead) elBody.appendChild(el('p', 'lead', lead));
    if (section === 'class') drawClass();
    else if (section === 'profession') drawProfession();
    else if (section === 'home') drawHome();
    else if (section === 'spells') drawSpells();
    else if (section === 'recipes') drawRecipes();
    else if (section === 'property') drawProperty();
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
    The spell book: one column per school, the spells under their rank, each
    with a mark that says yours, marked, or could take. Yours comes from the
    server (mine.spells) and cannot be unmarked; the rank over each column is
    the server's too (mine.ranks), and no rank at all is drawn rather than a
    guessed Novice. A click marks; Learn, or Confirm in Review while
    creating, is what sends.
  */
  function drawSpells() {
    var schools = bookSchools();
    var book = DATA.spells;
    if (!schools.length) {
      elBody.appendChild(el('p', 'lead', 'Pick your two schools on the Profession card first. The book fills with their spells.'));
      return;
    }
    var pts = spellPoints();
    var have = knownSpells();
    var n = markedCount();
    var leftPts = pointsLeft();
    var top = el('div', 'spellbar');
    // The count, when the server has sent one. When it has not, the marks
    // alone, and no number at all rather than one this page made up.
    var bar = '';
    if (leftPts !== null) {
      bar = leftPts + ' of ' + pts + (pts === 1 ? ' spell point' : ' spell points') + ' left' + (n ? ', ' + n + ' marked' : '');
    } else if (n) {
      bar = n + ' marked';
    }
    top.appendChild(el('div', 'spellpts', bar));
    top.appendChild(el('div', 'spellnote', creating()
      ? 'Not sent to the server yet. Confirm in Review sends what you marked.'
      : 'Marked spells go to the server when you press Learn.'));
    elBody.appendChild(top);
    var cols = el('div', 'cols spellcols');
    var idx = 0;
    schools.forEach(function (sc) {
      var col = el('div', 'col');
      var head = el('div', 'colhead', cap(sc));
      // The rank the server holds you at in this school, beside its name.
      // Nothing when the server has not said, which is the whole of creation.
      var schRank = rankOf(sc);
      if (schRank) head.appendChild(el('span', 'tag dim', RANK_NAMES[schRank] || cap(schRank)));
      col.appendChild(head);
      var byRank = book.schools[sc] || {};
      book.ranks.forEach(function (r) {
        var names = byRank[r.key] || [];
        if (!names.length) return;
        col.appendChild(el('div', 'rankhead', r.name));
        var why = lockedBecause(sc, r.key);
        names.forEach(function (name) {
          var i = idx++;
          var got = !!have[name];
          var shut = !got && !marked[name] && !!why;
          var row = el('div', 'spell' + (i === rowAt ? ' at' : '') + (got ? ' mine' : '') +
                       (marked[name] ? ' on' : '') + (shut ? ' shut' : ''));
          row.appendChild(el('span', 'spellname', name));
          row.appendChild(el('span', 'tag' + (got ? '' : (marked[name] ? ' gold' : ' dim')),
                             got ? 'yours' : (marked[name] ? 'marked' : (shut ? why : 'could take'))));
          // One handler, one rule: toggleMark says no to a spell that is
          // already yours, so the row does not have to know.
          row.onclick = function () {
            rowAt = i;
            toggleMark(sc, r.key, name);
            draw();
          };
          col.appendChild(row);
        });
      });
      cols.appendChild(col);
    });
    elBody.appendChild(cols);
  }

  /*
    The recipe book: one column per half you stand in, the families under it,
    and beside each family how many of it are open to you out of how many the
    half holds. Drawn the way the spell book beside it is drawn, two columns
    with the server's rank on the right of each column head.

    NOTHING HERE IS A MARK AND NOTHING IS SENT. The spell book has a Learn
    because a spell is a pick; a recipe is not picked, it is made, at the
    bench, and the server's craft gate is what answers for it. So this page
    reads and draws and that is the whole of it, and the foot carries no
    button while it is open.

    A HALF WITH NOTHING OPEN GETS A SENTENCE, NOT AN EMPTY BOX. Five of the
    fourteen halves own no recipe in the whole load order and a new
    Confectioner can bake nothing at all yet, so the server sends why and
    this draws it. Every one of those sentences is the server's.
  */
  /*
    THE PROPERTY PAGE.

    Patrick, 21 September: it "lists the Properties and wether they own them or
    not". So the row says which of the two it is in words rather than by a
    colour somebody has to learn, and the ones you hold come first because they
    are the ones you came here to look at.

    Nothing on this page is picked and nothing is sent. It is a list of what is
    already true, the same as the recipe book, so Confirm stays hidden and the
    keyboard has no rows to walk.

    THE SERVER DECIDES WHETHER THIS PAGE EXISTS AT ALL. It leaves the list off
    when somebody holds nothing and carries no key, and the button in the nav is
    drawn from whether the list arrived. There is nothing here that can put an
    empty page in front of anybody.
  */
  function propertyRows() {
    var rows = DATA && DATA.property;
    return (rows && rows.length) ? rows : [];
  }

  function drawProperty() {
    var pRows = propertyRows();
    if (!pRows.length) {
      elBody.appendChild(el('p', 'lead',
        'You hold nothing and carry no keys. Open a door and say /claim: it costs nothing.'));
      return;
    }
    var pHeld = 0;
    for (var i = 0; i < pRows.length; i++) if (pRows[i].mine) pHeld++;
    var pKeys = pRows.length - pHeld;

    var bar = el('div', 'spellbar');
    bar.appendChild(el('div', 'spellpts',
      (pHeld ? pHeld + (pHeld === 1 ? ' property held' : ' properties held') : 'Nothing held') +
      (pKeys ? ', ' + pKeys + (pKeys === 1 ? ' key carried' : ' keys carried') : '')));
    bar.appendChild(el('div', 'spellnote',
      'A place stays yours while you keep going into it. A key opens a door and ' +
      'nothing more: it is the deed that says a place is yours, and whoever is ' +
      'carrying that holds it.'));
    elBody.appendChild(bar);

    var wrap = el('div', 'cards');
    pRows.forEach(function (r) {
      var card = el('div', 'card' + (r.mine ? ' mine' : ' off'));
      var name = el('div', 'name', String(r.name || 'somewhere'));
      name.appendChild(el('span', 'tag', r.mine ? 'yours' : 'key only'));
      card.appendChild(name);
      card.appendChild(el('div', 'desc', r.mine
        ? (r.locked ? 'Locked. Anybody without a key has to pick it.'
                    : 'Unlocked. Say /lock at the door to turn it.') +
          (r.keyed ? ' You are carrying a key to it as well.' : '')
        : (r.by ? 'Held by ' + r.by + '. ' : 'Nobody holds it. ') +
          (r.locked ? 'Your key opens the door.'
                    : 'It is not locked, so your key is not needed yet.')));
      wrap.appendChild(card);
    });
    elBody.appendChild(wrap);
  }

  function drawRecipes() {
    var book = recipeBook();
    var halves = recipeHalves();
    if (!halves.length) {
      elBody.appendChild(el('p', 'lead', (book && book.none) ||
        'The server has not said what you can make yet. Give it a moment.'));
      return;
    }
    // The one line over the columns: what the whole book adds up to. A person
    // opening this wants the number before they want the breakdown.
    var open = 0, total = 0, locked = 0;
    halves.forEach(function (h) {
      open += Number(h.open) || 0;
      total += Number(h.total) || 0;
      locked += Number(h.locked) || 0;
    });
    var bar = el('div', 'spellbar');
    bar.appendChild(el('div', 'spellpts', total
      ? open + ' of ' + total + ' open to you right now'
      : 'Nothing in your halves is made from a recipe'));
    /*
      The rows your rank reaches that Skyrim will not list, said out loud. The
      server counts them as locked: a recipe carrying a perk, a spell or an
      item condition of its own, which the crafting menu evaluates on this
      machine before the server is ever asked. Without this line a new
      Hearthcook sees "1 of 112" with nothing saying where the other 48 rows
      on their own rung went, and reads the page as broken.
    */
    bar.appendChild(el('div', 'spellnote', locked
      ? 'Rank comes from doing the work. ' + locked +
        ' more are at your rank and held behind a perk, a spell or something you have to be holding.'
      : 'Rank comes from doing the work.'));
    elBody.appendChild(bar);

    var cols = el('div', 'cols bookcols' + (halves.length > 2 ? ' wide' : ''));
    halves.forEach(function (h) {
      var col = el('div', 'col');
      var head = el('div', 'colhead', String(h.name));
      // The rank the server holds you at in this half, beside its name, the
      // same place the spell book puts a school's rank.
      if (h.rank) head.appendChild(el('span', 'tag dim', RANK_NAMES[h.rank] || cap(h.rank)));
      col.appendChild(head);
      col.appendChild(el('div', 'bookhow', howYouHoldIt(String(h.how || 'own'), String(h.rank || ''))));
      var fams = Array.isArray(h.families) ? h.families : [];
      if (!fams.length) {
        col.appendChild(el('p', 'bookwhy', h.why ||
          'Nothing here is open to you yet.'));
        cols.appendChild(col);
        return;
      }
      col.appendChild(el('div', 'bookopen', (Number(h.open) || 0) + ' of ' + (Number(h.total) || 0) + ' open'));
      fams.forEach(function (f) {
        if (!f || !f.name) return;
        var row = el('div', 'bookrow');
        row.appendChild(el('span', 'bn', String(f.name)));
        row.appendChild(el('span', 'bv', (Number(f.open) || 0) + ' of ' + (Number(f.total) || 0)));
        col.appendChild(row);
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
      var m = markedCount();
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
    // The work towards the next rank, when the server has sent it, above the
    // fifteen skills: they are the two things a person came here to read.
    var prog = progressLines();
    if (prog.length) {
      var pw = el('div', 'progress');
      prog.forEach(function (p) {
        var prow = el('div', 'prow');
        prow.appendChild(el('div', 'pk', p.k));
        // Kept, so drawProgress can write the number into it without the
        // body being torn down around it.
        var pv = el('div', 'pv', p.t);
        prow.appendChild(pv);
        progRows.push(pv);
        pw.appendChild(prow);
      });
      elBody.appendChild(pw);
      progKey = JSON.stringify(prog.map(function (p) { return p.t; }));
    }
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
        var given = placedAt(s.key);
        var full = have >= CAP;
        var row = el('div', 'skill' + (idx === rowAt ? ' at' : '') + (full ? ' full' : (have ? ' some' : '')));
        row.appendChild(el('div', 'sn', s.name));
        // The placed pips first and in green, which in this panel is what is
        // already yours; the ones over them are what was spent and keep the
        // colour the row has always given them.
        var pips = el('div', 'pips');
        for (var i = 0; i < CAP; i++) {
          pips.appendChild(el('span', 'pip' + (i < have ? ' lit' : '') + (i < given ? ' given' : '')));
        }
        row.appendChild(pips);
        /*
          The plus offers the room that is left. Placed points fill a skill
          like any other, so a skill filled by what your choices placed is
          full and offers no plus: there is nothing on it to add to and
          nothing on it to take back. A skill that is part placed and part
          empty keeps its plus, because the server takes that spend and
          refuses only at the cap, and this page decides none of it.
        */
        var allPlaced = given > 0 && given >= have;
        var plus = el('div', 'plus' + ((pts > 0 && !full) ? '' : ' off'), '+');
        plus.title = (full && allPlaced) ? s.name + ' came with what you chose.'
                   : 'Put a point in ' + s.name +
                     (given ? '. ' + given + ' of these came with what you chose and do not move.' : '');
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
    rebuilt. In the world Confirm sits under every section that sends.

    CLOSE IS THERE WHILE CREATING NOW, and it used to be hidden.

    Djinn, 21 September: "There is no way to leave the character creation
    screen except to make a character then log out. this needs a resolution."
    The old note here said Escape and K shut the panel "and the server's
    reminder brings it back", which is exactly the complaint written down as
    though it were the design: you could shut it and it reopened thirty
    seconds later, so you could not shut it.

    Hiding the button did not stop anybody leaving either, since Escape
    already worked. All it did was hide that leaving was possible, from the
    people most likely to want it. The button is honest about what it does
    now, and closing tells the server, which holds the reminder off for ten
    minutes instead of thirty seconds. Nothing about the character is decided
    by it.
  */
  function drawFoot() {
    var cr = creating();
    var can = canConfirm();
    var line = status || hint();
    // The spell book's own button says Learn, because what it sends is not a
    // choice about who you are: it is the spells you marked, one pick each.
    var label = (!cr && section === 'spells') ? 'Learn' : 'Confirm';
    // The recipe book sends nothing, the same way the tree's plus buttons are
    // the tree's own sending, so neither carries a Confirm.
    var showConfirm = cr ? section === 'review'
      : (section !== 'tree' && section !== 'recipes' && section !== 'property');
    var shut = closeWord();
    var key = JSON.stringify([line, statusKind, can, label, showConfirm, cr, shut]);
    if (key === footKey) return;
    footKey = key;
    elStatus.className = 'status' + (statusKind ? ' ' + statusKind : '');
    elStatus.textContent = line;
    elConfirm.className = 'tsbtn primary' + (can ? '' : ' off');
    elConfirm.textContent = label;
    elConfirm.style.display = showConfirm ? '' : 'none';
    elClose.style.display = '';
    // Close Skyrim while creating and Close in the world. It said "Not now"
    // while creating and only put the panel down; see closeButton for why it
    // does not any more.
    elClose.className = 'tsbtn ghost' + ((cr && quitArmed) ? ' danger' : '');
    elCloseLabel.textContent = shut;
    elCloseKey.style.display = cr ? 'none' : '';
  }

  function hint() {
    if (section === 'tree') return 'Press + on a skill to put a point in it.';
    if (section === 'recipes') {
      var halves = recipeHalves();
      if (!halves.length) return 'Pick a profession and its half, and this fills with what that half can make.';
      var open = 0;
      for (var i = 0; i < halves.length; i++) open += Number(halves[i].open) || 0;
      if (!open) return 'Nothing is open to you yet. Every column says what it is waiting on.';
      return 'What you can make now, at a bench. Nothing here is picked or sent.';
    }
    if (section === 'spells') {
      if (!bookSchools().length) return 'The book needs your two schools.';
      if (creating()) return 'Click a spell to mark it. Nothing is sent until Confirm in Review.';
      if (learnWaiting()) return 'Sent. The server is checking.';
      if (markedCount()) return 'Learn sends the spells you marked, one point each.';
      // 0 is the server saying none; no number at all is the server saying
      // nothing, and the page does not put words in its mouth.
      var sp = spellPoints();
      if (sp !== null && sp <= 0) return 'No spell points to spend. More come with every rank.';
      return 'Mark the spells you want, then press Learn. One point each.';
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
  /*
    Learn lights when there is something to send and the points cover it: at
    least one spell marked, and no more marks than the points the server says
    you hold. Marking already asks the same question, and it is asked again
    here because the points are the server's and can change between the mark
    and the press. No number from the server is not a no: the marks go and
    the server answers them.

    It goes dark the moment it has sent and stays dark until the answer comes
    back, the way Confirm elsewhere goes dark the moment the thing it asked
    for is the server's. Every line Learn sends is a chat command the server
    clones and checks, so three presses on two marked spells used to be six
    of them.
  */
  /*
    How long Learn stays dark when no answer comes at all. NOT IN THE
    RULEBOOK: classes.md says nothing about how long a button waits, so this
    is a first number, long enough that a second press is a second thought
    and short enough that a lost answer does not strand the button. It is
    kept beside PENDING_MS, the other number of this kind on the page; this
    file has no TUNING block of its own and the server's is in gamemode.js.
  */
  var LEARN_WAIT_MS = 4000;
  var learnAt = 0;   // when Learn last sent, 0 when it is not waiting on anything
  function learnWaiting() {
    if (!learnAt) return false;
    if (Date.now() - learnAt >= LEARN_WAIT_MS) { learnAt = 0; return false; }
    for (var i = 0; i < pending.length; i++) if (pending[i].section === 'spells') return true;
    learnAt = 0;   // every spell it sent has been answered
    return false;
  }
  function canLearn() {
    if (learnWaiting()) return false;
    var n = markedCount();
    var p = spellPoints();
    return n > 0 && (p === null || n <= p);
  }

  function canConfirm() {
    if (creating()) return section === 'review' && !!softHome();
    if (section === 'spells') return canLearn();
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

  /*
    One pick to the server, remembered until its answer or a refusal comes
    back. A spell carries its name as well, because Learn puts several in
    flight at once and each one is cleared by its own answer.
  */
  function send(sec, words, spell) {
    pending.push({ section: sec, words: words, spell: spell || '', at: Date.now() });
    tell('pick', words);
  }

  /*
    Learn, in the world: every marked spell goes out as its own pick, in the
    order the book draws them, and the page waits exactly as the other
    sections wait. The mark stays until the server lists the spell as yours,
    so a refused one can be sent again.
  */
  function learn() {
    // The guard, and not only the dark button: Enter, a click on a button a
    // stylesheet failed to deaden, and a second call from anywhere else all
    // arrive here.
    if (learnWaiting()) return;
    var names = markedNames();
    if (!names.length) return;
    // The name goes as the book writes it, spaces and all: 'spell Ice Spike'
    // reaches the server as the chat line '/pick spell Ice Spike', so what it
    // reads is the rest of the line and not one word of it.
    names.forEach(function (n) { send('spells', 'spell ' + n, n); });
    learnAt = Date.now();
    status = 'Sent. The server is checking.'; statusKind = '';
    // Nothing else is coming if the answer is lost, so the button lights
    // itself again when the wait is over.
    setTimeout(function () { if (!learnWaiting()) draw(); }, LEARN_WAIT_MS + 50);
    draw();
  }

  function confirm() {
    if (!canConfirm()) return;
    if (creating()) { begin(); return; }
    if (section === 'spells') { learn(); return; }
    var p = picked[section];
    send(section, section === 'class' ? 'class ' + p.row : 'profession ' + p.row + ' ' + p.subs.join(','));
    status = 'Sent. The server is checking.'; statusKind = '';
    draw();
  }

  /*
    Begin, from Review while creating: every soft choice goes to the server
    now, one pick each, in the order profession, spells, class, town. The
    spells come after the profession because a spell needs the profession
    that owns it, and the town is last because the town is the pick that ends
    creation on the server, and anything sent after it would land in the
    world. A "later" mark sends nothing; the server never hears of it. What
    the server already has is not sent again, which is what a second Begin
    after a refused home relies on.
  */
  function begin() {
    var pf = softProf();
    if (pf && pf.whole && !haveProf()) send('profession', 'profession ' + picked.profession.row + ' ' + picked.profession.subs.join(','));
    markedNames().forEach(function (n) { send('spells', 'spell ' + n, n); });
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
    Shut by hand: the Close button, or Escape.

    While creating this also tells the server, which holds its reminder off
    for ten minutes instead of pushing the panel back in thirty seconds. That
    difference is the whole of Djinn's "there is no way to leave the character
    creation screen": closing already worked, it just did not last.

    Only from the two deliberate ways out. leave() above is creation ENDING
    and must not send it, and the server ignores it once the stage is past
    choosing anyway, so the two guards agree.
  */
  function closeByHand() {
    if (creating()) { tell('pick', 'later'); }
    api.close();
  }

  /*
    CLOSE SKYRIM, the panel's own button while creating.

    Patrick, 24 September: "the k not now button during creatioon doesnt
    close skyrim it exists the menu and lets the roam the room". While
    creating the button said Not now and did what Escape does, which is
    closeByHand above: the panel goes down, the server holds its reminder
    off, and the person is left standing in the hall. So while creating it
    says Close Skyrim and ends the game, through the front plugin's quit, the
    same one the character page's Close the game uses ('select:quit' in
    thornswood-front.js, and thornswood-select.js for the page).

    IT ASKS TWICE, the way that page does. The first press arms it and it
    says Press again to close Skyrim; a second press inside five seconds
    sends 'skills:quit'. A first press on its own disarms after five seconds,
    so a stray click never ends anybody's session. If the game is still here
    six seconds after the second press, the button comes back and the front
    is told, so it never sits on Closing for ever, which is how the
    character page's button was reported on 22 September.

    NO '/pick later' GOES FIRST. That record only holds the server's
    reminder off for the rest of this session, and the gamemode starts the
    reminder again from nothing on the next login (the seenAt check in its
    'choosing' stage), so a session that is ending has nothing to hold off.

    Outside creation the button is Close and puts the panel down, as it
    always has. Escape and K still put the panel down while creating;
    neither of them closes the game, which is why the K key cap is not
    shown beside Close Skyrim.
  */
  var QUIT_ARM_MS = 5000;
  var QUIT_BACK_MS = 6000;
  var quitArmed = 0;   // when the first press was, while it is armed
  var quitSent = 0;    // when 'skills:quit' went, until the game goes

  function closeWord() {
    if (!creating()) return 'Close';
    if (quitSent) return 'Closing Skyrim';
    if (quitArmed) return 'Press again to close Skyrim';
    return 'Close Skyrim';
  }

  function closeButton() {
    if (!creating()) { closeByHand(); return; }
    if (quitSent) return;
    var now = Date.now();
    if (quitArmed && now - quitArmed < QUIT_ARM_MS) {
      quitArmed = 0;
      quitSent = now;
      tell('quit');
      drawFoot();
      setTimeout(function () {
        if (!quitSent || Date.now() - quitSent < QUIT_BACK_MS) return;
        quitSent = 0;
        tell('quit did not take, the game is still here');
        drawFoot();
      }, QUIT_BACK_MS);
      return;
    }
    quitArmed = now;
    drawFoot();
    setTimeout(function () {
      if (!quitArmed || Date.now() - quitArmed < QUIT_ARM_MS) return;
      quitArmed = 0;
      drawFoot();
    }, QUIT_ARM_MS);
  }

  /*
    The server answered by rewriting the property. Each pick in flight is
    cleared by its own answer, the thing it asked for now set, and says so;
    a refusal clears the one its note is about (see refused). Confirm sends
    up to three at once and the server answers each with its own write, so
    the picks are read one at a time: a refused class must not swallow the
    home's answer, and only the home's own answer ends creation. A pick
    nothing answers in thirty seconds is dropped, so the list cannot grow
    for ever.
  */
  var PENDING_MS = 30000;
  function answered(before, after) {
    if (!pending.length) return;
    var keep = [];
    var now = Date.now();
    var known = knownOf(after);
    var cleared = false;
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
      else if (p.section === 'spells' && p.spell && known[p.spell] && !knownOf(before)[p.spell]) {
        // The server granted it. The mark has done its work and goes, and the
        // spell now reads as yours because the server says so.
        status = p.spell + ' is yours.'; statusKind = 'ok';
        marked[p.spell] = false;
        cleared = true;
      }
      else if (p.section === 'tree') { status = 'Spent.'; statusKind = 'ok'; }
      else done = false;
      if (done) picked[p.section] = null;
      else if (now - p.at < PENDING_MS) keep.push(p);
    });
    pending = keep;
    // A granted spell can hold up a marked one above it; tidyMarks sees that
    // it does not, because a granted spell counts for the rank below.
    if (cleared) tidyMarks();
  }

  /*
    A refusal, and which pick it answers.

    The server writes one note per refused pick and says in note.about which
    pick that was: class, profession, spell, town or spend, per the contract
    at the head of this file. The panel clears that pick and only that one.
    It used to shift the oldest pick in flight whatever the note was about,
    so a refused spell ate the profession's answer and the profession sat in
    the list until it timed out.

    A note with no about at all is still shown, and then the oldest pick is
    the one it is taken for, which is the best a panel can do without being
    told. A note about something this page has no word for clears nothing:
    the words are still shown, and whatever was really refused leaves the
    list on PENDING_MS. The card stays as it was picked either way, so it can
    be sent again or replaced.
  */
  var ABOUT_SECTION = { 'class': 'class', 'profession': 'profession', 'spell': 'spells', 'town': 'home', 'spend': 'tree' };
  function refused(text, about) {
    status = 'No: ' + text + '.'; statusKind = 'no';
    if (!pending.length) return;
    if (about) {
      var sec = ABOUT_SECTION[String(about)];
      if (!sec) return;
      for (var i = 0; i < pending.length; i++) {
        if (pending[i].section === sec) { pending.splice(i, 1); return; }
      }
      return;
    }
    pending.shift();
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
    if (e.key === 'Escape') { closeByHand(); e.preventDefault(); return; }
    if (e.key === 'Enter') {
      if (section === 'tree') {
        var flat = [];
        rows().forEach(function (a) { (a.subs || []).forEach(function (s) { flat.push(s.key); }); });
        if (flat[rowAt]) spend(flat[rowAt]);
      } else if (section === 'spells') {
        // Enter marks the lit spell, the way Enter puts a point in the lit
        // skill, and it keeps doing that however many are marked. Learn is a
        // press of its own: a book is marked several times before it is sent,
        // so an Enter that sent the moment one spell was marked would take
        // the keyboard away from the second.
        var sr = bookRows()[rowAt];
        if (sr) { toggleMark(sr.school, sr.rank, sr.name); draw(); }
      } else if (canConfirm()) { confirm(); }
      else {
        // Enter on a row picks it. While creating that is the choice, and
        // Enter in Review is Begin; in the world the second Enter confirms.
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
  elClose.onclick = function () { closeButton(); };

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
      quitArmed = 0;   // a panel put down with Close Skyrim armed comes back unarmed
      tell('closed');
    },
    toggle: function () {
      if (root.className === 'gone') { api.open(); } else { closeByHand(); }
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
        // A note is new when its time, its words or what it is about
        // changed: two refusals from one Confirm can carry the same
        // millisecond, and two picks can be refused in the same words.
        var nn = mine.note, bn = before && before.note;
        if (nn && nn.text && (!bn || bn.at !== nn.at || bn.text !== nn.text || bn.about !== nn.about)) refused(nn.text, nn.about);
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
