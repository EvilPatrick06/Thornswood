"""
test-python-version.py

#2276: the bot and its tests need Python 3.10 or newer (the bot runs on
3.12). The check is one shared module, _pyguard.py.

  1. python_too_old() says nothing on 3.10, 3.12 and later, and on 3.9 names
     the version, the path and py -3.12.
  2. bot.py and every bot/test-*.py import _pyguard as their first import,
     before anything else.
  3. bot.py and every bot/test-*.py, run on a faked 3.9 in a child Python,
     stop with that message: non-zero, no traceback, never reaching discord.
  4. Install-Bot.ps1 sends _pyguard.py with bot.py.

Never connects to anything.
"""
import _pyguard  # noqa: F401  (first: Python 3.10 or newer, #2276)
import ast
import glob
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PASS, FAIL = [], []


def yes(what, cond):
    (PASS if cond else FAIL).append(what)
    print(('PASS  ' if cond else 'FAIL  ') + what)


too_old = _pyguard.python_too_old
yes('3.12 is fine', too_old((3, 12, 10)) is None)
yes('3.10 is fine', too_old((3, 10, 0)) is None)
yes('3.14 is fine', too_old((3, 14, 5)) is None)
said = too_old((3, 9, 13), r'C:\Python39\python.exe') or ''
yes('3.9 is refused, naming the version, the path and py -3.12',
    '3.9.13' in said and 'Python39' in said and 'py -3.12' in said
    and '3.10 or newer' in said)


def first_import(path):
    tree = ast.parse(open(path, encoding='utf-8').read(), path)
    for node in tree.body:
        if isinstance(node, ast.Import):
            return node.names[0].name
        if isinstance(node, ast.ImportFrom):
            return node.module
        if not (isinstance(node, ast.Expr)
                and isinstance(getattr(node, 'value', None), ast.Constant)):
            return '(code before any import: %s)' % type(node).__name__
    return None


files = [os.path.join(HERE, 'bot.py')] + sorted(
    glob.glob(os.path.join(HERE, 'test-*.py')))
wrong = [os.path.basename(f) for f in files if first_import(f) != '_pyguard']
yes('bot.py and all %d bot tests import _pyguard first (wrong: %s)'
    % (len(files) - 1, wrong), not wrong and len(files) > 20)

CHILD = (
    'import sys, runpy\n'
    'sys.version_info = (3, 9, 13, "final", 0)\n'
    'class Stop(object):\n'
    '    def find_module(self, n, p=None):\n'
    '        return None\n'
    '    def find_spec(self, n, p=None, t=None):\n'
    '        if n.split(".")[0] in ("discord", "PIL", "bot", "card"):\n'
    '            raise ImportError("reached " + n)\n'
    '        return None\n'
    'sys.meta_path.insert(0, Stop())\n'
    'sys.path.insert(0, %r)\n'
    'sys.argv = [sys.argv[1]]\n'
    'runpy.run_path(sys.argv[0], run_name="__main__")\n' % HERE)
env = dict(os.environ, DISCORD_TOKEN='not-a-real-token')
bad = []
for f in files:
    p = subprocess.run([sys.executable, '-c', CHILD, f], capture_output=True,
                       text=True, env=env, timeout=60)
    out = (p.stdout or '') + (p.stderr or '')
    if not (p.returncode != 0 and 'needs Python 3.10 or newer' in out
            and 'reached ' not in out and 'Traceback' not in out):
        bad.append('%s (exit %s: %s)' % (os.path.basename(f), p.returncode,
                                         out.strip()[-160:]))
yes('on a faked 3.9, bot.py and every bot test stop with the plain message '
    'and nothing else (%d run; bad: %s)' % (len(files), bad), not bad)

install = open(os.path.join(HERE, '..', 'scripts', 'deploy', 'Install-Bot.ps1'),
               encoding='utf-8').read()
yes('Install-Bot.ps1 sends and checks _pyguard.py with bot.py',
    "'bot/_pyguard.py'" in install
    and "foreach ($f in 'bot.py', '_pyguard.py'," in install
    and "@('bot.py', '_pyguard.py', 'card.py')" in install)

print('%d passed, %d failed' % (len(PASS), len(FAIL)))
sys.exit(1 if FAIL else 0)
