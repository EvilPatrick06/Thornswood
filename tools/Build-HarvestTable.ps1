<#
  Build-HarvestTable.ps1

  Builds tools\harvests.json: the table the server needs to say who may pick
  which plant. Nothing in it is typed from memory. It is read out of the
  plugins of this build on this machine.

  WHY THE SERVER CAN DO THIS AT ALL

  SkyMP already picks plants by itself. MpObjectReference::ProcessActivate
  treats a FLOR or TREE base record as pickable: it reads the produce out of
  the record, gives it to whoever activated it, marks the reference harvested
  and schedules its regrowth. The gamemode's mp.onActivate is asked first and
  returning false blocks it. So the gate for gathering is already in place for
  every plant in the game, and the one thing the server lacks is a list of
  which base records are plants and what each one is worth. This builds that
  list.

  WHICH SUBRECORD IS THE PRODUCE, AND HOW THAT WAS PROVED

  It is PFIG, four bytes, a form id. It was not guessed. Every subrecord of
  every FLOR and TREE record in Skyrim.esm was counted first, which gives
  FLOR: EDID OBND FULL MODL MODT MODS PNAM RNAM FNAM PFIG SNAM PFPC
  TREE: EDID OBND MODL MODT PFIG SNAM PFPC FULL CNAM
  Of the four-byte candidates, SNAM is shared by whole families of plants
  (every mushroom in the game carries the same one, so it is the harvest
  sound), RNAM and FULL resolve through the string table to text, PNAM is on
  all 86 FLOR records including the ones that yield nothing, and PFPC is four
  separate bytes reading 100,100,100,100 on plants that yield and 0,0,0,0 on
  the ones that do not, so it is the per-season chance. PFIG is the only one
  left, it is present on exactly the records that yield something (83 of 86
  FLOR, 32 of 154 TREE, and the 32 TREEs with a PFIG are the same 32 with a
  FULL), and resolving it lands on the right item every time:
      TreeFloraMountainFlower01Blue -> MountainFlower01Blue, Blue Mountain Flower
      TreeFloraWheat01              -> Wheat
      TreeFloraTundraCotton01       -> TundraCotton, Tundra Cotton
      FloraMushroom01               -> Mushroom01, Fly Amanita

  WHERE THE GOLD VALUE IS, AND HOW THAT WAS PROVED

  An INGR record carries DATA, eight bytes: the value as a uint32, then the
  weight as a float. Read that way the numbers come out as the prices these
  ingredients actually have (Blue Mountain Flower 2, Nightshade 8, Blisterwort
  12, White Cap 0, Chaurus Eggs 10) and the weights come out as 0.1, 0.2,
  0.25, 0.3 and 0.5, which is what they weigh. The other candidate, the uint32
  at the front of ENIT, reads 23 for a Thistle Branch that sells for 1, so it
  is not a price and is not used. An ALCH record is laid out the other way
  round: DATA is four bytes and is the weight on its own, and the value is the
  uint32 at the front of ENIT (Potato 1, Salmon Meat 3, Cabbage 2).

  WHAT A FARM CROP IS, AND WHY THE SERVER OWNS THE RULE AND NOT THE LOOK

  The second pass writes the farm crop table: the plants somebody works a plot
  of, rather than the ones anybody finds in the wild. It reads the same records
  the same way and sorts them by what was measured in the SkyMP fork at
  C:\Thornswood-Dev\skymp.

  MpObjectReference::Activate fires the gamemode's ActivateEvent first, and
  returning false from mp.onActivate blocks ProcessActivateNormal outright, so
  the server can refuse any pick. That is where a crop rule can live at all.

  MpObjectReference::GetRelootTime hardcodes std::chrono::hours(1) for FLOR and
  TREE, so the engine regrows a picked plant an hour later whatever the server
  thinks of it. That hour is the free endless farming this table exists to stop.

  The gamemode cannot set isHarvested and cannot set a reloot time on one
  reference. Neither is among the bindings in
  skymp5-server/cpp/addon/property_bindings/PropertyBindingFactory.cpp, so
  there is no call to make. The server therefore owns the RULE and the engine
  owns the LOOK: a crop the server still counts as growing is a plant standing
  there looking ready to pick, and all the server can do is refuse the pick and
  say why. That is why the grow times below start at the engine's own hour and
  never go under it: the rule must not call a crop ripe while the model is
  still the picked one. The state of a plot belongs on the reference itself,
  through mp.makeProperty and mp.set, which survives a restart in the world
  save; this script writes none of that and only says which bases are crops.

  WHICH PLANTS ARE CROPS, AND HOW THAT WAS READ OFF THE DATA

  A farm crop is a TREE record whose produce is an ALCH, which on a plant is
  always a food. On this build that is exactly nine records: ash yam, cabbage,
  leek, potato, gourd, green apple, red apple, JK's carrot plant and tomato.
  Every one of them is a cultivated crop and nothing else gets through, because
  every meat rack, fish, clam, cheese bowl and butter churn in the game is a
  FLOR and not a TREE. The same rule read on FLOR instead would take in 27
  records here, 23 of them salmon, pheasant, rabbit, skeever, horker meat,
  mammoth cheese and the HearthFires butter churn. The other four are the FLOR
  copies JKs Skyrim.esp and JK's Whiterun's Outskirts.esp also ship of their
  apple and carrot, and the TREE copy of each is the one this takes.

  Two field crops give an INGR rather than a food, so no rule reaches them and
  they are named one at a time in CROP_BY_EDITOR_ID below: wheat and tundra
  cotton.

  The name in the table is the produce's name, the same as in the harvests
  table, because that is what somebody is handed. It is what the record says
  and not what the editor id suggests: XJKcarrotplant in JKs Skyrim.esp points
  its PFIG at the leek, so the table reads Leek. That is JK's own data and
  correcting it here would make the table disagree with what the pick gives.

  What it does, in order:
    - works out the load order: the five masters, then every plugin the
      reference plugin list enables
    - walks the FLOR and TREE top groups of each, in that order, so a plugin
      that overrides a plant wins over the one that defined it
    - keeps every record that carries a PFIG, and resolves that form id to the
      record it names, for its own name, its record type and its gold value
    - sorts each plant into one of classes.md's four ranks by what its produce
      is worth (see the knobs below)
    - runs the crops pass over those same plants: takes the farm crops out of
      them by the rule above, gives each one the rank its produce earns and a
      grow time worked out from the same price
    - writes tools\harvests.json, the crops beside the harvests in it, and
      prints both tables as JavaScript object literals, because the server
      ships as one file and cannot read the json

  Read only. It touches nothing in the game folder and nothing on the VPS, and
  it proves that by fingerprinting the game folder before and after and failing
  if anything moved.

  Usage:
    .\tools\Build-HarvestTable.ps1
    .\tools\Build-HarvestTable.ps1 -Data 'C:\Thornswood\Game\Data'
    .\tools\Build-HarvestTable.ps1 -PluginList 'C:\Thornswood\Profile\OwnGame\plugins.txt'
    .\tools\Build-HarvestTable.ps1 -NoInstall

  Exit code 1 if a plugin in the load order is missing, if a localised plugin
  has no string table, if the stations file this server places its own bases
  from is missing or does not parse, if a plant's produce names no record in
  the build, if two plants land on the same key, if a crop has no produce or no
  price, if two crops land on the same key, or if the game folder changed
  underneath it.
#>
param(
    [string] $Data       = 'C:\Thornswood\Game\Data',
    [string] $PluginList = 'C:\Thornswood\Profile\OwnGame\plugins.txt',
    [string] $Out        = '',
    [string] $JsOut      = '',
    # Print the table and leave tools\gamemode.js alone.
    [switch] $NoInstall
)

