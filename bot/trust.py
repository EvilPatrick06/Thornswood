"""
trust.py

The root certificates the bot trusts (issue #3111). bot.py writes this file's
bundle at every start, before anything opens a connection, and makes every
connection, discord.py's, aiohttp's and urllib's, through context() on it.

It is certifi's bundle (Mozilla's roots, pinned by hash in requirements.txt)
with every root whose subject or issuer names an organisation in DISTRUSTED
left out.

Why eMudhra is left out, measured 21 Oct 2026:

  - On 17 Oct eight eMudhra intermediates were found with private keys anyone
    could recover (Mozilla bug 2083449): six TLS ones under emSign Root TLS
    CA - G3 and two code signing ones. Mozilla removed emSign ECC Root CA -
    G3 in an emergency (bug 2084101, NSS 3.131.1).
  - certifi 2026.10.18 dropped all four emSign roots. 2026.10.19 put back
    emSign Root CA - G1, emSign Root CA - C1 and emSign ECC Root CA - C3
    (certifi commit 662df63, "Restore unaffected emSign roots"), because
    certifi follows Mozilla and Mozilla still lists them: it said it is not
    removing G1 "at this time", and C1 and C3 come out in NSS 3.132 at
    eMudhra's own request (bug 2083709).
  - Nothing the bot talks to chains to eMudhra: discord.com and its gateway,
    api.github.com, thornswood.net (Let's Encrypt) and the ping address. A
    root it never needs, from a CA whose key ceremony just failed, is trust
    the bot gives away for nothing, so the bot does not give it.

Following certifi still matters: a root Mozilla removes for any other reason
leaves with the next pinned certifi. This list only takes away, it never adds.

Standard library only here; certifi is imported by bundle_text(), so the
harness can run the filter on a fixture without the bot's libraries.

    python trust.py [BUNDLE]

says what the bundle (certifi's when none is named) keeps and leaves out, and
writes nothing. Install-Bot.ps1 runs it against the libraries it installed.
"""
import os
import re
import ssl
import sys

# Matched, ignoring case, against the organisation (O=) in each root's
# subject and issuer. eMudhra signs as "eMudhra Technologies Limited" and
# "eMudhra Inc".
DISTRUSTED = ('eMudhra',)

_PEM = re.compile(r'-----BEGIN CERTIFICATE-----\s.*?-----END CERTIFICATE-----', re.S)


def _names(cert, field):
    return dict(kv for rdn in cert.get(field, ()) for kv in rdn)


def describe(pem):
    """The subject and issuer of one PEM root, as ssl decodes them."""
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.load_verify_locations(cadata=pem)
    certs = ctx.get_ca_certs()
    if len(certs) != 1:
        raise ValueError('expected one CA certificate, read %d from:\n%s' % (len(certs), pem[:200]))
    return {'subject': _names(certs[0], 'subject'), 'issuer': _names(certs[0], 'issuer')}


def distrusted(info):
    """The DISTRUSTED entry this root falls under, or None."""
    orgs = (info['subject'].get('organizationName', ''), info['issuer'].get('organizationName', ''))
    for name in DISTRUSTED:
        if any(name.lower() in o.lower() for o in orgs):
            return name
    return None


def label(info):
    s = info['subject']
    return s.get('commonName') or s.get('organizationalUnitName') or s.get('organizationName') or '?'


def split(text):
    """(kept PEM text, kept count, [names left out]) for a bundle's text."""
    kept, out = [], []
    for m in _PEM.finditer(text):
        pem = m.group(0)
        info = describe(pem)
        if distrusted(info):
            out.append(label(info))
        else:
            kept.append(pem)
    if not kept:
        raise ValueError('no root certificate is left to trust')
    return '\n'.join(kept) + '\n', len(kept), out


def bundle_text(source=None):
    if source is None:
        import certifi
        source = certifi.where()
    with open(source, encoding='ascii') as f:
        return f.read()


def write_bundle(path, source=None):
    """
    Writes the trusted roots to path, whole or not at all, and returns
    (count kept, [names left out]). Rewritten at every start from certifi
    and this file, both read only to the bot's account, so a file left at
    path by anything else is never what the bot trusts.
    """
    text, count, out = split(bundle_text(source))
    tmp = path + '.tmp'
    with open(tmp, 'w', encoding='ascii', newline='\n') as f:
        f.write(text)
    os.replace(tmp, path)
    return count, out


def context(path):
    """
    A client SSL context that trusts the roots in path and nothing else.
    Given a file, ssl.create_default_context loads only that file; given
    none, on Windows it also loads the machine's certificate stores, and the
    box's LocalMachine Root store holds emSign Root CA - G1 (read 21 Oct).
    """
    return ssl.create_default_context(cafile=path)


if __name__ == '__main__':
    _, count, out = split(bundle_text(sys.argv[1] if len(sys.argv) > 1 else None))
    print('trusts %d roots' % count)
    for name in out:
        print('leaves out ' + name)
