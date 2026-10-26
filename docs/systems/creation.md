# Creation

A new character is made in the game, not in the launcher.

The game loads to its main menu. An empty slot starts a character. They
arrive in a quiet stone hall and the race menu opens. That menu is the
face, the race, and nothing else about the life they will lead. The ten
peoples and the rieklings are in [Races](races.md).

When the face is done they are dressed in a plain tunic and boots. A
riekling is dressed in the riekling cut of the same tunic and in
footwraps instead, because the tunic and boots are cut for the other peoples and
do not fit a riekling (Patrick, 12 October 2026). The
panel behind K opens on its own. On it:

- **Home.** The town they wake in. This one is required before they leave
  the hall. Confirming it sends them to that town's start spot, not its inn
  (#2622).
- **Class.** Hunter, Fisher, Gatherer, Miner or Farmer. Can be left for
  later and picked in the world from the same panel. Until it is picked,
  every seam, carcass, plant, fishing spot and crop turns them away.
- **Profession and half.** One profession, then one half of it. Can wait
  the same way. Until it is picked, they cannot make anything that is
  somebody's work, smelting and tanning included. See
  [Professions](professions.md).

They are handed 40 gold once, and nothing else, except a tool at the
moment a pick that needs one is made: a pickaxe for a Miner, a
woodcutter's axe for a Woodworker, a shovel and seed for a Farmer, a
crude fishing pole for a Fisher. The tool has 50 uses.

The towns are Whiterun, Riften, Solitude, Windhelm, Markarth, Falkreath,
Morthal, Dawnstar and Winterhold (`game\data\chargen.json`). The arrival
is that town's start spot (#2622): the stables or the carriage stop at
Whiterun, Solitude, Windhelm and Riften, Understone Keep in Markarth, and
a quiet spot of each of the other four. The inn spot is kept for staff, as
`/tp <town> inn`. A death wakes them at the nearest temple or Hall of the
Dead instead. See [Death](death.md).

Nothing about a character is chosen in the launcher. Skyrim's own
levelling is off, so the face menu does not start a perk tree.

## Changing character in the game

Change character, at the foot of the K panel, goes back to the same
choice without closing the game (#3128). Patrick settled it on 22 October
2026: any time out of combat, after ten seconds in place. A line a second
counts down; moving, a fight, getting hurt or dying stops it, and so does
pressing it again. At the end the world closes as it does when somebody
quits, the game goes to its main menu and the slots come back with the
character just left lit. A slot plays that character, an empty one makes a
new one in the hall, and the bin forgets one, as at the start of a game.
The button is not there while a character is being made.

A pick there moves the chat, voice and the join pass to the character
picked, and the launcher writes the list again after each pick and each
forget, checks in the id New character uses next, and counts the time
played against each character in turn.

## Where this is

The hall, the face, the K panel, the town, the waiting class and
profession, the 40 gold and the four tools are in the server: the
pickaxe, the woodcutter's axe, the shovel, and the crude fishing pole
a new fisher is handed, without which the water turns them away. The
farmer's seed is handed with the shovel. The public
steps are on the site's help page.

Somebody still choosing who puts the panel down gets it back on its
own: ten minutes after Escape or K, and within thirty seconds when it
went any other way. It comes back whether or not anything on it has
changed.
