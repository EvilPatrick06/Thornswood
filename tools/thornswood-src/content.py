# -*- coding: utf-8 -*-
"""Book content for Thornswood: skill manuals, class writs, travel papers."""

# ---- donor field bytes, lifted from vanilla records of the same mesh --------
MESH = {
  'book3': dict(
    modl = r'Clutter\Books\BasicBook03.nif',
    obnd = bytes.fromhex('f7fff5fffeff09000b000200'),
    modt = bytes.fromhex('020000000400000000000000bcda0f1964647300b5139f09b5ce5fb964647300b5139f09cd6472c964647300b5139f09f4c8a2a364647300b5139f09'),
    ynam = None, inam = 0x000153d4),
  'book6': dict(
    modl = r'Clutter\Books\BasicBook06.nif',
    obnd = bytes.fromhex('f7fff5ffffff09000b000200'),
    modt = bytes.fromhex('020000000400000000000000332e656964647300b5139f095e0c94bf64647300b5139f09cd6472c964647300b5139f09f4c8a2a364647300b5139f09'),
    ynam = None, inam = 0x00080a4a),
  'note2': dict(
    modl = r'Clutter\Books\Note02.nif',
    obnd = bytes.fromhex('000000000000000000000000'),
    modt = bytes.fromhex('020000000200000000000000c5d74c9464647300b5139f09ad43553b64647300b5139f09'),
    ynam = 0x000C7A54, inam = 0x0001541b),
  'note3': dict(
    modl = r'Clutter\Books\Note03.nif',
    obnd = bytes.fromhex('f8fffbff0000080005000000'),
    modt = bytes.fromhex('02000000040000000000000053e74be364647300b5139f09c397d13864647300b5139f09c5d74c9464647300b5139f09ad43553b64647300b5139f09'),
    ynam = 0x000C7A54, inam = 0x0001541c),
}

KWDA_VENDORITEMBOOK = 0x000937A2

# ---- the fifteen Keizaal manuals, which shipped as empty shells -------------
# fid -> (title, track, tier)
MANUAL_TITLES = {
  0x0500b276: ("A Miner's First Season",      'mining',     1),
  0x0500b277: ("Reading the Seam",            'mining',     2),
  0x0500b278: ("Deep Work",                   'mining',     3),
  0x0500b279: ("What the Mountain Keeps",     'mining',     4),
  0x0500b27b: ("Striking Iron",               'smithing',   1),
  0x0500b27a: ("The Temper and the Quench",   'smithing',   2),
  0x0500b27c: ("On Folded Steel",             'smithing',   3),
  0x0500b27d: ("The Last Hammer",             'smithing',   4),
  0x05015489: ("Axe, Wedge and Grain",        'woodcutter', 1),
  0x0501548a: ("Seasoning and Stack",         'woodcutter', 2),
  0x0501548b: ("The Charcoal Burner's Art",   'woodcutter', 3),
  0x0501548c: ("Slow Fire",                   'woodcutter', 4),
  0x05047f6c: ("The Second Distillation",     'alchemy',    2),
  0x05047f6d: ("Reagents Out of Season",      'alchemy',    3),
  0x05047f6e: ("The Quiet Bench",             'alchemy',    4),
}

TRACK_WORD = {'mining':'mining', 'smithing':'smithing',
              'woodcutter':'woodcutting', 'alchemy':'alchemy'}
TIER_WORD  = {1:'Novice', 2:'Journeyman', 3:'Expert', 4:'Master'}