# ---------------------------------------------------------------- knobs ----
# classes.md is the rulebook. It says a gatherer harvests flora and loose
# material, that four ranks climb by doing the work, and that rank decides
# which source somebody may work at all and how much it gives. It does not put
# a number on any of that. These are the judgement calls this script makes and
# they are here, in one block, rather than buried in the code.
#
# LANGUAGE: which string table the names come from. classes.md says nothing
# about language; the server and the panel are English, so English.
$LANGUAGE = 'english'
#
# RANK_MAX_VALUE: the gold value of the produce, at or below which a plant is
# that rank. This is THE KNOB. classes.md does not set these numbers and
# nothing in the game files ranks a plant, so the value of what it gives is
# the measure, because it is the one number the records already carry and it
# is what the world already agrees a thing is worth. Read top to bottom: the
# first rank whose ceiling the value fits is the rank.
#
# The spread this build actually has is printed every run, under 'ranking', so
# these can be moved against real numbers rather than against a guess. As it
# stands the values are 0, 1, 2, 3, 4, 5, 6, 8, 10, 12 and 20 gold and nothing
# in between, so a threshold anywhere in a gap moves nothing: 12 through 19
# all split the same way. The four below were chosen to sit on the gaps and to
# land where classes.md already says each rank should land.
#
# THE NOVICE CEILING WAS 0g UNTIL 20 SEPTEMBER, AND THAT RUNG WAS EMPTY IN THE
# OPEN WORLD. Measured that day against the table this script had just written:
# 50 rows ranked novice, and 33 of them were the planter sacks below, 1 was the
# clam at Oar's Rest and 1 the tree in the Ancestor Glade. The 15 that were
# left were every one of them a FloraMushroom03, 04 or 05, which is white cap,
# imp stool and namira's rot in a cave, because those three are the only
# ingredients in this build the records price at nothing. Everything a person
# walks past above ground was refused to a new Gatherer: lavender and thistle
# at 1g, the mountain flowers at 2g, snowberries and deathbell at 4g, all of
# them 'takes an Advanced Gatherer'. workPerRank.advanced in the gamemode is 20
# pieces of work, so the only road onto the second rung was twenty cave
# mushrooms. A ceiling of 1g puts the 1g ingredients on the rung with them and
# leaves advanced the biggest rank, which is the shape classes.md asks for.
#   novice   up to 1g. 'The basics of your half, and not much of it.' 57 rows
#            of the 147 in the table: white cap, imp stool, namira's rot,
#            lavender, thistle, creep cluster, juniper berries, jazbay grapes,
#            hanging moss and the rest of the 1g ingredients, plus ten crops
#            that a gatherer is refused anyway because a crop is the farming
#            block's.
#   advanced up to 5g. 'The everyday work. Most of what a hold actually
#            needs.' 61 rows: every mountain flower, snowberries, deathbell,
#            the eggs, wheat, the food crops. The biggest rank, which is what
#            that line asks for.
#   expert   up to 12g. 'The things people come looking for you specifically
#            to get.' 24 rows: nightshade, bleeding crown, nirnroot,
#            blisterwort.
#   master   everything above. 'The short list.' Five plants in this build:
#            ash creep cluster and the three from Update.esm.
$RANK_MAX_VALUE = @(
    @{ Rank = 'novice';   Max = 1 },
    @{ Rank = 'advanced'; Max = 5 },
    @{ Rank = 'expert';   Max = 12 },
    @{ Rank = 'master';   Max = 2147483647 }
)
#
# VALUE_RULES: where the gold value sits in each kind of record. Proved in the
# header. A produce record of a type that is not in here is reported and its
# plants go in the json's 'unranked' list instead of the table, because a rank
# guessed without a price is worse than no entry at all.
$VALUE_RULES = @{
    'INGR' = 'DATA0'   # DATA: value uint32, then weight float
    'MISC' = 'DATA0'   # same shape
    'SLGM' = 'DATA0'   # same shape
    'KEYM' = 'DATA0'   # same shape
    'ARMO' = 'DATA0'   # same shape
    'WEAP' = 'DATA0'   # DATA: value uint32, weight float, damage uint16
    'ALCH' = 'ENIT0'   # DATA is the weight alone; ENIT starts with the value
}
#
# PRODUCE_WITHOUT_A_PRICE: kinds of record that are a real answer to "what does
# this give" but carry no single item and no price. LVLI is the one this build
# has: six coin purse lists, sitting on flora that is loot rather than
# gathering. They are reported by name every run and listed in the json under
# 'unranked'. They are left out of the table on purpose, so the server does not
# gate picking up a purse behind a gatherer's rank.
$PRODUCE_WITHOUT_A_PRICE = @('LVLI', 'FLST', 'LVLN')
#
# PRODUCE_NOT_GATHERED: kinds of record that are a real item with a real price
# and still are not material anybody gathers. KEYM is the one this build has:
# ElysiumEstateSSE.esp hangs the key to the house on a FLOR record. Rank
# decides who may work a source at all, so leaving that in the table would
# mean only a gatherer could ever pick up their own front door key. They are
# reported by name every run and listed in the json under 'unranked'.
$PRODUCE_NOT_GATHERED = @('KEYM')
#
# PRODUCE_A_SCRIPT_MUST_OPEN: produce that is a sack rather than a thing. The
# HearthFires planters and the mead barrel in a built homestead give a MISC
# named for what is inside it and how many, 'Nightshade (3)' or
# 'Nord Mead (5)', which a Papyrus script opens into that many of the real
# item. This server does not run Papyrus, for the two reasons written out over
# the scripted activators in the gamemode, so the sack goes into a pack and
# stays a sack.
#
# They were in the table until 20 September and they did two things wrong at
# once. The records price a sack at nothing, so it ranked at the bottom while
# the same ingredient picked in the wild ranked where its price puts it: the
# planter of 'Nightshade (3)' was a novice plant and wild nightshade, which is
# the same nightshade at 8g, was refused to the same person as an expert's.
# Measured on 20 September, 29 ingredients sat at two ranks at once for that
# reason. And harvest() in the gamemode hands over one of whatever the row
# names, so the count in the name was thrown away before it could matter.
#
# Matched on the produce being a MISC whose name ends in a bracketed count,
# which on this build is exactly the 33 sacks and nothing else: every MISC
# produce that is a real item, the clam's fake coin and the Ancestor Glade's
# canticle bark, carries no count. They are reported by name every run and
# listed in the json under 'unranked'.
$PRODUCE_A_SCRIPT_MUST_OPEN = ' \(\d+\)$'
#
# OUR_STATIONS: the bases this server places in the world itself, read out of
# tools\thornswood-src\stations.json, which is the file the gamemode's own
# STATIONS line is generated from. A record Thornswood put in the world is
# answered by the station code written for it, never by a sweep of the load
# order, and neither pass may claim one.
#
# Measured on 20 September: Thornswood-Content.esp's beehive is a FLOR with an
# INGR produce like any other, so this pass read it and wrote it into the table
# as a wild plant worth 5g and therefore an advanced one. The day the gamemode
# started answering the table, pressing this server's own hive ran the gatherer
# class gate and then 'Picking Honeycomb takes an Advanced Gatherer', and
# because onActivate returns false for anything it answers, the engine's own
# handover was blocked as well: a Woodworker got nothing at all from a hive
# Thornswood placed for them. Nobody decided that. This is the check that stops
# the next FLOR or TREE this server places from being reclassified the same
# quiet way.
$STATIONS_FILE = Join-Path $PSScriptRoot 'thornswood-src\stations.json'
#
# ------------------------------------------------------ the crop knobs ------
#
# CROP_RECORD_TYPE and CROP_PRODUCE_TYPE: the rule that says a plant is a farm
# crop rather than something found in the wild. A TREE whose produce is an ALCH
# is a cultivated food on this build and nothing else is, which was read off the
# records and is argued out in full in the header. This is not a knob to turn on
# a hunch: moving either of these changes which plants somebody can farm, and
# FLOR plus ALCH in particular drags in every meat rack and clam in the game.
$CROP_RECORD_TYPE  = 'TREE'
$CROP_PRODUCE_TYPE = 'ALCH'
#
# CROP_BY_EDITOR_ID: the crops the rule cannot reach. Wheat and tundra cotton
# are grown in fields all over Skyrim and are TREE records like the rest, but
# their produce is an INGR and not a food, so no rule written on the record
# types finds them. Naming two records is honest; widening the rule to INGR to
# catch them would take in every mountain flower, mushroom and hanging moss in
# the game, which is gathering and not farming. Matched on the editor id
# exactly, so the HearthFires planter versions of the same two plants
# (BYOHHouseIngrdWheat01, BYOHHouseIngrdCotton01) are not caught by it.
$CROP_BY_EDITOR_ID = @('TreeFloraWheat01', 'TreeFloraTundraCotton01')
#
# CROP_NOT_A_PLOT_PREFIX: the HearthFires planters. These are Skyrim's own
# plant-and-grow system for a homestead garden: somebody puts a seed in the
# planter and the game grows it. They are TREE records and they give a MISC
# bundle, 'Cabbage (2)' or 'Nightshade (3)', which is a sack a Papyrus script
# turns into that many of the real thing. The server does not run Papyrus, so
# the sack would never open. They are not farm plots and are excluded by editor
# id prefix, which is 33 records on this build. The produce type rule already
# skips them, because a MISC is not an ALCH, but they are named here so that
# the reason is written down where somebody widening the rule will read it.
$CROP_NOT_A_PLOT_PREFIX = @('BYOHHouseFlora', 'BYOHHouseIngrd')
#
# CROP_GROW_MINUTES_*: how long a picked plot takes to come back. INVENTED, and
# the one real knob in this block. classes.md does not set it and nothing in
# the game files says it, so it is worked out from the one number the records
# already carry, the same number the ranks use: what the produce is worth.
#
#     minutes = BASE + produce value in gold * PER_GOLD, capped at MAX
#
# A cheap crop comes back fast and a dear one takes its time, so a plot of
# something worth having is worth waiting for. BASE is the engine's own hour
# and is a floor, not a guess: GetRelootTime hardcodes one hour for FLOR and
# TREE, the gamemode cannot change it and cannot set isHarvested, so an hour
# after a pick the plant looks ready whatever the server says. Anything under
# BASE would have the rule call a crop ripe while the model was still the
# picked one, and a grow time at or above BASE only ever means the plant looks
# ready a while before it is, which the server can explain when it refuses.
# MAX keeps one repriced ingredient in some future mod from putting a plot out
# of reach for a day.
#
# On this build the spread is nearly flat, because ten of the eleven crops give
# something the records price at one gold: ten at 75 minutes and wheat, at 5
# gold, at 135. It is worked out rather than typed so that a mod repricing a
# crop moves its grow time on its own, the same way it already moves its rank.
#
# CROP_RANK_BY_EDITOR_ID: which Farmer rank a crop asks for. INVENTED, and it
# deliberately does NOT use the gold value the rest of this script ranks by.
#
# PATRICK, 20 September: 'they cant grow them if they dont have the rank, they
# cant get the rank if they dont level up from growing them, they cant get the
# crops from anywhere so like how would do that'. He is right, and the gold rule
# is what made it a circle. RANK_MAX_VALUE ranks a plant by what its produce
# sells for, which is the GATHERER's ladder: it answers 'how valuable is this
# thing to find', and a rare flower deep in a cave should be worth more than one
# by the road. Applied to a farm it answers the wrong question entirely. Every
# one of the eleven crops produces something worth at least one gold, so every
# one of them came out Advanced, and a new Farmer is a Novice. Nothing to sow,
# so nothing to bring in, so no farming work, so no way to the Advanced they
# would need. The seeds handed out at creation were unplantable the day they
# arrived.
#
# So a crop is ranked by HOW HARD IT IS TO GROW, which is the only question a
# farm ladder should be asking, and that is a judgement and has to be written
# down rather than computed. The shape of it is the one classes.md publishes:
#
#   Novice    the common field crops. Cabbage, leek, potato, gourd, carrot.
#             These grow in rows outside every hold capital, they are in barrels
#             and on tables all over Skyrim, and a Novice can work them on their
#             first day. This is the rung the whole ladder stands on: unless a
#             beginner can both FIND and GROW something, farming cannot start.
#   Advanced  the ones that take a season. Wheat, tundra cotton, ash yam, tomato.
#   Expert    the orchard. Apples, because a tree is the longest thing anybody
#             here plants.
#   Master    nothing yet. Left open on purpose for whatever is added next.
#
# A crop this list does not name falls back to the gold rule, so a mod adding a
# crop still gets a rank rather than an error, and the fallback is reported.
#
# THE SERVER DOES NOT READ THIS. tools\gamemode.js carries its own CROP_RULES
# and that is what gates a plot, because the generated block in that file is
# overwritten by this script and a judgement written into it would be lost. This
# list exists so that tools\harvests.json does not sit there stating a different
# rank from the one the server enforces. THE TWO MUST AGREE: change one, change
# the other, and the names on each rung are the same names in both.
$CROP_RANK_BY_EDITOR_ID = @{
    'TreeFloraCabbage01'          = 'novice'
    'TreeFloraLeek01'             = 'novice'
    'XJKcarrotplant'              = 'novice'
    'TreeFloraPotatoPlant01'      = 'novice'
    'TreeGourdCluster01'          = 'novice'
    'TreeFloraWheat01'            = 'advanced'
    'TreeFloraTundraCotton01'     = 'advanced'
    'XJKWOTreeFloraTomatoPlant01' = 'advanced'
    'DLC2TreeFloraAshYam01'       = 'advanced'
    'XJKappleGreentree'           = 'expert'
    'XJKappleredtree'             = 'expert'
}
#
$CROP_GROW_MINUTES_BASE     = 60
$CROP_GROW_MINUTES_PER_GOLD = 15
$CROP_GROW_MINUTES_MAX      = 360

