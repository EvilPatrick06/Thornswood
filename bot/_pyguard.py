"""
_pyguard.py

The one Python version check for the bot and every bot test (#2276). Import
it first, before anything else:

    import _pyguard  # noqa: F401

The bot runs on Python 3.12 (Install-Bot.ps1, bot/requirements.txt), and what
it pins needs 3.10 or newer: Pillow 12 will not install on less. An older
Python fails later and far from the cause (an AttributeError deep in a test),
so it is refused here, at import, in plain words. On a Windows PC with more
than one Python, plain python is whichever is first on PATH; py -3.12 picks
the right one.

Standard library only, and nothing that will not parse on an old Python, so
the message is what an old Python sees.
"""
import sys

PYTHON_MIN = (3, 10)


def python_too_old(version=None, exe=None):
    """None when this Python can run the bot, else what to tell the person."""
    v = tuple(version or sys.version_info)[:3]
    if v[:2] >= PYTHON_MIN:
        return None
    return ('The Thornswood bot needs Python %d.%d or newer (it runs on 3.12), '
            'and this is Python %s at %s. On Windows, run it with py -3.12 '
            'instead of python.' % (PYTHON_MIN + ('.'.join(str(x) for x in v),
                                    exe or sys.executable)))


def require():
    said = python_too_old()
    if said:
        raise SystemExit(said)


require()
