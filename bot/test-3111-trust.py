"""
test-3111-trust.py

#3111: the roots the bot trusts, with the certifi requirements.txt pins and
the real bot.py import. tests\test-3111-bot-trust.js holds the same filter
on a fixture in the gate; this is the nightly half, with the bot's libraries.

  1. The certifi installed here is the one requirements.txt pins, so what is
     measured below is what the box runs.
  2. trust.write_bundle on certifi's own bundle keeps every root that is not
     eMudhra's, byte for byte and in order, and none that is, read back
     through ssl's own decoder.
  3. bot.py, imported in a child Python with its data folder in a scratch
     folder and SSL_CERT_FILE pointing somewhere else, writes roots.pem
     there over a planted file, and SSL_CERT_FILE and ssl's default cafile
     both name it afterwards, and the import prints nothing.

Never connects to anything.
"""
import _pyguard  # noqa: F401  (first: Python 3.11 or newer, #2276)
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

import certifi

import trust

HERE = os.path.dirname(os.path.abspath(__file__))
PASS, FAIL = [], []


def yes(what, cond, why=''):
    (PASS if cond else FAIL).append(what)
    print(('PASS  ' if cond else 'FAIL  ') + what + (('\n      ' + why) if why and not cond else ''))


def blocks(text):
    return re.findall(r'-----BEGIN CERTIFICATE-----\s.*?-----END CERTIFICATE-----', text, re.S)


# 1. the pin
req = open(os.path.join(HERE, 'requirements.txt'), encoding='utf-8').read()
pinned = re.search(r'^certifi==(\S+)', req, re.M).group(1)
yes('the certifi installed (%s) is the one requirements.txt pins (%s)' % (certifi.__version__, pinned),
    [int(x) for x in certifi.__version__.split('.')] == [int(x) for x in pinned.split('.')])

scratch = tempfile.mkdtemp(prefix='test-3111-')
try:
    # 2. certifi's bundle through the filter
    source = open(certifi.where(), encoding='ascii').read()
    every = blocks(source)
    theirs = [b for b in every if trust.distrusted(trust.describe(b))]
    ours = [b for b in every if not trust.distrusted(trust.describe(b))]
    dest = os.path.join(scratch, 'roots.pem')
    count, out = trust.write_bundle(dest)
    written = blocks(open(dest, encoding='ascii').read())
    yes('certifi %s carries %d roots, %d of them eMudhra\'s: %s' % (
        certifi.__version__, len(every), len(theirs), ', '.join(out) or 'none'),
        len(every) > 100 and len(out) == len(theirs))
    yes('every root that is not eMudhra\'s is written, byte for byte and in order',
        written == ours and count == len(ours))
    orgs = [trust.describe(b)['subject'].get('organizationName', '') for b in written]
    yes('none written is eMudhra\'s, read back through ssl',
        not [o for o in orgs if 'emudhra' in o.lower()] and not re.search('emsign|emudhra', open(dest).read(), re.I))

    # 3. the real import
    data = os.path.join(scratch, 'data')
    os.makedirs(data)
    planted = os.path.join(data, 'roots.pem')
    with open(planted, 'w') as f:
        f.write('planted by the harness\n')
    elsewhere = os.path.join(scratch, 'elsewhere.pem')
    shutil.copy(certifi.where(), elsewhere)
    env = dict(os.environ, THORNSWOOD_BOT_DATA=data, SSL_CERT_FILE=elsewhere,
               REQUESTS_CA_BUNDLE=elsewhere, DISCORD_TOKEN='not-a-real-token')
    probe = ('import json, os, ssl, sys; sys.path.insert(0, sys.argv[1]); import bot; '
             'print(json.dumps({"env": os.environ["SSL_CERT_FILE"], "req": os.environ["REQUESTS_CA_BUNDLE"], '
             '"cafile": ssl.get_default_verify_paths().cafile}))')
    r = subprocess.run([sys.executable, '-c', probe, HERE], env=env, capture_output=True, text=True, timeout=120)
    said = {}
    try:
        said = json.loads(r.stdout.strip().splitlines()[-1])
    except (ValueError, IndexError):
        pass
    yes('bot.py imports with its data folder and SSL_CERT_FILE elsewhere', r.returncode == 0 and said,
        (r.stdout + r.stderr)[-800:])
    same = lambda p: bool(p) and os.path.normcase(os.path.abspath(p)) == os.path.normcase(planted)
    yes('SSL_CERT_FILE, REQUESTS_CA_BUNDLE and ssl\'s default cafile all name data\\roots.pem afterwards',
        same(said.get('env')) and same(said.get('req')) and same(said.get('cafile')), json.dumps(said))
    text = open(planted, encoding='ascii').read()
    yes('the planted roots.pem was written over with the bundle, and it holds no eMudhra root',
        'planted' not in text and blocks(text) == ours)
    yes('and imported, it prints nothing, so a tool reading bot.py\'s output reads only its own',
        r.stdout.strip().count('\n') == 0)
    run = open(os.path.join(HERE, 'bot.py'), encoding='utf-8').read()
    main = run[run.rindex("\nif __name__ == '__main__':"):]
    yes('run as the bot, it logs how many roots it trusts and which it left out, before it connects',
        "log('trusting %d root certificates from %s, leaving out %s' % (" in main
        and main.index('trusting %d root') < main.index('client.run(TOKEN)'))
finally:
    shutil.rmtree(scratch, ignore_errors=True)

print('')
print('%d passed, %d failed' % (len(PASS), len(FAIL)))
sys.exit(1 if FAIL else 0)
