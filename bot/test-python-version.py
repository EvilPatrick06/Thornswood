"""
test-python-version.py

#2276: the bot and its tests need Python 3.10 or newer (the bot runs on
3.12). On a PC where plain `python` is an older one, bot.py must stop at once
with a plain message naming the fix, before any import that could fail in a
confusing way.

  1. python_too_old() says nothing on 3.10, 3.12 and later, and on 3.9 names
     the version, the path and py -3.12.
  2. The guard is the first thing bot.py runs: nothing but sys is imported
     before it.
  3. bot.py run by an old Python (a fake version, in a child) exits non-zero
     with that message and never reaches discord.

Never connects to anything.
"""
import ast
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BOT = os.path.join(HERE, 'bot.py')
PASS, FAIL = [], []


def yes(what, cond):
    (PASS if cond else FAIL).append(what)
    print(('PASS  ' if cond else 'FAIL  ') + what)


src = open(BOT, encoding='utf-8').read()
tree = ast.parse(src)
ns = {'sys': sys}
for node in tree.body:
    if isinstance(node, ast.Assign) and any(
            getattr(t, 'id', '') == 'PYTHON_MIN' for t in node.targets):
        exec(compile(ast.Module([node], []), BOT, 'exec'), ns)
    if isinstance(node, ast.FunctionDef) and node.name == 'python_too_old':
        exec(compile(ast.Module([node], []), BOT, 'exec'), ns)
too_old = ns.get('python_too_old')
yes('bot.py has python_too_old()', callable(too_old))

if callable(too_old):
    yes('3.12 is fine', too_old((3, 12, 10)) is None)
    yes('3.10 is fine', too_old((3, 10, 0)) is None)
    yes('3.14 is fine', too_old((3, 14, 5)) is None)
    said = too_old((3, 9, 13), r'C:\Python39\python.exe') or ''
    yes('3.9 is refused, naming the version, the path and py -3.12 (%s)' % said,
        '3.9.13' in said and 'Python39' in said and 'py -3.12' in said
        and '3.10 or newer' in said)

# 2. Nothing but sys imported before the guard runs.
first_guard = None
before = []
for i, node in enumerate(tree.body):
    if isinstance(node, ast.If) and 'python_too_old' in ast.dump(node.test):
        first_guard = i
        break
    if isinstance(node, (ast.Import, ast.ImportFrom)):
        before += [a.name for a in node.names] if isinstance(node, ast.Import) \
            else [node.module]
yes('the guard runs before any import but sys (%s)' % before,
    first_guard is not None and before == ['sys'])

# 3. Run for real with an old version faked, in a child Python.
child = (
    'import sys, runpy\n'
    'class V(tuple):\n'
    '    major, minor = 3, 9\n'
    'sys.version_info = V((3, 9, 13, "final", 0))\n'
    'sys.modules.pop("discord", None)\n'
    'class Stop(object):\n'
    '    def find_module(self, n, p=None):\n'
    '        return None\n'
    '    def find_spec(self, n, p=None, t=None):\n'
    '        if n == "discord": raise ImportError("reached discord")\n'
    '        return None\n'
    'sys.meta_path.insert(0, Stop())\n'
    'sys.argv = [%r]\n'
    'runpy.run_path(%r, run_name="__main__")\n' % (BOT, BOT))
env = dict(os.environ, DISCORD_TOKEN='not-a-real-token')
p = subprocess.run([sys.executable, '-c', child], capture_output=True,
                   text=True, env=env, timeout=60)
out = (p.stdout or '') + (p.stderr or '')
yes('bot.py on a faked 3.9 exits non-zero with the plain message, before '
    'discord (exit %s)' % p.returncode,
    p.returncode != 0 and 'needs Python 3.10 or newer' in out
    and 'reached discord' not in out and 'Traceback' not in out)

print('%d passed, %d failed' % (len(PASS), len(FAIL)))
sys.exit(1 if FAIL else 0)
