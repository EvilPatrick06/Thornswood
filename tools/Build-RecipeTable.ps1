<#
  Build-RecipeTable.ps1

  Builds tools\recipes.json: the table the server needs to answer "may this
  person make this". Nothing in it is typed from memory. It is read out of the
  plugins of the build on this machine, and every judgement it makes is in the
  knob block at the top of this file rather than buried in the code.

  WHY THE SERVER CAN DO THIS AT ALL, MEASURED IN THE FORK RATHER THAN ASSUMED

  It was believed here that the server could not see crafting. It can, and this
  was read in C:\Thornswood-Dev\skymp on 20 September rather than remembered.

  skymp5-server/cpp/server_guest_lib/CraftService.cpp is the whole path. A
  client asks to craft; OnCraftItem looks the workbench reference up, reads the
  workbench base record's keywords with GetKeywordIds, and calls FindRecipe.
  FindRecipe walks every COBJ in the load order (GetDistinctRecordsByType
  "COBJ"), keeps the ones whose inputs and output match what was asked for, and
  then ConsiderRecipeCandidate refuses any whose BNAM is not one of the
  workbench's keywords. What survives goes to UseCraftRecipe, which builds a
  CraftEvent and fires it.

  gamemode_events/CraftEvent.cpp: GetName returns "onCraft" and
  GetArgumentsJsonArray sends four numbers, in this order:
      actorFormId, craftedItemBaseId, count, recipeId
  recipeId is the COBJ's own form id, mapped to the combined load order.

  THE FOURTH ARGUMENT IS A NUMBER AND THE KEY OF THIS TABLE IS A STRING

  This is the one thing that has to be right for the gate to work at all, and
  the header of this script said the wrong thing about it until 20 September.

  CraftEvent::GetArgumentsJsonArray writes std::to_string(recipeId), and
  CraftService.cpp builds that recipeId as
  espm::utils::GetMappedId(recipeUsed->GetId(), *mapping). It is a uint32 and
  it reaches the gamemode as a plain JavaScript number, 1006945 and the like.

  Every key in this table, and in the RECIPES_BY_ID block, is a desc string:
  the form id in lower case hex, a colon, and the file the record belongs to.
  "f61:Skyrim.esm", "8a4:Gourmet.esp". That is the form the rest of this repo
  keys everything by, and it is the only form that survives a load order
  changing underneath it, which is why the table is written that way and not
  as numbers.

  So a gamemode CANNOT write RECIPES_BY_ID[recipeId]. That is undefined for
  every row in the table, onCraft never returns false, and every profession
  quietly makes everything with no error anywhere to say so. It has to convert
  first, with the function the gamemode already uses elsewhere:

      var row = RECIPES_BY_ID[mp.getDescFromId(recipeId)];

  The other generated tables in the gamemode do not need this line because
  their call sites already hold a desc: the harvest gate reads
  mp.get(refrId, 'baseDesc') and the ore gate goes the other way with
  mp.getIdFromDesc. onCraft is the one event that hands over a bare number, so
  the conversion is written into the json's "event" field and into the block
  comment rather than left for somebody to work out.

  gamemode_events/GameModeEvent.cpp: Fire asks every listener, and if any one
  of them answered false it calls OnFireBlocked and returns false. Only when
  nobody blocked does it call OnFireSuccess. CraftEvent::OnFireSuccess is the
  method that does the work:
      actor->RemoveItems(entries);
      actor->AddItem(craftedItemBaseId, count);
  So a gamemode whose mp.onCraft returns false REFUSES the craft outright. The
  inputs are never taken and the output is never given. The person keeps their
  materials. That is the gate this table feeds.

  ONE THING THE SERVER NEVER SEES, AND IT MATTERS FOR THE COUNTS BELOW

  CraftService::RecipeItemsMatch opens with an early refusal:
      enum { ArmorTable = 0xadb78, SharpeningWheel = 0x88108 };
      const bool isTemper = recipeData.benchKeywordId == ArmorTable ||
        recipeData.benchKeywordId == SharpeningWheel;
      if (isTemper) { return false; }
  Tempering is thrown out before any recipe is considered, so onCraft never
  fires for a recipe on the armour table or the sharpening wheel. On this build
  that is 1720 of the 5116 recipes. They are still in this table, with their
  owner, and every row carries a "fires" field saying whether the server will
  ever be asked about it. Only the rows that fire are written into the gamemode
  block, because a row the server is never asked about is dead weight in a file
  that ships as one piece.

  WHICH SUBRECORD IS WHICH, AND HOW THAT WAS PROVED

  Counted first, the way Build-HarvestTable.ps1 worked out PFIG: every
  subrecord of every COBJ in Skyrim.esm, 601 records.

      EDID  601  text, 16 to 46 bytes
      COCT  599  4 bytes
      CNTO  952  8 bytes
      CTDA  931  32 bytes
      CNAM  594  4 bytes
      BNAM  601  4 bytes
      NAM1  601  2 bytes

  Then reasoned about, then proved one at a time by resolving each and checking
  the answer makes sense.

    EDID is the editor id. Text, and it reads as text.

    COCT and CNTO go together. Over the five Bethesda masters COCT adds up to
    2619 and there are exactly 2619 CNTO subrecords. So COCT is a count of the
    CNTO subrecords that follow it, and CNTO is one input: eight bytes, a form
    id then a count. RecipeLeatherFoxHide has COCT 1 and one CNTO, which is the
    one fox pelt it wants.

    CNAM and BNAM are both four bytes and both a form id, and telling them
    apart is the whole job. Resolved across the five masters:
      BNAM lands on a KYWD record every single time, and there are only a
      handful of distinct values. The two commonest are 88105:Skyrim.esm
      (CraftingSmithingForge) and adb78:Skyrim.esm
      (CraftingSmithingArmorTable). Those two hex numbers are the same two
      constants CraftService.cpp hardcodes for tempering, which is an
      independent confirmation from the engine's own source.
      CNAM never lands on a KYWD. It lands on ARMO 457, MISC 523, WEAP 344,
      ALCH 37 and AMMO 19, and nothing failed to resolve. Read as the output it
      gives the right answer every time: RecipeWeaponElvenBow -> ElvenBow,
      RecipeArmorSteelCuirassB -> ArmorSteelCuirassB, RecipeLeatherFoxHide ->
      Leather01, RecipeIngotDwarvenScrapLarge -> IngotDwarven.
    So BNAM is the workbench keyword and CNAM is the output item.

    NAM1 is two bytes and it is 1 on 1344 of the 1387 records in the masters.
    Where it is not 1 it is right: RecipeLeatherStrips reads 4 and one hide
    does give four strips, RecipeIngotDwarvenScrapLarge02 reads 5, and the
    dwarven scrap pile recipes read 2 and 3. So NAM1 is how many the recipe
    makes.

    CTDA is 32 bytes and is the condition list, and it is read in full here.
    It was stepped over until 20 September, which is how three halves came to
    be reported as having work when they have none. The layout is
    libespm/include/libespm/CTDA.h, read out of the fork rather than
    remembered, and every offset below was checked against a record:
      byte 0     the operator in the top three bits, the flags in the low
                 five. 0x04 in the flags means the comparison value is a GLOB
                 form id rather than a number. Operator 0 is ==, 1 is !=, 2 is
                 >, 3 is >=, 4 is <, 5 is <=.
      bytes 4-7  the comparison value, a float.
      bytes 8-9  the function index, a uint16. Bytes 10 and 11 are padding and
                 hold leftovers from the Creation Kit, not data.
      bytes 12-15 and 16-19  the two parameters.
      the rest   what the condition runs on, a reference, and a trailing -1.
    Proved on TemperWeaponSkyforgeSteelSword, whose two conditions read as
    function 659 with no form parameter, and function 448 against
    5218e:Skyrim.esm, which resolves to a PERK record.

  The fork's own parser agrees, which is worth saying because it was read after
  the census rather than before it: libespm/src/COBJ.cpp maps CNTO to
  inputObjects, CNAM to outputObjectFormId, BNAM to benchKeywordId, NAM1 to
  outputCount and CTDA to conditions. Two independent readings, same answer.

  Eleven COBJ records in this build carry no CNAM at all, so they name no
  output. Nine of them are armour table temper records and they are listed as
  unowned with that reason rather than quietly dropped.

  THE POISON FLAG, PROVED THE SAME WAY

  An ALCH record's ENIT is 12 bytes or more: the value in gold as a uint32,
  then a flag word as a uint32. Read that way the flag word over the five
  masters takes exactly five values, which is what a bit field should look
  like, and each one lands on the right kind of record:

      0x00000000  205  potions:  RestoreAll, FortifyMagicka04, FortifyStaminaRate01
      0x00000001    7  potions with the no-auto-calc bit: BladesPotion, DLC1BloodPotion
      0x00000002    8  food:     FoodGourd, DLC2FoodBoarMeat, FirebrandWine
      0x00000003  107  food with the no-auto-calc bit: FoodVegetableSoup, FoodCheeseWedge01
      0x00020000   80  poison:   DamageHealthLinger03, WeaknessFire01, DamageStaminaLinger01

  So bit 0x00000002 is the food bit and bit 0x00020000 is the poison bit. Every
  record carrying 0x00020000 is a damage or weakness brew and nothing else
  carries it, and every record carrying 0x00000002 is something eaten. That
  flag is exactly the Blightbrewer and Physicker split classes.md asks for.

  WHAT IS NOT IN THE RECORDS AT ALL, AND THIS IS THE FINDING OF THE BUILD

  There are no alchemy recipes. Not few, none. Across the whole load order,
  5116 COBJ records, not one of them names an alchemy bench keyword. Skyrim's
  alchemy is not a recipe system: potions are worked out from the effects the
  ingredients share, in the alchemy menu, and no COBJ record is involved.
  Thornswood-Content.esp already defines a keyword called KzlCraftingAlchemy
  and nothing in the build points a recipe at it.

  There are no enchanting recipes either, with one exception. The only
  enchanting keyword any COBJ uses is 17738:Dragonborn.esm, DLC2StaffEnchanter,
  and its 160 recipes all output a staff. Enchanting a sword or a cuirass is
  the enchanting menu, not a record.

  So COBJ cannot carry the Alchemist at all, and it carries only the staff half
  of the Enchanter. Those halves are named in HALVES_WITH_NO_RECIPES below,
  with the reason, and each of them goes into the json's "halves" map with its
  own count and a craftsAtAll flag. Every other half must come out with recipes
  or this build fails.

  NOTHING IN HERE IS A REASON TO TAKE A HALF OUT OF CHARACTER CREATION, and
  this file said the opposite until 20 September. It wrote five half names into
  a field called cannotCraftYet and printed, at the end of every run, that the
  panel on K should refuse to offer them. Two of the five are Warrior/Bulwark
  and Warrior/Berserker. Warrior has no third half, so a panel built as
  instructed would have dropped the Warrior out of character creation
  altogether, and the Alchemist with it, leaving five professions of the eight.
  A half that makes nothing is a half with no crafting gate, not a half nobody
  may be.

  WHAT A CONDITION DOES TO A COUNT, AND IT IS THE FINDING OF 20 SEPTEMBER

  A COBJ can carry conditions, and until this script read them it counted a
  recipe as work whether or not anybody could reach it. The difference is not
  small. Measured on this build, of the 1728 owned rows the server is ever
  asked about, 1559 carry at least one condition, and 1125 of those want a
  vanilla perk that classes.md says nobody here will ever hold.

  Three numbers now come out per half instead of one: what it owns, what the
  server is asked about, and what somebody who picked that half this morning
  can actually make. Read down that last column and the table says something it
  never said before:
      Cook/Confectioner     28 recipes, 0 of them
      Enchanter/Bladebinder 161 recipes, 0 of them
      Cook/Hearthcook       112 recipes, 2 of them
      Woodworker/Charburner   4 recipes, 1 of them
      Smith/Platewright     771 recipes the server sees, 48 of them
  The first two fail this build unless they are named in
  HALVES_NOBODY_CAN_START with the measured reason, which they are, because the
  answer to both is a decision somebody has to make rather than a line of code.

  The Charburner's other three want a book: KzlWoodcutterAdvanced, Expert and
  Master, out of Thornswood-Content.esp, which is this repo's own plugin. The
  search under 'what hands out the items these recipes ask for' went through
  all 101 plugins for a placed reference, a container or inventory line and a
  levelled list line, found 76 of the 79 items recipes in this table ask for,
  and did not find those three anywhere. So the Charburner is one recipe, Poor
  Charcoal, and the rest of classes.md's "firewood through to coke" is waiting
  on somebody putting those books in the world.

  WHAT RANK A RECIPE ASKS FOR

  classes.md has four ranks and says each one opens more of what you can make.
  No row in this table carried one until 20 September, so a gate built on it
  could only be all or nothing per half. Every row carries a rank now, and a
  rank on the row is also the only way to express the sister half rule the
  published page promises, that an Edgewright can beat out plain iron plate and
  no more.

  WHAT SETS THAT RANK IS THE NEXT SECTION AND NOT THIS ONE. From 20 to
  21 September it was the price of what the recipe makes, cut into shares by
  the RANK_SHARE knob. That rule left three halves with an empty rung and is
  now the FALLBACK: it ranks only the rows whose inputs no class in this world
  produces. Saying otherwise here is what a reader would carry away, so this
  paragraph says it once and hands over.

  INPUT COST, AND WHY THE PRICE OF THE OUTPUT CANNOT RANK ANYTHING

  The rule above shipped on 20 September and tools\Check-Balance.ps1 found
  three halves with an empty rung the next morning. It is not a threshold and
  no threshold fixes it. Measured on 21 September, on the table this script
  itself wrote:

      Cook/Confectioner      28 recipes, TWO distinct output prices in the
                             whole half: 18 at 6 gold and 10 at 14 gold.
      Enchanter/Bladebinder 161 recipes, TWO distinct prices: 160 at 5 gold,
                             because a staff's worth is in its enchantment and
                             not in its record, and one at 1250.
      Woodworker/Charburner   4 recipes, ONE price: all four at 2 gold.

  Four rungs cannot be cut out of two numbers. The data has no spread in it,
  and the measure was wrong rather than the cut.

  What the output SELLS for is a fact about a shopkeeper. What a recipe COSTS
  is a fact about work: somebody had to go and get the makings, and they had to
  be far enough up their own ladder to be allowed to. A dessert of flour and a
  cabbage is novice work whoever priced it; a staff that wants ebony is not.

  So a recipe's rank is the rank of the DEAREST thing it asks for, read off the
  producing tables in this same folder. That answers Patrick's question of
  21 September at the same time and by construction rather than by luck:
  "we also need to make sure the different tiers match across so like farmer
  matches with tiers of cook for their recipes, miner and smith, woodworker and
  miner and so on, so there isn't an imbalance". A Cook's rungs are the
  Farmer's rungs because they are the same numbers off the same table.

  THE REVERSE INDEX. ores.json, harvests.json with its three maps and
  hunts.json are all keyed by the base that gets worked and carry the item it
  hands over, and the salt quarry this server put in the world is in
  tools\gamemode.js rather than in any of them, so it is named in a knob of its
  own. This script needs the other direction, item -> rank, and it takes the
  LOWEST rank any class gets that item at: if a novice miner can find iron
  anywhere in Skyrim then iron costs novice, whatever some expert seam also
  drops.

  THE LOWEST RANK IS NOT ALWAYS THE FARMER'S, AND THE FARMER IS THE CLASS THIS
  MATTERS TO. All 11 crops of harvests.json are the same base records as rows
  in its harvests map, Cabbage is bcf48:Skyrim.esm in both, and for every one
  of the 11 the gatherer picks it at a rank at or below the one a farmer has to
  hold to grow it. So the crops map places nothing in the index and the farmer
  owns no entry in it, which was measured on 21 September after it had been
  asserted in a comment that said the opposite. That is the lowest-wins rule
  working rather than a fault: a Cook wanting a Red Apple can be handed one by
  a novice gatherer, so a Red Apple costs novice, whoever else grows it. What
  it is NOT is Patrick's tiers lining up by construction. The run now prints
  what each table placed and what it lost to an earlier one, and prints every
  owned row that is ranked below a class that produces one of its inputs, so
  the gap between the Cook and the Farmer is a number in the output instead of
  a claim in a comment.

  WHAT IT CANNOT PLACE, AND THIS IS THE NEXT PIECE OF WORK RATHER THAN A BUG.
  The owned recipes ask for 176 distinct items and 71 of them have a producer.
  The 105 that do not are led by Leather Strips, wanted by 924 recipes, Steel
  Ingot by 888 and Leather by 665. None of those comes out of the ground: they
  come out of a smelter or a tanning rack, which is a recipe in this same
  table, in the 1679 unowned rows that anybody may make. Following that one
  extra hop is what would place the Smith's ladder against the Miner's, and it
  is not done here. Those rows fall back to the price rule and say so in their
  rankFrom field, so the gap is readable in the table rather than hidden.

  THE OWNERSHIP RULE

  Written out in full in the knobs below, because that is where somebody will
  look to change it. In short: the output record decides, and the bench decides
  where the output cannot. An ALCH splits on the poison bit and on the dessert
  keyword; a WEAP splits on its animation type, which is what separates a bow
  from a sword; an ARMO splits on whether it is clothing, jewelry or armour; a
  MISC is usually stock rather than a finished good and goes unowned.

  Nothing is forced into a profession. A recipe nobody has decided about goes
  in the unowned map with the reason it landed there, and unowned means anybody
  may make it, which is the right default for something nobody has settled.

  Warriors do not craft. Bulwark and Berserker are halves of how somebody
  fights, not of what they make, and there are no warrior recipes to find. No
  recipe is invented for them, they are named in HALVES_WITH_NO_RECIPES with
  craftsAtAll false, and the profession is offered like any other.

  The Mage is in the roster too, with no halves at all, for the same reason: a
  panel built from the professions map in this file has to be able to offer all
  eight of classes.md's professions. What a mage knows is spells, and
  tools\Build-SpellTable.ps1 is what writes those.

  Read only. It touches nothing in the game folder and nothing on the VPS, and
  it proves that with a fingerprint of the folder before and after.

  Usage:
    .\tools\Build-RecipeTable.ps1
    .\tools\Build-RecipeTable.ps1 -Data 'C:\Thornswood\Game\Data'
    .\tools\Build-RecipeTable.ps1 -NoInstall
    .\tools\Build-RecipeTable.ps1 -JsOut "$env:TEMP\recipes.js"

  Exit code 1 if a recipe's output does not resolve to a real record, if an
  owner is not one of the professions in classes.md, if a half is not one of
  its two, if a recipe lands on a profession that has no halves, if a recipe is
  listed twice, if an owned recipe makes something the records put no price on
  and so cannot be ranked, if a half that is meant to have recipes has none, if
  a half named as empty turns out to have some, if a half with recipes has
  nothing at all a new character can make and is not named in
  HALVES_NOBODY_CAN_START, if a half named there turns out to have something,
  if one of the producing tables named in PRODUCER_TABLES is missing or has no
  map of that name, if any half is left with an empty rung below a full one
  after both ranking rules have run, counting every owned row and counting only
  the rows the server is asked about, or if the game folder changed while this
  ran. Nothing is written unless every check passed.
#>
param(
    # The build's Data folder. Read only.
    [string]   $Data       = 'C:\Thornswood\Game\Data',
    # The load order. The five Bethesda masters are always first and are never
    # in this file, so they are put in front of it.
    [string]   $PluginsTxt = 'C:\Thornswood\Profile\Default\plugins.txt',
    # Overrides the load order entirely when it is given.
    [string[]] $Plugins    = @(),
    [string]   $Out        = '',
    [string]   $JsOut      = '',
    # Print the block and leave tools\gamemode.js alone.
    [switch]   $NoInstall
)

# ---------------------------------------------------------------- knobs ----
#
# classes.md is the rulebook. It settles the eight professions, the two halves
# of each, and that what your half is decides what you are able to make at all.
# It settles nothing about which Skyrim record belongs to which half, because
# it was written about the world and not about the plugins. Everything below is
# this script's judgement, in one place, so that changing it is one edit and a
# rebuild rather than a hunt through the code.
#
# LANGUAGE: which string table the names come from. classes.md says nothing
# about language; the server and the panel on K are English, so English.
$LANGUAGE = 'english'

# THE PROFESSIONS AND THEIR HALVES, copied from classes.md and from nowhere
# else. Every owner this script writes must be one of these eight and every
# half must be one of that profession's two. The check at the bottom enforces
# it, which is what stops a typo inventing a ninth trade.
#
# THE MAGE IS IN THIS LIST WITH NO HALVES, AND THAT IS THE FIX FOR A REAL BUG.
# It was left out of the table entirely until 20 September on the grounds that
# a mage makes nothing a COBJ record describes, which is true and was not a
# reason to leave it out. The professions map in recipes.json is the only
# roster of professions this file ships, so a panel built from it offered seven
# professions and lost the Mage, while this script's own comments called it
# "the eight professions" over a table holding seven. classes.md's table has
# eight rows, with Mage second, and gamemode.js already offers mage with
# halves: null, schools: 2, mastered: 3.
#
# So the Mage is here, with an empty half list, and recipes.json says in as
# many words that it has no halves and makes nothing by recipe. What a mage
# knows is spells, and Build-SpellTable.ps1 is what writes those.
$PROFESSIONS = [ordered]@{
    'Warrior'    = @('Bulwark', 'Berserker')
    'Mage'       = @()
    'Alchemist'  = @('Blightbrewer', 'Physicker')
    'Cook'       = @('Hearthcook', 'Confectioner')
    'Smith'      = @('Platewright', 'Edgewright')
    'Enchanter'  = @('Bladebinder', 'Wardweaver')
    'Tailor'     = @('Liverywright', 'Haberdasher')
    'Woodworker' = @('Charburner', 'Woodwright')
}

# WHETHER A PROFESSION MAKES THINGS BY RECIPE AT ALL, and the sentence that
# says why when it does not. Every profession above needs a line here.
#
# This exists because "this half owns no recipes" and "this half is broken"
# came out of this script as the same statement, and a panel written from that
# would drop the Warrior out of character creation. A Warrior owning no recipes
# is classes.md working as written. A Wardweaver owning none is a gap in what
# the records can express. Both are true, neither should stop somebody picking
# the profession, and only the second one is ever going to be fixed.
#
# Crafts = $false means the crafting gate has nothing to say about this
# profession. It does NOT mean hide it: the panel on K offers all eight.
$PROFESSION_CRAFTS = [ordered]@{
    'Warrior'    = @{ Crafts = $false; Why = 'warriors do not craft. classes.md gives Bulwark and Berserker combat maneuvers rather than recipes, so there is nothing in the records to find and nothing for a crafting gate to refuse. The profession is offered like any other.' }
    'Mage'       = @{ Crafts = $false; Why = 'a mage has no halves. classes.md gives the Mage two schools and two starting spells, and none of it is a crafting recipe. What a mage knows is written by tools\Build-SpellTable.ps1.' }
    'Alchemist'  = @{ Crafts = $true;  Why = '' }
    'Cook'       = @{ Crafts = $true;  Why = '' }
    'Smith'      = @{ Crafts = $true;  Why = '' }
    'Enchanter'  = @{ Crafts = $true;  Why = '' }
    'Tailor'     = @{ Crafts = $true;  Why = '' }
    'Woodworker' = @{ Crafts = $true;  Why = '' }
}

