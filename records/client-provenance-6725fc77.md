# Client provenance at 6725fc77

The canonical fork commit is `6725fc778a99b2cf344426afb8158df500b7ad6f`, merged
through native PR 8. The native worktree's source tree matches the reviewed and
tested PR head `ad31917923bd08e04e5143662d52fbd67ac9a876` exactly.

MpClientPlugin was relinked with the canonical native archive. The link map
confirms that updated server-only members remain unreachable from the client.
The other five runtime files retain their verified baseline hashes because
their source and build inputs are unchanged. The six hashes and sizes are in
client-build.json. The DLL hash is
`0fd1d604101d3b31f3250ff72b0686a6df2061e738bc762942cf73fbb8b46105`.

Evidence is under build/npc-client-verification in the native worktree:
isolated archives, link-client.rsp and MpClientPlugin.map. Native verification
passed 478,784 assertions across 342 cases. These checks did not start the
game or launcher.
