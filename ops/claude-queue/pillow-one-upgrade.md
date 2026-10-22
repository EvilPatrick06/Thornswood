# Pillow on One: bot tests run under the wrong python

Lane: Waystone (found while testing #2276)
Box: One (Patrick's desktop), not the bot host

## Finding
- bot/test-join-card.py calls Image.get_flattened_data(). Pillow first added it in 12.1.0 (2026-01-02), the same release that deprecated getdata().
- bot/requirements.in pins pillow==12.3.0, and bot/requirements.txt pins it by version and sha256 hash (#2190). So the requirements are fine.
- On One, plain `python` is Python 3.9 (C:\Users\evilp\AppData\Local\Programs\Python\Python39), which has Pillow 11.2.1. That is why test-join-card.py fails there with AttributeError get_flattened_data.
- Pillow 12 needs Python 3.10 or newer, so Pillow cannot be upgraded on the 3.9 install at all.
- The bot targets Python 3.12 (requirements.txt header, build.yml and build-pr.yml use 3.12). On One, `py -3.12` already has pillow 12.3.0 and discord.py 2.7.1. With it, test-join-card.py gives 42 passed, 0 failed.

## Claude steps
1. On One, make sure Python 3.12 has the pinned set (it should already):
   py -3.12 -m pip install --require-hashes --only-binary :all: -r C:\ThornswoodTemps&Worktrees\Thornswood\bot\requirements.txt
2. Verify, from the repo's bot folder:
   py -3.12 bot\test-join-card.py     (expect 42 passed, 0 failed)
3. Optional, and Patrick's call: put Python 3.12 ahead of 3.9 on PATH, or remove 3.9, so a plain `python` runs 3.12. Until then, lanes run bot tests with `py -3.12`.

## Risks
- Do not try `python -m pip install pillow>=12.1` on 3.9. pip will either refuse or leave 11.x, because Pillow 12 needs Python 3.10 or newer.
- Changing PATH or removing 3.9 could break other tools on One that use 3.9. Check before you change it.
- The bot host should already be on 3.12 with the hashed requirements from #2190. If its install is older, it needs the same requirements install there, as part of the normal bot install.
- Requirements already pin Pillow, so no requirements change is needed.
