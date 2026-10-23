'use strict';
// One shape for a character's form id (#2870). A runtime form's formDesc is
// its local hex alone; its runtime form id is 0xff000000 | local, the number
// mp.get(actorId) and the actor events carry. Every register that keeps a
// character stores that number, and every compare uses it, so a formDesc is
// turned into it here and nowhere else. A desc with a plugin is a placed
// form, never a character, and has no runtime form id: formIdOf gives 0.
//
// The same two functions are copied where one file has to stand alone (the
// gamemode's release helper and merchant purses, merchant-commission-state.js,
// scripts\vps\Delete-Person.ps1, scripts\vps\Server-Log.js and the two
// scripts\ops form id scripts), and ConvertFrom-ThornswoodFormDesc in
// scripts\ops\Release-List.ps1 is the PowerShell twin.
// tests\test-2870-form-id-shape.js fails when a copy differs from this one.
function formIdOf(desc) {
  if (typeof desc !== 'string' || !/^[0-9a-f]{1,6}$/i.test(desc)) return 0;
  var local = parseInt(desc, 16);
  return local > 0 ? 0xff000000 + local : 0;
}
function isFormId(n) {
  return Number.isSafeInteger(n) && n > 0xff000000 && n <= 0xffffffff;
}
module.exports = { formIdOf, isFormId };