MANUAL_BODY = {
 ('mining',1): "Any fool can swing at rock. The trick is to stop swinging at rock that will not give.<br><br>"
               "Walk the face first. Look for the pale line, the one that runs a little wetter than the stone "
               "around it. That is your seam. Set the pick's point on it, not across it, and let the weight of "
               "the head do the work. You are not breaking the stone. You are persuading it to come apart along "
               "a fault it already has.",
 ('mining',2): "You have worked a season and your hands have stopped bleeding. Good. Now learn to read.<br><br>"
               "A seam that runs level will keep running level. A seam that dips is heading for water, and water "
               "means you stop. A seam that splits into three has already given you everything it has; take what "
               "is loose and move on. The quarry pays the patient and buries the stubborn.",
 ('mining',3): "Deep work is different work. The air goes stale, the light goes strange, and the stone begins to "
               "hold things that were never meant to be near daylight.<br><br>"
               "Salts of the fire and the frost sit in pockets, never in seams. You will know one by the colour of "
               "the dust and by the way the pick rings instead of thuds. Take these slowly. They are worth more "
               "than a month of common salt, and they are not forgiving of a hurried hand.",
 ('mining',4): "There is a point past which no manual can take you, and you have reached it.<br><br>"
               "What remains is simply this: the mountain keeps what it keeps, and gives what it gives, and the "
               "difference between a master and a journeyman is only that the master has stopped arguing about "
               "which is which.",
 ('smithing',1): "The forge is not hot enough. It is almost never hot enough. That is the first thing to learn "
                 "and the last thing anyone believes.<br><br>"
                 "Iron worked cold splits. Iron worked at a dull red bends and will not hold. Wait for the straw "
                 "colour, work fast, and put it back in the fire the moment the colour goes. Ten short heats beat "
                 "one long one, every time.",
 ('smithing',2): "Hardening and tempering are opposites, and you need both.<br><br>"
                 "Quench too fast and you get a blade that will take an edge and snap on the first parry. Quench "
                 "too slow and you get a bar of soft metal shaped like a sword. The oil, the water, the time in "
                 "each: these are the whole craft. Everything else is shaping.",
 ('smithing',3): "Folding is misunderstood. It does not make the steel stronger. It makes it even, which in "
                 "practice is the same thing.<br><br>"
                 "Every ingot has a bad half. Fold it, and the bad half is spread thin through the good. Fold it "
                 "again and the fault is gone entirely, or near enough that no blow will find it.",
 ('smithing',4): "You will make one more hammer in your life than you need, and you will give the last one away.<br><br>"
                 "That is the whole of it. The craft does not end in a masterwork. It ends in a apprentice who does "
                 "not need you any more.",
 ('woodcutter',1): "Read the grain before you read the tree.<br><br>"
                   "Set the wedge where the rings run straight and the round will open like a book. Set it across "
                   "a knot and you will spend the afternoon getting your axe back. Split green wood; stack dry "
                   "wood. Never the other way about.",
 ('woodcutter',2): "A stack is not a heap. A stack is a machine for moving air.<br><br>"
                   "Bark side up on the outside courses, bark side down within. Leave a hand's width between the "
                   "rows and a foot beneath the bottom one. Wood stacked properly in spring will burn clean by "
                   "autumn. Wood thrown in a pile will still be hissing at you next year.",
 ('woodcutter',3): "Charcoal is wood with the hurry taken out of it.<br><br>"
                   "The kiln must smoulder, never burn. You are driving the water and the smoke out and leaving "
                   "the heat behind. Open a vent and you lose the lot. Seal it too tight and you have a pile of "
                   "damp sticks. The burner who sleeps through a night's watch has no charcoal in the morning.",
 ('woodcutter',4): "Slow fire is the oldest trade there is, older than iron, older than the men who use it.<br><br>"
                   "Everything that comes after, every forge and every blade, waits on somebody sitting up all "
                   "night with a mound of earth, doing nothing, very carefully.",
 ('alchemy',1): "Taste nothing. This is not caution, it is arithmetic: you have one mouth and there are four "
                "effects in every reagent.<br><br>"
                "Learn the four by sight, by smell, and by what the mortar does when you work them. A reagent "
                "that fights the pestle is telling you something. A reagent that goes to paste at once is telling "
                "you something else.",
 ('alchemy',2): "A single distillation gives you a potion. A second gives you a potion you can sell.<br><br>"
                "The difference is everything the first pass left behind: the bitterness, the sediment, the "
                "effect nobody asked for. Boil gently, decant slowly, and throw away more than you keep.",
 ('alchemy',3): "Out of season is not the same as out of use.<br><br>"
                "Dried mountain flower is weaker than fresh and steadier than either. Frozen reagents keep their "
                "restorative effects and lose their harmful ones almost entirely, which is a gift if you know it "
                "and a mystery if you do not.",
 ('alchemy',4): "The bench should be quiet. Not tidy: quiet.<br><br>"
                "You will know you have arrived when you stop reaching for the recipe, and start reaching for "
                "the jar you already know is wrong, to see what it does.",
}

# ---- new records ------------------------------------------------------------
BASE = 0x05e80000

WELCOME_FID = BASE + 0x00
ALCHEMY_NOVICE_FID = BASE + 0x01