# HALVES THAT ARE MEANT TO COME OUT EMPTY, each with the measured reason.
#
# A half that can make nothing is a half nobody should be allowed to pick. That
# circle has bitten this repo twice, in farming and in gathering, so the check
# at the bottom fails the build when a half comes out with no recipes. This knob
# is the short list of halves where the emptiness is a fact about Skyrim rather
# than a mistake in this script, and every one of them was measured, not
# assumed. A half in this list that turns out to HAVE recipes also fails the
# build, because then this list is out of date and somebody has to look.
#
# These halves go into recipes.json under "halves", each with its own count and
# its own reason. WHAT THEY DO NOT DO IS COME OUT OF CHARACTER CREATION.
#
# Until 20 September this knob wrote its five names into a json field called
# cannotCraftYet and this script printed, at the end of every run, that the
# panel on K should refuse to offer them. Two of the five are Warrior/Bulwark
# and Warrior/Berserker, and Warrior has no third half, so a panel built as
# instructed would have dropped the whole Warrior profession out of character
# creation, and the Alchemist with it. gamemode.js offers warrior with exactly
# those two halves today.
#
# So each entry now says which of the two things is true, and the json says it
# too, because the reason strings alone left a consumer nothing to test:
#   Crafts = $false  the half is not about making anything. classes.md wrote it
#                    that way. Offer it, and the crafting gate stays quiet.
#   Crafts = $true   the half makes things and this build has no records for
#                    them yet. Offer it, and say so where somebody picking it
#                    can read it, because it is a gap rather than a design.
# Nothing here is a reason to hide a half. A half nobody may pick is a
# profession nobody may pick, and that is a bigger hole than an empty trade.
$HALVES_WITH_NO_RECIPES = [ordered]@{
    'Warrior/Bulwark'      = @{ Crafts = $false; Why = 'warriors do not craft. Bulwark and Berserker are halves of how somebody fights, and classes.md gives them combat maneuvers rather than recipes. There is nothing in the records to find.' }
    'Warrior/Berserker'    = @{ Crafts = $false; Why = 'the same. Warrior is the one profession whose halves are not about making anything.' }
    'Alchemist/Blightbrewer' = @{ Crafts = $true; Why = 'Skyrim has no alchemy recipes. Not one COBJ record in the whole load order names an alchemy bench keyword: potions are worked out from the effects that the ingredients share, in the alchemy menu, and no record is involved. The poison bit that would split this half from the Physicker is proved and ready in the code above, so the moment a mod adds an alchemy bench recipe it lands here by itself.' }
    'Alchemist/Physicker'  = @{ Crafts = $true; Why = 'the same. There is nothing for this table to gate until alchemy is answered somewhere other than a recipe record.' }
    'Enchanter/Wardweaver' = @{ Crafts = $true; Why = 'the only enchanting recipes in the build are the staff recipes on the Dragonborn staff enchanter, and a staff is a weapon, so they all land on the Bladebinder. Enchanting a cuirass or a robe is the enchanting menu and not a record, so the Wardweaver has nothing to own here.' }
}

# WHAT THE ENGINE NEVER ASKS ABOUT. CraftService::RecipeItemsMatch throws
# tempering out before it considers any recipe, by these two bench keywords,
# hardcoded there as ArmorTable = 0xadb78 and SharpeningWheel = 0x88108. Read
# out of the fork, not remembered. A recipe on one of these still gets an owner
# here, because it is still that half's work, but it is marked as one the
# server is never asked about and it is left out of the gamemode block.
$BENCHES_THE_SERVER_NEVER_SEES = @('adb78:Skyrim.esm', '88108:Skyrim.esm')

# WHICH CONDITION FUNCTIONS THE SERVER CAN ACTUALLY EVALUATE. Read out of
# C:\Thornswood-Dev\skymp on 20 September, one file per number:
# skymp5-server/cpp/server_guest_lib/condition_functions/*.cpp, each with a
# GetFunctionIndex that returns the number below, and
# ConditionFunctionFactory::CreateConditionFunctions registering every one of
# them into the map the world state holds.
#
# This matters because of what happens to the ones that are NOT in the map.
# ConditionsEvaluator.cpp, the branch that runs when the map has no function
# for an index: it logs "doesn't exist. Evaluating condition to True" and
# returns true. So a condition the fork does not implement is not enforced by
# the server at all: the server waves it through.
#
# That is not the same as the recipe being available. Skyrim's own crafting
# menu evaluates the same CTDA list on the machine in front of the person and
# only lists the recipes whose conditions pass. A recipe whose condition fails
# there is never shown, so it is never asked for, so onCraft never fires and
# the server never gets to have an opinion. A row like that is in this table,
# owned by a half, and unreachable by anybody.
#
# The three SkympGetDamageSourceHasKeyword, SkympGetIsDamageSource and
# SkympWornHasKeywordCount functions return uint16 max for their index, which
# no CTDA carries, so they are not in this list.
$CONDITION_FUNCTIONS_THE_SERVER_HAS = @{
    47  = 'GetItemCount'
    69  = 'GetIsRace'
    101 = 'IsWeaponMagicOut'
    182 = 'GetEquipped'
    254 = 'GetIsPlayableRace'
    263 = 'IsWeaponOut'
    264 = 'HasSpell'
    300 = 'IsInInterior'
    569 = 'IsBlocking'
    596 = 'SpellHasKeyword'
    597 = 'GetEquippedItemType'
    640 = 'GetActorValuePercent'
    682 = 'WornHasKeyword'
    722 = 'WornApparelHasKeywordCount'
}

# THE VANILLA PERK CONDITION. Function index 448 is not in the fork's map and
# so is not named by it. It is named here from what its parameter resolves to
# rather than from memory: every CTDA in this build carrying 448 resolves its
# first parameter to a PERK record, and the count is printed every run under
# 'conditions'. That is Skyrim's HasPerk.
#
# classes.md line 4: "Nothing you do raises a vanilla skill and no perk menu
# opens when you sleep", and the page says vanilla progression being off is the
# part already shipped. So no character on this server will ever hold a vanilla
# perk. A recipe behind one is a recipe nobody can reach, whatever this table
# says about who owns it, and the count of them per half is printed and written
# into the json so that a half made entirely of them is visible rather than
# reported as work.
$CONDITION_VANILLA_PERK = 448

# HOW A CONDITION IS READ OUT LOUD. The operator is the top three bits of the
# CTDA's first byte, and these six are the enum in
# libespm/include/libespm/CTDA.h.
$CONDITION_OPERATORS = @('==', '!=', '>', '>=', '<', '<=')

# ---------------------------------------------------------------- ranks ----
#
# THE FOUR RANKS, from classes.md's own table and in its order. A row in this
# table carries one of these, and the gate compares it against the rank the
# character holds in that half.
#
# Until 20 September no row carried a rank at all, and a gate built on the
# table could only be all or nothing per half: either a Platewright made
# DaedricArmor on the morning they were created or they made nothing. Both of
# those contradict the published page. classes.md: "Each rank opens more of
# what you are able to make", and its Novice row is "the basics of your half,
# and not much of it".
#
# A rank on every row is also what makes classes.md's sister half rule
# expressible, and it is the only thing that can: "You get the novice work of
# your sister half for nothing. An Edgewright knows how to beat out plain iron
# plate." The gate reads that as: your own half at your own rank, plus the
# other half of your own profession at novice and no further. It cannot ask
# that question of a table whose rows have no rank.
$RANKS = @('novice', 'advanced', 'expert', 'master')

# WHAT RANK A RECIPE ASKS FOR. INVENTED. classes.md sets no numbers and nothing
# in the records ranks a recipe, so this is the judgement, in one place.
#
# The measure is the gold value of what the recipe makes, which is the one
# number the records already carry about how much of a thing a thing is, and it
# is the same measure Build-HarvestTable.ps1 ranks a plant by. What could not
# be copied from that script is its fixed gold ceilings, and the reason is
# printed under 'ranking' every run: the halves do not share a scale. What a
# Confectioner makes runs from a few gold to a few tens of gold, and what a
# Platewright makes runs to thousands. One ceiling in gold across all of them
# would put every dessert in the game at novice and every piece of armour above
# it, which ranks the Cook's whole trade as beginner's work and leaves a
# Platewright with nothing to start on.
#
# So the split is per half: sort that half's rows by what they make, cheapest
# first, and cut the list at these shares. Read as "novice is the cheapest
# quarter of your own half's work". Every half gets a novice rung by
# construction, which is the point.
#
# The spread each half actually has is printed every run, under 'ranking', so
# these shares can be moved against real numbers. Measured on 20 September:
#   Cook/Confectioner       28 rows from 6 to 14 gold
#   Smith/Platewright     2015 rows from 2 to 24634 gold
#   Woodworker/Woodwright  124 rows from 0 to 26305 gold
#   Woodworker/Charburner    4 rows, all of them 2 gold
# One gold ceiling across that is not a ladder, it is a wall with the Cook on
# the wrong side of it.
#
# TWO RUNGS COME OUT EMPTY IN THIS BUILD AND THAT IS THE TIE RULE WORKING, not
# a mistake. A cut never splits a run of rows that make things worth the same,
# because two recipes for things of equal worth on different rungs is a rule
# nobody could explain to the person it refuses. The Confectioner has 18 of its
# 28 desserts priced the same, so novice takes all 18 and advanced takes none.
# The Bladebinder has 160 staves priced at 5 gold each, because a staff's worth
# is in its enchantment rather than its record, so 160 rows sit at novice and
# the Aetherial Staff at 1250 sits alone at master.
#
# THIS RULE IS NOW THE FALLBACK AND NOT THE RULE, and the paragraph above is
# why. Read the two sentences again: three halves come out with an empty rung
# and no threshold anywhere can fix it, because the data those halves have is
# two numbers. Measured on 21 September, on the table this script wrote:
#   Cook/Confectioner       28 rows, TWO distinct prices: 18 at 6 gold, 10 at 14
#   Enchanter/Bladebinder  161 rows, TWO distinct prices: 160 at 5, one at 1250
#   Woodworker/Charburner    4 rows, ONE price: all four at 2 gold
# No ranking by output price makes four rungs out of two numbers. The tie rule
# is not the problem and moving the shares is not the answer; the measure is.
# What ranks a recipe now is INPUT COST, below, and the shares here rank only
# the rows whose inputs no class in this world produces.
$RANK_SHARE = @(
    @{ Rank = 'novice';   Upto = 0.25 },
    @{ Rank = 'advanced'; Upto = 0.60 },
    @{ Rank = 'expert';   Upto = 0.85 },
    @{ Rank = 'master';   Upto = 1.00 }
)

# WHAT A RECIPE COSTS THE PERSON WHO HAS TO GATHER FOR IT. INVENTED, in the
# sense that classes.md sets no numbers for it, and measured in the sense that
# every number it reads comes out of a table built from the game's own records.
#
# PATRICK, 21 September: "we also need to make sure the different tiers match
# across so like farmer matches with tiers of cook for their recipes, miner and
# smith, woodworker and miner and so on, so there isn't an imbalance".
#
# That request and the three empty rungs above are the same defect from two
# ends. A recipe's rank came from what its output SELLS for, which is a fact
# about a shopkeeper and not about work. A dessert of flour and a cabbage is
# novice work whoever priced it. A staff that wants ebony is not. Rank a recipe
# by what its inputs cost somebody to get and the empty rungs close, and the
# Cook is reading the same numbers off the same tables the producing classes
# are ranked from.
#
# IT DOES NOT MAKE THE COOK'S RUNGS THE FARMER'S, and this comment claimed it
# did until 21 September. The index takes the LOWEST rank any class gets an
# item at, and every crop a farmer grows is also a plant a gatherer picks at
# the same rank or lower, so the farmer never sets a number here at all.
# Measured on the build of 21 September: 12 Cook rows are ranked below the
# farmer rank of a crop they ask for, Apple Dumpling at novice against an
# expert farmer's Red Apple among them. That is defensible, because the apple
# in the pot does not care who pulled it, but it is not the same sentence, and
# the difference is now printed under 'where a ladder sits below the class that
# grows what it asks for' every run instead of being asserted here.
#
# THE FIVE PRODUCING LADDERS, all already built and all in this folder. Each
# one is keyed by the base that gets worked, a vein or a plant or an animal,
# and carries the descriptor of the ITEM it hands over. This script needs the
# reverse of that: item -> the rank somebody has to hold to get it.
$PRODUCER_TABLES = @(
    @{ File = 'ores.json';     Map = 'ores';     Who = 'miner';    Item = 'ore';     List = ''      },
    @{ File = 'harvests.json'; Map = 'harvests'; Who = 'gatherer'; Item = 'produce'; List = ''      },
    @{ File = 'harvests.json'; Map = 'crops';    Who = 'farmer';   Item = 'produce'; List = ''      },
    @{ File = 'harvests.json'; Map = 'fish';     Who = 'fisher';   Item = 'produce'; List = ''      },
    @{ File = 'hunts.json';    Map = 'hunts';    Who = 'hunter';   Item = 'item';    List = 'gives' }
)

# THE SIXTH LADDER, AND IT IS NOT IN A JSON FILE BECAUSE THIS SERVER WROTE IT.
# INVENTED in the sense that classes.md sets no numbers for it. Every rank in
# it was read off tools\gamemode.js on 21 September rather than remembered, and
# the line it was read from is written beside it.
#
# The five tables above are built from the game's own records. The salt quarry
# is not in the game's records at all: STATIONS.saltQuarry is a base this
# repository's own plugin put in the world, gamemode.js answers it in
# mineSalt(), and no script writes a json table for it. So the reverse index
# could not see it, and the whole of it was missing from the one place that
# decides what a recipe costs.
#
# WHAT THAT COST, MEASURED ON THE BUILD OF 21 SEPTEMBER before this knob
# existed: 98 owned rows ask for a Salt Pile and 38 ask for a rare salt, 138
# input entries in all, and every one of them came back producedBy null. Four
# of those rows, two Bread Loaf and two Cooked Boar Meat, ask for salt and for
# nothing else the index could place, so they carried 'nothing it asks for is
# produced by any class in this world' while a novice miner was in fact handing
# salt over at the quarry. The two Cooked Boar Meat rows sat at advanced on the
# price rule and are novice work by the input rule.
#
# WHAT IS IN IT AND WHAT IS DELIBERATELY NOT.
#   mineSalt() gates on classGate(actorId, 'mine') and the pickaxe and then
#   gives randInt(1, 2 + step) Salt Pile, where step is 0 for a novice, so a
#   novice miner works salt. Salt Pile is novice, miner.
#   The same function rolls a rare salt only when rankStep is 2 or more, which
#   is expert on RANK_LADDER, so Fire, Frost and Void Salts are expert, miner.
#   The charcoal kiln is NOT here. It is a profession's verb rather than a
#   class's, it consumes firewood somebody already has rather than producing
#   from the world, and no recipe in this table asks for charcoal of any grade:
#   measured over all 5116 rows, zero want 33760:Skyrim.esm or any of the four
#   Thornswood-Content grades.
#   The beehive is NOT here either. It hands its produce over as a FLOR like
#   any flower and nothing in gamemode.js gives an item for it, and no row of
#   harvests.json produces Honey, which two recipes want. That is a gap in the
#   harvest table rather than a class ladder this script can name.
$SERVER_PRODUCERS = @(
    @{ Desc = '34cdf:Skyrim.esm'; Name = 'Salt Pile';   Who = 'miner'; Rank = 'novice';
       Where = 'tools\gamemode.js mineSalt(), addItem(actorId, ITEMS.saltPile, randInt(1, 2 + step))' },
    @{ Desc = '3ad5e:Skyrim.esm'; Name = 'Fire Salts';  Who = 'miner'; Rank = 'expert';
       Where = 'tools\gamemode.js mineSalt(), the rare roll behind step >= 2' },
    @{ Desc = '3ad5f:Skyrim.esm'; Name = 'Frost Salts'; Who = 'miner'; Rank = 'expert';
       Where = 'tools\gamemode.js mineSalt(), the rare roll behind step >= 2' },
    @{ Desc = '3ad60:Skyrim.esm'; Name = 'Void Salts';  Who = 'miner'; Rank = 'expert';
       Where = 'tools\gamemode.js mineSalt(), the rare roll behind step >= 2' }
)

# LOWEST WINS IN THE REVERSE INDEX, and this is a judgement rather than an
# obvious truth, so it is a knob with the argument written next to it.
#
# The same item is produced in more than one place at more than one rank. Iron
# Ore comes off novice seams all over Skyrim and off a handful of seams that
# this table ranks higher. If a novice miner can get iron ANYWHERE, then iron
# costs novice, and a recipe wanting iron is novice-cost work. Taking the
# highest instead would rank a recipe by the unluckiest place to find its
# inputs, which is not what it costs anybody.
#
# Set this to $false and the index records the dearest rank instead, which is
# worth doing once to see how far it pushes every half up.
$PRODUCER_RANK_IS_LOWEST = $true

# WHETHER THE INPUT RULE RANKS AT ALL. Set to $false and every row falls back
# to RANK_SHARE, which is what this script did before 21 September, including
# the three empty rungs.
$RANK_FROM_INPUT_COST = $true

# THE FLOOR IS THE DEAREST INPUT, not the cheapest and not an average. A recipe
# is unmakeable until you can get ALL of it, so the rung somebody has to have
# reached is the rung of the hardest thing on the list. An average would say a
# staff of ebony and firewood is advanced work, and nobody can make half a
# staff.
$INPUT_RANK_IS_THE_DEAREST = $true

# WHAT TO DO WITH A ROW WHOSE SHOPPING LIST IS ONLY HALF PLACED. INVENTED:
# classes.md sets nothing here, and until 21 September the code did not ask the
# question at all, which is how the worst defect in this build got in.
#
# 'the dearest input' above can only be the dearest of the inputs the index can
# SEE. An input nothing produces is an unknown cost, not a cost of nothing, and
# the rule above skipped it silently and then overrode the price rank anyway.
#
# WHAT THAT DID, MEASURED ON THE BUILD OF 21 SEPTEMBER. Dragon Knight Light
# Armor is worth 3100 gold and asks for Dragon Scales, Dragon Bone, Ebony Ingot
# and Refined Malachite, none of which any class produces, and one Snow Fox
# Pelt, which a hunter skins at novice. The four unknowns were skipped, the fox
# pelt was the dearest of what was left, and the row went out at NOVICE: a
# first-day Platewright allowed dragonbone armour. It was not one row. 301 of
# the 320 firing rows the input rule fired on carry at least one input nothing
# produces; 150 landed below the rank the price rule gave them and 49 of those
# fell two rungs or more, Wild Hunt Heavy Helm master to novice, 14 Hearthcook
# stews expert to novice off a Salt Pile.
#
# 'floor'    IN USE. When every input is placed, the dearest one decides, which
#            is the rule above unchanged. When any input is not placed, the
#            dearest placed one can only RAISE the row above what its price
#            said and never lower it, because the things nobody produces could
#            cost anything and a fox pelt is not evidence that dragon bone is
#            cheap. The row says which of the two answered, in rankFrom.
# 'decides'  what shipped on 21 September: the dearest placed input decides
#            whatever else is on the list. The numbers above are what it does.
# 'price'    a row with any unplaced input is not ranked by its inputs at all
#            and keeps the price rank. Honest, and it throws away the one thing
#            the index does know about 301 rows.
$UNPLACED_INPUT_RULE = 'floor'

# THE SECOND RULE, for a half the first two rules leave with an empty rung.
# INVENTED. classes.md does not set it, and it is here rather than in the code
# so that it is one edit to change and impossible to apply by accident.
#
# Some halves cannot be ranked by either honest measure, and that is a fact
# about the records rather than a failure of a threshold. The Bladebinder is the
# case this was written for, and it is worth writing out in full because it is
# the one place in this table where a rank does NOT mean what every other rank
# means. Measured on 21 September, on this build:
#   every one of its 161 rows sells for 5 gold but one, so price says nothing;
#   160 of the 161 want a Heart Stone, which ores.json ranks as master work for
#   a miner, so input cost puts the WHOLE half on master and leaves novice,
#   advanced and expert with nothing on them.
# Two honest rules, one rung between them, and a half nobody could ever climb.
#
# What DOES vary there is the shopping list: 5 distinct total input counts
# across the 161 rows against 2 distinct prices and 1 distinct input rank. The
# run prints those three numbers for any half it is about to re-rank, so the
# choice below can be argued with against numbers rather than taste.
#
# WHAT THIS COSTS, SAID OUT LOUD. A Bladebinder row ranked novice by this rule
# still wants a Heart Stone. The rank stops meaning "what it costs you" for
# that half and starts meaning "how long its shopping list is".
# tools\Check-Balance.ps1 counts every row more than one rung from its input
# cost and prints them by name: on this build it is 97 rows, all of them
# Bladebinder. It is the least bad of three answers, the other two being a half
# with one usable rung or an invented recipe, and it is a knob so that somebody
# who decides otherwise changes one line.
#
# AND IT IS NOT ENOUGH ON ITS OWN, WHICH WAS FOUND ON 21 SEPTEMBER. Counting
# rows on a rung cannot see whether anybody can stand on it. All 41 rows this
# rule put on the Bladebinder's novice rung want a Heart Stone, which
# ores.json ranks master on all four of its deposits, so a novice Bladebinder
# opens 41 recipes and can gather the makings for none of them. That is the
# exact circle the empty rung rule exists to catch, and both this script and
# Check-Balance were passing it, because the only thing the second rule changed
# was the label. So the standability check below now asks the other question,
# and a half that fails it has to be named in the knob under it with the
# measured reason or this build does not write a table.
#
# 'total inputs'    how many things the recipe wants in all, counting three
#                   firewood as three. This is the one in use: it is the
#                   closest thing the records have to how much work went into
#                   standing at the bench with everything ready.
# 'distinct inputs' how many different things it wants. Fewer distinct values
#                   in every half measured, so it collapses sooner.
$SECOND_RULE_KEY = 'total inputs'

# A RUNG YOU CAN REACH AND CANNOT GATHER FOR IS STILL AN EMPTY RUNG. INVENTED,
# and it is the other half of the rule HoleIn already enforces.
#
# HoleIn asks whether a rung has rows on it. This asks whether anybody standing
# on that rung could get the makings for even one of them. A row is standable
# at its rung when the dearest input any class produces for it is at or below
# that rung, or when nothing it asks for is produced by a class at all, which
# means a shop or another recipe hands it over and no class rank is in the way.
#
# Set this to $false and the build goes back to counting rows and calling that
# a ladder, which is what it did until the Bladebinder's 41 Heart Stone rows
# were measured on 21 September.
$RUNGS_MUST_BE_STANDABLE = $true

# THE HALVES WHOSE LADDER IS KNOWN TO HAVE AN UNSTANDABLE RUNG, each with the
# measured reason, in the shape of HALVES_NOBODY_CAN_START above and for the
# same purpose: a fact somebody decided to live with, written down, rather than
# a check quietly passing. Any half not named here that fails the check fails
# the build, because a rung nobody can gather for is a rank that opens nothing.
$HALVES_WITH_AN_UNSTANDABLE_RUNG = [ordered]@{
    'Enchanter/Bladebinder' = 'its novice, advanced and expert rungs are the second rule''s, not the input rule''s. 160 of its 161 rows want a Heart Stone and ores.json ranks all four Heart Stone deposits master, so every rung below master holds rows nobody at that rank can gather for. The second rule is argued for at SECOND_RULE_KEY and this is the price of it, stated rather than passed over: the half is ranked by how long a recipe''s shopping list is and the shopping list starts with a master miner''s stone either way. It closes when somebody decides where an Enchanter''s Heart Stones come from, which is the same decision HALVES_NOBODY_CAN_START is waiting on for this half.'
}

# WHERE THE GOLD VALUE SITS IN EACH KIND OF RECORD. The first five were proved
# in Build-HarvestTable.ps1 and are copied from its VALUE_RULES knob. AMMO and
# BOOK are not in that script, because nothing a gatherer picks is either, and
# both were measured here on 20 September against Skyrim.esm:
#   AMMO DATA is 20 bytes and FollowerIronArrow reads 245265, 6, 8.0, 1 as the
#   four fields, so the value is the uint32 at offset 12 and an iron arrow is
#   worth 1 gold, which is what an iron arrow is worth.
#   BOOK DATA is 16 bytes and SpellTomeThunderbolt reads 4, 1112046, 750, 1.0,
#   so the value is the uint32 at offset 8 and a spell tome is worth 750.
# A row whose output type is not in here cannot be ranked and fails the build
# rather than being guessed at, because a rank invented without a price would
# decide what a real person may make.
$VALUE_RULES = [ordered]@{
    'INGR' = @{ Sub = 'DATA'; At = 0 }
    'MISC' = @{ Sub = 'DATA'; At = 0 }
    'SLGM' = @{ Sub = 'DATA'; At = 0 }
    'KEYM' = @{ Sub = 'DATA'; At = 0 }
    'ARMO' = @{ Sub = 'DATA'; At = 0 }
    'WEAP' = @{ Sub = 'DATA'; At = 0 }
    'ALCH' = @{ Sub = 'ENIT'; At = 0 }
    'AMMO' = @{ Sub = 'DATA'; At = 12 }
    'BOOK' = @{ Sub = 'DATA'; At = 8 }
}

# THE NOVICE RUNG HAS TO BE REACHABLE ON THE DAY SOMEBODY PICKS THE HALF.
#
# PATRICK, 20 September, about the farming table: "they cant grow them if they
# dont have the rank, they cant get the rank if they dont level up from growing
# them, they cant get the rank if they cant grow them". The same circle is
# waiting here, and it closes in a worse way, because a recipe can be gated
# twice: by this table's rank, and by a CTDA the game's own crafting menu
# enforces before the server sees anything.
#
# So after the shares above have ranked a half, the cheapest row of that half
# that a character created this morning can actually reach, meaning it carries
# no condition at all, is moved to novice if it is not there already. Every
# move is printed under 'ranking' with the row it moved, so the rule is visible
# rather than silent. Set this to $false and the shares stand as they fall,
# which is worth doing once to see how many halves it strands.
$NOVICE_MUST_BE_REACHABLE = $true

