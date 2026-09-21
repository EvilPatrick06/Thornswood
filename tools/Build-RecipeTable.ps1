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
  recipeId is the COBJ's own form id, mapped to the combined load order. That
  is the key this table is written under.

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

    CTDA is 32 bytes and is the condition list. It is read here only to be
    stepped over. The server evaluates conditions itself in
    CraftService::EvaluateCraftRecipeConditions, so this table does not.

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
  of the Enchanter. Those halves are named in EMPTY_HALVES_EXPECTED below, with
  the reason, and they are written into the json under cannotCraftYet so that
  the panel on K can refuse to offer a half that can make nothing. Every other
  half must come out with recipes or this build fails.

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
  recipe is invented for them and they are named in the exempt knob.

  Read only. It touches nothing in the game folder and nothing on the VPS, and
  it proves that with a fingerprint of the folder before and after.

  Usage:
    .\tools\Build-RecipeTable.ps1
    .\tools\Build-RecipeTable.ps1 -Data 'C:\Thornswood\Game\Data'
    .\tools\Build-RecipeTable.ps1 -NoInstall
    .\tools\Build-RecipeTable.ps1 -JsOut "$env:TEMP\recipes.js"

  Exit code 1 if a recipe's output does not resolve to a real record, if an
  owner is not one of the professions in classes.md, if a half is not one of
  its two, if a recipe is listed twice, if a half that is meant to have recipes
  has none, if a half named as empty turns out to have some, or if the game
  folder changed while this ran. Nothing is written unless every check passed.
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
# Mage is not here. classes.md says the Mage works differently: two schools and
# two spells, no halves, and nothing a mage does is a crafting recipe. The
# spell table is Build-SpellTable.ps1's job, not this one's.
$PROFESSIONS = [ordered]@{
    'Warrior'    = @('Bulwark', 'Berserker')
    'Alchemist'  = @('Blightbrewer', 'Physicker')
    'Cook'       = @('Hearthcook', 'Confectioner')
    'Smith'      = @('Platewright', 'Edgewright')
    'Enchanter'  = @('Bladebinder', 'Wardweaver')
    'Tailor'     = @('Liverywright', 'Haberdasher')
    'Woodworker' = @('Charburner', 'Woodwright')
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
# These names are written into recipes.json under cannotCraftYet. The panel on
# K should read that and refuse to offer them, rather than letting somebody
# spend a character on a half with nothing behind it.
$EMPTY_HALVES_EXPECTED = [ordered]@{
    'Warrior/Bulwark'      = 'warriors do not craft. Bulwark and Berserker are halves of how somebody fights, and classes.md gives them combat maneuvers rather than recipes. There is nothing in the records to find.'
    'Warrior/Berserker'    = 'the same. Warrior is the one profession whose halves are not about making anything.'
    'Alchemist/Blightbrewer' = 'Skyrim has no alchemy recipes. Not one COBJ record in the whole load order names an alchemy bench keyword: potions are worked out from the effects that the ingredients share, in the alchemy menu, and no record is involved. The poison bit that would split this half from the Physicker is proved and ready in the code above, so the moment a mod adds an alchemy bench recipe it lands here by itself.'
    'Alchemist/Physicker'  = 'the same. There is nothing for this table to gate until alchemy is answered somewhere other than a recipe record.'
    'Enchanter/Wardweaver' = 'the only enchanting recipes in the build are the 160 staff recipes on the Dragonborn staff enchanter, and a staff is a weapon, so they all land on the Bladebinder. Enchanting a cuirass or a robe is the enchanting menu and not a record, so the Wardweaver has nothing to own here.'
}

# WHAT THE ENGINE NEVER ASKS ABOUT. CraftService::RecipeItemsMatch throws
# tempering out before it considers any recipe, by these two bench keywords,
# hardcoded there as ArmorTable = 0xadb78 and SharpeningWheel = 0x88108. Read
# out of the fork, not remembered. A recipe on one of these still gets an owner
# here, because it is still that half's work, but it is marked as one the
# server is never asked about and it is left out of the gamemode block.
$BENCHES_THE_SERVER_NEVER_SEES = @('adb78:Skyrim.esm', '88108:Skyrim.esm')

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
$LIVERYWRIGHT_KEYWORDS = @('WAF_MaterialFaction', 'CWMission03ImperialGarb')
$LIVERYWRIGHT_WORDS    = @(
    'Robe', 'Vestment', 'Livery', 'Cowl',
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
$SCAN_TYPES = @('KYWD', 'COBJ') + $OUTPUT_TYPES

# desc -> the record, last one in the load order wins, because that is the
# record the game is using
$items   = @{}
$kwName  = @{}
# desc -> the recipe, same rule. Ordered so the json and the block come out in
# load order, which makes a rebuild a small diff rather than a shuffle.
$recipes = New-Object System.Collections.Specialized.OrderedDictionary
$perPluginRecipes = @{}
$seenTwice = New-Object 'System.Collections.Generic.List[string]'

foreach ($pl in $order) {
    $path = Join-Path $Data $pl
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $b = [System.IO.File]::ReadAllBytes($path)
    if ([System.Text.Encoding]::ASCII.GetString($b, 0, 4) -ne 'TES4') { Bad "not a plugin: $path"; continue }
    $headerSize = [int][BitConverter]::ToUInt32($b, 4)
    $localized  = [bool]([BitConverter]::ToUInt32($b, 8) -band 0x80)
    $masters    = Get-PluginMasters $b $headerSize
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
                    $kwds = New-Object 'System.Collections.Generic.List[string]'
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
                            elseif ($sub -eq 'CNTO') { $inputs++ }
                            elseif ($sub -eq 'COCT' -and $sz -eq 4) { $coct = [int][BitConverter]::ToUInt32($rec, $k) }
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
                        $recipes[$desc] = [pscustomobject]@{
                            Desc = $desc; Edid = $edid; SeenIn = $pl
                            Plugin = $desc.Split(':')[1]
                            Local = ($formId -band 0xFFFFFF)
                            OutDesc = $outDesc; BenchDesc = $benchDesc
                            Count = $nam1; Inputs = $inputs; Coct = $coct
                        }
                        $here++
                        if (-not $perPluginRecipes.ContainsKey($pl)) { $perPluginRecipes[$pl] = 0 }
                        $perPluginRecipes[$pl] = $perPluginRecipes[$pl] + 1
                    } else {
                        if (-not $full) { $full = $edid; $fullFrom = 'the editor id' }
                        $items[$desc] = [pscustomobject]@{
                            Desc = $desc; Type = $label; Edid = $edid; Name = $full; NameFrom = $fullFrom
                            AlchFlags = $alchFlags; HasEnit = $hasEnit; WeapAnim = $weapAnim
                            Keywords = $kwds.ToArray(); SeenIn = $pl
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

function MatchesWord([string]$text, $words) {
    if (-not $text) { return $false }
    $lower = $text.ToLowerInvariant()
    foreach ($w in $words) { if ($lower.Contains($w.ToLowerInvariant())) { return $true } }
    return $false
}

# The Tailor's half. The faction keywords first because they are read out of
# the record, then the word list, which is the judgement.
function TailorHalf($item, $names) {
    if (HasAnyKeyword $names $LIVERYWRIGHT_KEYWORDS) { return @('Liverywright', 'the output carries a faction dress keyword') }
    if (MatchesWord $item.Edid $LIVERYWRIGHT_WORDS)  { return @('Liverywright', 'the output''s editor id matches the robe and faction word list') }
    if (MatchesWord $item.Name $LIVERYWRIGHT_WORDS)  { return @('Liverywright', 'the output''s name matches the robe and faction word list') }
    return @('Haberdasher', 'clothing that is neither a robe nor faction dress')
}

$owned    = New-Object System.Collections.Specialized.OrderedDictionary
$unowned  = New-Object System.Collections.Specialized.OrderedDictionary
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
        if ($o.WeapAnim -eq $WEAP_ANIM_STAFF) {
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

    $owned[$desc] = [pscustomobject]@{
        Edid = $r.Edid; OutDesc = $o.Desc; OutName = $o.Name; OutType = $o.Type
        BenchDesc = $r.BenchDesc; BenchName = $benchName
        Owner = $ownerName; Half = $half; Reason = $reason
        Count = $r.Count; Inputs = $r.Inputs; Fires = $fires
        Plugin = $r.Plugin; SeenIn = $r.SeenIn; Local = $r.Local
        NameFrom = $o.NameFrom
    }
}

# ------------------------------------------------------------- the checks ---

Write-Host ''
Write-Host 'checks' -ForegroundColor Cyan

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
foreach ($p in $PROFESSIONS.Keys) {
    foreach ($h in $PROFESSIONS[$p]) {
        $perHalf[$p + '/' + $h] = 0
        $perHalfFiring[$p + '/' + $h] = 0
    }
}
foreach ($desc in $owned.Keys) {
    $row = $owned[$desc]
    $key = $row.Owner + '/' + $row.Half
    if (-not $perHalf.ContainsKey($key)) { $perHalf[$key] = 0; $perHalfFiring[$key] = 0 }
    $perHalf[$key] = $perHalf[$key] + 1
    if ($row.Fires) { $perHalfFiring[$key] = $perHalfFiring[$key] + 1 }
}

Write-Host ("  {0,-14} {1,-14} {2,8}  {3,8}" -f 'profession', 'half', 'recipes', 'the server is asked about')
foreach ($p in $PROFESSIONS.Keys) {
    $total = 0
    foreach ($h in $PROFESSIONS[$p]) { $total += $perHalf[$p + '/' + $h] }
    foreach ($h in $PROFESSIONS[$p]) {
        $key = $p + '/' + $h
        Write-Host ("  {0,-14} {1,-14} {2,8}  {3,8}" -f $p, $h, $perHalf[$key], $perHalfFiring[$key])
    }
    Note ("{0}: {1} in all" -f $p, $total)
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
        $expectedEmpty = $EMPTY_HALVES_EXPECTED.Contains($key)
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
        Bad ("{0} is named in EMPTY_HALVES_EXPECTED as having nothing, and it has {1} recipe(s). That knob is out of date and the reason written in it is no longer true." -f $k, $perHalf[$k])
    }
}
foreach ($k in $EMPTY_HALVES_EXPECTED.Keys) {
    Loud ("{0} owns nothing, on purpose: {1}" -f $k, $EMPTY_HALVES_EXPECTED[$k])
}
Loud 'those halves go into recipes.json under cannotCraftYet. The panel on K should not offer a half that can make nothing.'

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
$doc.Add('  "readFrom": ' + (JsonStr 'BNAM is the workbench keyword, CNAM is the output item, NAM1 is how many it makes, COCT and CNTO are the inputs, CTDA is the conditions the server evaluates itself') + ',')
$doc.Add('  "event": ' + (JsonStr 'mp.onCraft(actorFormId, craftedItemBaseId, count, recipeId). recipeId is the key of this table. Returning false refuses the craft outright: CraftEvent::OnFireSuccess is what removes the inputs and adds the output, and GameModeEvent::Fire only calls it when nobody blocked.') + ',')
$doc.Add('  "default": ' + (JsonStr 'a recipe id this table does not carry is one nobody owns, and anybody may make it') + ',')
$doc.Add('  "fires": ' + (JsonStr 'false means the server is never asked about this recipe. CraftService::RecipeItemsMatch throws out the armour table (adb78) and the sharpening wheel (88108) before it considers anything, so tempering never reaches onCraft.') + ',')
$doc.Add('  "count": ' + ($owned.Count + $unowned.Count) + ',')
$doc.Add('  "owned": ' + $owned.Count + ',')
$doc.Add('  "unownedCount": ' + $unowned.Count + ',')

$doc.Add('  "professions": {')
$pn = 0
foreach ($p in $PROFESSIONS.Keys) {
    $pn++
    $comma = ','
    if ($pn -eq $PROFESSIONS.Count) { $comma = '' }
    $halves = @()
    foreach ($h in $PROFESSIONS[$p]) { $halves += (JsonStr $h) }
    $doc.Add('    ' + (JsonStr $p) + ': [' + ($halves -join ', ') + ']' + $comma)
}
$doc.Add('  },')

$doc.Add('  "counts": {')
$cn = 0
$keys = @()
foreach ($p in $PROFESSIONS.Keys) { foreach ($h in $PROFESSIONS[$p]) { $keys += ($p + '/' + $h) } }
foreach ($k in $keys) {
    $cn++
    $comma = ','
    if ($cn -eq $keys.Count) { $comma = '' }
    $doc.Add('    ' + (JsonStr $k) + ': { "recipes": ' + $perHalf[$k] + ', "theServerIsAsked": ' + $perHalfFiring[$k] + ' }' + $comma)
}
$doc.Add('  },')

$doc.Add('  "cannotCraftYet": {')
$en = 0
foreach ($k in $EMPTY_HALVES_EXPECTED.Keys) {
    $en++
    $comma = ','
    if ($en -eq $EMPTY_HALVES_EXPECTED.Count) { $comma = '' }
    $doc.Add('    ' + (JsonStr $k) + ': ' + (JsonStr $EMPTY_HALVES_EXPECTED[$k]) + $comma)
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
    $doc.Add('    ' + (JsonStr $desc) + ': { "editorId": ' + (JsonStr $r.Edid) +
             ', "out": ' + (JsonStr $r.OutDesc) + ', "name": ' + (JsonStr $r.OutName) +
             ', "type": ' + (JsonStr $r.OutType) + ', "makes": ' + $r.Count +
             ', "inputs": ' + $r.Inputs +
             ', "bench": ' + (JsonStr $r.BenchDesc) + ', "benchName": ' + (JsonStr $r.BenchName) +
             ', "owner": ' + (JsonStr $r.Owner) + ', "half": ' + (JsonStr $r.Half) +
             ', "fires": ' + $firesTxt + ', "plugin": ' + (JsonStr $r.Plugin) +
             ', "nameFrom": ' + (JsonStr $r.NameFrom) +
             ', "why": ' + (JsonStr $r.Reason) + ' }' + $comma)
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
    $blockRows.Add('    ' + (JsonStr $desc) + ': { "out": ' + (JsonStr $r.OutDesc) + ', "name": ' + (JsonStr $r.OutName) +
                   ', "type": ' + (JsonStr $r.OutType) + ', "makes": ' + $r.Count +
                   ', "owner": ' + (JsonStr $r.Owner) + ', "half": ' + (JsonStr $r.Half) + ' },')
}
if ($blockRows.Count -gt 0) {
    $last = $blockRows[$blockRows.Count - 1]
    $blockRows[$blockRows.Count - 1] = $last.Substring(0, $last.Length - 1)
}

$lines = New-Object 'System.Collections.Generic.List[string]'
$lines.Add('  /* Built by tools\Build-RecipeTable.ps1 out of the game''s own records. Do not hand edit.')
$lines.Add('     ' + $blockRows.Count + ' crafting recipes, out of ' + ($owned.Count + $unowned.Count) + ' in tools\recipes.json.')
$lines.Add('')
$lines.Add('     Recipe id -> what it makes, what kind of record that is, how many it')
$lines.Add('     makes, and which profession and which half of it owns the recipe. The')
$lines.Add('     id is the fourth argument of mp.onCraft. Returning false from onCraft')
$lines.Add('     refuses the craft and the person keeps their materials.')
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
if (-not $NoInstall -and $fail -eq 0) {
    $gm = Join-Path $PSScriptRoot 'gamemode.js'
    $open  = '  var RECIPES_BY_ID = {'
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
            foreach ($row in $blockRows) { $body.Add($row) }
            $body.Add('  };')
            $body.Add('')
            $new = $text.Substring(0, $a) + (($body -join "`r`n")) + "`r`n" + $text.Substring($b)
            [System.IO.File]::WriteAllText($gm, $new, (New-Object System.Text.UTF8Encoding($false)))
            Ok ("wrote {0} recipes into the RECIPES_BY_ID block of {1}" -f $blockRows.Count, $gm)
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