$ErrorActionPreference = 'Stop'

if (-not $Out) { $Out = Join-Path $PSScriptRoot 'harvests.json' }

$fail = 0
function Ok  ($m) { Write-Host "  ok    $m" -ForegroundColor Green }
function Bad ($m) { Write-Host "  FAIL  $m" -ForegroundColor Red; $script:fail++ }
function Note($m) { Write-Host "        $m" -ForegroundColor DarkGray }

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

# The masters a plugin declares, in order. A record's form id carries the
# index of the file it really belongs to in its top byte, so a JKs Skyrim.esp
# record with 00 up there is a Skyrim.esm record being overridden and the desc
# has to say Skyrim.esm.
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
    # ',' on purpose. A bare 'return $masters' is unrolled on the way out, and
    # a plugin with exactly one master then comes back as the bare string
    # 'Skyrim.esm' instead of a list of one. Its .Count still reads 1, so
    # nothing complains, but $masters[0] indexes the STRING and hands back the
    # character 'S', and every overridden record in Update.esm, Dawnguard.esm,
    # HearthFires.esm and Dragonborn.esm gets the desc '77e1c:S'. Those four
    # have exactly one master each, so this is the common case, not the odd one.
    return ,$masters.ToArray()
}

# form id -> '<hex>:<the plugin that really owns it>', the shape the server's
# espm descs take.
function Desc-Of([uint32]$formId, $masters, [string]$pl) {
    $mi = [int]($formId -shr 24)
    $owner = $pl
    if ($mi -lt $masters.Count) { $owner = $masters[$mi] }
    return ('{0:x}' -f ($formId -band 0xFFFFFF)) + ':' + $owner
}

# One json string, quoted and escaped. Written here rather than reached for
# with ConvertTo-Json so the file comes out the same on 5.1 and on 7.
function JsonStr($s) {
    $t = [string]$s
    $t = $t.Replace('\', '\\')
    $t = $t.Replace('"', '\"')
    $t = $t.Replace("`r", '\r')
    $t = $t.Replace("`n", '\n')
    $t = $t.Replace("`t", '\t')
    return '"' + $t + '"'
}

# Everything sitting directly in the game folder, with its size and its last
# write. Taken before the work and again after it, so 'read only' is something
# the run proves rather than something the header claims. Only the top level:
# every file this script opens is a plugin or a BSA sitting right there.
function Get-FolderFingerprint([string]$dir) {
    $lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($p in ([System.IO.Directory]::GetFileSystemEntries($dir) | Sort-Object)) {
        $fi = New-Object System.IO.FileInfo $p
        if ($fi.Exists) {
            $lines.Add($fi.Name + '|' + $fi.Length + '|' + $fi.LastWriteTimeUtc.Ticks)
        } else {
            $di = New-Object System.IO.DirectoryInfo $p
            $lines.Add($di.Name + '|dir|' + $di.LastWriteTimeUtc.Ticks)
        }
    }
    return ,$lines.ToArray()   # ',' for the same reason as Get-PluginMasters
}

function Rank-For([int]$value) {
    foreach ($r in $RANK_MAX_VALUE) {
        if ($value -le [int]$r.Max) { return [string]$r.Rank }
    }
    return [string]$RANK_MAX_VALUE[$RANK_MAX_VALUE.Count - 1].Rank
}

# The grow time of a crop, in minutes, out of what its produce is worth. The
# formula and every number in it are in the crop knobs at the top.
function Grow-Minutes([int]$value) {
    $m = $CROP_GROW_MINUTES_BASE + $value * $CROP_GROW_MINUTES_PER_GOLD
    if ($m -gt $CROP_GROW_MINUTES_MAX) { $m = $CROP_GROW_MINUTES_MAX }
    if ($m -lt $CROP_GROW_MINUTES_BASE) { $m = $CROP_GROW_MINUTES_BASE }
    return [int]$m
}

# ------------------------------------------------------- the game folder ----

Write-Host ''
Write-Host 'the game folder' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $Data)) { throw "not found: $Data" }
$fingerBefore = Get-FolderFingerprint $Data
Ok ("{0}: {1} entries before" -f $Data, $fingerBefore.Count)

# ------------------------------------------------------- the load order -----

Write-Host ''
Write-Host 'the load order' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $PluginList)) { throw "not found: $PluginList" }
# The five masters are always loaded and the reference list does not name them,
# so they go on the front. Everything else is a line in that list: '*' means
# enabled, '#' is a comment, and a line with no '*' is a plugin sitting in the
# folder switched off, which is not part of this build.
$order = New-Object 'System.Collections.Generic.List[string]'
foreach ($m in @('Skyrim.esm', 'Update.esm', 'Dawnguard.esm', 'HearthFires.esm', 'Dragonborn.esm')) { $order.Add($m) }
$offCount = 0
foreach ($ln in [System.IO.File]::ReadAllLines($PluginList)) {
    $t = $ln.Trim()
    if (-not $t) { continue }
    if ($t.StartsWith('#')) { continue }
    if (-not $t.StartsWith('*')) { $offCount++; continue }
    $t = $t.Substring(1).Trim()
    if (-not $order.Contains($t)) { $order.Add($t) }
}
Ok ("{0} plugins: the 5 masters and {1} from {2}" -f $order.Count, ($order.Count - 5), $PluginList)
if ($offCount -gt 0) { Note "$offCount line(s) in that list are switched off and were left out" }

$missing = New-Object 'System.Collections.Generic.List[string]'
foreach ($pl in $order) { if (-not (Test-Path -LiteralPath (Join-Path $Data $pl))) { $missing.Add($pl) } }
if ($missing.Count -gt 0) {
    Bad ("{0} plugin(s) the list enables are not in {1}: {2}" -f $missing.Count, $Data, ($missing -join ', '))
} else {
    Ok 'every one of them is in the game folder'
}

# ------------------------------------------------------- the string tables --

Write-Host ''
Write-Host 'names' -ForegroundColor Cyan
# A localised plugin keeps its names in a string table instead of in the
# record. The five masters are localised and their English tables live inside
# Skyrim - Interface.bsa on this machine rather than loose in Data\Strings. A
# mod plugin that is localised keeps its table loose or in its own BSA.
$tables   = @{}
$bsaCache = @{}
$looseDir = Join-Path $Data 'Strings'

function Get-BsaCached([string]$name) {
    if ($bsaCache.ContainsKey($name)) { return $bsaCache[$name] }
    $p = Join-Path $Data $name
    if (-not (Test-Path -LiteralPath $p)) { $bsaCache[$name] = $null; return $null }
    $got = $null
    try { $got = Get-BsaStringFiles $p } catch { Note ("could not read {0}: {1}" -f $name, $_.Exception.Message); $got = $null }
    $bsaCache[$name] = $got
    return $got
}

$localised = @{}
foreach ($pl in $order) {
    $path = Join-Path $Data $pl
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $head = New-Object byte[] 12
    $fs = [System.IO.File]::OpenRead($path)
    [void]$fs.Read($head, 0, 12)
    $fs.Dispose()
    $localised[$pl] = [bool]([BitConverter]::ToUInt32($head, 8) -band 0x80)
    if (-not $localised[$pl]) { continue }

    $base = [System.IO.Path]::GetFileNameWithoutExtension($pl)
    $want = $base.ToLowerInvariant() + '_' + $LANGUAGE + '.strings'
    $loose = Join-Path $looseDir $want
    if (Test-Path -LiteralPath $loose) {
        $tables[$pl] = @{ Table = (Read-StringTable ([System.IO.File]::ReadAllBytes($loose))); Where = 'Data\Strings' }
        continue
    }
    foreach ($cand in @(($base + '.bsa'), ($base + ' - Interface.bsa'), 'Skyrim - Interface.bsa')) {
        $files = Get-BsaCached $cand
        if ($files -and $files.ContainsKey($want)) {
            $tables[$pl] = @{ Table = (Read-StringTable $files[$want]); Where = $cand }
            break
        }
    }
}
$locCount = 0
foreach ($pl in $order) { if ($localised.ContainsKey($pl) -and $localised[$pl]) { $locCount++ } }
Ok ("{0} of {1} plugins are localised; the rest keep their names in their own records" -f $locCount, $order.Count)
foreach ($pl in $order) {
    if (-not ($localised.ContainsKey($pl) -and $localised[$pl])) { continue }
    if ($tables.ContainsKey($pl)) { Note ("{0}: {1} strings, from {2}" -f $pl, $tables[$pl].Table.Count, $tables[$pl].Where) }
    else { Bad ("{0}: localised and no $LANGUAGE string table found; its names would fall back to editor ids" -f $pl) }
}