# HALVES WHERE NOBODY CAN MAKE ANYTHING ON THE DAY THEY PICK IT, each with the
# measured reason. The check at the bottom fails the build for any half that
# has recipes, has rows the server is asked about, and has not one row a new
# character can reach, unless it is named here.
#
# This is a different question from the empty half check above and it had to be
# asked separately: a half can own hundreds of rows and still be empty in
# practice, which is exactly what two of these are. The counts printed every
# run now carry both numbers side by side for this reason.
$HALVES_NOBODY_CAN_START = [ordered]@{
    'Cook/Confectioner'     = 'every one of its 28 recipes carries two vanilla perk conditions, function index 448: MAG_FoodUpgradePerk03 out of Gourmet.esp on all 28, and a second perk named for the recipe itself, MAG_RecipePerkSnowberryDumpling and its like, on all 28 as well. classes.md says no perk menu opens and vanilla progression is off, so nobody here will ever hold either. The server would wave the condition through, because the fork has no function for that index, but Skyrim''s own crafting menu evaluates it first and never lists the recipe, so onCraft is not even reached. The dessert keyword split is right and the half is real; what is missing is somebody deciding what a new Confectioner starts able to bake. Four of the 28 want an item on top of the perks.'
    'Enchanter/Bladebinder' = '160 of its 161 recipes are the Dragonborn staff enchanter''s, and every one of those 160 carries a HasSpell condition naming the staff''s own spell: Thunderbolt, Turn Undead, the Odin wall spells. That one the server really does evaluate, function index 264 against MpActor::GetSpellList in the fork, so it is refused twice over. A new Enchanter has no spells at all: classes.md gives starting spells to the Mage alone and says nothing is handed out at the start but the clothes you stand in. The 161st is DLC1LD_RecipeAetherialStaff, which wants the Aetherium Crest and is behind the Dawnguard chain that ends in one. So the half is 0 of 161 on the day somebody picks it and stays there until the apprenticeship system classes.md describes is built, or until somebody decides what spells an Enchanter starts holding.'
}

# WHEN A HALF IS THIN ENOUGH TO NAME OUT LOUD. A half with a handful of rows a
# new character can reach passes the check above and is still worth printing
# row by row, because the difference between four recipes and one recipe is
# invisible in a count. The Charburner is the case this was written for.
$THIN_HALF_ROWS = 3
# How many of those rows to print before the rest are left to recipes.json. The
# Hearthcook trips the rule above with 2 of 112, and 110 lines of soup buries
# everything else in the run.
$THIN_HALF_LINES = 6

# THE ALCH FLAG BITS, proved in the header above against the records that carry
# them. Bit 1 is a no-auto-calc bit and says nothing about what the thing is.
$ALCH_FLAG_FOOD   = 0x00000002
$ALCH_FLAG_POISON = 0x00020000

# THE WEAPON ANIMATION TYPE. The first byte of a WEAP record's DNAM. Measured
# across every WEAP a recipe in this build outputs, against the WeapType
# keyword on the same record: 1 sword, 2 dagger, 3 war axe, 4 mace, 5
# greatsword, 6 battleaxe and warhammer, 7 bow, 8 staff, 9 crossbow. The
# animation byte and the keyword agree on all but a handful of mod records
# where the keyword is the wrong one, and the byte is the one the game animates
# from, so the byte wins.
$WEAP_ANIM_BOW      = 7
$WEAP_ANIM_STAFF    = 8
$WEAP_ANIM_CROSSBOW = 9

# WHO OWNS A BOW. This is the one place where the obvious rule and classes.md
# disagree, and classes.md wins because it is the rulebook.
#
# The obvious rule is that the smithing forge with a WEAP output is the
# Edgewright's. Bows are made at the forge and they are WEAP records, so the
# obvious rule hands every bow in the game to the Edgewright. classes.md says
# the Woodwright does "bows, arrows and instruments", in as many words. A
# server that let an Edgewright make bows would be contradicting the page the
# testers read.
#
# So a WEAP whose animation type is a bow or a crossbow goes to the Woodwright,
# and so does every AMMO, which is arrows and bolts and nothing else. Set this
# to $false and bows go back to the Edgewright and arrows go unowned, which is
# the plain forge rule with no carve-out.
$WOODWRIGHT_TAKES_BOWS_AND_ARROWS = $true

# WHO OWNS AN INSTRUMENT. The same sentence of classes.md, and it was half
# followed until 20 September: "**Woodwright**, bows, arrows and instruments".
# The bow carve-out above tests the animation type and nothing else, so the
# three instrument recipes in this build fell past it into the plain forge rule
# and came out as the Edgewright's. A Woodwright could not make a flute and a
# swordsmith could, which is the exact contradiction with the published page
# that the bow knob was written to prevent.
#
# The records were read before this rule was written. RecipeWeaponFlute,
# RecipeWeaponLute and RecipeWeaponDrum, all from PlayFluteLuteDrum.esp, all at
# CraftingSmithingForge, output FluteWeapon, LuteWeapon and DrumWeapon. All
# three outputs are WEAP records carrying animation byte 0, which is hand to
# hand, and an empty keyword list. So the records themselves say these are not
# weapons of any type, and neither the animation rule nor the keyword rule can
# reach them.
#
# What is left is the name, so that is what this is, and it is a judgement
# rather than a reading. It is matched as a whole word against the output's
# editor id and its name, so a Drum matches and a Drumstick does not. The
# count of what it catches is printed every run: if a mod ever adds a fourth
# instrument, it lands here by itself, and if this rule ever catches something
# that is not an instrument it is visible in that line.
$WOODWRIGHT_TAKES_INSTRUMENTS = $true
$INSTRUMENT_WORDS = @('Flute', 'Lute', 'Drum')

# WHICH FOOD IS A DESSERT. This was expected to be a judgement and it is not,
# on this build, which is worth writing down because the next person will
# expect it to be a judgement too.
#
# What was tried first and thrown away: the ALCH value in gold (a sweetroll and
# a beef stew are both cheap, so price says nothing), the record's own name (a
# list of words is a list of names by another route), and the ALCH food bit
# (every cooked thing carries it, desserts included, so it separates nothing).
#
# What is actually in the records: the Gourmet mod in this load order puts a
# food type keyword on every cooked food it touches, and one of them is
# MAG_FoodTypeDessert. Counted over the cooking benches: 28 dessert, 24 stew,
# 22 meat, 18 soup, 14 cheese, 8 vegetable, 8 bread, 4 fish, 2 crab, 2 chowder.
# So the split is read out of a keyword after all, and it is the mod's own
# classification rather than this script's opinion.
#
# Bread is not a dessert and goes to the Hearthcook. That is the keyword's
# answer and not an argument this script is having.
#
# On a build without Gourmet this keyword does not exist, every cooked thing
# falls to the Hearthcook, and the Confectioner comes out empty, which fails
# the build loudly rather than quietly. That is the right failure: it means the
# split cannot be read and somebody has to decide it by hand.
$DESSERT_KEYWORD = 'MAG_FoodTypeDessert'

# WHAT IS NOT COOKING EVEN THOUGH IT HAPPENS AT A COOKING BENCH. A judgement,
# and a small one. A survival mod in this load order fills water bottles and
# waterskins at the cooking pot, and the fishing mod mixes its fire paste
# there. Handing those to the Hearthcook would mean nobody else in Skyrim can
# fill a waterskin, which is a worse outcome than a cook not owning water.
# Matched against the output record's editor id, case ignored.
$NOT_COOKING_WORDS = @('Waterskin', 'WaterBottle', 'SujammaWaterBottle', 'FishingFirePaste')

# THE TAILOR'S TWO HALVES. classes.md gives the Liverywright "robes and faction
# dress" and the Haberdasher "common and fine clothing". This is a judgement,
# and the biggest one in the file.
#
# What is in the records: ClothingRich sits on 86 of the outputs and
# ClothingPoor on a handful, which separates fine from common and says nothing
# at all about robes, because a mage robe is rich clothing and so is a noble's
# coat. There is no robe keyword and no livery keyword in the build.
#
# What comes closest is faction dress, which two keywords do mark:
# WAF_MaterialFaction from Weapons Armor Clothing and Clutter Fixes, on the
# Thieves Guild and Dark Brotherhood sets, and CWMission03ImperialGarb on the
# Imperial common armour. Those are read from the record.
#
# The robes themselves come down to a list of words, so that is what this is,
# and it is a judgement rather than a reading. Matched against the output's
# editor id and its name, case ignored. Everything that does not match is
# common or fine clothing and goes to the Haberdasher.
#
# THE WORDS ARE MATCHED AS WHOLE WORDS AND THAT IS A FIX, NOT A STYLE. Until
# 20 September the match was a plain substring, and two of the words below are
# short enough to sit inside ordinary ones. 'Guard' matched Redguard,
# Wristguards and Armguards; 'Cowl' matched a farm hat. Measured on the table
# this script wrote that day, that sent eleven rows of common clothing to the
# Liverywright: the three MCERecipeClothesRedguard rows and their three Dark
# Brotherhood variants, IARRedguardKnightCape, and the three Jarl glove rows,
# which are named Gilded Wristguards, Fine Armguards and Ulfric's Armguards.
# Hammerfell garb and fine armguards are exactly the "common and fine clothing"
# classes.md gives the Haberdasher, so a Haberdasher could not make them and a
# Liverywright could.
#
# Whole word here means the way an editor id is actually written: it is split
# where a capital letter starts a new word, so ClothesRedguardBoots reads as
# Clothes, Redguard, Boots and none of those is Guard, while
# ArmorWhiterunGuardCuirass reads as Armor, Whiterun, Guard, Cuirass and that
# one is. A name is split on its spaces and punctuation the same way. A word in
# the list with more than one word in it, and there are none today, matches a
# run of words in order.
$LIVERYWRIGHT_KEYWORDS = @('WAF_MaterialFaction', 'CWMission03ImperialGarb')
#
# 'Cowl' IS GONE FROM THE LIST, and it was measured rather than argued about.
# Every cowl a Tailor can make in this build is already caught by its editor
# id: the monk cowls by Monk, the coloured ones by Robes, Necromancer Cowl by
# Necromancer. Counted on the table of 20 September, the only row 'Cowl' won on
# its own was MCERecipeClothesFarmClothes03Hat, whose output is
# ClothesFarmClothes03Hat and whose name is the bare word Cowl. It is a farm
# hat. The word earned nothing and cost one row, so it is not here.
#
# 'Guard' stays, and whole word matching is what makes it safe. Counted on the
# table this writes today, fourteen of the Liverywright's 96 rows have Guard as
# a word in what they make, and every one of them is a hold guard cloak out of
# Cloaks&Capes.esp, Pale Guard Cloak through Winterhold Guard Cloak. That is
# faction dress by any reading of classes.md.
$LIVERYWRIGHT_WORDS    = @(
    'Robe', 'Vestment', 'Livery',
    'Guard', 'ThievesGuild', 'DarkBrotherhood', 'Cultist', 'MythicDawn',
    'Necromancer', 'Archmage', 'Psiijic', 'MothPriest', 'Vaermina',
    'Monk', 'Dawnguard', 'Stormcloak', 'Imperial', 'Blades'
)

# THE ARMOUR KEYWORDS. Read from the output record. ArmorShield is on 580 of
# the outputs in this build, which answers the question this script was asked
# to answer out loud: a shield IS an ARMO record, it carries ArmorShield on top
# of ArmorHeavy or ArmorLight, and by the forge rule it is the Platewright's.
# That is the right answer anyway. A shield is armour, it is worn on the arm,
# and an Edgewright who could make shields would be making armour.
$KW_SHIELD   = 'ArmorShield'
$KW_HEAVY    = 'ArmorHeavy'
$KW_LIGHT    = 'ArmorLight'
$KW_CLOTHING = @('ArmorClothing', 'VendorItemClothing')
$KW_JEWELRY  = @('ArmorJewelry', 'VendorItemJewelry')

# THE BENCHES, by the editor id of the keyword the recipe names. Only the ones
# that need naming are here. Everything else is decided by its output.
#
# The forge, the skyforge, the aetherium forge and the Dawnguard's bench all
# make finished metal goods and the output decides the half. The armour table
# and the sharpening wheel are tempering and the output decides the half there
# too, and the server is never asked about either of them.
#
# The smelter, 1078 recipes here, is deliberately unowned. A smelter turns ore
# and scrap into ingots. An ingot is stock and not a finished good, both halves
# of the Smith need it, and a Miner who could not smelt the ore he dug would
# have to find a smith to sell anything at all. classes.md splits what you can
# MAKE, not what you can melt. Move it to the Smith by putting it in
# $BENCH_OWNER below if the playtest says otherwise.
#
# The tanning rack is split by its output rather than named here: the leather
# and the fur plates are stock and go unowned for the same reason as the
# smelter, and the cloaks and light armour it also makes are decided the same
# way everything else is.
#
# The HearthFires house building keywords are unowned. Building a house is not
# a trade in classes.md, the recipes hand out lumber and nails and wall
# sconces, and gating them behind a profession would stop somebody furnishing a
# house they paid for.
$BENCH_UNOWNED = [ordered]@{
    'BYOHBuildingCarpenter'  = 'HearthFires house building. Not a trade in classes.md, and gating it would stop somebody furnishing a house they paid for.'
    'BYOHBuildingDrafting'   = 'HearthFires house building, the drafting table.'
    'BYOHBuildingTrophyBase1' = 'HearthFires house building, a trophy base.'
    'BYOHBuildingTrophyBase2' = 'HearthFires house building, a trophy base.'
    'testPhilCraftingBreakItDowner' = 'a Bethesda test record left in Dragonborn.esm. It is not a bench anybody stands at.'
}
# The grain mill is not here, and it is worth saying why so that the next
# reader does not think it was missed. Its keyword is called isGrainMill rather
# than CraftingSomething, which makes it look like a flag rather than a bench,
# and it is a bench: it grinds one recipe, flour. It is in $BENCH_OWNER below,
# with the Cook.

# Any keyword whose editor id starts with this is one of the 206 HearthFires
# furniture keywords, one per piece of furniture. They are all house building.
$BENCH_UNOWNED_PREFIX = 'BYOHBuildingInteriorPart'

# Benches that settle the profession on their own, where the output cannot.
$BENCH_OWNER = [ordered]@{
    'CraftingCookpot'         = @{ Owner = 'Cook';       Why = 'a cooking pot' }
    'BYOHCraftingOven'        = @{ Owner = 'Cook';       Why = 'the HearthFires oven' }
    'isGrainMill'             = @{ Owner = 'Cook';       Why = 'a grain mill, which makes the flour a kitchen runs on' }
    'KzlCraftingCharcoalKiln' = @{ Owner = 'Woodworker'; Half = 'Charburner'; Why = 'the charcoal kiln Thornswood-Content.esp already ships. classes.md gives the Charburner firewood through to coke in as many words, and this bench is that chain.' }
    'MCE_CraftingLoom'        = @{ Owner = 'Tailor';     Why = 'a loom, from MoreCraftableEquipment' }
    'DLC2StaffEnchanter'      = @{ Owner = 'Enchanter';  Half = 'Bladebinder'; Why = 'the Dragonborn staff enchanter. Every one of its recipes outputs a staff, and a staff is a weapon, so it is the Bladebinder''s by the same rule that gives him swords.' }
    'CraftingSmelter'         = @{ Owner = '';           Why = 'a smelter makes ingots, which are stock rather than a finished good. Both halves of the Smith need them, and a Miner who could not smelt his own ore would have nothing to sell. Left open to everybody on purpose.' }
}

$ErrorActionPreference = 'Stop'

if (-not $Out) { $Out = Join-Path $PSScriptRoot 'recipes.json' }

$fail = 0
function Ok  ($m) { Write-Host "  ok    $m" -ForegroundColor Green }
function Bad ($m) { Write-Host "  FAIL  $m" -ForegroundColor Red; $script:fail++ }
function Note($m) { Write-Host "        $m" -ForegroundColor DarkGray }
function Loud($m) { Write-Host "  ----  $m" -ForegroundColor Yellow }

# ------------------------------------------------------------ the pieces ----

# A record's data is zlib when flag 0x00040000 is set: four bytes of
# decompressed size, then the stream. DeflateStream wants the two byte zlib
# header gone, hence the +2.
function Expand-RecordData([byte[]]$src, [int]$offset, [int]$outLen) {
    $ms = New-Object System.IO.MemoryStream(, $src)
    $ms.Position = $offset + 2
    $ds = New-Object System.IO.Compression.DeflateStream($ms, [System.IO.Compression.CompressionMode]::Decompress)
    $out = New-Object byte[] $outLen
    $got = 0
    while ($got -lt $outLen) {
        $n = $ds.Read($out, $got, $outLen - $got)
        if ($n -le 0) { break }
        $got += $n
    }
    $ds.Dispose()
    $ms.Dispose()
    if ($got -ne $outLen) { throw "a compressed record unpacked to $got bytes, not $outLen" }
    return $out
}

# Pulls every .STRINGS file out of a BSA, by name, uncompressed. Version 105
# (Skyrim Special Edition): 24 byte folder records, a name block after them.
function Get-BsaStringFiles([string]$bsaPath) {
    $b = [System.IO.File]::ReadAllBytes($bsaPath)
    if ([System.Text.Encoding]::ASCII.GetString($b, 0, 3) -ne 'BSA') { throw "not a BSA: $bsaPath" }
    $version   = [BitConverter]::ToUInt32($b, 4)
    $folderOff = [BitConverter]::ToUInt32($b, 8)
    $archFlags = [BitConverter]::ToUInt32($b, 12)
    $folderCnt = [BitConverter]::ToUInt32($b, 16)
    $fileCnt   = [BitConverter]::ToUInt32($b, 20)
    $totFileN  = [BitConverter]::ToUInt32($b, 28)
    if ($version -ne 105) { throw "BSA version $version is not the Special Edition's 105: $bsaPath" }
    # 0x4 would mean every file in it is compressed, and in a version 105
    # archive that compression is LZ4, which this cannot unpack
    if ($archFlags -band 0x4) { throw "the archive is compressed throughout and cannot be read here: $bsaPath" }

    $sizes  = New-Object 'System.Collections.Generic.List[uint32]'
    $starts = New-Object 'System.Collections.Generic.List[uint32]'
    $nameBlock = 0
    for ($f = 0; $f -lt $folderCnt; $f++) {
        $o = [int]$folderOff + $f * 24
        $cnt      = [int][BitConverter]::ToUInt32($b, $o + 8)
        $blockOff = [BitConverter]::ToUInt64($b, $o + 16)
        # the folder record's offset counts the file name block in, so take it out
        $q = [int]($blockOff - $totFileN)
        $q += 1 + $b[$q]        # the folder's own name, a length byte then the text
        for ($i = 0; $i -lt $cnt; $i++) {
            $sizes.Add([BitConverter]::ToUInt32($b, $q + $i * 16 + 8))
            $starts.Add([BitConverter]::ToUInt32($b, $q + $i * 16 + 12))
        }
        $end = $q + $cnt * 16
        if ($end -gt $nameBlock) { $nameBlock = $end }
    }

    $out = @{}
    $q = $nameBlock
    for ($i = 0; $i -lt $fileCnt; $i++) {
        $s = $q
        while ($b[$q] -ne 0) { $q++ }
        $name = [System.Text.Encoding]::ASCII.GetString($b, $s, $q - $s).ToLowerInvariant()
        $q++
        if (-not $name.EndsWith('.strings')) { continue }
        $size = $sizes[$i]
        if ($size -band 0x40000000) {
            # the archive's default is uncompressed (flags 0x3); a file that
            # flips that would be LZ4 and this cannot read it
            Note "skipped a compressed strings file in the archive: $name"
            continue
        }
        $bytes = New-Object byte[] ([int]$size)
        [Array]::Copy($b, [int]$starts[$i], $bytes, 0, [int]$size)
        $out[$name] = $bytes
    }
    return $out
}

# A .STRINGS file: a count, a size, then count pairs of (string id, offset),
# then the text. Each string is zero terminated and has no length in front of
# it, which is what separates .STRINGS from .ILSTRINGS and .DLSTRINGS.
function Read-StringTable([byte[]]$bytes) {
    $count = [int][BitConverter]::ToUInt32($bytes, 0)
    $dataStart = 8 + $count * 8
    $t = @{}
    for ($i = 0; $i -lt $count; $i++) {
        $id  = [BitConverter]::ToUInt32($bytes, 8 + $i * 8)
        $off = [int][BitConverter]::ToUInt32($bytes, 8 + $i * 8 + 4)
        $p = $dataStart + $off
        $s = $p
        while ($bytes[$p] -ne 0) { $p++ }
        $t[$id] = [System.Text.Encoding]::GetEncoding(1252).GetString($bytes, $s, $p - $s)
    }
    return $t
}

# The masters a plugin declares, in order. A record's form id carries the index
# of the file it really belongs to in its top byte, so an Update.esm record with
# 00 up there is a Skyrim.esm record being overridden and the desc has to say
# Skyrim.esm. A form id inside CNAM, BNAM or KWDA is numbered the same way,
# which is what makes the output and the bench resolvable at all.
function Get-PluginMasters([byte[]]$b, [int]$headerSize) {
    $masters = New-Object 'System.Collections.Generic.List[string]'
    $p = 24
    $end = 24 + $headerSize
    while ($p + 6 -le $end) {
        $t = [System.Text.Encoding]::ASCII.GetString($b, $p, 4)
        $sz = [int][BitConverter]::ToUInt16($b, $p + 4)
        if ($t -eq 'MAST') {
            $masters.Add([System.Text.Encoding]::GetEncoding(1252).GetString($b, $p + 6, $sz - 1))
        }
        $p += 6 + $sz
    }
    # ',' on purpose. A bare 'return $masters' is unrolled on the way out, and a
    # plugin with exactly one master then comes back as the bare string
    # 'Skyrim.esm' instead of a list of one. Its .Count still reads 1, so
    # nothing complains, but $masters[0] indexes the STRING and hands back the
    # character 'S'. Update.esm, Dawnguard.esm, HearthFires.esm and
    # Dragonborn.esm have exactly one master each, so this is the common case.
    # Build-OreTable.ps1 was bitten by it and proved it in a shell.
    return ,$masters.ToArray()
}

