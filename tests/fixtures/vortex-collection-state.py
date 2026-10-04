"""Real compressed LevelDB fixtures for installed collection revision metadata."""
import pathlib
import runpy
import struct
import sys
import json

tools = runpy.run_path(str(pathlib.Path(__file__).with_name('vortex-profile-state.py')))
fixture, record, lp = (tools[n] for n in ('fixture', 'record', 'lp'))
root = pathlib.Path(sys.argv[1])
mod = 'persistent###mods###skyrimse###collection_current###attributes###'
author = 'persistent###mods###skyrimse###vortex_collection_local###attributes###'
cache = 'collections###revisions###123###info###'


def rows(values, sequence=10):
    return [(k.encode() + struct.pack('<Q', ((sequence+i) << 8) | 1), json.dumps(v).encode())
            for i, (k, v) in enumerate(values.items())]


def batch(k, value=None, deleted=False, sequence=30):
    return struct.pack('<QI', sequence, 1) + bytes([not deleted]) + lp(k.encode()) + (b'' if deleted else lp(json.dumps(value).encode()))


base = {mod+'collectionSlug': '7essxf', mod+'revisionNumber': 2}
fixture(root, 'collection-compressed', rows(base))
fixture(root, 'collection-updated', rows(base), record(batch(mod+'revisionNumber', 3)))
fixture(root, 'collection-downgraded', rows(base), record(batch(mod+'revisionNumber', 1)))
fixture(root, 'collection-deleted', rows(base), record(batch(mod+'collectionSlug', deleted=True)))
fixture(root, 'collection-revision-deleted', rows(base), record(batch(mod+'revisionNumber', deleted=True)))
fixture(root, 'collection-other-slug', rows(base), record(batch(mod+'collectionSlug', 'other')))
fixture(root, 'collection-mixed', rows({**base, mod.replace('collection_current', 'collection_other')+'collectionSlug': 'other', mod.replace('collection_current', 'collection_other')+'revisionNumber': 99}))
fixture(root, 'collection-latest-not-installed', rows({**base, mod+'newestFileId': 123, mod+'newestVersion': '99', cache+'collection###slug': '7essxf', cache+'revisionNumber': 99}))
directory = fixture(root, 'collection-obsolete', rows(base))
(directory / '000099.ldb').write_bytes(tools['table'](rows({mod+'collectionSlug': '7essxf', mod+'revisionNumber': 99}, 100)))
linked = {author+'newestFileId': 123, author+'newestVersion': '2', cache+'collection###slug': '7essxf', cache+'revisionNumber': 2}
fixture(root, 'collection-authoring', rows(linked))
fixture(root, 'collection-authoring-version', rows({k:v for k,v in linked.items() if k != cache+'revisionNumber'}))
fixture(root, 'collection-authoring-numeric-version', rows({**{k:v for k,v in linked.items() if k != cache+'revisionNumber'}, author+'newestVersion': 2}))
fixture(root, 'collection-cache-only', rows({cache+'collection###slug': '7essxf', cache+'revisionNumber': 99}))
fixture(root, 'collection-ordinary-mod-cache', rows({k.replace(author, mod):v for k,v in linked.items()}))
fixture(root, 'collection-other-author', rows({**linked, cache+'collection###slug': 'other'}))
fixture(root, 'collection-author-link-deleted', rows(linked), record(batch(author+'newestFileId', deleted=True)))
for label, value in [('negative', -2), ('zero', 0), ('fraction', 2.5), ('overflow', 99999999999), ('string-revision', '2')]:
    fixture(root, 'collection-'+label, rows({**base, mod+'revisionNumber': value}))
directory = fixture(root, 'collection-corrupt', rows(base))
data = bytearray((directory / '000001.ldb').read_bytes()); data[0] ^= 1
(directory / '000001.ldb').write_bytes(data)
fixture(root, 'collection-partial', rows(base), record(batch(mod+'revisionNumber', 3))[:-4])