# ------------------------------------------------ the bases that are ours ---

Write-Host ''
Write-Host 'the stations this server places' -ForegroundColor Cyan
# Read before the plants are, so that a missing or broken stations file stops
# the run here rather than after a table has been built that cannot tell a
# station from a flower. The case for the check is over OUR_STATIONS at the top.
$ourStations = New-Object 'System.Collections.Generic.HashSet[string]'
if (-not (Test-Path -LiteralPath $STATIONS_FILE)) {
    Bad ("{0} is not there, so this run cannot tell a base this server placed from a wild plant" -f $STATIONS_FILE)
} else {
    $stationsJson = $null
    try { $stationsJson = (Get-Content -LiteralPath $STATIONS_FILE -Raw) | ConvertFrom-Json }
    catch { Bad ("{0} does not parse as json: {1}" -f $STATIONS_FILE, $_.Exception.Message) }
    if ($stationsJson) {
        foreach ($s in $stationsJson.PSObject.Properties) {
            [void]$ourStations.Add([string]$s.Value)
            Note ("{0,-14} {1}" -f $s.Name, $s.Value)
        }
        Ok ("{0} bases this server places itself, read from {1}" -f $ourStations.Count, $STATIONS_FILE)
    }
}

# --------------------------------------------------- the FLOR/TREE records --

Write-Host ''
Write-Host 'plants' -ForegroundColor Cyan
# desc -> the plant, the load order winner. A plugin later in the order that
# overrides a plant replaces what an earlier one said about it, which is what
# the game does.
$plants  = New-Object System.Collections.Specialized.OrderedDictionary
$noYield = 0
$fromEdid = New-Object 'System.Collections.Generic.List[string]'
$overrides = 0

foreach ($pl in $order) {
    $path = Join-Path $Data $pl
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $b = [System.IO.File]::ReadAllBytes($path)
    if ([System.Text.Encoding]::ASCII.GetString($b, 0, 4) -ne 'TES4') { Bad "not a plugin: $path"; continue }
    $headerSize = [int][BitConverter]::ToUInt32($b, 4)
    $loc     = $localised[$pl]
    $masters = Get-PluginMasters $b $headerSize
    $strTable = $null
    if ($tables.ContainsKey($pl)) { $strTable = $tables[$pl].Table }

    $here = 0
    $i = 24 + $headerSize
    while ($i + 24 -le $b.Length) {
        if ([System.Text.Encoding]::ASCII.GetString($b, $i, 4) -ne 'GRUP') { break }
        $groupSize = [int][BitConverter]::ToUInt32($b, $i + 4)
        if ($groupSize -lt 24) { break }
        $label = [System.Text.Encoding]::ASCII.GetString($b, $i + 8, 4)
        if ($label -eq 'FLOR' -or $label -eq 'TREE') {
            $j = $i + 24
            $groupEnd = $i + $groupSize
            while ($j + 24 -le $groupEnd) {
                $type     = [System.Text.Encoding]::ASCII.GetString($b, $j, 4)
                $dataSize = [int][BitConverter]::ToUInt32($b, $j + 4)
                # a nested GRUP counts its own 24 byte header in its size; a
                # record does not. FLOR and TREE groups hold no nested groups,
                # but a walk that cannot tell the two apart runs off the end.
                if ($type -eq 'GRUP') { $j += $dataSize; continue }
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
                    $k = 0; $over = 0
                    $edid = ''; $full = ''; $fullFrom = ''
                    $pfig = [uint32]0
                    $seasons = ''
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
                            if ($loc -and $sz -eq 4) {
                                $sid = [BitConverter]::ToUInt32($rec, $k)
                                if ($strTable -and $strTable.ContainsKey($sid)) { $full = $strTable[$sid]; $fullFrom = 'string table' }
                            } elseif ($sz -gt 1) {
                                $full = [System.Text.Encoding]::GetEncoding(1252).GetString($rec, $k, $sz - 1)
                                $fullFrom = 'the record'
                            }
                        } elseif ($sub -eq 'PFIG' -and $sz -eq 4) {
                            $pfig = [BitConverter]::ToUInt32($rec, $k)
                        } elseif ($sub -eq 'PFPC' -and $sz -eq 4) {
                            # the chance of a yield in spring, summer, autumn, winter
                            $seasons = ('{0},{1},{2},{3}' -f $rec[$k], $rec[$k+1], $rec[$k+2], $rec[$k+3])
                        }
                        $k += $sz
                    }

                    $desc = Desc-Of $formId $masters $pl
                    if ($pfig -eq 0) {
                        # a tree, a shrub, a stump: pickable in the engine's
                        # eyes but it gives nothing, so it is not a source
                        if ($plants.Contains($desc)) { $plants.Remove($desc) }
                        $noYield++
                    } else {
                        if (-not $full) { $full = $edid; $fullFrom = 'the editor id'; $fromEdid.Add($desc) }
                        if ($plants.Contains($desc)) { $overrides++ }
                        $plants[$desc] = [pscustomobject]@{
                            Desc        = $desc
                            Kind        = $label
                            Edid        = $edid
                            Full        = $full
                            FullFrom    = $fullFrom
                            Plugin      = $desc.Substring($desc.IndexOf(':') + 1)
                            SeenIn      = $pl
                            Seasons     = $seasons
                            ProduceForm = $pfig
                            ProduceDesc = (Desc-Of $pfig $masters $pl)
                        }
                        $here++
                    }
                }
                $j += 24 + $dataSize
            }
        }
        $i += $groupSize
    }
    if ($here -gt 0) { Note ("{0}: {1} FLOR/TREE records that yield something" -f $pl, $here) }
}
Ok ("{0} plants that yield something, across {1} plugins" -f $plants.Count, (($plants.Values | ForEach-Object { $_.SeenIn } | Sort-Object -Unique).Count))
Note ("{0} FLOR/TREE records carry no produce and are not sources" -f $noYield)
if ($overrides -gt 0) { Note "$overrides of them were overridden by a plugin later in the load order" }
if ($fromEdid.Count -gt 0) { Note ("{0} had no readable name and fell back to their editor id" -f $fromEdid.Count) }

# ------------------------------------------------------------ the produce ---

Write-Host ''
Write-Host 'produce' -ForegroundColor Cyan
$wanted = @{}
foreach ($d in $plants.Keys) { $wanted[$plants[$d].ProduceDesc] = $true }
Ok ("{0} distinct produce records to resolve" -f $wanted.Count)

# Walk every top group of every plugin, but only unpack a record we want.
# Rather than build a desc for every record in the build and compare strings,
# each wanted desc is turned back into the raw form id it would have inside
# THIS plugin, once, before the walk. Then the test in the inner loop is one
# lookup on a number. That is the difference between seconds and minutes.
# CELL, WRLD and DIAL are skipped: they hold references, cells and dialogue,
# and a base item is never in one.
$produce = @{}
foreach ($pl in $order) {
    $path = Join-Path $Data $pl
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $b = [System.IO.File]::ReadAllBytes($path)
    if ([System.Text.Encoding]::ASCII.GetString($b, 0, 4) -ne 'TES4') { continue }
    $headerSize = [int][BitConverter]::ToUInt32($b, 4)
    $loc     = $localised[$pl]
    $masters = Get-PluginMasters $b $headerSize
    $strTable = $null
    if ($tables.ContainsKey($pl)) { $strTable = $tables[$pl].Table }

    # owning plugin -> the index this plugin's records use for it. Its own
    # records use the index one past the last master.
    $indexOf = @{}
    for ($mi = 0; $mi -lt $masters.Count; $mi++) { $indexOf[$masters[$mi].ToLowerInvariant()] = $mi }
    $indexOf[$pl.ToLowerInvariant()] = $masters.Count
    $here = @{}
    foreach ($w in $wanted.Keys) {
        $cut   = [string]$w
        $at    = $cut.IndexOf(':')
        $local = [Convert]::ToUInt32($cut.Substring(0, $at), 16)
        $owner = $cut.Substring($at + 1).ToLowerInvariant()
        if (-not $indexOf.ContainsKey($owner)) { continue }
        $here[[uint32](([uint32]$indexOf[$owner] -shl 24) -bor $local)] = $cut
    }
    if ($here.Count -eq 0) { continue }

    $i = 24 + $headerSize
    while ($i + 24 -le $b.Length) {
        if ([System.Text.Encoding]::ASCII.GetString($b, $i, 4) -ne 'GRUP') { break }
        $groupSize = [int][BitConverter]::ToUInt32($b, $i + 4)
        if ($groupSize -lt 24) { break }
        $label = [System.Text.Encoding]::ASCII.GetString($b, $i + 8, 4)
        if ($label -ne 'CELL' -and $label -ne 'WRLD' -and $label -ne 'DIAL') {
            $j = $i + 24
            $groupEnd = $i + $groupSize
            while ($j + 24 -le $groupEnd) {
                $type     = [System.Text.Encoding]::ASCII.GetString($b, $j, 4)
                $dataSize = [int][BitConverter]::ToUInt32($b, $j + 4)
                if ($type -eq 'GRUP') { $j += $dataSize; continue }
                $formId   = [BitConverter]::ToUInt32($b, $j + 12)
                if ($here.ContainsKey($formId)) {
                    $desc = $here[$formId]
                    $recFlags = [BitConverter]::ToUInt32($b, $j + 8)
                    if ($recFlags -band 0x00040000) {
                        $outLen = [int][BitConverter]::ToUInt32($b, $j + 24)
                        $rec = Expand-RecordData $b ($j + 28) $outLen
                    } else {
                        $rec = New-Object byte[] $dataSize
                        [Array]::Copy($b, $j + 24, $rec, 0, $dataSize)
                    }
                    $k = 0; $over = 0
                    $edid = ''; $full = ''; $fullFrom = ''
                    $value = -1
                    $rule = ''
                    if ($VALUE_RULES.ContainsKey($type)) { $rule = $VALUE_RULES[$type] }
                    while ($k + 6 -le $rec.Length) {
                        $sub = [System.Text.Encoding]::ASCII.GetString($rec, $k, 4)
                        $sz  = [int][BitConverter]::ToUInt16($rec, $k + 4)
                        $k += 6
                        if ($over -gt 0) { $sz = $over; $over = 0 }
                        if ($sub -eq 'XXXX') { $over = [int][BitConverter]::ToUInt32($rec, $k); $k += $sz; continue }
                        if ($sub -eq 'EDID' -and $sz -gt 1) {
                            $edid = [System.Text.Encoding]::GetEncoding(1252).GetString($rec, $k, $sz - 1)
                        } elseif ($sub -eq 'FULL') {
                            if ($loc -and $sz -eq 4) {
                                $sid = [BitConverter]::ToUInt32($rec, $k)
                                if ($strTable -and $strTable.ContainsKey($sid)) { $full = $strTable[$sid]; $fullFrom = 'string table' }
                            } elseif ($sz -gt 1) {
                                $full = [System.Text.Encoding]::GetEncoding(1252).GetString($rec, $k, $sz - 1)
                                $fullFrom = 'the record'
                            }
                        } elseif ($rule -eq 'DATA0' -and $sub -eq 'DATA' -and $sz -ge 4) {
                            $value = [int][BitConverter]::ToUInt32($rec, $k)
                        } elseif ($rule -eq 'ENIT0' -and $sub -eq 'ENIT' -and $sz -ge 4) {
                            $value = [int][BitConverter]::ToUInt32($rec, $k)
                        }
                        $k += $sz
                    }
                    if (-not $full) { $full = $edid; $fullFrom = 'the editor id' }
                    # what the plugin that DEFINED this item said it was
                    # worth, kept so a later plugin repricing it is visible
                    $firstValue  = $value
                    $firstSeenIn = $pl
                    if ($produce.ContainsKey($desc)) {
                        $firstValue  = $produce[$desc].FirstValue
                        $firstSeenIn = $produce[$desc].FirstSeenIn
                    }
                    $produce[$desc] = [pscustomobject]@{
                        Desc        = $desc
                        Type        = $type
                        Edid        = $edid
                        Full        = $full
                        FullFrom    = $fullFrom
                        Value       = $value
                        SeenIn      = $pl
                        FirstValue  = $firstValue
                        FirstSeenIn = $firstSeenIn
                    }
                }
                $j += 24 + $dataSize
            }
        }
        $i += $groupSize
    }
}