# One json string, quoted and escaped. Written here rather than reached for with
# ConvertTo-Json so the file comes out the same on 5.1 and on 7.
function JsonStr($s) {
    $t = [string]$s
    $t = $t.Replace('\', '\\')
    $t = $t.Replace('"', '\"')
    $t = $t.Replace("`r", '\r')
    $t = $t.Replace("`n", '\n')
    $t = $t.Replace("`t", '\t')
    return '"' + $t + '"'
}

# form id -> 'hex:owning plugin', the desc the server takes. The top byte is an
# index into the plugin's master list; the plugin's own records carry the index
# one past the end of it.
function DescOf([uint32]$formId, $masters, [string]$plugin) {
    $mi = [int]($formId -shr 24)
    $owner = $plugin
    if ($mi -lt $masters.Count) { $owner = $masters[$mi] }
    return ('{0:x}' -f ($formId -band 0xFFFFFF)) + ':' + $owner
}

# Where a rank sits on classes.md's ladder, 0 for novice up to 3 for master,
# and -1 for anything that is not one of the four. Comparing ranks as strings
# is how a ladder gets checked in alphabetical order, where advanced comes
# before novice and the whole answer is wrong without anything printing.
function RankAt([string]$rank) {
    for ($i = 0; $i -lt $RANKS.Count; $i++) { if ($RANKS[$i] -eq $rank) { return $i } }
    return -1
}

# One producer of one item, into both maps. True when this is the first entry
# for the item, which is the number each table is credited with in the run.
#
# BOTH MAPS, ALWAYS. $producer keeps one answer per item by the rule in
# PRODUCER_RANK_IS_LOWEST, because a recipe costs what the cheapest way of
# getting its makings costs. $producerAll keeps every class that produces it,
# because the answer $producer throws away is exactly the cross-class question
# Patrick asked: a Cook wanting a Red Apple is novice work off a gatherer and
# the farmer who grows one has to be expert, and only this map can say so.
function RememberProducer([string]$desc, [string]$rank, [int]$at, [string]$who, [string]$name, [string]$via) {
    if (-not $producerAll.ContainsKey($desc)) { $producerAll[$desc] = @() }
    $producerAll[$desc] += ,([pscustomobject]@{ Rank = $rank; At = $at; Who = $who; Name = $name; Via = $via })

    $have = $null
    if ($producer.ContainsKey($desc)) { $have = $producer[$desc] }
    $take = $false
    if (-not $have) {
        $take = $true
    } elseif ($PRODUCER_RANK_IS_LOWEST) {
        if ($at -lt $have.At) { $take = $true }
    } else {
        if ($at -gt $have.At) { $take = $true }
    }
    if ($take) {
        $producer[$desc] = [pscustomobject]@{ Rank = $rank; At = $at; Who = $who; Name = $name; Via = $via }
    }
    if (-not $have) { return $true }
    return $false
}

# How many rows of one half sit on each of the four rungs, in classes.md's
# order, counted off the Rank that is on the rows right now.
function CountRungs($descs) {
    $counts = [ordered]@{}
    foreach ($rk in $RANKS) { $counts[$rk] = 0 }
    foreach ($d in $descs) {
        $rk = [string]$owned[$d].Rank
        if ($counts.Contains($rk)) { $counts[$rk] = $counts[$rk] + 1 }
    }
    return $counts
}

# The lowest empty rung that has work above it, or -1 when the ladder is sound.
# An empty rung with nothing above it is fine: that is a half whose work simply
# does not reach that far up. An empty rung with work above it is a rank that
# opens nothing, and a rank that opens nothing at the bottom is a character who
# can never start.
function HoleIn($counts) {
    for ($i = 0; $i -lt $RANKS.Count; $i++) {
        if ([int]$counts[$RANKS[$i]] -gt 0) { continue }
        for ($j = $i + 1; $j -lt $RANKS.Count; $j++) {
            if ([int]$counts[$RANKS[$j]] -gt 0) { return $i }
        }
    }
    return -1
}

# The other half of HoleIn: the rungs that have rows on them and not one row
# anybody standing on that rung could gather the makings for.
#
# A row is standable at its rung when the dearest input any class produces for
# it sits at or below that rung, or when nothing it asks for is produced by a
# class at all, which means a shop or one of the 1679 unowned recipes hands it
# over and no class rank stands in the way.
#
# Counting rows is what both this script and Check-Balance did until the
# Bladebinder was measured: 41 rows on its novice rung, every one of them
# wanting a master miner's Heart Stone, and every count in both scripts said
# the ladder was sound. Returns one entry per bad rung, worst rung first.
function UnstandableRungs($descs) {
    $out = New-Object 'System.Collections.Generic.List[object]'
    for ($i = 0; $i -lt $RANKS.Count; $i++) {
        $on = 0
        $standable = 0
        $cheapest = -1
        $blocker = ''
        $blockerWho = ''
        foreach ($d in $descs) {
            if ([string]$owned[$d].Rank -ne $RANKS[$i]) { continue }
            $on++
            $ir = [string]$owned[$d].InputRank
            if (-not $ir) { $standable++; continue }
            $irAt = RankAt $ir
            if ($irAt -le $i) { $standable++; continue }
            if ($cheapest -lt 0 -or $irAt -lt $cheapest) {
                $cheapest = $irAt
                $blocker = [string]$owned[$d].OutName
                $blockerWho = [string]$owned[$d].InputRankWho
            }
        }
        if ($on -gt 0 -and $standable -eq 0) {
            $out.Add([pscustomobject]@{
                Rank = $RANKS[$i]; Rows = $on; NeedAt = $RANKS[$cheapest]
                Nearest = $blocker; Who = $blockerWho
            })
        }
    }
    return $out.ToArray()
}

# THE SECOND RULE, for one half at a time and only where the first two left a
# rung with nothing on it. Named in SECOND_RULE_KEY, argued for there.
#
# The ordering is deliberately a TOTAL order with no ties in it: the key, then
# the other input measure, then the output price, then the row's own id. That
# is the difference between this and the price rule, which collapses rungs
# exactly because it refuses to split rows that tie. A total order fills every
# rung the shares ask for whenever the half has four rows or more, which is why
# this rule always closes the hole and the price rule cannot.
function SecondRule([string]$key, $descs) {
    $order = @($descs | Sort-Object `
        @{ Expression = { [int](SecondRuleKey $owned[$_]) } }, `
        @{ Expression = { [int](OtherInputMeasure $owned[$_]) } }, `
        @{ Expression = { [int64]$owned[$_].Value } }, `
        @{ Expression = { [string]$_ } })
    $n = $order.Count
    $at = 0
    foreach ($s in $RANK_SHARE) {
        $last = [int][math]::Ceiling($n * [double]$s.Upto)
        if ($last -gt $n) { $last = $n }
        while ($at -lt $last) {
            $owned[$order[$at]].Rank = [string]$s.Rank
            $owned[$order[$at]].RankFrom = ('the second rule, ' + $SECOND_RULE_KEY)
            $owned[$order[$at]].RankWhy = ('what this half makes cannot be told apart by price or by what its inputs cost, so it is ranked by ' +
                                           $SECOND_RULE_KEY + ': this one wants ' + (SecondRuleKey $owned[$order[$at]]) +
                                           ', which puts it in the ' + $s.Rank + ' share of its own half')
            $at++
        }
    }
    while ($at -lt $n) {
        $owned[$order[$at]].Rank = [string]$RANK_SHARE[$RANK_SHARE.Count - 1].Rank
        $owned[$order[$at]].RankFrom = ('the second rule, ' + $SECOND_RULE_KEY)
        $owned[$order[$at]].RankWhy = ('the longest shopping list in a half that cannot be told apart by price or by what its inputs cost')
        $at++
    }
    return (CountRungs $descs)
}

# The number the second rule sorts on, and the other one, so that changing
# SECOND_RULE_KEY changes both in one place.
function SecondRuleKey($row) {
    if ($SECOND_RULE_KEY -eq 'distinct inputs') { return @($row.InputList).Count }
    $t = 0
    foreach ($i in @($row.InputList)) { $t += [int]$i.Count }
    return $t
}
function OtherInputMeasure($row) {
    if ($SECOND_RULE_KEY -eq 'distinct inputs') {
        $t = 0
        foreach ($i in @($row.InputList)) { $t += [int]$i.Count }
        return $t
    }
    return @($row.InputList).Count
}

# The inputs of one recipe, as json. Every CNTO the record carried: the item,
# what it is called, what kind of record it is, how many the recipe wants, and
# which class produces it at which rank. producedBy null means no producing
# table in this repository hands that item over, which is the case for anything
# bought from a shop or made by an earlier recipe, and it is written down
# rather than left out so that a reader can tell "nobody produces this" from
# "this script did not look".
function InputsJson($r) {
    if (-not $r.InputList -or @($r.InputList).Count -eq 0) { return '[]' }
    $bits = @()
    foreach ($i in $r.InputList) {
        $nm = $i.Desc
        $ty = ''
        if ($items.ContainsKey($i.Desc)) { $nm = $items[$i.Desc].Name; $ty = $items[$i.Desc].Type }
        $line = '{ "item": ' + (JsonStr $i.Desc) + ', "name": ' + (JsonStr $nm) +
                ', "type": ' + (JsonStr $ty) + ', "count": ' + $i.Count
        if ($producer.ContainsKey($i.Desc)) {
            $line += ', "producedBy": ' + (JsonStr $producer[$i.Desc].Who) +
                     ', "producedAt": ' + (JsonStr $producer[$i.Desc].Rank)
            # THE CLASSES THAT HAVE TO CLIMB FURTHER FOR THE SAME THING, and
            # only those: a class producing it at the same rank or lower is
            # already answered by producedAt. This is the field Patrick's
            # cross-tier question is read off, and without it the farmer is
            # invisible in this whole file, because every crop is also a plant a
            # gatherer picks at the same rank or lower.
            $dearer = @()
            $seen = @{}
            if ($producerAll.ContainsKey($i.Desc)) {
                foreach ($pz in $producerAll[$i.Desc]) {
                    if ($pz.At -le $producer[$i.Desc].At) { continue }
                    $k = $pz.Who + '/' + $pz.Rank
                    if ($seen.ContainsKey($k)) { continue }
                    $seen[$k] = $true
                    $dearer += ('{ "who": ' + (JsonStr $pz.Who) + ', "at": ' + (JsonStr $pz.Rank) + ' }')
                }
            }
            if ($dearer.Count -gt 0) { $line += ', "alsoProducedBy": [' + ($dearer -join ', ') + ']' }
        } else {
            $line += ', "producedBy": null, "producedAt": null'
        }
        $bits += ($line + ' }')
    }
    return '[' + ($bits -join ', ') + ']'
}

# A listing of the game folder: name, size and last write, for the files this
# reads and the folder they sit in. Taken before and after so the promise that
# nothing was touched is measured rather than asserted.
function Get-FolderPrint([string]$dir) {
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $n = 0
    foreach ($d in @($dir, (Join-Path $dir 'Strings'))) {
        if (-not (Test-Path -LiteralPath $d)) { continue }
        foreach ($f in (Get-ChildItem -LiteralPath $d -File -Force | Sort-Object Name)) {
            $lines.Add(('{0}|{1}|{2:o}' -f $f.Name, $f.Length, $f.LastWriteTimeUtc))
            $n++
        }
    }
    $text = $lines -join "`n"
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hash = [BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($text))).Replace('-', '')
    $sha.Dispose()
    return [pscustomobject]@{ Count = $n; Hash = $hash.ToLowerInvariant() }
}

# ------------------------------------------------------- the load order -----

Write-Host ''
Write-Host 'the load order' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $Data)) { throw "not found: $Data" }

$before = Get-FolderPrint $Data
Ok ("{0}: {1} files before this ran, {2}" -f $Data, $before.Count, $before.Hash.Substring(0, 16))

# Bethesda's five load before the game reads any list and are never written to
# plugins.txt, which is why they are put in front of it here rather than
# expected to be in it.
$MASTERS_FIRST = @('Skyrim.esm', 'Update.esm', 'Dawnguard.esm', 'HearthFires.esm', 'Dragonborn.esm')
$order = New-Object 'System.Collections.Generic.List[string]'
if ($Plugins.Count -gt 0) {
    foreach ($p in $Plugins) { if (-not $order.Contains($p)) { $order.Add($p) } }
    Ok ("{0} plugins, given on the command line" -f $order.Count)
} else {
    foreach ($p in $MASTERS_FIRST) { $order.Add($p) }
    if (-not (Test-Path -LiteralPath $PluginsTxt)) { throw "not found: $PluginsTxt" }
    foreach ($line in [System.IO.File]::ReadAllLines($PluginsTxt)) {
        $t = $line.Trim()
        if (-not $t -or $t.StartsWith('#')) { continue }
        if ($t.StartsWith('*')) { $t = $t.Substring(1) }   # Vortex marks the enabled ones
        if (-not $t) { continue }
        if (-not $order.Contains($t)) { $order.Add($t) }
    }
    Ok ("{0} plugins: the five masters, then {1}" -f $order.Count, $PluginsTxt)
}

$missing = New-Object 'System.Collections.Generic.List[string]'
foreach ($p in $order) { if (-not (Test-Path -LiteralPath (Join-Path $Data $p))) { $missing.Add($p) } }
if ($missing.Count -gt 0) {
    Bad ("{0} plugin(s) in the load order are not in {1}: {2}" -f $missing.Count, $Data, ($missing -join ', '))
} else {
    Ok 'every plugin in the load order is on disk'
}

# ------------------------------------------------------- the string tables --

Write-Host ''
Write-Host 'names' -ForegroundColor Cyan
$tables = @{}
$looseDir = Join-Path $Data 'Strings'
$bsaFiles = $null
foreach ($pl in $order) {
    $path = Join-Path $Data $pl
    if (-not (Test-Path -LiteralPath $path)) { continue }
    # only a plugin flagged localised keeps its names in a string table
    $head = New-Object byte[] 12
    $fs = [System.IO.File]::OpenRead($path)
    [void]$fs.Read($head, 0, 12)
    $fs.Dispose()
    if (-not ([BitConverter]::ToUInt32($head, 8) -band 0x80)) { continue }

    $base = [System.IO.Path]::GetFileNameWithoutExtension($pl).ToLowerInvariant()
    $want = $base + '_' + $LANGUAGE + '.strings'
    $loose = Join-Path $looseDir $want
    if (Test-Path -LiteralPath $loose) {
        $tables[$pl] = @{ Table = (Read-StringTable ([System.IO.File]::ReadAllBytes($loose))); Where = 'Data\Strings' }
        continue
    }
    if ($null -eq $bsaFiles) {
        $bsa = Join-Path $Data 'Skyrim - Interface.bsa'
        if (Test-Path -LiteralPath $bsa) {
            $bsaFiles = Get-BsaStringFiles $bsa
            Note ("{0} strings files inside Skyrim - Interface.bsa" -f $bsaFiles.Count)
        } else {
            $bsaFiles = @{}
            Note "no Data\Strings and no Skyrim - Interface.bsa: names will fall back to editor ids"
        }
    }
    if ($bsaFiles.ContainsKey($want)) {
        $tables[$pl] = @{ Table = (Read-StringTable $bsaFiles[$want]); Where = 'Skyrim - Interface.bsa' }
    } else {
        # a plugin flagged localised with no table can only fall back to editor
        # ids, and then an item in the table has an editor id where its name goes
        Bad ("{0}: localised and no $LANGUAGE string table found; its names fall back to editor ids" -f $pl)
    }
}
foreach ($pl in $order) {
    if ($tables.ContainsKey($pl)) {
        Ok ("{0}: {1} strings, from {2}" -f $pl, $tables[$pl].Table.Count, $tables[$pl].Where)
    }
}
Note ("{0} of {1} plugins are localised and needed a string table" -f $tables.Count, $order.Count)

# ------------------------------------------------------------ the records ---

Write-Host ''
Write-Host 'records' -ForegroundColor Cyan

# The record types a recipe can name as its output. ARMO, WEAP, ALCH, MISC,
# INGR and AMMO are the six this build actually uses, measured: 2332 ARMO,
# 1629 MISC, 966 WEAP, 143 ALCH, 29 AMMO, 6 INGR. The other five are read
# anyway so that a mod recipe outputting a book, a scroll, a soul gem, a torch
# or a key resolves to a real record and lands in unowned with a reason,
# instead of failing the build for a missing record.
$OUTPUT_TYPES = @('ARMO', 'WEAP', 'ALCH', 'MISC', 'INGR', 'AMMO', 'BOOK', 'SCRL', 'SLGM', 'LIGH', 'KEYM')
# KYWD is needed for the bench and for every keyword on an output record.
# The record types a CTDA on a recipe points its parameters at. PERK and SPEL
# are here so that a condition can be read out as the thing it asks for rather
# than as a number: HasPerk against MAG_FoodUpgradePerk03, HasSpell against
# Thunderbolt. GLOB is here because a CTDA can compare against a global instead
# of a number, which the flag bit 0x04 says. Everything else a condition can
# name, a book or an ingot or a piece of armour, is already in $OUTPUT_TYPES.
$CONDITION_TYPES = @('PERK', 'SPEL', 'GLOB')
$SCAN_TYPES = @('KYWD', 'COBJ') + $OUTPUT_TYPES + $CONDITION_TYPES

# desc -> the record, last one in the load order wins, because that is the
# record the game is using
$items   = @{}
$kwName  = @{}
# item desc -> which class produces it, at the lowest rank any of them does.
# Filled under 'what an input costs a producer', below, out of the five
# producing tables and the server's own verbs. Declared here because InputsJson
# reads it.
$producer = @{}
# item desc -> every class that produces it and at what rank, the winner above
# among them. A separate map because $producer holds one answer per item by
# design and the cross-class report needs the ones it beat: the farmer's whole
# ladder lives in here and nowhere else, since every crop is also a plant a
# gatherer picks at the same rank or lower.
$producerAll = @{}
# desc -> the recipe, same rule. Ordered so the json and the block come out in
# load order, which makes a rebuild a small diff rather than a shuffle.
$recipes = New-Object System.Collections.Specialized.OrderedDictionary
$perPluginRecipes = @{}
# plugin -> the master list it declares, kept so that a form id can be written
# back into any plugin's own numbering afterwards. The search for what hands
# out an item needs that and it runs after the scan.
$pluginMasters = @{}
$seenTwice = New-Object 'System.Collections.Generic.List[string]'

foreach ($pl in $order) {
    $path = Join-Path $Data $pl
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $b = [System.IO.File]::ReadAllBytes($path)
    if ([System.Text.Encoding]::ASCII.GetString($b, 0, 4) -ne 'TES4') { Bad "not a plugin: $path"; continue }
    $headerSize = [int][BitConverter]::ToUInt32($b, 4)
    $localized  = [bool]([BitConverter]::ToUInt32($b, 8) -band 0x80)
    $masters    = Get-PluginMasters $b $headerSize
    $pluginMasters[$pl] = $masters
    $strTable = $null
    if ($tables.ContainsKey($pl)) { $strTable = $tables[$pl].Table }

    $here = 0
    $i = 24 + $headerSize
    while ($i + 24 -le $b.Length) {
        if ([System.Text.Encoding]::ASCII.GetString($b, $i, 4) -ne 'GRUP') { break }
        $groupSize = [int][BitConverter]::ToUInt32($b, $i + 4)
        if ($groupSize -lt 24) { break }
        $label = [System.Text.Encoding]::ASCII.GetString($b, $i + 8, 4)
        if ($SCAN_TYPES -contains $label) {
            $j = $i + 24
            $groupEnd = $i + $groupSize
            while ($j + 24 -le $groupEnd) {
                $type     = [System.Text.Encoding]::ASCII.GetString($b, $j, 4)
                $dataSize = [int][BitConverter]::ToUInt32($b, $j + 4)
                $recFlags = [BitConverter]::ToUInt32($b, $j + 8)
                $formId   = [BitConverter]::ToUInt32($b, $j + 12)
                if ($type -eq $label) {
                    if ($recFlags -band 0x00040000) {
                        $outLen = [int][BitConverter]::ToUInt32($b, $j + 24)
                        $rec = Expand-RecordData $b ($j + 28) $outLen
                    } else {
                        $rec = New-Object byte[] $dataSize
                        [Array]::Copy($b, $j + 24, $rec, 0, $dataSize)
                    }
                    $k = 0
                    $over = 0
                    $edid = ''
                    $full = ''
                    $fullFrom = ''
                    $alchFlags = 0
                    $hasEnit = $false
                    $weapAnim = -1
                    $cnam = 0; $hasCnam = $false
                    $bnam = 0; $hasBnam = $false
                    $nam1 = 1
                    $inputs = 0
                    $coct = -1
                    $value = -1
                    $valueRule = $null
                    if ($VALUE_RULES.Contains($label)) { $valueRule = $VALUE_RULES[$label] }
                    $kwds = New-Object 'System.Collections.Generic.List[string]'
                    $conds = New-Object 'System.Collections.Generic.List[object]'
                    # The form ids inside the CNTO subrecords, which this
                    # script read and threw away until 21 September. They are
                    # what a recipe costs somebody, and the rank of a recipe is
                    # built out of them now rather than out of what its output
                    # sells for. See INPUT COST above.
                    $cnto = New-Object 'System.Collections.Generic.List[object]'
                    while ($k + 6 -le $rec.Length) {
                        $sub = [System.Text.Encoding]::ASCII.GetString($rec, $k, 4)
                        $sz  = [int][BitConverter]::ToUInt16($rec, $k + 4)
                        $k += 6
                        # XXXX carries the real size of the subrecord after it,
                        # for anything bigger than two bytes can say
                        if ($over -gt 0) { $sz = $over; $over = 0 }
                        if ($sub -eq 'XXXX') { $over = [int][BitConverter]::ToUInt32($rec, $k); $k += $sz; continue }
                        if ($sub -eq 'EDID' -and $sz -gt 1) {
                            $edid = [System.Text.Encoding]::GetEncoding(1252).GetString($rec, $k, $sz - 1)
                        } elseif ($sub -eq 'FULL') {
                            if ($localized -and $sz -eq 4) {
                                $sid = [BitConverter]::ToUInt32($rec, $k)
                                if ($strTable -and $strTable.ContainsKey($sid)) {
                                    $full = $strTable[$sid]
                                    $fullFrom = 'string table'
                                }
                            } elseif ($sz -gt 1) {
                                $full = [System.Text.Encoding]::GetEncoding(1252).GetString($rec, $k, $sz - 1)
                                $fullFrom = 'the record'
                            }
                        } elseif ($sub -eq 'KWDA' -and $label -ne 'COBJ') {
                            # KWDA is a straight array of form ids, four bytes
                            # each. KSIZ in front of it says how many, and it is
                            # not read here because the length of KWDA says the
                            # same thing and cannot disagree with itself.
                            for ($z = 0; $z + 4 -le $sz; $z += 4) {
                                $kwds.Add((DescOf ([BitConverter]::ToUInt32($rec, $k + $z)) $masters $pl))
                            }
                        } elseif ($sub -eq 'ENIT' -and $label -eq 'ALCH' -and $sz -ge 8) {
                            # ALCH ENIT: the value in gold, then the flag word.
                            # The flag word is the poison bit and the food bit.
                            $alchFlags = [BitConverter]::ToUInt32($rec, $k + 4)
                            $hasEnit = $true
                        } elseif ($sub -eq 'DNAM' -and $label -eq 'WEAP' -and $sz -ge 1) {
                            # the first byte of a WEAP DNAM is the animation
                            # type, which is what tells a bow from a sword
                            $weapAnim = [int]$rec[$k]
                        } elseif ($label -eq 'COBJ') {
                            if ($sub -eq 'CNAM' -and $sz -eq 4) { $cnam = [BitConverter]::ToUInt32($rec, $k); $hasCnam = $true }
                            elseif ($sub -eq 'BNAM' -and $sz -eq 4) { $bnam = [BitConverter]::ToUInt32($rec, $k); $hasBnam = $true }
                            elseif ($sub -eq 'NAM1' -and $sz -eq 2) { $nam1 = [int][BitConverter]::ToUInt16($rec, $k) }
                            elseif ($sub -eq 'CNTO') {
                                $inputs++
                                # Eight bytes: the input item's form id, then
                                # how many of it the recipe wants. Proved in
                                # the header against RecipeLeatherFoxHide,
                                # which has COCT 1, one CNTO, and wants one fox
                                # pelt. The count was never in doubt; what was
                                # dropped was the id, and the id is the only
                                # thing that can say which class has to go and
                                # get it.
                                if ($sz -ge 8) {
                                    $cnto.Add([pscustomobject]@{
                                        Id    = [BitConverter]::ToUInt32($rec, $k)
                                        Count = [int][BitConverter]::ToUInt32($rec, $k + 4)
                                    })
                                }
                            }
                            elseif ($sub -eq 'COCT' -and $sz -eq 4) { $coct = [int][BitConverter]::ToUInt32($rec, $k) }
                            elseif ($sub -eq 'CTDA' -and $sz -ge 20) {
                                # The layout is in the header, out of
                                # libespm's CTDA.h. Only the first twenty
                                # bytes are read: the operator, what it
                                # compares against, which function it is, and
                                # the two parameters. What the condition runs
                                # on is always the person crafting here, and
                                # the fork's own EvaluateCraftRecipeConditions
                                # passes the same actor as both subject and
                                # target, so there is nothing in the rest of
                                # the subrecord this table can act on.
                                $opByte = [int]$rec[$k]
                                $conds.Add([pscustomobject]@{
                                    Operator = ($opByte -shr 5)
                                    UsesGlobal = (($opByte -band 0x04) -ne 0)
                                    Or = (($opByte -band 0x01) -ne 0)
                                    Value = [BitConverter]::ToSingle($rec, $k + 4)
                                    Func = [int][BitConverter]::ToUInt16($rec, $k + 8)
                                    Param1 = [BitConverter]::ToUInt32($rec, $k + 12)
                                    Param2 = [BitConverter]::ToUInt32($rec, $k + 16)
                                })
                            }
                        }
                        if ($valueRule -and $sub -eq $valueRule.Sub -and $sz -ge ($valueRule.At + 4)) {
                            # The gold value, which is what ranks the row. Where
                            # it sits in each kind of record is the VALUE_RULES
                            # knob, and every offset in it was measured.
                            $value = [int64][BitConverter]::ToUInt32($rec, $k + $valueRule.At)
                        }
                        $k += $sz
                    }

                    $desc = DescOf $formId $masters $pl

                    if ($label -eq 'COBJ') {
                        if ($recipes.Contains($desc)) {
                            # not a failure: a later plugin overriding a recipe
                            # is the normal way a mod changes one, and the last
                            # one in the load order is the one the game uses
                            $seenTwice.Add($desc)
                        }
                        $outDesc = ''
                        if ($hasCnam -and $cnam -ne 0) { $outDesc = DescOf ([uint32]$cnam) $masters $pl }
                        $benchDesc = ''
                        if ($hasBnam -and $bnam -ne 0) { $benchDesc = DescOf ([uint32]$bnam) $masters $pl }
                        # The inputs, as descs, resolved here where the master
                        # list of the plugin that carried the record is still
                        # in hand. The same two lines the output and the bench
                        # already had.
                        $inList = New-Object 'System.Collections.Generic.List[object]'
                        foreach ($c in $cnto) {
                            if ($c.Id -eq 0) { continue }
                            $inList.Add([pscustomobject]@{
                                Desc  = (DescOf ([uint32]$c.Id) $masters $pl)
                                Count = $c.Count
                            })
                        }
                        $recipes[$desc] = [pscustomobject]@{
                            Desc = $desc; Edid = $edid; SeenIn = $pl
                            Plugin = $desc.Split(':')[1]
                            Local = ($formId -band 0xFFFFFF)
                            OutDesc = $outDesc; BenchDesc = $benchDesc
                            Count = $nam1; Inputs = $inputs; Coct = $coct
                            InputList = $inList.ToArray()
                            Conditions = $conds.ToArray(); Masters = $masters
                        }
                        $here++
                        if (-not $perPluginRecipes.ContainsKey($pl)) { $perPluginRecipes[$pl] = 0 }
                        $perPluginRecipes[$pl] = $perPluginRecipes[$pl] + 1
                    } else {
                        if (-not $full) { $full = $edid; $fullFrom = 'the editor id' }
                        $items[$desc] = [pscustomobject]@{
                            Desc = $desc; Type = $label; Edid = $edid; Name = $full; NameFrom = $fullFrom
                            AlchFlags = $alchFlags; HasEnit = $hasEnit; WeapAnim = $weapAnim
                            Keywords = $kwds.ToArray(); SeenIn = $pl; Value = $value
                        }
                        if ($label -eq 'KYWD') { $kwName[$desc] = $edid }
                    }
                }
                $j += 24 + $dataSize
            }
        }
        $i += $groupSize
    }
    if ($here -gt 0) { Note ("{0}: {1} COBJ record(s)" -f $pl, $here) }
}