# key, fid, title, gear, blurb
CLASSES = [
 ('warrior', BASE+0x10, "Writ of the Shield",
  "Heavy iron, a plain sword, and a shield that has been hit before.<br><br>"
  "You start able to take a blow. What you do with that is your own business."),
 ('ranger',  BASE+0x11, "Writ of the Long Road",
  "Hide and leather, a hunting bow, a quiver that will not last the week, and a knife for the work "
  "afterwards.<br><br>You start able to eat without asking anyone."),
 ('mage',    BASE+0x12, "Writ of the Open Book",
  "Robes, two tomes, and enough soul gems to be dangerous to yourself.<br><br>"
  "Read the tomes. They are not decoration."),
 ('smith',   BASE+0x13, "Writ of the Anvil",
  "Blacksmith's clothes, iron and steel to work, strips of leather, and the novice manual.<br><br>"
  "You start with something to sell by the end of the first day."),
 ('miner',   BASE+0x14, "Writ of the Deep Seam",
  "Miner's clothes, a pick, torches, and the novice manual.<br><br>"
  "Salt is dull and salt is steady. The quarries are marked on no map; ask."),
 ('forager', BASE+0x15, "Writ of the Green Hand",
  "Traveller's clothes, a woodcutter's axe, and the two novice manuals that pay for themselves.<br><br>"
  "Wood, charcoal, and whatever grows by the road."),
]

# key, fid, title, town, blurb
DESTS = [
 ('whiterun',  BASE+0x20, "Passage to Whiterun",   "Whiterun",
  "The Temple of Kynareth, in the middle of everything.<br><br>"
  "Work in the fields, work in the market, and the road out goes four ways."),
 ('solitude',  BASE+0x21, "Passage to Solitude",   "Solitude",
  "The Temple of the Divines, on the arch above the sea.<br><br>"
  "Money and ships and people who will tell you their business unasked."),
 ('windhelm',  BASE+0x22, "Passage to Windhelm",   "Windhelm",
  "The Temple of Talos, in the cold half of the city.<br><br>"
  "Stone, snow, and the docks. Nobody will make you welcome and nobody will stop you."),
 ('markarth',  BASE+0x23, "Passage to Markarth",   "Markarth",
  "The Temple of Dibella, high in the stone city.<br><br>"
  "Silver below, Forsworn above, and a long way down in every direction."),
 ('riften',    BASE+0x24, "Passage to Riften",     "Riften",
  "The Temple of Mara, by the lake.<br><br>"
  "Fish, mead, and a canal you should not fall into. Good place to start quietly."),
 ('ravenrock', BASE+0x25, "Passage to Raven Rock", "Raven Rock",
  "The Temple at Raven Rock, across the water on Solstheim.<br><br>"
  "Ash, silence, and a very long way from anyone else. Choose it on purpose."),
]

WELCOME_TEXT = (
 "You are somewhere that is not anywhere, and you will not be here long.<br><br>"
 "Two things remain. First, in your pack you will find six writs. Read one. Whichever you read is "
 "the trade you begin with, and the gear that comes with it will be in your hands before you have "
 "finished the last line.<br><br>"
 "Second, once the writ is read, six passages take its place. Read one of those and you will wake "
 "in the temple of the town it names, with a bed and a road and no further ceremony.<br><br>"
 "You can only read one of each. Take your time over both.<br><br>"
 "[pagebreak]<br><br>"
 "A word on the trades. None of them locks anything: a miner may learn smithing and a mage may "
 "swing an axe. The writ decides what you own on the first morning, not what you are.<br><br>"
 "A word on the towns. Death will return you to the nearest temple, not to the one you choose "
 "here, so choose for the neighbours rather than for safety.<br><br>"
 "That is everything. Go on."
)


# ---- message boxes, so the choices are a menu rather than a pile of books ----
# Format taken from SkyrimUnboundPreviewModeMessage, which is a working four
# button menu in this same load order: EDID, DESC, INAM (0), DNAM (1 means
# message box rather than notification), then one ITXT per button.
TRADE_MENU_FID = BASE + 0x30
TOWN_MENU_FID  = BASE + 0x31

TRADE_MENU = {
  'edid': 'ThornswoodTradeMenu',
  'desc': 'What do you do for a living?',
  'buttons': [c[0].capitalize() if c[0] != 'forager' else 'Forager' for c in CLASSES],
}
TOWN_MENU = {
  'edid': 'ThornswoodTownMenu',
  'desc': 'Where do you begin?',
  'buttons': [d[3] for d in DESTS],
}