$unresolved = New-Object 'System.Collections.Generic.List[string]'
foreach ($w in ($wanted.Keys | Sort-Object)) { if (-not $produce.ContainsKey($w)) { $unresolved.Add($w) } }
if ($unresolved.Count -gt 0) {
    Bad ("{0} produce form id(s) name no record in this build: {1}" -f $unresolved.Count, ($unresolved -join ', '))
    foreach ($u in $unresolved) {
        foreach ($d in $plants.Keys) {
            if ($plants[$d].ProduceDesc -eq $u) { Note ("  wanted by {0} {1} ({2})" -f $d, $plants[$d].Edid, $plants[$d].Full) }
        }
    }
} else {
    Ok ("all {0} resolved" -f $produce.Count)
}
$byType = @{}
foreach ($d in $produce.Keys) {
    $t = $produce[$d].Type
    if (-not $byType.ContainsKey($t)) { $byType[$t] = 0 }
    $byType[$t] = $byType[$t] + 1
}
foreach ($t in ($byType.Keys | Sort-Object)) { Note ("{0}: {1}" -f $t, $byType[$t]) }

# A mod later in the load order that reprices an item moves the rank of every
# plant that grows it, which is the load order doing its job and is worth
# seeing rather than guessing at.
$repriced = New-Object 'System.Collections.Generic.List[string]'
foreach ($d in ($produce.Keys | Sort-Object)) {
    $q = $produce[$d]
    if ($q.SeenIn -ne $q.FirstSeenIn -and $q.Value -ne $q.FirstValue) {
        $repriced.Add(("{0} {1}g in {2}, {3}g in {4}" -f $q.Full, $q.FirstValue, $q.FirstSeenIn, $q.Value, $q.SeenIn))
    }
}
if ($repriced.Count -gt 0) {
    Note ("{0} of them are repriced by a plugin later in the load order, and the later price is the one used:" -f $repriced.Count)
    foreach ($r in $repriced) { Note ('  ' + $r) }
}

# ------------------------------------------------------------- the ranking --

Write-Host ''
Write-Host 'ranking' -ForegroundColor Cyan
$table    = New-Object System.Collections.Specialized.OrderedDictionary
$detail   = New-Object System.Collections.Specialized.OrderedDictionary
$unranked = New-Object System.Collections.Specialized.OrderedDictionary
$values   = New-Object 'System.Collections.Generic.List[int]'

foreach ($d in ($plants.Keys | Sort-Object)) {
    $p = $plants[$d]
    if (-not $produce.ContainsKey($p.ProduceDesc)) { continue }
    $q = $produce[$p.ProduceDesc]
    $why = ''
    if ($ourStations.Contains([string]$d)) {
        $why = 'this server places this one itself and answers it with the station code written for it, so it is not a plant for this pass to rank'
    } elseif ($PRODUCE_WITHOUT_A_PRICE -contains $q.Type) {
        $why = 'its produce is a ' + $q.Type + ', which is a list of things rather than one thing, and carries no price'
    } elseif ($PRODUCE_NOT_GATHERED -contains $q.Type) {
        $why = 'its produce is a ' + $q.Type + ', which is not material anybody gathers'
    } elseif ([string]$q.Type -eq 'MISC' -and ([string]$q.Full) -match $PRODUCE_A_SCRIPT_MUST_OPEN) {
        $why = 'its produce is a sack, ' + $q.Full + ', that only a Papyrus script opens, and this server does not run Papyrus'
    } elseif (-not $VALUE_RULES.ContainsKey($q.Type)) {
        $why = 'nothing here knows where the price sits in a ' + $q.Type + ' record'
    } elseif ($q.Value -lt 0) {
        $why = 'its produce is a ' + $q.Type + ' with no readable price'
    }
    if ($why) {
        $unranked[$d] = [ordered]@{
            editorId    = $p.Edid
            name        = $p.Full
            produce     = $q.Desc
            produceName = $q.Full
            produceType = $q.Type
            why         = $why
        }
        continue
    }
    $values.Add([int]$q.Value)
    $rank = Rank-For ([int]$q.Value)
    $table[$d] = [pscustomobject]@{ Produce = $q.Desc; Name = $q.Full; Rank = $rank }
    $detail[$d] = [ordered]@{
        rank         = $rank
        produce      = $q.Desc
        produceName  = $q.Full
        produceType  = $q.Type
        produceValue = [int]$q.Value
        produceFrom  = $q.SeenIn
        name         = $p.Full
        editorId     = $p.Edid
        recordType   = $p.Kind
        plugin       = $p.Plugin
        definedIn    = $p.SeenIn
        formId       = '0x' + ('{0:X6}' -f ([Convert]::ToUInt32($d.Substring(0, $d.IndexOf(':')), 16)))
        seasons      = $p.Seasons
        nameFrom     = $p.FullFrom
    }
}