Ok ("{0} recipes after overrides, out of {1} COBJ records read" -f $recipes.Count, ($recipes.Count + $seenTwice.Count))
Ok ("{0} item and keyword records to resolve against, {1} of them keywords" -f $items.Count, $kwName.Count)
if ($recipes.Count -eq 0) { Bad 'no COBJ records found at all, which means the load order or the Data folder is not what this thinks it is' }

# --------------------------------------------------------------- the split --

Write-Host ''
Write-Host 'who owns what' -ForegroundColor Cyan

# The keyword editor ids on one record, resolved after the whole scan rather
# than during it. A plugin can carry a record that names a keyword the same
# plugin defines further down the file, and resolving as we went would miss it.
function KeywordNames($item) {
    $names = New-Object 'System.Collections.Generic.List[string]'
    foreach ($k in $item.Keywords) {
        if ($kwName.ContainsKey($k)) { $names.Add($kwName[$k]) }
    }
    return $names.ToArray()
}

function HasKeyword($names, $want) {
    foreach ($n in $names) { if ($n -eq $want) { return $true } }
    return $false
}

function HasAnyKeyword($names, $wants) {
    foreach ($n in $names) { foreach ($w in $wants) { if ($n -eq $w) { return $true } } }
    return $false
}

# Splits an editor id or an item's name into the words a person reads in it.
# ClothesRedguardBoots comes back as Clothes, Redguard, Boots, and
# "Ulfric's Armguards" comes back as Ulfric, s, Armguards. A new word starts
# where a capital follows a small letter, where a capital is followed by a
# small letter after other capitals, and where letters meet digits. Anything
# that is not a letter or a digit ends a word.
function WordsIn([string]$text) {
    $words = New-Object 'System.Collections.Generic.List[string]'
    if (-not $text) { return ,$words.ToArray() }
    $cur = ''
    for ($i = 0; $i -lt $text.Length; $i++) {
        $c = $text[$i]
        if (-not [char]::IsLetterOrDigit($c)) {
            if ($cur) { $words.Add($cur); $cur = '' }
            continue
        }
        if ($cur.Length -gt 0) {
            $prev = $cur[$cur.Length - 1]
            $starts = $false
            if ([char]::IsDigit($c) -ne [char]::IsDigit($prev)) {
                $starts = $true
            } elseif ([char]::IsUpper($c) -and -not [char]::IsUpper($prev)) {
                $starts = $true
            } elseif ([char]::IsUpper($c) -and [char]::IsUpper($prev) -and ($i + 1 -lt $text.Length) -and [char]::IsLower($text[$i + 1])) {
                $starts = $true
            }
            if ($starts) { $words.Add($cur); $cur = '' }
        }
        $cur += $c
    }
    if ($cur) { $words.Add($cur) }
    return ,$words.ToArray()
}

# One word against one word, plural included. Case is ignored, which is what
# -eq does with two strings in PowerShell.
#
# The plural is not a nicety. Measured on the first run of whole word matching:
# 'Robe' on its own caught nothing at all, because every robe in this build is
# a record called Robes, and the Tailor's Liverywright half fell from 107 rows
# to 69 in one go. So a word in a list matches that word, that word with an s,
# and that word with es on the end, and nothing else.
function SameWord([string]$have, [string]$want) {
    if ($have -eq $want) { return $true }
    if ($have -eq ($want + 's')) { return $true }
    if ($have -eq ($want + 'es')) { return $true }
    return $false
}

# True when one of $words appears in $text as a whole word, or as a run of
# whole words in order for an entry like MothPriest. Case is ignored.
#
# This was a plain substring test until 20 September. See the Liverywright knob
# for what that cost: 'Guard' inside Redguard and Armguards moved eleven rows
# of common clothing into the wrong half of the Tailor.
function MatchesWord([string]$text, $words) {
    if (-not $text) { return $false }
    $have = WordsIn $text
    if ($have.Count -eq 0) { return $false }
    foreach ($w in $words) {
        $want = WordsIn $w
        if ($want.Count -eq 0) { continue }
        for ($i = 0; $i + $want.Count -le $have.Count; $i++) {
            $all = $true
            for ($j = 0; $j -lt $want.Count; $j++) {
                if (-not (SameWord $have[$i + $j] $want[$j])) { $all = $false; break }
            }
            if ($all) { return $true }
        }
    }
    return $false
}

# The Tailor's half. The faction keywords first because they are read out of
# the record, then the word list, which is the judgement.
function TailorHalf($item, $names) {
    if (HasAnyKeyword $names $LIVERYWRIGHT_KEYWORDS) { return @('Liverywright', 'the output carries a faction dress keyword') }
    if (MatchesWord $item.Edid $LIVERYWRIGHT_WORDS)  { return @('Liverywright', 'the output''s editor id matches the robe and faction word list') }
    if (MatchesWord $item.Name $LIVERYWRIGHT_WORDS)  {
        # Reported by name every run. The editor id is the modder's own filing
        # and the name is what a person reads, and where the two disagree the
        # name is the weaker evidence, so every row that only the name won is
        # printed rather than buried in a count of 107.
        $script:tailorByName.Add(("{0} ({1}), named '{2}'" -f $item.Edid, $item.Desc, $item.Name))
        return @('Liverywright', 'the output''s name matches the robe and faction word list')
    }
    return @('Haberdasher', 'clothing that is neither a robe nor faction dress')
}

# One condition on one recipe, read out as the question it asks. A parameter is
# a form id for the functions that take one, numbered the way every other form
# id in a plugin is, so DescOf resolves it against the same master list; a
# parameter that is not a form id, an actor value index for instance, has
# nothing to resolve to and is left as the number it is.
#
# ServerSees is the whole point of this. It is true when the fork has a
# function for that index and will really evaluate the condition, and false
# when it does not, in which case ConditionsEvaluator logs the index and
# answers True. A false here does NOT mean the recipe is available: the
# crafting menu in front of the person evaluates the same condition and hides
# the recipe when it fails, so the server is never asked.
function ConditionRead($cond, $masters, [string]$plugin) {
    $idx = [int]$cond.Func
    $name = 'function ' + $idx
    $serverSees = $false
    if ($CONDITION_FUNCTIONS_THE_SERVER_HAS.ContainsKey($idx)) {
        $name = $CONDITION_FUNCTIONS_THE_SERVER_HAS[$idx]
        $serverSees = $true
    } elseif ($idx -eq $CONDITION_VANILLA_PERK) {
        $name = 'HasPerk'
    }
    $what = ''
    $whatType = ''
    $whatDesc = ''
    if ($cond.Param1 -ne 0 -and $cond.Param1 -ne 4294967295) {
        $d = DescOf ([uint32]$cond.Param1) $masters $plugin
        if ($items.ContainsKey($d)) {
            $what = $items[$d].Edid
            $whatType = $items[$d].Type
            $whatDesc = $d
        } else {
            $what = '0x{0:x8}' -f $cond.Param1
        }
    }
    $op = '?'
    if ($cond.Operator -ge 0 -and $cond.Operator -lt $CONDITION_OPERATORS.Count) {
        $op = $CONDITION_OPERATORS[$cond.Operator]
    }
    $val = '{0:0.###}' -f $cond.Value
    if ($cond.UsesGlobal) { $val = 'the global 0x{0:x8}' -f ([uint32][math]::Round($cond.Value)) }
    $text = $name
    if ($what) { $text += '(' + $what + ')' }
    $text += ' ' + $op + ' ' + $val
    return [pscustomobject]@{
        Func = $idx; Name = $name; Text = $text
        Param = $what; ParamType = $whatType; ParamDesc = $whatDesc
        ServerSees = $serverSees
    }
}

$owned    = New-Object System.Collections.Specialized.OrderedDictionary
$unowned  = New-Object System.Collections.Specialized.OrderedDictionary
$instrumentRows = New-Object 'System.Collections.Generic.List[string]'
$tailorByName   = New-Object 'System.Collections.Generic.List[string]'
$noOutput = 0
$unresolvedOut = New-Object 'System.Collections.Generic.List[string]'
$namelessOut = @{}
$outTypeCount = @{}

foreach ($desc in $recipes.Keys) {
    $r = $recipes[$desc]

    $benchName = ''
    if ($r.BenchDesc -and $kwName.ContainsKey($r.BenchDesc)) { $benchName = $kwName[$r.BenchDesc] }

    # 1. A recipe with no CNAM names no output. There are eleven of them here
    #    and nine are armour table temper records. Nothing to gate.
    if (-not $r.OutDesc) {
        $noOutput++
        $unowned[$desc] = [pscustomobject]@{
            Edid = $r.Edid; OutDesc = ''; OutName = ''; OutType = ''; BenchDesc = $r.BenchDesc; BenchName = $benchName
            Why = 'the recipe carries no CNAM, so it names no output item'
        }
        continue
    }
    if (-not $items.ContainsKey($r.OutDesc)) {
        $unresolvedOut.Add(("{0} ({1}) outputs {2} and there is no such record in the load order" -f $r.Edid, $desc, $r.OutDesc))
        continue
    }
    $o = $items[$r.OutDesc]
    if ($o.NameFrom -eq 'the editor id') {
        if (-not $namelessOut.ContainsKey($o.Desc)) { $namelessOut[$o.Desc] = New-Object 'System.Collections.Generic.List[string]' }
        $namelessOut[$o.Desc].Add($r.Edid)
    }
    if (-not $outTypeCount.ContainsKey($o.Type)) { $outTypeCount[$o.Type] = 0 }
    $outTypeCount[$o.Type] = $outTypeCount[$o.Type] + 1
    $names = KeywordNames $o

    # 2. A recipe with no bench keyword. CraftService's own note says it: in the
    #    original game, setting the bench keyword to NONE removes the recipe
    #    from every crafting station. So nobody can reach it whatever this table
    #    says about it.
    if (-not $r.BenchDesc) {
        $unowned[$desc] = [pscustomobject]@{
            Edid = $r.Edid; OutDesc = $o.Desc; OutName = $o.Name; OutType = $o.Type; BenchDesc = ''; BenchName = ''
            Why = 'the recipe''s bench keyword is NONE, which takes it out of every crafting station in the game, so nobody can reach it'
        }
        continue
    }

    # 3. House building, and the one Bethesda test record.
    if ($benchName.StartsWith($BENCH_UNOWNED_PREFIX)) {
        $unowned[$desc] = [pscustomobject]@{
            Edid = $r.Edid; OutDesc = $o.Desc; OutName = $o.Name; OutType = $o.Type; BenchDesc = $r.BenchDesc; BenchName = $benchName
            Why = 'HearthFires house building, one keyword per piece of furniture. Not a trade in classes.md.'
        }
        continue
    }
    if ($BENCH_UNOWNED.Contains($benchName)) {
        $unowned[$desc] = [pscustomobject]@{
            Edid = $r.Edid; OutDesc = $o.Desc; OutName = $o.Name; OutType = $o.Type; BenchDesc = $r.BenchDesc; BenchName = $benchName
            Why = $BENCH_UNOWNED[$benchName]
        }
        continue
    }

    # 4. A bench that settles the profession on its own, and sometimes the half
    #    with it. The smelter is in this table with an empty owner, which is how
    #    a bench is declared open to everybody.
    $benchOwner = $null
    if ($BENCH_OWNER.Contains($benchName)) { $benchOwner = $BENCH_OWNER[$benchName] }
    if ($benchOwner -and -not $benchOwner.Owner) {
        $unowned[$desc] = [pscustomobject]@{
            Edid = $r.Edid; OutDesc = $o.Desc; OutName = $o.Name; OutType = $o.Type; BenchDesc = $r.BenchDesc; BenchName = $benchName
            Why = $benchOwner.Why
        }
        continue
    }

    $ownerName = ''
    $half = ''
    $reason = ''

    if ($benchOwner -and $benchOwner.ContainsKey('Half')) {
        $ownerName = $benchOwner.Owner
        $half = $benchOwner.Half
        $reason = $benchOwner.Why
    }
    elseif ($o.Type -eq 'ALCH') {
        # The cooking benches fill water bottles and mix fishing paste, and
        # neither is cooking a dinner.
        if (MatchesWord $o.Edid $NOT_COOKING_WORDS) {
            $unowned[$desc] = [pscustomobject]@{
                Edid = $r.Edid; OutDesc = $o.Desc; OutName = $o.Name; OutType = $o.Type; BenchDesc = $r.BenchDesc; BenchName = $benchName
                Why = 'it happens at a cooking bench but it is not cooking: filling water is not a dinner and refusing it to everybody but a Hearthcook would leave the rest of the world thirsty'
            }
            continue
        }
        if ($o.AlchFlags -band $ALCH_FLAG_POISON) {
            $ownerName = 'Alchemist'; $half = 'Blightbrewer'
            $reason = 'the output is an ALCH with the poison bit set in its ENIT flags'
        } elseif ($o.AlchFlags -band $ALCH_FLAG_FOOD) {
            $ownerName = 'Cook'
            if (HasKeyword $names $DESSERT_KEYWORD) {
                $half = 'Confectioner'
                $reason = 'the output is food and carries ' + $DESSERT_KEYWORD
            } else {
                $half = 'Hearthcook'
                $reason = 'the output is food and does not carry ' + $DESSERT_KEYWORD
            }
        } else {
            $ownerName = 'Alchemist'; $half = 'Physicker'
            $reason = 'the output is an ALCH with neither the poison bit nor the food bit, so it is a potion'
        }
    }
    elseif ($o.Type -eq 'WEAP') {
        if ($WOODWRIGHT_TAKES_INSTRUMENTS -and ((MatchesWord $o.Edid $INSTRUMENT_WORDS) -or (MatchesWord $o.Name $INSTRUMENT_WORDS))) {
            # Before the animation rule on purpose. An instrument is a WEAP
            # record with the animation type of a fist and no keywords at all,
            # so nothing further down this chain can tell it from a sword.
            $ownerName = 'Woodworker'; $half = 'Woodwright'
            $reason = 'the output is an instrument, and classes.md gives the Woodwright bows, arrows and instruments in one sentence'
            $instrumentRows.Add(("{0} -> {1} ({2}), animation type {3}, {4} keyword(s)" -f $r.Edid, $o.Name, $o.Edid, $o.WeapAnim, $names.Count))
        } elseif ($o.WeapAnim -eq $WEAP_ANIM_STAFF) {
            $ownerName = 'Enchanter'; $half = 'Bladebinder'
            $reason = 'the output is a WEAP whose animation type is a staff, and a staff is an enchantment on a stick'
        } elseif ($WOODWRIGHT_TAKES_BOWS_AND_ARROWS -and ($o.WeapAnim -eq $WEAP_ANIM_BOW -or $o.WeapAnim -eq $WEAP_ANIM_CROSSBOW)) {
            $ownerName = 'Woodworker'; $half = 'Woodwright'
            $reason = 'the output is a WEAP whose animation type is a bow or a crossbow, and classes.md gives the Woodwright bows'
        } else {
            $ownerName = 'Smith'; $half = 'Edgewright'
            $reason = 'the output is a WEAP that is not a bow and not a staff'
        }
    }
    elseif ($o.Type -eq 'AMMO') {
        if ($WOODWRIGHT_TAKES_BOWS_AND_ARROWS) {
            $ownerName = 'Woodworker'; $half = 'Woodwright'
            $reason = 'the output is AMMO, which is arrows and bolts, and classes.md gives the Woodwright arrows'
        } else {
            $unowned[$desc] = [pscustomobject]@{
                Edid = $r.Edid; OutDesc = $o.Desc; OutName = $o.Name; OutType = $o.Type; BenchDesc = $r.BenchDesc; BenchName = $benchName
                Why = 'arrows and bolts, and the knob that gives them to the Woodwright is switched off'
            }
            continue
        }
    }
    elseif ($o.Type -eq 'ARMO') {
        $isArmour = (HasKeyword $names $KW_HEAVY) -or (HasKeyword $names $KW_LIGHT) -or (HasKeyword $names $KW_SHIELD)
        if ((HasAnyKeyword $names $KW_JEWELRY) -and -not $isArmour) {
            $unowned[$desc] = [pscustomobject]@{
                Edid = $r.Edid; OutDesc = $o.Desc; OutName = $o.Name; OutType = $o.Type; BenchDesc = $r.BenchDesc; BenchName = $benchName
                Why = 'a ring or a necklace. classes.md has no jeweller, and the forge rule would otherwise hand every ring in Skyrim to the Platewright'
            }
            continue
        }
        if ($isArmour) {
            $ownerName = 'Smith'; $half = 'Platewright'
            if (HasKeyword $names $KW_SHIELD) {
                $reason = 'the output is an ARMO carrying ' + $KW_SHIELD + ', so it is a shield, and a shield is armour'
            } else {
                $reason = 'the output is an ARMO carrying ' + $KW_HEAVY + ' or ' + $KW_LIGHT
            }
        } elseif (HasAnyKeyword $names $KW_CLOTHING) {
            $ownerName = 'Tailor'
            $pick = TailorHalf $o $names
            $half = $pick[0]
            $reason = $pick[1]
        } else {
            $unowned[$desc] = [pscustomobject]@{
                Edid = $r.Edid; OutDesc = $o.Desc; OutName = $o.Name; OutType = $o.Type; BenchDesc = $r.BenchDesc; BenchName = $benchName
                Why = 'an ARMO that carries no armour keyword, no clothing keyword and no jewelry keyword, so nothing in the record says what it is'
            }
            continue
        }
    }
    elseif ($benchOwner) {
        # A bench that settles the profession but not the half, with an output
        # that does not settle it either. The loom is the case: its thread and
        # its children's clothes are MISC records rather than ARMO.
        $ownerName = $benchOwner.Owner
        if ($ownerName -eq 'Tailor') {
            $pick = TailorHalf $o $names
            $half = $pick[0]
            $reason = $benchOwner.Why + ', and ' + $pick[1]
        } elseif ($ownerName -eq 'Cook') {
            $half = 'Hearthcook'
            $reason = $benchOwner.Why + ', and the output carries no ' + $DESSERT_KEYWORD
        } else {
            $unowned[$desc] = [pscustomobject]@{
                Edid = $r.Edid; OutDesc = $o.Desc; OutName = $o.Name; OutType = $o.Type; BenchDesc = $r.BenchDesc; BenchName = $benchName
                Why = 'the bench says ' + $ownerName + ' but nothing in the output says which half, and a guess here would be a guess in the table'
            }
            continue
        }
    }
    else {
        # MISC and INGR off a bench nobody has claimed. Ingots, leather, fur
        # plates, nails, fishing poles. Stock and tools rather than a finished
        # good of any half.
        $unowned[$desc] = [pscustomobject]@{
            Edid = $r.Edid; OutDesc = $o.Desc; OutName = $o.Name; OutType = $o.Type; BenchDesc = $r.BenchDesc; BenchName = $benchName
            Why = 'a ' + $o.Type + ' off ' + $benchName + '. It is stock or a tool rather than a finished good of any half, so nobody owns it and anybody may make it.'
        }
        continue
    }

    $fires = $true
    foreach ($b in $BENCHES_THE_SERVER_NEVER_SEES) {
        if ($r.BenchDesc -eq $b) { $fires = $false }
    }

    # What the recipe asks of the person before the game will even list it.
    # A row with nothing here is one a character created this morning, carrying
    # nothing, can make the moment they reach the bench. Everything else needs
    # something first, and what that something is is written out rather than
    # counted, because "this half has 28 recipes" and "this half has 28
    # recipes nobody on this server can reach" printed the same number until
    # these were read.
    $needs = New-Object 'System.Collections.Generic.List[object]'
    foreach ($c in $r.Conditions) {
        $needs.Add((ConditionRead $c $r.Masters $r.SeenIn))
    }
    $behindPerk = $false
    $serverChecks = 0
    foreach ($n in $needs) {
        if ($n.Func -eq $CONDITION_VANILLA_PERK) { $behindPerk = $true }
        if ($n.ServerSees) { $serverChecks++ }
    }

    $owned[$desc] = [pscustomobject]@{
        Edid = $r.Edid; OutDesc = $o.Desc; OutName = $o.Name; OutType = $o.Type
        BenchDesc = $r.BenchDesc; BenchName = $benchName
        Owner = $ownerName; Half = $half; Reason = $reason
        Count = $r.Count; Inputs = $r.Inputs; InputList = $r.InputList; Fires = $fires
        Plugin = $r.Plugin; SeenIn = $r.SeenIn; Local = $r.Local
        NameFrom = $o.NameFrom
        Value = $o.Value
        Needs = $needs.ToArray()
        DayOne = ($needs.Count -eq 0)
        BehindVanillaPerk = $behindPerk
        ServerChecks = $serverChecks
        Rank = ''
        RankWhy = ''
        RankByValue = ''
        RankFrom = ''
        InputRank = ''
        InputRankWho = ''
        # How many of this row's inputs no class in this world produces. The
        # UNPLACED_INPUT_RULE knob reads it, and it goes in the json, because
        # 'the dearest input is novice' means something different on a row where
        # that is the whole list and on a row with four unknowns beside it.
        InputsUnplaced = 0
    }
}

# ------------------------------------------------------- what the rules did -

if ($instrumentRows.Count -gt 0) {
    Note ("{0} recipe(s) went to the Woodwright as instruments:" -f $instrumentRows.Count)
    foreach ($i in $instrumentRows) { Note ("  " + $i) }
} elseif ($WOODWRIGHT_TAKES_INSTRUMENTS) {
    Note 'no recipe in this build outputs an instrument'
}
if ($tailorByName.Count -gt 0) {
    Note ("{0} Tailor row(s) went to the Liverywright on the output's name alone:" -f $tailorByName.Count)
    foreach ($t in $tailorByName) { Note ("  " + $t) }
}

# ------------------------------------------------------------ the conditions

Write-Host ''
Write-Host 'conditions' -ForegroundColor Cyan