if ($values.Count -gt 0) {
    $arr = $values.ToArray()
    [Array]::Sort($arr)
    $sum = 0
    foreach ($v in $arr) { $sum += $v }
    Ok ("{0} plants ranked; produce values run {1} to {2}, median {3}, mean {4:n1}" -f `
        $arr.Length, $arr[0], $arr[$arr.Length - 1], $arr[[int]($arr.Length / 2)], ($sum / $arr.Length))
    $spread = @{}
    foreach ($v in $arr) { if (-not $spread.ContainsKey($v)) { $spread[$v] = 0 }; $spread[$v] = $spread[$v] + 1 }
    $line = New-Object 'System.Collections.Generic.List[string]'
    foreach ($v in ($spread.Keys | Sort-Object)) { $line.Add(("{0}g x{1}" -f $v, $spread[$v])) }
    Note ('the whole spread: ' + ($line -join ', '))
}
$perRank = New-Object System.Collections.Specialized.OrderedDictionary
foreach ($r in $RANK_MAX_VALUE) { $perRank[[string]$r.Rank] = 0 }
foreach ($d in $table.Keys) { $perRank[[string]$table[$d].Rank] = $perRank[[string]$table[$d].Rank] + 1 }
foreach ($r in $RANK_MAX_VALUE) {
    Note ("{0,-9} value up to {1,-10} {2} plants" -f $r.Rank, $r.Max, $perRank[[string]$r.Rank])
}
# What the records price at nothing, now that the sacks are out of the table:
# white cap, imp stool and namira's rot, which really are worth nothing, the
# fake coin in the clam at Oar's Rest and the canticle bark in the Ancestor
# Glade. They land on the first rung together and that is the right place for
# them. This still reports them every run, because a produce record repriced to
# 0 by a plugin later in the order is how a dear ingredient would quietly
# become a novice pick, and the line below is the only place that would show it.
$freeOnes = @{}
foreach ($d in $table.Keys) {
    $q = $produce[$plants[$d].ProduceDesc]
    if ([int]$q.Value -eq 0) { $freeOnes[$q.Desc] = $q }
}
if ($freeOnes.Count -gt 0) {
    Note ("{0} of the produce records are priced at 0 gold, so every plant that grows one is the lowest rank:" -f $freeOnes.Count)
    foreach ($k in ($freeOnes.Keys | Sort-Object { $freeOnes[$_].Full })) {
        Note ("  {0,-30} {1} {2}" -f $freeOnes[$k].Full, $freeOnes[$k].Type, $k)
    }
}

if ($unranked.Count -gt 0) {
    Note ("{0} plants have no usable price and are in the json's unranked list, not the table:" -f $unranked.Count)
    foreach ($d in $unranked.Keys) {
        Note ("  {0} {1} -> {2} {3}" -f $d, $unranked[$d].editorId, $unranked[$d].produceType, $unranked[$d].produce)
    }
}

# -------------------------------------------------------------- the crops ---
#
# The same plants again, this time asking which of them is a plot somebody
# farms. The rule and every exclusion are in the crop knobs at the top and the
# case for them is in the header. This pass invents no records: a crop is one
# of the plants the pass above already read, with a rank off the same price and
# a grow time worked out from it.
#
Write-Host ''
Write-Host 'crops' -ForegroundColor Cyan
$crops    = New-Object System.Collections.Specialized.OrderedDictionary
$cropWhy  = New-Object System.Collections.Specialized.OrderedDictionary
$planters = New-Object 'System.Collections.Generic.List[string]'
$byName   = 0

foreach ($d in ($plants.Keys | Sort-Object)) {
    $p = $plants[$d]

    # the HearthFires planters first, so a planter can never be picked up by
    # the rule or by a name below it
    $isPlanter = $false
    foreach ($pre in $CROP_NOT_A_PLOT_PREFIX) {
        if ([string]$p.Edid -like ($pre + '*')) { $isPlanter = $true }
    }
    if ($isPlanter) { $planters.Add([string]$p.Edid); continue }

    # and a base this server places itself is never a plot either, for the
    # reason written over OUR_STATIONS at the top: it is answered by the
    # station code and not by a table built out of a sweep of the load order.
    if ($ourStations.Contains([string]$d)) { continue }

    $named = ($CROP_BY_EDITOR_ID -contains [string]$p.Edid)

    # A plant whose produce names no record in this build is already a failed
    # check above, and there is nothing here to rank or to time. It is failed
    # again by name when it is one of the crops named by hand, because that
    # list is written against this build and a name in it that resolves to
    # nothing means the list is now wrong.
    if (-not $produce.ContainsKey($p.ProduceDesc)) {
        if ($named) {
            Bad ("the named crop {0} ({1}) has produce {2}, which names no record in this build" -f $p.Edid, $d, $p.ProduceDesc)
        }
        continue
    }
    $q = $produce[$p.ProduceDesc]

    $byRule = ([string]$p.Kind -eq $CROP_RECORD_TYPE -and [string]$q.Type -eq $CROP_PRODUCE_TYPE)
    if (-not $byRule -and -not $named) { continue }

    # No price, no rank and no grow time, and a crop is not something to leave
    # half filled in: rank decides who may work a plot at all and the grow time
    # decides when it comes back, so an entry missing either would be a plot
    # anybody could strip. This fails the run rather than writing a guess.
    if (-not $VALUE_RULES.ContainsKey([string]$q.Type)) {
        Bad ("the crop {0} ({1}) gives a {2} and nothing here knows where the price sits in one" -f $p.Edid, $d, $q.Type)
        continue
    }
    if ([int]$q.Value -lt 0) {
        Bad ("the crop {0} ({1}) gives {2}, a {3} with no readable price, so it has no rank and no grow time" -f $p.Edid, $d, $q.Full, $q.Type)
        continue
    }

    if ($named -and -not $byRule) { $byName++ }
    $crops[$d] = [pscustomobject]@{
        Produce = $q.Desc
        Name    = $q.Full
        Rank    = $(if ($CROP_RANK_BY_EDITOR_ID.ContainsKey([string]$p.Edid)) {
                        $CROP_RANK_BY_EDITOR_ID[[string]$p.Edid]
                    } else {
                        # Not on the farm ladder, so the gold rule is all there
                        # is. Reported below rather than passed over in silence.
                        Rank-For ([int]$q.Value)
                    })
        RankFrom = $(if ($CROP_RANK_BY_EDITOR_ID.ContainsKey([string]$p.Edid)) { 'the farm ladder' } else { 'the gold rule, because the farm ladder does not name it' })
        Grow    = (Grow-Minutes ([int]$q.Value))
    }
    $how = 'a ' + $CROP_RECORD_TYPE + ' giving an ' + $CROP_PRODUCE_TYPE
    if ($named -and -not $byRule) { $how = 'named in CROP_BY_EDITOR_ID, its produce type is ' + $q.Type }
    $cropWhy[$d] = $how
}

Ok ("{0} farm crops: {1} by the rule and {2} named by hand" -f $crops.Count, ($crops.Count - $byName), $byName)
foreach ($d in $crops.Keys) {
    $c = $crops[$d]
    Note ("  {0,-34} {1,-22} {2,-9} {3,4} min   {4}" -f $plants[$d].Edid, $c.Name, $c.Rank, $c.Grow, $cropWhy[$d])
}
Note ("grow time is {0} + value x {1} minutes, capped at {2}; the {0} is the engine's own reloot hour and is a floor" -f `
    $CROP_GROW_MINUTES_BASE, $CROP_GROW_MINUTES_PER_GOLD, $CROP_GROW_MINUTES_MAX)
if ($planters.Count -gt 0) {
    Note ("{0} HearthFires planter records were left out: they are Skyrim's own plant-and-grow system and their MISC bundle only opens in a Papyrus script the server does not run" -f $planters.Count)
}

# ------------------------------------------------------------- the checks ---

Write-Host ''
Write-Host 'checks' -ForegroundColor Cyan

if ($table.Count -eq 0) { Bad 'no plants at all, so there is nothing to write' }
else { Ok ("{0} plants in the table" -f $table.Count) }

# duplicates: an OrderedDictionary cannot hold one key twice, so this is
# really a check that nothing built a key two different ways
$seen = @{}
$dupes = 0
foreach ($d in $table.Keys) {
    $key = [string]$d
    if ($seen.ContainsKey($key)) { Bad ("{0} is in the table twice" -f $key); $dupes++ }
    $seen[$key] = $true
}
if ($dupes -eq 0) { Ok 'no plant is in the table twice' }

# the ids: hex digits and a plugin named, on both sides of every entry. Four
# hex digits is a real length here, not a fault: gamemode.js already carries
# 9456:PlayFluteLuteDrum.esp.
$shape = '^[0-9a-f]{1,8}:[^:]+\.es[mpl]$'
$odd = New-Object 'System.Collections.Generic.List[string]'
foreach ($d in $table.Keys) {
    if ([string]$d -cnotmatch $shape) { $odd.Add(("the plant {0}" -f $d)) }
    if ([string]$table[$d].Produce -cnotmatch $shape) { $odd.Add(("the produce of {0}: {1}" -f $d, $table[$d].Produce)) }
}
if ($odd.Count -gt 0) { foreach ($o in $odd) { Bad ("an id that does not look right: {0}" -f $o) } }
else { Ok 'every desc on both sides is hex digits and a plugin' }

# a plant with no name is a message that reads 'You pick the .'
$nameless = New-Object 'System.Collections.Generic.List[string]'
foreach ($d in $table.Keys) { if (-not [string]$table[$d].Name) { $nameless.Add([string]$d) } }
if ($nameless.Count -gt 0) { Bad ("{0} entries have no name for their produce: {1}" -f $nameless.Count, ($nameless -join ', ')) }
else { Ok 'every entry names what it gives' }

# every rank is one of classes.md's four
$ranks = @('novice', 'advanced', 'expert', 'master')
$oddRank = New-Object 'System.Collections.Generic.List[string]'
foreach ($d in $table.Keys) { if ($ranks -notcontains [string]$table[$d].Rank) { $oddRank.Add([string]$d) } }
if ($oddRank.Count -gt 0) { Bad ("{0} entries have a rank that is not one of the four in classes.md" -f $oddRank.Count) }
else { Ok "every rank is one of classes.md's four" }

# the crops, checked the same way and for the same reasons. A crop table with a
# hole in it is worse than none: the server would gate a plot on a rank that is
# not a rank, or hand back a grow time of nothing and let the plot be stripped.
if ($crops.Count -eq 0) { Bad 'no farm crops at all, so the rule found nothing and the crops block would go out empty' }
else { Ok ("{0} crops in the crops table" -f $crops.Count) }

$seenCrop = @{}
$cropDupes = 0
foreach ($d in $crops.Keys) {
    $key = [string]$d
    if ($seenCrop.ContainsKey($key)) { Bad ("{0} is in the crops table twice" -f $key); $cropDupes++ }
    $seenCrop[$key] = $true
}
if ($cropDupes -eq 0) { Ok 'no crop is in the crops table twice' }

$oddCrop = New-Object 'System.Collections.Generic.List[string]'
foreach ($d in $crops.Keys) {
    if ([string]$d -cnotmatch $shape) { $oddCrop.Add(("the crop {0}" -f $d)) }
    if ([string]$crops[$d].Produce -cnotmatch $shape) { $oddCrop.Add(("the produce of the crop {0}: {1}" -f $d, $crops[$d].Produce)) }
}
if ($oddCrop.Count -gt 0) { foreach ($o in $oddCrop) { Bad ("an id that does not look right: {0}" -f $o) } }
else { Ok 'every crop desc on both sides is hex digits and a plugin' }

# a crop with no produce name is a message that reads 'The  is still growing.'
$namelessCrop = New-Object 'System.Collections.Generic.List[string]'
foreach ($d in $crops.Keys) { if (-not [string]$crops[$d].Name) { $namelessCrop.Add([string]$d) } }
if ($namelessCrop.Count -gt 0) { Bad ("{0} crops have no name for their produce: {1}" -f $namelessCrop.Count, ($namelessCrop -join ', ')) }
else { Ok 'every crop names what it gives' }

$oddCropRank = New-Object 'System.Collections.Generic.List[string]'
foreach ($d in $crops.Keys) { if ($ranks -notcontains [string]$crops[$d].Rank) { $oddCropRank.Add([string]$d) } }
if ($oddCropRank.Count -gt 0) { Bad ("{0} crops have a rank that is not one of the four in classes.md" -f $oddCropRank.Count) }
else { Ok "every crop's rank is one of classes.md's four" }

# THE NOVICE RUNG MUST NOT BE EMPTY. This is the check that would have caught
# the circle Patrick found on 20 September: every crop ranked advanced or above
# means a new Farmer has nothing to sow, no farming work to do, and therefore no
# way to the rank that would let them start. A farm ladder with no bottom rung
# is not a ladder.
$noviceCrops = @($crops.Keys | Where-Object { [string]$crops[$_].Rank -eq 'novice' })
if ($noviceCrops.Count -eq 0) {
    Bad "no crop asks for novice, so a new farmer has nothing they may sow and no way to earn a rank that would let them"
} else {
    Ok ("{0} crop(s) a novice farmer may sow on their first day" -f $noviceCrops.Count)
}

# And say which crops fell through the farm ladder onto the gold rule, because
# that is the rank nobody chose and it is the one worth arguing with.
$fellThrough = @($crops.Keys | Where-Object { [string]$crops[$_].RankFrom -ne 'the farm ladder' })
if ($fellThrough.Count -eq 0) {
    Ok 'every crop is ranked by the farm ladder'
} else {
    Note ("{0} crop(s) are not on the farm ladder and took the gold rule instead: {1}" -f $fellThrough.Count,
          (($fellThrough | ForEach-Object { [string]$crops[$_].Name + ' (' + [string]$crops[$_].Rank + ')' }) -join ', '))
}

# the floor is the whole design: under the engine's reloot hour the rule would
# call a crop ripe while the plant still looked picked
$oddGrow = New-Object 'System.Collections.Generic.List[string]'
foreach ($d in $crops.Keys) {
    $g = [int]$crops[$d].Grow
    if ($g -lt $CROP_GROW_MINUTES_BASE -or $g -gt $CROP_GROW_MINUTES_MAX) {
        $oddGrow.Add(("{0} grows in {1} minutes" -f $d, $g))
    }
}
if ($oddGrow.Count -gt 0) {
    Bad ("{0} crops have a grow time outside {1} to {2} minutes: {3}" -f `
        $oddGrow.Count, $CROP_GROW_MINUTES_BASE, $CROP_GROW_MINUTES_MAX, ($oddGrow -join ', '))
} else {
    Ok ("every crop grows in {0} to {1} minutes, never under the engine's own hour" -f $CROP_GROW_MINUTES_BASE, $CROP_GROW_MINUTES_MAX)
}

# a crop the harvests table does not carry would be a plot the gathering gate
# never sees, so the two tables have to agree on what a plant is
$loose = New-Object 'System.Collections.Generic.List[string]'
foreach ($d in $crops.Keys) { if (-not $table.Contains($d)) { $loose.Add([string]$d) } }
if ($loose.Count -gt 0) { Bad ("{0} crops are not in the harvests table: {1}" -f $loose.Count, ($loose -join ', ')) }
else { Ok 'every crop is a plant the harvests table already carries' }

$fingerAfter = Get-FolderFingerprint $Data
$moved = New-Object 'System.Collections.Generic.List[string]'
if ($fingerAfter.Count -ne $fingerBefore.Count) {
    $moved.Add(("{0} entries before, {1} after" -f $fingerBefore.Count, $fingerAfter.Count))
} else {
    for ($i = 0; $i -lt $fingerBefore.Count; $i++) {
        if ($fingerBefore[$i] -ne $fingerAfter[$i]) { $moved.Add(("{0} -> {1}" -f $fingerBefore[$i], $fingerAfter[$i])) }
    }
}
if ($moved.Count -gt 0) {
    Bad ("the game folder changed while this ran, which it must not: {0}" -f ($moved -join '; '))
} else {
    Ok ("the game folder is untouched: {0} entries, same names, sizes and timestamps before and after" -f $fingerAfter.Count)
}

# ------------------------------------------------------------- the writing -

Write-Host ''
Write-Host 'writing' -ForegroundColor Cyan
# The json is written out by hand rather than with ConvertTo-Json, and there is
# no timestamp in it, so that the same game files give byte for byte the same
# file: ConvertTo-Json lays out Windows PowerShell 5.1 and PowerShell 7
# differently, and a rebuild that changed nothing would be a whole-file diff.
$docLines = New-Object 'System.Collections.Generic.List[string]'
$docLines.Add('{')
$docLines.Add('  "builtBy": ' + (JsonStr 'tools\Build-HarvestTable.ps1') + ',')
$docLines.Add('  "source": ' + (JsonStr ('the FLOR and TREE records of ' + $order.Count + ' plugins, the 5 masters and what ' + $PluginList + ' enables')) + ',')
$docLines.Add('  "language": ' + (JsonStr $LANGUAGE) + ',')
$docLines.Add('  "rankedBy": ' + (JsonStr 'the gold value of the produce, the thresholds in RANK_MAX_VALUE at the top of the script') + ',')
$docLines.Add('  "cropsRankedBy": ' + (JsonStr ('how hard the crop is to grow, named one at a time in CROP_RANK_BY_EDITOR_ID at the top of the script, ' +
    'because the gold value is the gatherer''s ladder and ranking a farm by it put every crop at advanced and left a new farmer nothing to sow')) + ',')
$thr = New-Object 'System.Collections.Generic.List[string]'
foreach ($r in $RANK_MAX_VALUE) { $thr.Add('    ' + (JsonStr ([string]$r.Rank)) + ': ' + [int]$r.Max) }
$docLines.Add('  "rankMaxValue": {')
$docLines.Add(($thr -join (',' + "`r`n")))
$docLines.Add('  },')
$docLines.Add('  "count": ' + $table.Count + ',')
$docLines.Add('  "harvests": {')
$n = 0
foreach ($d in $table.Keys) {
    $n++
    $comma = ','
    if ($n -eq $table.Count) { $comma = '' }
    $e = $table[$d]
    $docLines.Add('    ' + (JsonStr ([string]$d)) + ': { "produce": ' + (JsonStr ([string]$e.Produce)) +
                  ', "name": ' + (JsonStr ([string]$e.Name)) +
                  ', "rank": ' + (JsonStr ([string]$e.Rank)) + ' }' + $comma)
}
$docLines.Add('  },')
# the crops sit beside the harvests rather than inside them: every crop is also
# a harvest, and a reader of this file should be able to see at a glance which
# of the plants are plots somebody farms.
$docLines.Add('  "cropsAre": ' + (JsonStr ('a ' + $CROP_RECORD_TYPE + ' whose produce is an ' + $CROP_PRODUCE_TYPE +
    ', which on a plant is a food, plus the ones named in CROP_BY_EDITOR_ID at the top of the script; the HearthFires planters are left out')) + ',')
$docLines.Add('  "cropGrowMinutes": ' + (JsonStr ('base + the produce value in gold x perGold, capped at max, and never under base, which is the hour the engine reloots a FLOR or TREE in on its own')) + ',')
$docLines.Add('  "cropGrowMinutesKnobs": {')
$docLines.Add('    "base": ' + [int]$CROP_GROW_MINUTES_BASE + ',')
$docLines.Add('    "perGold": ' + [int]$CROP_GROW_MINUTES_PER_GOLD + ',')
$docLines.Add('    "max": ' + [int]$CROP_GROW_MINUTES_MAX)
$docLines.Add('  },')
$docLines.Add('  "cropCount": ' + $crops.Count + ',')
$docLines.Add('  "crops": {')
$n = 0
foreach ($d in $crops.Keys) {
    $n++
    $comma = ','
    if ($n -eq $crops.Count) { $comma = '' }
    $c = $crops[$d]
    $docLines.Add('    ' + (JsonStr ([string]$d)) + ': { "produce": ' + (JsonStr ([string]$c.Produce)) +
                  ', "name": ' + (JsonStr ([string]$c.Name)) +
                  ', "rank": ' + (JsonStr ([string]$c.Rank)) +
                  ', "growMinutes": ' + [int]$c.Grow + ' }' + $comma)
}
$docLines.Add('  },')
$docLines.Add('  "unranked": {')
$n = 0
foreach ($d in $unranked.Keys) {
    $n++
    $comma = ','
    if ($n -eq $unranked.Count) { $comma = '' }
    $u = $unranked[$d]
    $docLines.Add('    ' + (JsonStr ([string]$d)) + ': {')
    $fields = New-Object 'System.Collections.Generic.List[string]'
    foreach ($f in $u.Keys) { $fields.Add('      "' + $f + '": ' + (JsonStr ([string]$u[$f]))) }
    $docLines.Add(($fields -join (',' + "`r`n")))
    $docLines.Add('    }' + $comma)
}
$docLines.Add('  },')
$docLines.Add('  "detail": {')
$n = 0
foreach ($d in $detail.Keys) {
    $n++
    $comma = ','
    if ($n -eq $detail.Count) { $comma = '' }
    $v = $detail[$d]
    $docLines.Add('    ' + (JsonStr ([string]$d)) + ': {')
    $fields = New-Object 'System.Collections.Generic.List[string]'
    foreach ($f in $v.Keys) {
        if ($f -eq 'produceValue') { $fields.Add('      "' + $f + '": ' + [int]$v[$f]) }
        else { $fields.Add('      "' + $f + '": ' + (JsonStr ([string]$v[$f]))) }
    }
    $docLines.Add(($fields -join (',' + "`r`n")))
    $docLines.Add('    }' + $comma)
}
$docLines.Add('  }')
$docLines.Add('}')
$json = ($docLines -join "`r`n") + "`r`n"

# A run that failed leaves the table it could not rebuild exactly as it was.
# Nothing is written until every check above has passed: pointing -Data at a
# folder that is not there, or at a build with half its plugins missing, must
# not quietly replace a good table with a short one.
if ($fail -gt 0) {
    Bad ("{0} check(s) failed, so {1} was left exactly as it was" -f $fail, $Out)
} else {
    [System.IO.File]::WriteAllText($Out, $json, (New-Object System.Text.UTF8Encoding($false)))
    Ok ("wrote {0} ({1} plants, {2} bytes)" -f $Out, $table.Count, $json.Length)
}

$lines = New-Object 'System.Collections.Generic.List[string]'
$lines.Add('/* Built by tools\Build-HarvestTable.ps1 out of the FLOR and TREE records of this build.')
$lines.Add('     ' + $table.Count + ' plants, the same table as tools\harvests.json.')
$lines.Add('     The key is the plant''s base record. The server already picks a FLOR or TREE on')
$lines.Add('     its own, so onActivate only has to look the base up here and decide.')
$lines.Add('     Paste it between the HARVESTS_BY_BASE markers in tools\gamemode.js. Do not hand edit. */')
$lines.Add('  var HARVESTS_BY_BASE = {')
$n = 0
foreach ($d in $table.Keys) {
    $n++
    $comma = ','
    if ($n -eq $table.Count) { $comma = '' }
    $e = $table[$d]
    # double quoted, the same as the installed block, so what is printed here
    # and what is written into the gamemode are the same text. Half these
    # names carry an apostrophe (Namira's Rot, Dragon's Tongue, Hawk's Egg)
    # and a single quoted literal would be one backslash away from broken.
    $lines.Add('    ' + (JsonStr ([string]$d)) + ': { "produce": ' + (JsonStr ([string]$e.Produce)) +
               ', "name": ' + (JsonStr ([string]$e.Name)) +
               ', "rank": ' + (JsonStr ([string]$e.Rank)) + ' }' + $comma)
}
$lines.Add('  };')
$literal = $lines -join [Environment]::NewLine

$cropLines = New-Object 'System.Collections.Generic.List[string]'
$cropLines.Add('/* Built by tools\Build-HarvestTable.ps1 out of the same records as the harvests.')
$cropLines.Add('     ' + $crops.Count + ' farm crops, the same table as the crops map in tools\harvests.json.')
$cropLines.Add('     A crop is a plot somebody works rather than a plant anybody finds: a ' + $CROP_RECORD_TYPE + ' whose')
$cropLines.Add('     produce is an ' + $CROP_PRODUCE_TYPE + ', which on a plant is a food, plus wheat and tundra cotton,')
$cropLines.Add('     which give an ingredient and are named one at a time in the script.')
$cropLines.Add('     growMinutes is how long after a pick the server counts the plot as grown.')
$cropLines.Add('     The engine reloots a FLOR or TREE an hour after a pick and the gamemode cannot')
$cropLines.Add('     set isHarvested or a reloot time, so the plant looks ready before it is: the')
$cropLines.Add('     server refuses the pick until growMinutes is up and says how long is left.')
$cropLines.Add('     Paste it between the CROPS_BY_BASE markers in tools\gamemode.js. Do not hand edit. */')
$cropLines.Add('  var CROPS_BY_BASE = {')
$n = 0
foreach ($d in $crops.Keys) {
    $n++
    $comma = ','
    if ($n -eq $crops.Count) { $comma = '' }
    $c = $crops[$d]
    # double quoted for the same reason as the harvests literal above
    $cropLines.Add('    ' + (JsonStr ([string]$d)) + ': { "produce": ' + (JsonStr ([string]$c.Produce)) +
                   ', "name": ' + (JsonStr ([string]$c.Name)) +
                   ', "rank": ' + (JsonStr ([string]$c.Rank)) +
                   ', "growMinutes": ' + [int]$c.Grow + ' }' + $comma)
}
$cropLines.Add('  };')
$cropLiteral = $cropLines -join [Environment]::NewLine

# ---------------------------------------------------------------- install --
#
# The gamemode carries the table, because the server is deployed as one file
# and cannot read tools\harvests.json. Nothing hand edits that block: this
# writes it between its own markers, the way the other generated blocks in
# this repo are written. -NoInstall prints it and leaves the file alone.
#
# The declaration line is found rather than assumed, so whichever of var or
# const the block is written with, and whatever indent it sits at, is kept.
#
if (-not $NoInstall -and $fail -eq 0) {
    $gm = Join-Path $PSScriptRoot 'gamemode.js'
    if (-not (Test-Path -LiteralPath $gm)) {
        Note "no gamemode.js beside this script, so the table was not installed"
    } else {
        $text = [System.IO.File]::ReadAllText($gm)
        $close = '// ==== end HARVESTS_BY_BASE ===='
        $m = [regex]::Match($text, '(?m)^([ \t]*)(var|const|let)[ \t]+HARVESTS_BY_BASE[ \t]*=[ \t]*\{')
        $b = $text.IndexOf($close)
        # back up to the start of that line, so the end marker keeps the indent
        # it was written with instead of being shunted to column zero
        while ($b -gt 0 -and $text[$b - 1] -ne "`n") { $b-- }
        if (-not $m.Success -or $b -lt 0 -or $b -lt $m.Index) {
            Note ("{0} has no HARVESTS_BY_BASE block yet, so nothing was written into it." -f $gm)
            Note "  It needs a declaration line and an end marker, in this order:"
            Note "      var HARVESTS_BY_BASE = {"
            Note "      };"
            Note "      // ==== end HARVESTS_BY_BASE ===="
            Note "  Run this again once they are there, or paste the block printed below."
        } else {
            $indent = $m.Groups[1].Value
            $kw     = $m.Groups[2].Value
            $body = New-Object 'System.Collections.Generic.List[string]'
            $body.Add($indent + $kw + ' HARVESTS_BY_BASE = {')
            $k = 0
            foreach ($d in $table.Keys) {
                $k++
                $comma = ','
                if ($k -eq $table.Count) { $comma = '' }
                $e = $table[$d]
                $body.Add($indent + '  ' + (JsonStr ([string]$d)) + ': { "produce": ' + (JsonStr ([string]$e.Produce)) +
                          ', "name": ' + (JsonStr ([string]$e.Name)) +
                          ', "rank": ' + (JsonStr ([string]$e.Rank)) + ' }' + $comma)
            }
            $body.Add($indent + '};')
            $body.Add('')
            $new = $text.Substring(0, $m.Index) + (($body -join "`r`n")) + "`r`n" + $text.Substring($b)
            [System.IO.File]::WriteAllText($gm, $new, (New-Object System.Text.UTF8Encoding($false)))
            Ok ("wrote {0} plants into the HARVESTS_BY_BASE block of {1}" -f $table.Count, $gm)
        }
    }
}

# The crops block goes in the same way and under the same rules: its own
# markers, never hand edited, and only when nothing failed. It is written
# separately from the harvests block rather than inside it because the two are
# read at different moments in the gamemode, the harvests on any pick and the
# crops only when the pick is at a plot.
#
# A gamemode.js with no CROPS_BY_BASE markers yet is the expected case the
# first time this runs, and it is not a failure and not a place to improvise:
# the block is printed, the two lines it needs are named, and the file is left
# exactly as it was. Writing the table anywhere this script chose by itself
# would put the server's crop rule in a spot nobody agreed on.
#
if (-not $NoInstall -and $fail -eq 0) {
    $gm = Join-Path $PSScriptRoot 'gamemode.js'
    if (-not (Test-Path -LiteralPath $gm)) {
        Note "no gamemode.js beside this script, so the crops were not installed"
    } else {
        $text = [System.IO.File]::ReadAllText($gm)
        $close = '// ==== end CROPS_BY_BASE ===='
        $m = [regex]::Match($text, '(?m)^([ \t]*)(var|const|let)[ \t]+CROPS_BY_BASE[ \t]*=[ \t]*\{')
        $b = $text.IndexOf($close)
        # back up to the start of that line, so the end marker keeps the indent
        # it was written with instead of being shunted to column zero
        while ($b -gt 0 -and $text[$b - 1] -ne "`n") { $b-- }
        if (-not $m.Success -or $b -lt 0 -or $b -lt $m.Index) {
            Note ("{0} has no CROPS_BY_BASE block yet, so the crops were NOT written into it." -f $gm)
            Note "  It needs a declaration line and an end marker, in this order:"
            Note "      var CROPS_BY_BASE = {"
            Note "      };"
            Note "      // ==== end CROPS_BY_BASE ===="
            Note "  Run this again once they are there, or paste the block printed below."
        } else {
            $indent = $m.Groups[1].Value
            $kw     = $m.Groups[2].Value
            $body = New-Object 'System.Collections.Generic.List[string]'
            $body.Add($indent + $kw + ' CROPS_BY_BASE = {')
            $k = 0
            foreach ($d in $crops.Keys) {
                $k++
                $comma = ','
                if ($k -eq $crops.Count) { $comma = '' }
                $c = $crops[$d]
                $body.Add($indent + '  ' + (JsonStr ([string]$d)) + ': { "produce": ' + (JsonStr ([string]$c.Produce)) +
                          ', "name": ' + (JsonStr ([string]$c.Name)) +
                          ', "rank": ' + (JsonStr ([string]$c.Rank)) +
                          ', "growMinutes": ' + [int]$c.Grow + ' }' + $comma)
            }
            $body.Add($indent + '};')
            $body.Add('')
            $new = $text.Substring(0, $m.Index) + (($body -join "`r`n")) + "`r`n" + $text.Substring($b)
            [System.IO.File]::WriteAllText($gm, $new, (New-Object System.Text.UTF8Encoding($false)))
            Ok ("wrote {0} crops into the CROPS_BY_BASE block of {1}" -f $crops.Count, $gm)
        }
    }
}

Write-Host ''
Write-Host 'the same table, ready to paste into the gamemode:' -ForegroundColor Cyan
Write-Host $literal
Write-Host ''
Write-Host 'the crops, ready to paste into the gamemode:' -ForegroundColor Cyan
Write-Host $cropLiteral
if ($JsOut) {
    # both blocks, in the order they are read in the gamemode. -JsOut is the
    # paste file and a crops block left out of it would be a table somebody had
    # to go back to the console for.
    $both = $literal + [Environment]::NewLine + [Environment]::NewLine + $cropLiteral
    [System.IO.File]::WriteAllText($JsOut, $both, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ''
    Ok "wrote $JsOut"
}

Write-Host ''
if ($fail) {
    Write-Host "$fail check(s) failed. Read those before the table ships." -ForegroundColor Red
    exit 1
}
Write-Host ("the table is complete: {0} plants, {1} with no price left out and listed, none doubled." -f $table.Count, $unranked.Count) -ForegroundColor Green
Write-Host ("the crops are complete: {0} of those plants are farm plots, every one with a produce, a rank and a grow time, none doubled." -f $crops.Count) -ForegroundColor Green