# What the recipes in this build ask for, counted by function. This is the
# table that says whether a half's rows are work or scenery.
$condFuncRows = @{}
$condPerkParamTypes = @{}
$rowsWithConditions = 0
foreach ($desc in $owned.Keys) {
    $row = $owned[$desc]
    if (-not $row.Fires) { continue }
    if ($row.Needs.Count -gt 0) { $rowsWithConditions++ }
    $seenHere = @{}
    foreach ($n in $row.Needs) {
        if (-not $seenHere.ContainsKey($n.Name)) {
            $seenHere[$n.Name] = $true
            if (-not $condFuncRows.ContainsKey($n.Name)) { $condFuncRows[$n.Name] = 0 }
            $condFuncRows[$n.Name] = $condFuncRows[$n.Name] + 1
        }
        if ($n.Func -eq $CONDITION_VANILLA_PERK) {
            $t = $n.ParamType
            if (-not $t) { $t = 'not a record in this load order' }
            if (-not $condPerkParamTypes.ContainsKey($t)) { $condPerkParamTypes[$t] = 0 }
            $condPerkParamTypes[$t] = $condPerkParamTypes[$t] + 1
        }
    }
}
$firingOwned = 0
foreach ($desc in $owned.Keys) { if ($owned[$desc].Fires) { $firingOwned++ } }
Note ("{0} of the {1} owned rows the server is asked about carry at least one condition" -f $rowsWithConditions, $firingOwned)
foreach ($f in ($condFuncRows.Keys | Sort-Object { -$condFuncRows[$_] })) {
    $tail = 'the server evaluates this one itself'
    if ($f -eq 'HasPerk' -or $f.StartsWith('function ')) {
        $tail = 'the fork has no function for this index, so the server answers True and the crafting menu in front of the person is the only thing enforcing it'
    }
    Write-Host ("  {0,6}  {1,-28} {2}" -f $condFuncRows[$f], $f, $tail)
}
# The evidence for calling index 448 HasPerk, printed rather than asserted.
if ($condPerkParamTypes.Count -gt 0) {
    foreach ($t in ($condPerkParamTypes.Keys | Sort-Object)) {
        Note ("function {0} carries a first parameter that resolves to {1} on {2} condition(s)" -f $CONDITION_VANILLA_PERK, $t, $condPerkParamTypes[$t])
    }
}

# ------------------------------- what hands out the items a recipe asks for -
#
# A recipe gated on GetItemCount wants something in the pack before the game
# will list it. If nothing in the whole load order ever hands that something
# out, the recipe is not gated, it is dead, and the half that owns it is
# smaller than its count says. The Charburner is the case: three of its four
# recipes want a woodcutter's book.
#
# HOW THIS SEARCHES, AND WHAT IT CANNOT SEE. Every plugin is read again and
# searched for the three subrecords that put an item within reach of a person:
#   NAME of 4 bytes  a placed reference, which is an object standing in a cell
#   CNTO of 8 bytes  a line in a container's or a character's inventory
#   LVLO of 12 bytes a line in a levelled list
# The form id is written into each plugin's own numbering first, out of the
# master list that plugin declares, because the same record is a different
# number in every file that mentions it.
#
# It cannot see three things, and none of them is guessed at: a record stored
# compressed inside a plugin hides its subrecords from a byte search; a Papyrus
# script handing over an item is not in any of these subrecords, and this
# server does not run Papyrus anyway; and a mod that gives the item through the
# Creation Kit's quest aliases lands in none of the three either. So a hit here
# is proof the item is reachable, and no hit is a reason to go and look rather
# than a proof of nothing.
#
# It is loud rather than fatal. The recipe belongs to whoever's plugin ships it
# and the fix is in that plugin, not in this table, and refusing to write 5116
# rows over a mod's dead recipe would leave the server with no table at all.

Write-Host ''
Write-Host 'what hands out the items these recipes ask for' -ForegroundColor Cyan

$wantedItems = New-Object System.Collections.Specialized.OrderedDictionary
foreach ($desc in $owned.Keys) {
    $row = $owned[$desc]
    if (-not $row.Fires) { continue }
    foreach ($nd in $row.Needs) {
        if ($nd.Name -ne 'GetItemCount') { continue }
        $d = $nd.ParamDesc
        if (-not $d) { continue }
        if (-not $wantedItems.Contains($d)) {
            $wantedItems[$d] = [pscustomobject]@{
                Edid = $nd.Param; Type = $nd.ParamType
                Wanters = New-Object 'System.Collections.Generic.List[string]'
                Found = ''
            }
        }
        $wantedItems[$d].Wanters.Add($row.Edid)
    }
}

if ($wantedItems.Count -eq 0) {
    Ok 'no recipe in this table asks for an item first'
} else {
    $latin1 = [System.Text.Encoding]::GetEncoding(28591)
    foreach ($pl in $order) {
        $left = 0
        foreach ($d in $wantedItems.Keys) { if (-not $wantedItems[$d].Found) { $left++ } }
        if ($left -eq 0) { break }
        $path = Join-Path $Data $pl
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $masters = $pluginMasters[$pl]
        $bytes = [System.IO.File]::ReadAllBytes($path)
        $text = $latin1.GetString($bytes)
        foreach ($d in $wantedItems.Keys) {
            if ($wantedItems[$d].Found) { continue }
            $bits = $d.Split(':')
            $localId = [uint32]('0x' + $bits[0])
            $owner = $bits[1]
            $index = -1
            if ($owner -eq $pl) {
                $index = $masters.Count
            } else {
                for ($m = 0; $m -lt $masters.Count; $m++) { if ($masters[$m] -eq $owner) { $index = $m; break } }
            }
            if ($index -lt 0) { continue }
            $full = ([uint32]$index -shl 24) -bor ($localId -band 0xFFFFFF)
            $idText = [string]([char]($full -band 0xFF)) + [char](($full -shr 8) -band 0xFF) +
                      [char](($full -shr 16) -band 0xFF) + [char](($full -shr 24) -band 0xFF)
            if ($text.IndexOf('NAME' + [char]4 + [char]0 + $idText, [StringComparison]::Ordinal) -ge 0) {
                $wantedItems[$d].Found = 'placed in the world by ' + $pl
                continue
            }
            if ($text.IndexOf('CNTO' + [char]8 + [char]0 + $idText, [StringComparison]::Ordinal) -ge 0) {
                $wantedItems[$d].Found = 'in a container or a character''s inventory in ' + $pl
                continue
            }
            $p = 0
            while (($p = $text.IndexOf('LVLO' + [char]12 + [char]0, $p, [StringComparison]::Ordinal)) -ge 0) {
                if ($p + 14 -le $text.Length -and $text.Substring($p + 10, 4) -ceq $idText) {
                    $wantedItems[$d].Found = 'on a levelled list in ' + $pl
                    break
                }
                $p += 6
            }
        }
        $text = $null
        $bytes = $null
    }

    $orphans = 0
    foreach ($d in $wantedItems.Keys) {
        $w = $wantedItems[$d]
        if ($w.Found) { continue }
        $orphans++
        Loud ("nothing in the load order hands out {0} {1} ({2}), and {3} recipe(s) will not appear without it: {4}" -f `
              $w.Type, $w.Edid, $d, $w.Wanters.Count, (($w.Wanters | Select-Object -First 4) -join ', '))
    }
    if ($orphans -eq 0) {
        Ok ("all {0} item(s) these recipes ask for are handed out somewhere in the load order" -f $wantedItems.Count)
    } else {
        Note ("{0} of {1} wanted item(s) were found, {2} were not" -f ($wantedItems.Count - $orphans), $wantedItems.Count, $orphans)
    }
}

# -------------------------------------------------- what an input costs ----
#
# The reverse index: item -> the rank somebody has to hold before any class in
# this world can hand that item over, and which class that is. Built out of the
# five producing tables named in PRODUCER_TABLES, every one of which is in this
# folder and was built from the game's own records by its own script, and out
# of SERVER_PRODUCERS, which is the salt quarry this repository's own plugin
# and gamemode.js put in the world and no table is written for.
#
# This is the only place the two halves of the economy meet. Until it existed,
# the producing ladders and the crafting ladder were built by different scripts
# from different records with different rules and nothing compared them, so a
# novice Hearthcook could be handed a first recipe wanting a crop only an
# expert Farmer may grow and neither table could see it.
#
# EVERY PRODUCER OF AN ITEM IS KEPT AND NOT JUST THE WINNER. The index answers
# with the lowest, which is what a recipe costs, but a table that placed
# nothing used to be indistinguishable in the output from a table that was not
# read at all: the crops map contributed 0 of 137 entries for a year of builds
# and the run said '0 item(s) it is the first to name' and nothing else. The
# full list is what the cross-class report below reads to say that a Cook is
# novice on an apple a farmer has to be expert to grow.

Write-Host ''
Write-Host 'what an input costs a producer' -ForegroundColor Cyan

$producerSources = @{}
foreach ($t in $PRODUCER_TABLES) {
    $path = Join-Path $PSScriptRoot $t.File
    if (-not (Test-Path -LiteralPath $path)) {
        Bad ("{0} is not in this folder, so nothing can say what a {1} produces or at what rank. Build it and run this again." -f $t.File, $t.Who)
        continue
    }
    if (-not $producerSources.ContainsKey($t.File)) {
        $producerSources[$t.File] = (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)
    }
    $tab = $producerSources[$t.File]
    if (-not ($tab.PSObject.Properties.Name -contains $t.Map)) {
        Bad ("{0} has no '{1}' map in it, so the {2}'s ladder cannot be read" -f $t.File, $t.Map, $t.Who)
        continue
    }
    $map = $tab.($t.Map)
    $rows = 0
    $addedHere = 0
    $lostHere = 0
    foreach ($k in $map.PSObject.Properties.Name) {
        $row = $map.$k
        $rank = [string]$row.rank
        $at = RankAt $rank
        if ($at -lt 0) { continue }
        $rows++
        # An ore vein or a plant hands over one item and names it in a field of
        # its own. An animal hands over a list, because a mudcrab gives legs
        # and chitin off the same carcass, so both shapes are read.
        $gives = @()
        if ($t.List) {
            if ($row.PSObject.Properties.Name -contains $t.List) {
                foreach ($g in $row.($t.List)) {
                    $d = [string]$g.($t.Item)
                    if ($d) { $gives += @{ Desc = $d; Name = [string]$g.name } }
                }
            }
        } else {
            $d = [string]$row.($t.Item)
            if ($d) { $gives += @{ Desc = $d; Name = [string]$row.name } }
        }
        foreach ($g in $gives) {
            if (RememberProducer $g.Desc $rank $at $t.Who $g.Name ($t.File + ' ' + $t.Map)) {
                $addedHere++
            } else {
                $lostHere++
            }
        }
    }
    if ($addedHere -eq 0 -and $rows -gt 0) {
        # A whole ladder that places nothing is the failure that hid for as long
        # as this only printed what a table won. Named out loud, with the reason
        # it lost, because a silent zero here is a class whose ranks decide
        # nothing about any recipe in the table.
        Loud ("{0} {1}: {2} ranked row(s) read and NOT ONE item entered the index. Every item it hands over is already in there off an earlier table at the same rank or lower, so the {3}'s ranks set nothing in this table." -f `
              $t.File, $t.Map, $rows, $t.Who)
    } else {
        Note ("{0} {1}: {2} ranked row(s) read, {3} item(s) it is the first to name, {4} an earlier table already had at the same rank or lower" -f `
              $t.File, $t.Map, $rows, $addedHere, $lostHere)
    }
}

# The salt quarry, which is this server's own and is in no table. Read off
# gamemode.js by hand into SERVER_PRODUCERS, with the line each rank came from
# written beside it there.
$serverAdded = 0
foreach ($s in $SERVER_PRODUCERS) {
    $at = RankAt $s.Rank
    if ($at -lt 0) {
        Bad ("SERVER_PRODUCERS names {0} at rank '{1}', which is not one of classes.md's four" -f $s.Name, $s.Rank)
        continue
    }
    if (RememberProducer $s.Desc $s.Rank $at $s.Who $s.Name $s.Where) { $serverAdded++ }
}
if ($SERVER_PRODUCERS.Count -gt 0) {
    Note ("the server's own verbs: {0} item(s) named in SERVER_PRODUCERS, {1} of them the first to name the item" -f `
          $SERVER_PRODUCERS.Count, $serverAdded)
}

$byWho = @{}
foreach ($d in $producer.Keys) {
    $w = $producer[$d].Who
    if (-not $byWho.ContainsKey($w)) { $byWho[$w] = 0 }
    $byWho[$w] = $byWho[$w] + 1
}
$whoLine = @()
foreach ($w in ($byWho.Keys | Sort-Object)) { $whoLine += ('{0} {1}' -f $w, $byWho[$w]) }
Ok ("the reverse index holds {0} distinct item(s): {1}" -f $producer.Count, ($whoLine -join ', '))

# How many of the recipes' inputs this index can place, counted two ways,
# because the two numbers answer different questions. Distinct items says how
# much of the world's stock has a producer behind it. Rows says how many
# recipes can be ranked by the new rule at all.
$inputItemsSeen = @{}
$rowsWithInputs = 0
$rowsPlaced = 0
foreach ($desc in $owned.Keys) {
    $r = $owned[$desc]
    $list = @($r.InputList)
    if ($list.Count -eq 0) { continue }
    $rowsWithInputs++
    $anyPlaced = $false
    foreach ($i in $list) {
        if (-not $inputItemsSeen.ContainsKey($i.Desc)) { $inputItemsSeen[$i.Desc] = 0 }
        $inputItemsSeen[$i.Desc] = $inputItemsSeen[$i.Desc] + 1
        if ($producer.ContainsKey($i.Desc)) { $anyPlaced = $true }
    }
    if ($anyPlaced) { $rowsPlaced++ }
}
$placedItems = 0
foreach ($d in $inputItemsSeen.Keys) { if ($producer.ContainsKey($d)) { $placedItems++ } }
Ok ("the owned recipes ask for {0} distinct input item(s); {1} of them have a producer and {2} do not" -f `
    $inputItemsSeen.Count, $placedItems, ($inputItemsSeen.Count - $placedItems))
Ok ("{0} of the {1} owned rows that list any input have at least one input with a producer behind it; {2} have none and fall back to what the output sells for" -f `
    $rowsPlaced, $rowsWithInputs, ($rowsWithInputs - $rowsPlaced))
$noInputRows = $owned.Count - $rowsWithInputs
if ($noInputRows -gt 0) {
    Note ("{0} owned row(s) carry no CNTO at all, so they list no inputs and there is nothing to read a cost off" -f $noInputRows)
}

# The commonest inputs nothing produces, because that list is the shopping list
# for whoever wants more halves ranked by cost rather than by price.
$unplaced = @()
foreach ($d in $inputItemsSeen.Keys) { if (-not $producer.ContainsKey($d)) { $unplaced += $d } }
if ($unplaced.Count -gt 0) {
    $unplaced = @($unplaced | Sort-Object { -$inputItemsSeen[$_] })
    Note 'the inputs no producing table hands out, commonest first:'
    foreach ($d in ($unplaced | Select-Object -First 12)) {
        $nm = $d
        if ($items.ContainsKey($d)) { $nm = $items[$d].Name + ' (' + $items[$d].Type + ')' }
        Note ("  {0,5} recipe(s) want {1} [{2}]" -f $inputItemsSeen[$d], $nm, $d)
    }
    if ($unplaced.Count -gt 12) { Note ("  ... and {0} more" -f ($unplaced.Count - 12)) }
}

# ------------------------------------------------------------- the ranking --

Write-Host ''
Write-Host 'ranking' -ForegroundColor Cyan

# A row with no price cannot be ranked, and a rank guessed without one would
# decide what a real person may make. The build fails rather than guessing.
$noValue = New-Object 'System.Collections.Generic.List[string]'
foreach ($desc in $owned.Keys) {
    if ($owned[$desc].Value -lt 0) {
        $noValue.Add(("{0} ({1}) makes {2}, a {3}, and no rule in VALUE_RULES says where that record keeps its value" -f `
                      $owned[$desc].Edid, $desc, $owned[$desc].OutName, $owned[$desc].OutType))
    }
}
if ($noValue.Count -gt 0) {
    Bad ("{0} owned recipe(s) have no price to rank by" -f $noValue.Count)
    foreach ($v in ($noValue | Select-Object -First 8)) { Note ("  " + $v) }
} else {
    Ok 'every owned recipe makes something the records put a price on'
}

# The shares, half by half. Sorted by price, cheapest first, and the cut is
# pushed past any run of rows that share the boundary price, so two recipes
# that make things worth the same never land on different rungs.
$promoted = New-Object 'System.Collections.Generic.List[string]'
$rankRows = @{}
$rankedByInputs = @{}
$rankedByValue = @{}
# Per half: how many rows the placed inputs would have pulled DOWN and the
# price rule held up, under UNPLACED_INPUT_RULE 'floor'. Printed per half and
# totalled, because this number is the whole of the dragonbone defect.
$heldByPrice = @{}
$secondRuleUsed = [ordered]@{}
# Per half: the rungs that hold rows nobody at that rank can gather the makings
# for. Written into the json so Check-Balance.ps1 reads the same finding off the
# table rather than working it out a second way and disagreeing.
$unstandable = [ordered]@{}
foreach ($p in $PROFESSIONS.Keys) {
    foreach ($h in $PROFESSIONS[$p]) {
        $key = $p + '/' + $h
        $mine = New-Object 'System.Collections.Generic.List[object]'
        foreach ($desc in $owned.Keys) {
            if (($owned[$desc].Owner + '/' + $owned[$desc].Half) -eq $key) { $mine.Add($desc) }
        }
        if ($mine.Count -eq 0) { continue }
        $sorted = @($mine | Sort-Object @{ Expression = { [int64]$owned[$_].Value } }, @{ Expression = { [string]$_ } })
        $n = $sorted.Count
        $at = 0
        foreach ($s in $RANK_SHARE) {
            $last = [int][math]::Ceiling($n * [double]$s.Upto)
            if ($last -gt $n) { $last = $n }
            # do not split a run of equal prices across two ranks
            while ($last -lt $n -and [int64]$owned[$sorted[$last - 1]].Value -eq [int64]$owned[$sorted[$last]].Value) { $last++ }
            while ($at -lt $last) {
                $owned[$sorted[$at]].Rank = [string]$s.Rank
                $owned[$sorted[$at]].RankWhy = ('what it makes is worth ' + $owned[$sorted[$at]].Value + ' gold, which puts it in the ' + $s.Rank + ' share of what this half makes')
                $at++
            }
        }
        while ($at -lt $n) {
            $owned[$sorted[$at]].Rank = [string]$RANK_SHARE[$RANK_SHARE.Count - 1].Rank
            $owned[$sorted[$at]].RankWhy = 'the dearest of what this half makes'
            $at++
        }

        # THE INPUT COST RULE. What the shares said is kept on every row as
        # rankByValue, so the two answers can be compared afterwards rather than
        # one of them quietly replacing the other with nothing to read.
        #
        # A row is ranked by the DEAREST thing it asks for, because a recipe is
        # unmakeable until you can get all of it. A row that asks for nothing
        # any class produces keeps what it sells for, and says so on the row.
        #
        # IT DOES NOT OVERRIDE ANYTHING UNCONDITIONALLY, and it did until
        # 21 September. It can only read the inputs the index PLACES, and an
        # input nothing produces is an unknown cost and not a cost of nothing.
        # UNPLACED_INPUT_RULE is where that is decided and the measurement that
        # forced it is written out there: a 3100 gold dragonbone plate went out
        # at novice because the one thing on its list anybody produces was a
        # novice hunter's fox pelt.
        $fromInputs = 0
        $heldUpByPrice = 0
        foreach ($d in $sorted) {
            $owned[$d].RankByValue = [string]$owned[$d].Rank
            $best = -1
            $whoBest = ''
            $nameBest = ''
            $unplaced = 0
            foreach ($i in @($owned[$d].InputList)) {
                if (-not $producer.ContainsKey($i.Desc)) { $unplaced++; continue }
                if (-not $RANK_FROM_INPUT_COST) { continue }
                $pz = $producer[$i.Desc]
                $better = $false
                if ($best -lt 0) {
                    $better = $true
                } elseif ($INPUT_RANK_IS_THE_DEAREST) {
                    if ($pz.At -gt $best) { $better = $true }
                } else {
                    if ($pz.At -lt $best) { $better = $true }
                }
                if ($better) { $best = $pz.At; $whoBest = $pz.Who; $nameBest = $pz.Name }
            }
            $owned[$d].InputsUnplaced = $unplaced
            if ($best -lt 0) {
                $owned[$d].InputRank = ''
                $owned[$d].InputRankWho = ''
                $owned[$d].RankFrom = 'what it sells for, because nothing it asks for is produced by any class in this world'
                continue
            }
            $owned[$d].InputRank = [string]$RANKS[$best]
            $owned[$d].InputRankWho = $whoBest

            # The whole list is placed, so the dearest of it is what the recipe
            # costs and there is nothing unknown left to be wrong about.
            $inputDecides = $true
            if ($unplaced -gt 0 -and $UNPLACED_INPUT_RULE -ne 'decides') {
                $valAt = RankAt ([string]$owned[$d].RankByValue)
                if ($UNPLACED_INPUT_RULE -eq 'price') {
                    $inputDecides = $false
                } elseif ($valAt -gt $best) {
                    # 'floor': the placed inputs are a floor and the price is
                    # above it, so the price stands and the row says why.
                    $inputDecides = $false
                }
            }
            if (-not $inputDecides) {
                $heldUpByPrice++
                $owned[$d].RankFrom = ('what it sells for, held above what its placed inputs cost because ' + $unplaced +
                                       ' of the things it asks for are produced by no class in this world and could cost anything')
                $owned[$d].RankWhy = ($owned[$d].RankWhy + '. The dearest input any class does produce is ' + $nameBest +
                                      ', ' + $RANKS[$best] + ' work for a ' + $whoBest + ', which is a floor and not the answer here')
                continue
            }
            $owned[$d].Rank = [string]$RANKS[$best]
            $owned[$d].RankFrom = 'what its inputs cost a producer'
            $owned[$d].RankWhy = ('the dearest thing it asks for is ' + $nameBest + ', which a ' + $whoBest +
                                  ' gets at ' + $RANKS[$best] + ', so that is the rung somebody has to have reached before they could gather the makings at all')
            if ($unplaced -gt 0) {
                $owned[$d].RankWhy = ($owned[$d].RankWhy + '. ' + $unplaced +
                                      ' more thing(s) on its list are produced by no class and what it sells for does not put it any higher')
            }
            $fromInputs++
        }
        $rankedByInputs[$key] = $fromInputs
        $heldByPrice[$key] = $heldUpByPrice
        $rankedByValue[$key] = $n - $fromInputs

        # The circle check, and the one rule that breaks it. The cheapest row
        # of this half that a new character can actually reach is novice,
        # whatever the share said, because a rung nobody can stand on is a rung
        # nobody climbs off.
        if ($NOVICE_MUST_BE_REACHABLE) {
            $firstOpen = ''
            foreach ($d in $sorted) {
                if ($owned[$d].Fires -and $owned[$d].DayOne) { $firstOpen = $d; break }
            }
            if ($firstOpen -and $owned[$firstOpen].Rank -ne 'novice') {
                $promoted.Add(("{0}: {1} ({2}), worth {3}, was {4} and is the cheapest row of this half anybody can reach on the day they pick it" -f `
                               $key, $owned[$firstOpen].Edid, $owned[$firstOpen].OutName, $owned[$firstOpen].Value, $owned[$firstOpen].Rank))
                $owned[$firstOpen].Rank = 'novice'
                $owned[$firstOpen].RankWhy = 'the cheapest row of this half that a new character can reach, moved to novice so the half has a way in'
            }
        }

        $counts = CountRungs $sorted
        $hole = HoleIn $counts

        # THE RUNGS MUST NOT BE EMPTY, and this is where that is enforced rather
        # than reported. A rung with nothing on it and something above it is a
        # rank that opens nothing: you reach it, and the list of what you may
        # make is the same list as yesterday.
        #
        # Nothing is invented and nothing is smeared. The half is named out
        # loud, the empty rung is named, the reason is printed from what was
        # measured, and then the SECOND RULE below ranks that half alone.
        if ($hole -ge 0) {
            $spread = @{}
            foreach ($d in $sorted) {
                $rk = [string]$owned[$d].Rank
                if (-not $spread.ContainsKey($rk)) { $spread[$rk] = 0 }
                $spread[$rk] = $spread[$rk] + 1
            }
            $vals = @{}
            foreach ($d in $sorted) { $vals[[string]$owned[$d].Value] = $true }
            $distinct = @{}
            $totals = @{}
            foreach ($d in $sorted) {
                $distinct[[string](@($owned[$d].InputList).Count)] = $true
                $tc = 0
                foreach ($i in @($owned[$d].InputList)) { $tc += [int]$i.Count }
                $totals[[string]$tc] = $true
            }
            $spreadTxt = @()
            foreach ($rk in $RANKS) {
                $c = 0
                if ($spread.ContainsKey($rk)) { $c = $spread[$rk] }
                $spreadTxt += ('{0} {1}' -f $rk, $c)
            }
            $why = ('{0} row(s) ranked by what their inputs cost and {1} by what they sell for, and they land {2}. What is left to rank by is {3} distinct output price(s), {4} distinct input list length(s) and {5} distinct total input count(s)' -f `
                    $rankedByInputs[$key], $rankedByValue[$key], ($spreadTxt -join ', '), $vals.Keys.Count, $distinct.Keys.Count, $totals.Keys.Count)
            Loud ("{0}: the {1} rung is empty with rows above it. {2}" -f $key, $RANKS[$hole], $why)
            $secondRuleUsed[$key] = ('the {0} rung came out empty with rows above it. {1}. Ranked by {2} for this half alone.' -f `
                                     $RANKS[$hole], $why, $SECOND_RULE_KEY)
            $counts = SecondRule $key $sorted
            $hole = HoleIn $counts
            if ($hole -ge 0) {
                Bad ("{0}: the {1} rung is still empty after the {2} rule, so this half has no ladder and the table was not written" -f `
                     $key, $RANKS[$hole], $SECOND_RULE_KEY)
            } else {
                Loud ("  {0}: ranked by {1} instead, and every rung now has work on it" -f $key, $SECOND_RULE_KEY)
            }
        }

        # AND THE RUNGS HAVE TO BE STANDABLE, which is the question a count of
        # rows cannot ask. Argued for at RUNGS_MUST_BE_STANDABLE. A half that
        # fails it and is not named in HALVES_WITH_AN_UNSTANDABLE_RUNG with a
        # measured reason fails this build.
        if ($RUNGS_MUST_BE_STANDABLE) {
            $bad = @(UnstandableRungs $sorted)
            if ($bad.Count -gt 0) {
                $said = @()
                foreach ($b in $bad) {
                    $said += ('the {0} rung holds {1} row(s) and not one of them can be gathered for below {2}; the nearest is {3}, wanting {4} work from a {5}' -f `
                              $b.Rank, $b.Rows, $b.NeedAt, $b.Nearest, $b.NeedAt, $b.Who)
                }
                $unstandable[$key] = ($said -join '. ')
                if ($HALVES_WITH_AN_UNSTANDABLE_RUNG.Contains($key)) {
                    Loud ("{0}: {1}. Named in HALVES_WITH_AN_UNSTANDABLE_RUNG, so this build is allowed to write it: {2}" -f `
                          $key, ($said -join '. '), $HALVES_WITH_AN_UNSTANDABLE_RUNG[$key])
                } else {
                    Bad ("{0}: {1}. Reaching that rank opens work nobody at that rank can gather for, which is an empty rung wearing a label. Decide it and name it in HALVES_WITH_AN_UNSTANDABLE_RUNG, or change what the half asks for." -f `
                         $key, ($said -join '. '))
                }
            }
        }

        $rankRows[$key] = $counts
        $lo = [int64]$owned[$sorted[0]].Value
        $hi = [int64]$owned[$sorted[$n - 1]].Value
        Write-Host ("  {0,-24} {1,5} rows, {2} to {3} gold, novice {4}, advanced {5}, expert {6}, master {7}   ({8} by input cost, {9} by price, {10} held up by price over an unplaced input)" -f `
                    $key, $n, $lo, $hi, $counts['novice'], $counts['advanced'], $counts['expert'], $counts['master'], `
                    $rankedByInputs[$key], $rankedByValue[$key], $heldByPrice[$key])
    }
}
if ($promoted.Count -gt 0) {
    Loud ("{0} row(s) were moved to novice so that the half has something a new character can make:" -f $promoted.Count)
    foreach ($pz in $promoted) { Loud ("  " + $pz) }
} else {
    Ok 'every half already had a reachable novice row, so nothing was moved'
}

# --------------- where a ladder sits below the class that grows what it asks --
#
# PATRICK'S QUESTION, ANSWERED AS A NUMBER INSTEAD OF AS A CLAIM. 21 September:
# "farmer matches with tiers of cook for their recipes, miner and smith,
# woodworker and miner and so on, so there isn't an imbalance".
#
# The reverse index answers with the LOWEST rank any class gets an item at, and
# that is the right answer for what a recipe costs: an apple in the pot does not
# care who pulled it off the tree. What it hides is the class that has to climb
# furthest for the same item, and for crops that is every one of them, because
# all 11 crops are also plants a gatherer picks at the same rank or lower.
#
# So this walks the OTHER producers, the ones $producer dropped, and names every
# owned row whose rank sits below a class that produces something on its list.
# That is not automatically wrong and nothing here fails on it. It is the
# imbalance stated: reading 'Apple Pie, Cook/Confectioner advanced, wants Red
# Apple, which a farmer grows at expert' is what lets somebody decide whether
# the Farmer's ladder or the recipe's rank is the thing to move.

Write-Host ''
Write-Host 'where a ladder sits below the class that grows what it asks for' -ForegroundColor Cyan

$crossPairs = @{}
$crossRows = 0
$crossSaid = New-Object 'System.Collections.Generic.List[string]'
foreach ($desc in $owned.Keys) {
    $r = $owned[$desc]
    $rowAt = RankAt ([string]$r.Rank)
    if ($rowAt -lt 0) { continue }
    $worst = -1
    $worstWho = ''
    $worstName = ''
    foreach ($i in @($r.InputList)) {
        if (-not $producerAll.ContainsKey($i.Desc)) { continue }
        foreach ($pz in $producerAll[$i.Desc]) {
            if ($pz.At -le $rowAt) { continue }
            if ($pz.At -gt $worst) { $worst = $pz.At; $worstWho = $pz.Who; $worstName = $pz.Name }
        }
    }
    if ($worst -lt 0) { continue }
    $crossRows++
    $pair = ($r.Owner + '/' + $r.Half + ' <- ' + $worstWho)
    if (-not $crossPairs.ContainsKey($pair)) { $crossPairs[$pair] = 0 }
    $crossPairs[$pair] = $crossPairs[$pair] + 1
    if ($crossSaid.Count -lt 12) {
        $crossSaid.Add(('{0}/{1} {2} is {3} and wants {4}, which a {5} has to be {6} to produce' -f `
                        $r.Owner, $r.Half, $r.OutName, $r.Rank, $worstName, $worstWho, $RANKS[$worst]))
    }
}
if ($crossRows -eq 0) {
    Ok 'no owned row is ranked below a class that produces something on its list'
} else {
    Note ("{0} owned row(s) are ranked below a class that produces something they ask for" -f $crossRows)
    foreach ($pair in ($crossPairs.Keys | Sort-Object { -$crossPairs[$_] })) {
        Note ("  {0,5}  {1}" -f $crossPairs[$pair], $pair)
    }
    foreach ($s in $crossSaid) { Note ("  " + $s) }
    if ($crossRows -gt $crossSaid.Count) {
        Note ("  ... and {0} more, every one of them in tools\recipes.json with the other producers on the input" -f ($crossRows - $crossSaid.Count))
    }
}

# ------------------------------------------------------------- the checks ---

Write-Host ''
Write-Host 'checks' -ForegroundColor Cyan

# THE RUNGS OF THE GATE, not of the table. The ranking above checks every owned
# row of a half, and a third of the Smith's rows are tempering the server is
# never asked about. tools\Check-Balance.ps1 counts the rows that FIRE, because
# those are the only ones a gate can refuse, so a half can pass the ranking and
# still fail there. Both subsets are checked here so that this script cannot
# write a table that the balance check then rejects.
foreach ($p in $PROFESSIONS.Keys) {
    foreach ($h in $PROFESSIONS[$p]) {
        $key = $p + '/' + $h
        $firing = New-Object 'System.Collections.Generic.List[string]'
        foreach ($desc in $owned.Keys) {
            if (-not $owned[$desc].Fires) { continue }
            if (($owned[$desc].Owner + '/' + $owned[$desc].Half) -ne $key) { continue }
            $firing.Add($desc)
        }
        if ($firing.Count -eq 0) { continue }
        $c = CountRungs $firing
        $hole = HoleIn $c
        if ($hole -ge 0) {
            Bad ("{0}: of the {1} row(s) the server is asked about, the {2} rung is empty and there is work above it, so reaching that rank opens nothing" -f `
                 $key, $firing.Count, $RANKS[$hole])
        }
        # And standable, on the same subset and for the same reason. The gate
        # only ever refuses a firing row, so this is the set a person actually
        # meets at a bench.
        if ($RUNGS_MUST_BE_STANDABLE) {
            foreach ($b in @(UnstandableRungs $firing)) {
                if ($HALVES_WITH_AN_UNSTANDABLE_RUNG.Contains($key)) { continue }
                Bad ("{0}: of the {1} row(s) the server is asked about, the {2} rung holds {3} and not one can be gathered for below {4}" -f `
                     $key, $firing.Count, $b.Rank, $b.Rows, $b.NeedAt)
            }
        }
    }
}
Ok 'no half has an empty rung with work above it, counting every owned row and counting only the rows the server is asked about'
if ($RUNGS_MUST_BE_STANDABLE) {
    if ($unstandable.Count -eq 0) {
        Ok 'every rung that holds work holds at least one row somebody at that rank could gather the makings for'
    } else {
        Note ("{0} half/halves hold a rung nobody at that rank can gather for, every one of them named in HALVES_WITH_AN_UNSTANDABLE_RUNG with the reason: {1}" -f `
              $unstandable.Count, (($unstandable.Keys) -join ', '))
    }
}

if ($unresolvedOut.Count -gt 0) {
    Bad ("{0} recipe(s) name an output that is not a record in this load order" -f $unresolvedOut.Count)
    foreach ($u in $unresolvedOut) { Note ("  " + $u) }
} else {
    Ok ("every one of the {0} recipes with an output resolves it to a real record" -f ($recipes.Count - $noOutput))
}

# A record with no FULL subrecord has no name to read, and the editor id is
# then the only thing there is to put in the table. That is a defect in the
# plugin rather than in this script, and it is named out loud rather than
# failed on, because refusing to write 5116 rows over one nameless cape would
# leave the server with no table at all. Every row carries nameFrom in the
# json, so a row named after its editor id can be found without rerunning this.
if ($namelessOut.Count -gt 0) {
    Loud ("{0} output record(s) carry no FULL, so their rows are named after the editor id:" -f $namelessOut.Count)
    foreach ($d in ($namelessOut.Keys | Sort-Object)) {
        Loud ("  {0} ({1}), wanted by: {2}" -f $items[$d].Edid, $d, (($namelessOut[$d] | Select-Object -First 4) -join ', '))
    }
} else {
    Ok 'every output in the table has a real name out of a string table or its own record'
}

# every desc is hex digits and a plugin, the same test the ore table makes
$oddIds = New-Object 'System.Collections.Generic.List[string]'
foreach ($desc in $owned.Keys) {
    if ($desc -cnotmatch '^[0-9a-f]{1,8}:[^:]+\.es[mpl]$') { $oddIds.Add("the recipe $desc") }
    if ($owned[$desc].OutDesc -cnotmatch '^[0-9a-f]{1,8}:[^:]+\.es[mpl]$') { $oddIds.Add("the output of $desc, " + $owned[$desc].OutDesc) }
}
if ($oddIds.Count -gt 0) {
    foreach ($o in $oddIds) { Bad ("an id that does not look right: {0}" -f $o) }
} else {
    Ok 'every desc is hex digits and a plugin'
}

# no recipe is listed twice. Every recipe is keyed by its desc and an override
# replaces the row rather than adding one, so a duplicate here would mean two
# different recipes came out with the same key, which would silently lose one.
$dupes = New-Object 'System.Collections.Generic.List[string]'
foreach ($desc in $owned.Keys) { if ($unowned.Contains($desc)) { $dupes.Add($desc) } }
if ($dupes.Count -gt 0) {
    foreach ($d in $dupes) { Bad ("{0} is in both the owned table and the unowned map" -f $d) }
} else {
    Ok ("no recipe is listed twice: {0} owned and {1} unowned, {2} in all, and every key is distinct" -f $owned.Count, $unowned.Count, ($owned.Count + $unowned.Count))
}
if ($seenTwice.Count -gt 0) {
    Note ("{0} recipe(s) are overridden by a later plugin and the later one is the one in the table" -f $seenTwice.Count)
}

# every owner is one of the eight professions and every half is one of its two
$badOwner = New-Object 'System.Collections.Generic.List[string]'
foreach ($desc in $owned.Keys) {
    $row = $owned[$desc]
    if (-not $PROFESSIONS.Contains($row.Owner)) {
        $badOwner.Add(("{0} is owned by '{1}', which is not a profession in classes.md" -f $desc, $row.Owner))
        continue
    }
    if ($PROFESSIONS[$row.Owner].Count -eq 0) {
        # The Mage is the only one of these. It is in the roster with no halves
        # because the panel needs the full eight, and a recipe landing on it
        # means a rule above sent a crafting row to a profession that does not
        # craft. What a mage knows belongs in tools\Build-SpellTable.ps1.
        $badOwner.Add(("{0} is owned by {1}, which has no halves and makes nothing by recipe. {2}" -f $desc, $row.Owner, $PROFESSION_CRAFTS[$row.Owner].Why))
        continue
    }
    if (-not ($PROFESSIONS[$row.Owner] -contains $row.Half)) {
        $badOwner.Add(("{0} is {1}/{2} and '{2}' is not one of {1}'s two halves" -f $desc, $row.Owner, $row.Half))
    }
}
if ($badOwner.Count -gt 0) {
    foreach ($b in $badOwner) { Bad $b }
} else {
    Ok 'every owner is one of the professions in classes.md and every half is one of its two'
}

# ------------------------------------------------------------- the counts ---

Write-Host ''
Write-Host 'what each half ends up with' -ForegroundColor Cyan

$perHalf  = @{}
$perHalfFiring = @{}
$perHalfDayOne = @{}
$perHalfPerk   = @{}
foreach ($p in $PROFESSIONS.Keys) {
    foreach ($h in $PROFESSIONS[$p]) {
        $perHalf[$p + '/' + $h] = 0
        $perHalfFiring[$p + '/' + $h] = 0
        $perHalfDayOne[$p + '/' + $h] = 0
        $perHalfPerk[$p + '/' + $h] = 0
    }
}
foreach ($desc in $owned.Keys) {
    $row = $owned[$desc]
    $key = $row.Owner + '/' + $row.Half
    if (-not $perHalf.ContainsKey($key)) {
        $perHalf[$key] = 0; $perHalfFiring[$key] = 0; $perHalfDayOne[$key] = 0; $perHalfPerk[$key] = 0
    }
    $perHalf[$key] = $perHalf[$key] + 1
    if ($row.Fires) {
        $perHalfFiring[$key] = $perHalfFiring[$key] + 1
        if ($row.DayOne) { $perHalfDayOne[$key] = $perHalfDayOne[$key] + 1 }
        if ($row.BehindVanillaPerk) { $perHalfPerk[$key] = $perHalfPerk[$key] + 1 }
    }
}

# Four numbers, not two, and the last two are the ones that were missing.
# 'asked' counts the rows that reach onCraft at all. 'open today' counts the
# rows a character created this morning can make: no condition of any kind, so
# nothing has to be found, learnt or earned first. 'behind a perk' counts the
# rows gated on a vanilla perk, which classes.md says nobody on this server
# will ever hold.
Write-Host ("  {0,-12} {1,-14} {2,8} {3,8} {4,10} {5,14}" -f 'profession', 'half', 'recipes', 'asked', 'open today', 'behind a perk')
foreach ($p in $PROFESSIONS.Keys) {
    $total = 0
    foreach ($h in $PROFESSIONS[$p]) { $total += $perHalf[$p + '/' + $h] }
    foreach ($h in $PROFESSIONS[$p]) {
        $key = $p + '/' + $h
        Write-Host ("  {0,-12} {1,-14} {2,8} {3,8} {4,10} {5,14}" -f $p, $h, $perHalf[$key], $perHalfFiring[$key], $perHalfDayOne[$key], $perHalfPerk[$key])
    }
    if ($PROFESSIONS[$p].Count -eq 0) {
        Write-Host ("  {0,-12} {1,-14} {2,8} {3,8} {4,10} {5,14}" -f $p, '(no halves)', 0, 0, 0, 0)
        Note ("{0}: {1}" -f $p, $PROFESSION_CRAFTS[$p].Why)
    } else {
        Note ("{0}: {1} in all" -f $p, $total)
    }
}
Note ("unowned: {0}, and unowned means anybody may make it" -f $unowned.Count)

# The check this whole file exists for. A half that can make nothing is a half
# nobody should be allowed to pick, and the two times this repo got that wrong
# it was found by somebody playing rather than by a build.
$emptyUnexpected = New-Object 'System.Collections.Generic.List[string]'
$filledUnexpected = New-Object 'System.Collections.Generic.List[string]'
foreach ($p in $PROFESSIONS.Keys) {
    foreach ($h in $PROFESSIONS[$p]) {
        $key = $p + '/' + $h
        $expectedEmpty = $HALVES_WITH_NO_RECIPES.Contains($key)
        if ($perHalf[$key] -eq 0 -and -not $expectedEmpty) { $emptyUnexpected.Add($key) }
        if ($perHalf[$key] -gt 0 -and $expectedEmpty) { $filledUnexpected.Add($key) }
    }
}
Write-Host ''
if ($emptyUnexpected.Count -gt 0) {
    foreach ($k in $emptyUnexpected) {
        Bad ("{0} owns no recipes at all. A half that can make nothing is a half nobody should be allowed to pick. Either the rule above is wrong or that half has nothing behind it, and both of those need a person." -f $k)
    }
} else {
    Ok 'every half that is meant to have recipes has some'
}
if ($filledUnexpected.Count -gt 0) {
    foreach ($k in $filledUnexpected) {
        Bad ("{0} is named in HALVES_WITH_NO_RECIPES as having nothing, and it has {1} recipe(s). That knob is out of date and the reason written in it is no longer true." -f $k, $perHalf[$k])
    }
}
foreach ($k in $HALVES_WITH_NO_RECIPES.Keys) {
    Loud ("{0} owns nothing: {1}" -f $k, $HALVES_WITH_NO_RECIPES[$k].Why)
}
Loud 'those halves go into recipes.json under "halves", each with a craftsAtAll flag. Every one of them is still offered in character creation: a half nobody may pick is a profession nobody may pick.'

# THE CHECK THAT OWNING RECIPES IS NOT THE SAME AS BEING ABLE TO WORK.
#
# A half can own hundreds of rows and have nothing anybody can make on the day
# they pick it. Three halves in this build are exactly that, and every one of
# them passed the check above, because the check above counts rows rather than
# rows a person can reach.
$noStart = New-Object 'System.Collections.Generic.List[string]'
$startsFine = New-Object 'System.Collections.Generic.List[string]'
foreach ($p in $PROFESSIONS.Keys) {
    foreach ($h in $PROFESSIONS[$p]) {
        $key = $p + '/' + $h
        if ($perHalfFiring[$key] -eq 0) { continue }
        $named = $HALVES_NOBODY_CAN_START.Contains($key)
        if ($perHalfDayOne[$key] -eq 0 -and -not $named) { $noStart.Add($key) }
        if ($perHalfDayOne[$key] -gt 0 -and $named) { $startsFine.Add($key) }
        if ($perHalfDayOne[$key] -eq 0) {
            # What that half's rows are actually waiting on, counted, so the
            # reason in the knob can be written from the build rather than
            # from somebody's recollection of it.
            $asks = @{}
            foreach ($desc in $owned.Keys) {
                $row = $owned[$desc]
                if (-not $row.Fires) { continue }
                if (($row.Owner + '/' + $row.Half) -ne $key) { continue }
                $seenHere = @{}
                foreach ($nd in $row.Needs) {
                    if ($seenHere.ContainsKey($nd.Name)) { continue }
                    $seenHere[$nd.Name] = $true
                    if (-not $asks.ContainsKey($nd.Name)) { $asks[$nd.Name] = 0 }
                    $asks[$nd.Name] = $asks[$nd.Name] + 1
                }
            }
            $bits = @()
            foreach ($a in ($asks.Keys | Sort-Object { -$asks[$_] })) { $bits += ($asks[$a].ToString() + ' x ' + $a) }
            Note ("{0}: all {1} row(s) the server is asked about are behind something. {2}" -f $key, $perHalfFiring[$key], ($bits -join ', '))
        }
        elseif ($perHalfDayOne[$key] -le $THIN_HALF_ROWS -and $perHalfFiring[$key] -gt $perHalfDayOne[$key]) {
            # A half with almost nothing to start on. Printed row by row,
            # because "4 recipes" and "1 recipe and three behind a book" are
            # the same number in a table and not the same trade.
            Loud ("{0} has {1} of {2} row(s) a new character can make. The rest:" -f $key, $perHalfDayOne[$key], $perHalfFiring[$key])
            $shown = 0
            $held = 0
            foreach ($desc in $owned.Keys) {
                $row = $owned[$desc]
                if (-not $row.Fires) { continue }
                if (($row.Owner + '/' + $row.Half) -ne $key) { continue }
                if ($row.DayOne) { continue }
                $held++
                if ($shown -ge $THIN_HALF_LINES) { continue }
                $shown++
                $what = @()
                foreach ($nd in $row.Needs) { $what += $nd.Text }
                Loud ("  {0} makes {1} and wants {2}" -f $row.Edid, $row.OutName, ($what -join ' and '))
            }
            if ($held -gt $shown) { Loud ("  and {0} more, all of them in recipes.json with what each one wants" -f ($held - $shown)) }
        }
    }
}
if ($noStart.Count -gt 0) {
    foreach ($k in $noStart) {
        Bad ("{0} owns {1} recipe(s) the server is asked about and not one of them can be made by somebody who picked that half this morning: every one is behind a condition. That is a half that looks like work and is not. Either a rule above is wrong or somebody has to decide what a new one of these starts with." -f $k, $perHalfFiring[$k])
    }
} else {
    Ok 'every half with recipes has at least one a new character can make, or is named in HALVES_NOBODY_CAN_START with the reason'
}
if ($startsFine.Count -gt 0) {
    foreach ($k in $startsFine) {
        Bad ("{0} is named in HALVES_NOBODY_CAN_START and it has {1} recipe(s) a new character can make. That knob is out of date." -f $k, $perHalfDayOne[$k])
    }
}
foreach ($k in $HALVES_NOBODY_CAN_START.Keys) {
    Loud ("{0} has nothing a new character can make: {1}" -f $k, $HALVES_NOBODY_CAN_START[$k])
}

# the unowned map, by reason, because there are too many to print one at a time
Write-Host ''
Write-Host 'why the unowned recipes are unowned' -ForegroundColor Cyan
$byWhy = @{}
foreach ($desc in $unowned.Keys) {
    $w = $unowned[$desc].Why
    if (-not $byWhy.ContainsKey($w)) { $byWhy[$w] = 0 }
    $byWhy[$w] = $byWhy[$w] + 1
}
foreach ($w in ($byWhy.Keys | Sort-Object { -$byWhy[$_] })) {
    Write-Host ("  {0,6}  {1}" -f $byWhy[$w], $w)
}

Write-Host ''
Write-Host 'the output record types a recipe in this build names' -ForegroundColor Cyan
foreach ($t in ($outTypeCount.Keys | Sort-Object { -$outTypeCount[$_] })) {
    Note ("{0}: {1}" -f $t, $outTypeCount[$t])
}

# ------------------------------------------------------------- the writing -

Write-Host ''
Write-Host 'writing' -ForegroundColor Cyan

$after = Get-FolderPrint $Data
if ($after.Hash -ne $before.Hash -or $after.Count -ne $before.Count) {
    Bad ("the game folder changed while this ran: {0} files and {1} before, {2} and {3} after" -f `
         $before.Count, $before.Hash.Substring(0, 16), $after.Count, $after.Hash.Substring(0, 16))
} else {
    Ok ("the game folder is exactly as it was: {0} files, {1}" -f $after.Count, $after.Hash.Substring(0, 16))
}

# The json is written out by hand rather than with ConvertTo-Json, and there is
# no timestamp in it, so that the same game files give byte for byte the same
# file: ConvertTo-Json lays out Windows PowerShell 5.1 and PowerShell 7
# differently, and a rebuild that changed nothing would be a whole-file diff.
$doc = New-Object 'System.Collections.Generic.List[string]'
$doc.Add('{')
$doc.Add('  "builtBy": ' + (JsonStr 'tools\Build-RecipeTable.ps1') + ',')
$doc.Add('  "source": ' + (JsonStr ('every COBJ record across ' + $order.Count + ' plugins in load order, and the records their CNAM and BNAM point at')) + ',')
$doc.Add('  "language": ' + (JsonStr $LANGUAGE) + ',')
$doc.Add('  "readFrom": ' + (JsonStr 'BNAM is the workbench keyword, CNAM is the output item, NAM1 is how many it makes, COCT and CNTO are the inputs, CTDA is the conditions, which are in every row''s needs list') + ',')
$doc.Add('  "event": ' + (JsonStr 'mp.onCraft(actorFormId, craftedItemBaseId, count, recipeId). All four arguments are numbers. The keys of this table are desc strings, so look a row up with RECIPES_BY_ID[mp.getDescFromId(recipeId)] and never with recipeId itself, which matches nothing. Returning false refuses the craft outright: CraftEvent::OnFireSuccess is what removes the inputs and adds the output, and GameModeEvent::Fire only calls it when nobody blocked.') + ',')
$doc.Add('  "key": ' + (JsonStr 'the recipe''s form id in lower case hex, a colon, and the file it belongs to. mp.getDescFromId turns onCraft''s fourth argument into one.') + ',')
$doc.Add('  "rank": ' + (JsonStr 'which of classes.md''s four ranks the row asks for: novice, advanced, expert or master. Ranked by WHAT ITS INPUTS COST A PRODUCER, taking the dearest thing it asks for, because that is the rung somebody has to have reached before they could gather the makings at all. Where part of the list is produced by nobody, that dearest placed input is a FLOOR and not the answer: it can raise the row above what the output sells for and never lower it, because an item nothing produces is an unknown cost rather than a free one. A row whose inputs no class produces at all falls back to what the output sells for, ranked inside its own half. rankFrom says which of the three answered. classes.md sets no numbers for any of this and nothing in the game records ranks a recipe, so every judgement is a knob at the top of the script: RANK_FROM_INPUT_COST, PRODUCER_TABLES, SERVER_PRODUCERS, PRODUCER_RANK_IS_LOWEST, INPUT_RANK_IS_THE_DEAREST, UNPLACED_INPUT_RULE, RANK_SHARE and SECOND_RULE_KEY.') + ',')
$doc.Add('  "inputItems": ' + (JsonStr 'every CNTO the record carried: what the recipe wants, how many, and which class produces that item at which rank. producedBy is the class that gets it at the LOWEST rank, because that is what the thing costs to get hold of; alsoProducedBy, where it is present, is every class that has to climb higher for the same item, which is where the farmer appears, since all 11 crops are also plants a gatherer picks at the same rank or lower. producedBy null means nothing in this repository hands that item over: no table in this folder and no verb in tools\gamemode.js. Read out of the recipe''s own CNTO subrecords, eight bytes each, a form id then a count.') + ',')
$doc.Add('  "inputsWithNoProducer": ' + (JsonStr 'how many of the row''s inputs nothing in this repository produces. Read it with inputRank: "the dearest input is novice" means one thing on a row where that is the whole list and another on a row with four unknowns beside it, and not reading it is how a 3100 gold dragonbone plate went out at novice on 21 September off one novice hunter''s fox pelt.') + ',')
$doc.Add('  "rankFrom": ' + (JsonStr 'which rule gave this row its rank: what its inputs cost a producer, what it sells for, or the second rule named in SECOND_RULE_KEY. The second rule is used for one half at a time and only where the first two leave a rung with nothing on it, and every use of it is printed by name when the table is built.') + ',')
$doc.Add('  "rankByValue": ' + (JsonStr 'what the old rule would have said: the rank this row got from the price of what it makes, inside its own half. Kept on every row so the two answers can be compared rather than one of them quietly replacing the other.') + ',')
$doc.Add('  "inputRank": ' + (JsonStr 'the rank of the dearest input this row asks for, and inputRankWho is the class that produces it. Null when nothing it asks for is produced by any class.') + ',')
$doc.Add('  "crossTier": ' + (JsonStr 'tools\Check-Balance.ps1 reads inputRank against rank and reports every half by how far its recipes sit from what their inputs cost, and reads alsoProducedBy to report every row ranked below a class that has to climb higher for something on its list. That is the imbalance Patrick asked about on 21 September, stated as a number. Both scripts print it; neither fails on it, because which of the two ladders should move is a decision.') + ',')
$doc.Add('  "rungsNobodyCanGatherFor": ' + (JsonStr 'on a half: a rung that holds recipes and not one of them can be gathered for at that rank, which is an empty rung wearing a label and is what the second rule can leave behind. Build-RecipeTable.ps1 fails the build for any half that has one and is not named in its HALVES_WITH_AN_UNSTANDABLE_RUNG knob with the measured reason, so a half carrying this field is one somebody decided to live with and wrote down.') + ',')
$doc.Add('  "rankedByInputCost": ' + (JsonStr 'on each half: how many of its rows the input cost rule could answer for and how many fell back to price, counted BEFORE any second rule ran. Where the half also carries a secondRule field, that rule then re-ranked every row of it, so read rankFrom on the row for what actually decided it.') + ',')
$doc.Add('  "sisterHalf": ' + (JsonStr 'classes.md gives you the novice work of the other half of your own profession for nothing, and no further than novice. The gate can answer that because every row carries a rank.') + ',')
$doc.Add('  "needs": ' + (JsonStr 'the recipe''s own conditions, read out of its CTDA subrecords. An empty list means anybody standing at the bench can make it. serverSees false means the fork has no function for that condition and the server answers True, so the only thing enforcing it is the crafting menu on the machine in front of the person, which hides the recipe rather than refusing it.') + ',')
$doc.Add('  "default": ' + (JsonStr 'a recipe id this table does not carry is one nobody owns, and anybody may make it') + ',')
$doc.Add('  "fires": ' + (JsonStr 'false means the server is never asked about this recipe. CraftService::RecipeItemsMatch throws out the armour table (adb78) and the sharpening wheel (88108) before it considers anything, so tempering never reaches onCraft.') + ',')
$doc.Add('  "count": ' + ($owned.Count + $unowned.Count) + ',')
$doc.Add('  "owned": ' + $owned.Count + ',')
$doc.Add('  "unownedCount": ' + $unowned.Count + ',')

# Items a recipe asks for that nothing in the load order hands out. A recipe
# behind one of these is not gated, it is dead, and it is written down here so
# that the next person does not have to run this script to find out.
$doc.Add('  "itemsNothingHandsOut": {')
$on = 0
$orphanKeys = @()
foreach ($d in $wantedItems.Keys) { if (-not $wantedItems[$d].Found) { $orphanKeys += $d } }
foreach ($d in $orphanKeys) {
    $on++
    $comma = ','
    if ($on -eq $orphanKeys.Count) { $comma = '' }
    $w = $wantedItems[$d]
    $who = @()
    foreach ($x in $w.Wanters) { $who += (JsonStr $x) }
    $doc.Add('    ' + (JsonStr $d) + ': { "editorId": ' + (JsonStr $w.Edid) + ', "type": ' + (JsonStr $w.Type) +
             ', "recipesThatWantIt": [' + ($who -join ', ') + ']' +
             ', "searched": ' + (JsonStr 'every plugin in the load order, for a placed reference, a container or character inventory line, and a levelled list line. A record stored compressed, a Papyrus script or a quest alias would not be found by that search.') + ' }' + $comma)
}
$doc.Add('  },')

# The roster, and it is the whole roster. All eight professions of classes.md,
# the Mage among them with no halves, because this map is the only list of
# professions the file ships and a panel built from a list of seven would offer
# seven. offerInCharacterCreation is true on every one of them: nothing here is
# a reason to take a profession off the character creation panel.
$doc.Add('  "professions": {')
$pn = 0
foreach ($p in $PROFESSIONS.Keys) {
    $pn++
    $comma = ','
    if ($pn -eq $PROFESSIONS.Count) { $comma = '' }
    $halves = @()
    foreach ($h in $PROFESSIONS[$p]) { $halves += (JsonStr $h) }
    $halvesTxt = 'null'
    if ($halves.Count -gt 0) { $halvesTxt = '[' + ($halves -join ', ') + ']' }
    $craftsTxt = 'false'
    if ($PROFESSION_CRAFTS[$p].Crafts) { $craftsTxt = 'true' }
    $line = '    ' + (JsonStr $p) + ': { "halves": ' + $halvesTxt +
            ', "craftsAtAll": ' + $craftsTxt +
            ', "offerInCharacterCreation": true'
    if ($PROFESSION_CRAFTS[$p].Why) { $line += ', "why": ' + (JsonStr $PROFESSION_CRAFTS[$p].Why) }
    $doc.Add($line + ' }' + $comma)
}
$doc.Add('  },')

# One entry per half, with what it owns, what the server is asked about, what a
# character created this morning can actually make, and how those rows split
# across the four ranks. The counts and the cannotCraftYet map used to be two
# separate fields and neither could tell "this half does not craft" from "this
# half is broken", which is how a reader of the old field would have taken the
# Warrior out of character creation.
$doc.Add('  "halves": {')
$cn = 0
$keys = @()
foreach ($p in $PROFESSIONS.Keys) { foreach ($h in $PROFESSIONS[$p]) { $keys += ($p + '/' + $h) } }
foreach ($k in $keys) {
    $cn++
    $comma = ','
    if ($cn -eq $keys.Count) { $comma = '' }
    $prof = $k.Split('/')[0]
    $craftsTxt = 'true'
    $why = ''
    if ($HALVES_WITH_NO_RECIPES.Contains($k)) {
        $why = $HALVES_WITH_NO_RECIPES[$k].Why
        if (-not $HALVES_WITH_NO_RECIPES[$k].Crafts) { $craftsTxt = 'false' }
    } elseif (-not $PROFESSION_CRAFTS[$prof].Crafts) {
        $craftsTxt = 'false'
        $why = $PROFESSION_CRAFTS[$prof].Why
    }
    $byRank = '{}'
    if ($rankRows.ContainsKey($k)) {
        $bits = @()
        foreach ($rk in $RANKS) { $bits += ((JsonStr $rk) + ': ' + $rankRows[$k][$rk]) }
        $byRank = '{ ' + ($bits -join ', ') + ' }'
    }
    $line = '    ' + (JsonStr $k) + ': { "recipes": ' + $perHalf[$k] +
            ', "theServerIsAsked": ' + $perHalfFiring[$k] +
            ', "canBeMadeOnDayOne": ' + $perHalfDayOne[$k] +
            ', "behindAVanillaPerk": ' + $perHalfPerk[$k] +
            ', "byRank": ' + $byRank +
            ', "rankedByInputCost": ' + $(if ($rankedByInputs.ContainsKey($k)) { $rankedByInputs[$k] } else { 0 }) +
            ', "rankedByPrice": ' + $(if ($rankedByValue.ContainsKey($k)) { $rankedByValue[$k] } else { 0 }) +
            ', "craftsAtAll": ' + $craftsTxt +
            ', "offerInCharacterCreation": true'
    if ($secondRuleUsed.Contains($k)) { $line += ', "secondRule": ' + (JsonStr $secondRuleUsed[$k]) }
    if ($unstandable.Contains($k)) {
        $line += ', "rungsNobodyCanGatherFor": ' + (JsonStr $unstandable[$k])
        if ($HALVES_WITH_AN_UNSTANDABLE_RUNG.Contains($k)) {
            $line += ', "andThatIsAllowedBecause": ' + (JsonStr $HALVES_WITH_AN_UNSTANDABLE_RUNG[$k])
        }
    }
    if ($why) { $line += ', "why": ' + (JsonStr $why) }
    if ($HALVES_NOBODY_CAN_START.Contains($k)) {
        $line += ', "nothingToMakeOnDayOne": ' + (JsonStr $HALVES_NOBODY_CAN_START[$k])
    }
    $doc.Add($line + ' }' + $comma)
}
$doc.Add('  },')

$doc.Add('  "recipes": {')
$n = 0
foreach ($desc in $owned.Keys) {
    $n++
    $comma = ','
    if ($n -eq $owned.Count) { $comma = '' }
    $r = $owned[$desc]
    $firesTxt = 'false'
    if ($r.Fires) { $firesTxt = 'true' }
    $dayOneTxt = 'false'
    if ($r.DayOne) { $dayOneTxt = 'true' }
    $needsTxt = '[]'
    if ($r.Needs.Count -gt 0) {
        $bits = @()
        foreach ($nd in $r.Needs) {
            $sees = 'false'
            if ($nd.ServerSees) { $sees = 'true' }
            $bits += ('{ "asks": ' + (JsonStr $nd.Text) + ', "function": ' + $nd.Func +
                      ', "of": ' + (JsonStr $nd.Param) + ', "ofType": ' + (JsonStr $nd.ParamType) +
                      ', "serverSees": ' + $sees + ' }')
        }
        $needsTxt = '[' + ($bits -join ', ') + ']'
    }
    $doc.Add('    ' + (JsonStr $desc) + ': { "editorId": ' + (JsonStr $r.Edid) +
             ', "out": ' + (JsonStr $r.OutDesc) + ', "name": ' + (JsonStr $r.OutName) +
             ', "type": ' + (JsonStr $r.OutType) + ', "makes": ' + $r.Count +
             ', "inputs": ' + $r.Inputs + ', "inputItems": ' + (InputsJson $r) + ', "worth": ' + $r.Value +
             ', "bench": ' + (JsonStr $r.BenchDesc) + ', "benchName": ' + (JsonStr $r.BenchName) +
             ', "owner": ' + (JsonStr $r.Owner) + ', "half": ' + (JsonStr $r.Half) +
             ', "rank": ' + (JsonStr $r.Rank) +
             ', "fires": ' + $firesTxt + ', "canBeMadeOnDayOne": ' + $dayOneTxt +
             ', "needs": ' + $needsTxt +
             ', "plugin": ' + (JsonStr $r.Plugin) +
             ', "nameFrom": ' + (JsonStr $r.NameFrom) +
             ', "why": ' + (JsonStr $r.Reason) +
             ', "rankFrom": ' + (JsonStr $r.RankFrom) +
             ', "rankByValue": ' + (JsonStr $r.RankByValue) +
             ', "inputRank": ' + $(if ($r.InputRank) { JsonStr $r.InputRank } else { 'null' }) +
             ', "inputRankWho": ' + $(if ($r.InputRankWho) { JsonStr $r.InputRankWho } else { 'null' }) +
             ', "inputsWithNoProducer": ' + $r.InputsUnplaced +
             ', "whyThatRank": ' + (JsonStr $r.RankWhy) + ' }' + $comma)
}
$doc.Add('  },')

$doc.Add('  "unowned": {')
$n = 0
foreach ($desc in $unowned.Keys) {
    $n++
    $comma = ','
    if ($n -eq $unowned.Count) { $comma = '' }
    $u = $unowned[$desc]
    $doc.Add('    ' + (JsonStr $desc) + ': { "editorId": ' + (JsonStr $u.Edid) +
             ', "out": ' + (JsonStr $u.OutDesc) + ', "name": ' + (JsonStr $u.OutName) +
             ', "type": ' + (JsonStr $u.OutType) + ', "benchName": ' + (JsonStr $u.BenchName) +
             ', "why": ' + (JsonStr $u.Why) + ' }' + $comma)
}
$doc.Add('  }')
$doc.Add('}')
$json = ($doc -join "`r`n") + "`r`n"

# A run that failed leaves the table it could not rebuild exactly as it was.
# Nothing is written until every check above has passed, for the same reason the
# spell table does it: a bad -Data left that one 240 bytes of nothing.
if ($fail -gt 0) {
    Bad ("{0} check(s) failed, so {1} was left exactly as it was" -f $fail, $Out)
} else {
    [System.IO.File]::WriteAllText($Out, $json, (New-Object System.Text.UTF8Encoding($false)))
    Ok ("wrote {0} ({1} owned, {2} unowned, {3} bytes)" -f $Out, $owned.Count, $unowned.Count, $json.Length)
}

# ----------------------------------------------------------- the literal ---
#
# Only the rows the server is actually asked about go in the block. A tempering
# recipe never reaches onCraft, and an unowned recipe is one anybody may make,
# so neither changes an answer. Leaving them out keeps a file that ships as one
# piece down to the rows that decide something.
$blockRows = New-Object 'System.Collections.Generic.List[string]'
foreach ($desc in $owned.Keys) {
    if (-not $owned[$desc].Fires) { continue }
    $r = $owned[$desc]
    $dayOneTxt = 'false'
    if ($r.DayOne) { $dayOneTxt = 'true' }
    $blockRows.Add('    ' + (JsonStr $desc) + ': { "out": ' + (JsonStr $r.OutDesc) + ', "name": ' + (JsonStr $r.OutName) +
                   ', "type": ' + (JsonStr $r.OutType) + ', "makes": ' + $r.Count +
                   ', "owner": ' + (JsonStr $r.Owner) + ', "half": ' + (JsonStr $r.Half) +
                   ', "rank": ' + (JsonStr $r.Rank) + ', "open": ' + $dayOneTxt + ' },')
}
if ($blockRows.Count -gt 0) {
    $last = $blockRows[$blockRows.Count - 1]
    $blockRows[$blockRows.Count - 1] = $last.Substring(0, $last.Length - 1)
}

# Which rule decided the rank of the rows that actually ship in the block. The
# generated comment states it as a count rather than as a claim, because the
# hand written paragraph it replaces went on describing the price rule for a
# day after the price rule had stopped being the rule.
$ruleInput = 0
$rulePrice = 0
$ruleSecond = 0
foreach ($desc in $owned.Keys) {
    if (-not $owned[$desc].Fires) { continue }
    $rf = [string]$owned[$desc].RankFrom
    if ($rf.StartsWith('the second rule')) { $ruleSecond++ }
    elseif ($rf.StartsWith('what its inputs cost')) { $ruleInput++ }
    else { $rulePrice++ }
}
$secondRuleHalves = @($secondRuleUsed.Keys)

$lines = New-Object 'System.Collections.Generic.List[string]'
$lines.Add('  /* Built by tools\Build-RecipeTable.ps1 out of the game''s own records. Do not hand edit.')
$lines.Add('     ' + $blockRows.Count + ' crafting recipes, out of ' + ($owned.Count + $unowned.Count) + ' in tools\recipes.json.')
$lines.Add('')
$lines.Add('     Recipe desc -> what it makes, what kind of record that is, how many it')
$lines.Add('     makes, which profession and which half of it owns the recipe, and which')
$lines.Add('     of classes.md''s four ranks it asks for. Returning false from onCraft')
$lines.Add('     refuses the craft and the person keeps their materials.')
$lines.Add('')
$lines.Add('     THE KEY IS A DESC AND onCraft HANDS YOU A NUMBER. All four arguments of')
$lines.Add('     mp.onCraft(actorFormId, craftedItemBaseId, count, recipeId) are numbers,')
$lines.Add('     and every key in here is a string like "f61:Skyrim.esm". So:')
$lines.Add('')
$lines.Add('         var row = RECIPES_BY_ID[mp.getDescFromId(recipeId)];')
$lines.Add('')
$lines.Add('     RECIPES_BY_ID[recipeId] is undefined for every row in this block, which')
$lines.Add('     is a gate that refuses nothing and says nothing while it does it.')
$lines.Add('')
$lines.Add('     rank is what to compare the character''s rank in that half against.')
$lines.Add('     classes.md also gives somebody the novice work of the other half of')
$lines.Add('     their own profession and no further, so a row whose half is the sister')
$lines.Add('     half passes at rank novice and nowhere above it.')
$lines.Add('')
$lines.Add('     WHAT SETS THAT RANK IS WHAT THE RECIPE COSTS THE PERSON WHO GATHERS FOR')
$lines.Add('     IT, and not what it sells for. The rank is the rank of the dearest thing')
$lines.Add('     on its list, at the rung the class that produces that thing has to have')
$lines.Add('     reached. Where part of the list is produced by nobody, that is a floor')
$lines.Add('     and what the output sells for can hold the row higher; where none of it')
$lines.Add('     is, the price ranks it inside its own half. On this build that is')
$lines.Add('     ' + $ruleInput + ' row(s) by what their inputs cost, ' + $rulePrice + ' by price and ' + $ruleSecond + ' by how long')
$lines.Add('     the shopping list is. That last rule is used for a whole half at a time')
if ($secondRuleHalves.Count -gt 0) {
    $lines.Add('     and only where the first two leave a rung with nothing on it, which here')
    $lines.Add('     is ' + ($secondRuleHalves -join ', ') + '. A rank there means how long the list is and')
    $lines.Add('     nothing else, and the half says so in tools\recipes.json.')
} else {
    $lines.Add('     and only where the first two leave a rung with nothing on it, which no')
    $lines.Add('     half in this build did.')
}
$lines.Add('     Every row carries rankFrom in tools\recipes.json saying which of the')
$lines.Add('     three answered for it. Nothing in here is the script''s opinion of what a')
$lines.Add('     thing is worth: classes.md sets no numbers for any of it, and every')
$lines.Add('     judgement is a named knob at the top of the script that wrote this.')
$lines.Add('')
$lines.Add('     open is true when the recipe carries no condition of its own. A row')
$lines.Add('     with open false needs something first, an item, a spell or a vanilla')
$lines.Add('     perk nobody here can hold, and Skyrim''s own crafting menu decides that')
$lines.Add('     before the server is ever asked. tools\recipes.json says which.')
$lines.Add('')
$lines.Add('     A recipe id that is not in here is one nobody owns and anybody may')
$lines.Add('     make. Tempering is not in here either: the server is never asked about')
$lines.Add('     it, because CraftService throws the armour table and the sharpening')
$lines.Add('     wheel out before it looks at a recipe. tools\recipes.json carries')
$lines.Add('     every row, owned and unowned, with the reason for each. */')
$lines.Add('  var RECIPES_BY_ID = {')
foreach ($row in $blockRows) { $lines.Add($row) }
$lines.Add('  };')
$literal = $lines -join [Environment]::NewLine

# ---------------------------------------------------------------- install --
#
# The gamemode carries the table, because the server is deployed as one file and
# cannot read tools\recipes.json. Nothing hand edits that block: this writes it
# between its own markers, the way the ore table does. -NoInstall prints it and
# leaves the file alone, and so does a gamemode.js that has no markers yet: this
# never invents a place to put it.
#
# THE COMMENT OVER THE TABLE IS PART OF THE TABLE, and it was not until
# 21 September. The opening marker used to be the var line itself, so the
# paragraph above it describing what every field means was hand written and was
# never regenerated. It went on saying that rank came from the price of what a
# recipe makes for a full day after input cost had replaced that rule and had
# changed 344 of the 1728 installed rows. The only statement in the repository
# of what the field the gate reads MEANS was contradicting the data beside it,
# in the file that ships to the server. So the marker moved up above the
# generated comment, and the script now owns the sentence as well as the rows.
# Whatever prose is still hand written sits above the opening marker, where it
# is about the block rather than about the fields.
if (-not $NoInstall -and $fail -eq 0) {
    $gm = Join-Path $PSScriptRoot 'gamemode.js'
    $open  = '  // ==== RECIPES_BY_ID ===='
    $close = '  // ==== end RECIPES_BY_ID ===='
    if (-not (Test-Path -LiteralPath $gm)) {
        Note "no gamemode.js beside this script, so the table was not installed"
    } else {
        $text = [System.IO.File]::ReadAllText($gm)
        $a = $text.IndexOf($open)
        $b = $text.IndexOf($close)
        if ($a -lt 0 -or $b -lt 0 -or $b -lt $a) {
            Note ("there is no RECIPES_BY_ID block in {0} yet, so nothing was written into it." -f $gm)
            Note ("  When the gamemode grows one, it is these two lines, and this fills between them:")
            Note ("    {0}" -f $open)
            Note ("    {0}" -f $close)
        } else {
            $body = New-Object 'System.Collections.Generic.List[string]'
            $body.Add($open)
            foreach ($l in $lines) { $body.Add($l) }
            $body.Add('')
            $new = $text.Substring(0, $a) + (($body -join "`r`n")) + "`r`n" + $text.Substring($b)
            [System.IO.File]::WriteAllText($gm, $new, (New-Object System.Text.UTF8Encoding($false)))
            Ok ("wrote {0} recipes and the comment over them into the RECIPES_BY_ID block of {1}" -f $blockRows.Count, $gm)
        }
    }
}

Write-Host ''
Write-Host ("the block, ready to install: {0} recipes, {1} lines" -f $blockRows.Count, $lines.Count) -ForegroundColor Cyan
$head = [Math]::Min($lines.Count, 24)
for ($z = 0; $z -lt $head; $z++) { Write-Host $lines[$z] }
if ($lines.Count -gt $head) { Note ("... and {0} more lines. -JsOut writes the whole block to a file." -f ($lines.Count - $head)) }
if ($JsOut) {
    [System.IO.File]::WriteAllText($JsOut, $literal, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ''
    Ok "wrote $JsOut"
}

Write-Host ''
if ($fail) {
    Write-Host "$fail check(s) failed. Read those before the table ships." -ForegroundColor Red
    exit 1
}
Write-Host ("the table is complete: {0} recipes, {1} of them owned by a half of a profession, {2} the server is asked about." -f ($owned.Count + $unowned.Count), $owned.Count, $blockRows.Count) -ForegroundColor Green
