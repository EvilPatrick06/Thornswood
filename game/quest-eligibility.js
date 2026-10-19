'use strict';
// Pure eligibility for the expanded catalogue. The caller owns session fences
// and reads saved state without entering character initialization or migration.
function record(value) {
  return !!value && typeof value === 'object' && !Array.isArray(value);
}
function field(value, key) {
  if (!record(value)) return undefined;
  var desc = Object.getOwnPropertyDescriptor(value, key);
  return desc && desc.enumerable && Object.prototype.hasOwnProperty.call(desc, 'value') ? desc.value : undefined;
}
function strings(value) {
  if (!Array.isArray(value)) return null;
  var out = [];
  for (var i = 0; i < value.length; i++) {
    var desc = Object.getOwnPropertyDescriptor(value, i);
    if (!desc || !desc.enumerable || !Object.prototype.hasOwnProperty.call(desc, 'value') ||
        typeof desc.value !== 'string') return null;
    out.push(desc.value);
  }
  return out;
}
function createQuestEligibility(source) {
  var table, spellIds;
  try {
    table = JSON.parse(JSON.stringify(source.table));
    spellIds = JSON.parse(JSON.stringify(source.spellIds));
    if (!record(table) || !Array.isArray(table.ranks) ||
        table.ranks.join(',') !== 'novice,advanced,expert,master' ||
        !record(table.classes) || !record(table.professions) ||
        !Array.isArray(table.schools) || !record(table.spells) || !record(spellIds)) throw Error('metadata');
  } catch (error) { throw new Error('Invalid quest eligibility metadata.'); }
  var ranks = table.ranks;
  function validate(gate) {
    function invalid() { throw new Error('Invalid quest gate.'); }
    if (!record(gate)) return invalid();
    var prototype = Object.getPrototypeOf(gate);
    if (prototype !== null && prototype !== Object.prototype) return invalid();
    var keys = Reflect.ownKeys(gate), out = Object.create(null);
    keys.forEach(function (key) {
      if (['open', 'classKey', 'profession', 'rank', 'half', 'school'].indexOf(key) < 0 ||
          (key === 'open' ? field(gate, key) !== true : typeof field(gate, key) !== 'string')) invalid();
      out[key] = field(gate, key);
    });
    if (keys.length === 1 && out.open === true) return Object.freeze(out);
    if (field(out, 'open') !== undefined || ranks.indexOf(out.rank) < 0) return invalid();
    if (field(out, 'classKey') !== undefined) {
      if (keys.length !== 2 || !field(table.classes, out.classKey)) return invalid();
    } else {
      var profession = field(table.professions, out.profession);
      if (!record(profession)) return invalid();
      if (out.profession === 'mage') {
        if (field(out, 'half') !== undefined || keys.length !== (field(out, 'school') === undefined ? 2 : 3) ||
            field(out, 'school') !== undefined && table.schools.indexOf(out.school) < 0 ||
            out.rank === 'master' && field(out, 'school') === undefined) return invalid();
      } else if (field(out, 'school') !== undefined ||
          keys.length !== (field(out, 'half') === undefined ? 2 : 3) ||
          !record(profession.halves) || field(out, 'half') !== undefined && !field(profession.halves, out.half) ||
          out.rank === 'master' && field(out, 'half') === undefined) return invalid();
    }
    return Object.freeze(out);
  }
  function allows(gate, state) {
    try {
      gate = validate(gate);
      if (gate.open === true) return true;
      var standing = field(state, 'ranks');
      if (field(state, 'v') !== 1 || !record(standing)) return false;
      function hasRank(key) {
        var index = ranks.indexOf(field(standing, key));
        return index >= 0 && index >= ranks.indexOf(gate.rank);
      }
      if (field(gate, 'classKey') !== undefined) {
        return field(state, 'cls') === gate.classKey && hasRank(gate.classKey);
      }
      if (field(state, 'prof') !== gate.profession) return false;
      if (gate.profession !== 'mage') {
        var halves = Object.keys(table.professions[gate.profession].halves);
        return field(gate, 'half') !== undefined ? hasRank(gate.half) : halves.some(hasRank);
      }
      var schools = strings(field(state, 'schools'));
      if (!schools || schools.some(function (s) {return table.schools.indexOf(s) < 0;})) return false;
      var selected = field(gate, 'school') !== undefined ? [gate.school] : schools;
      return selected.some(function (school) {
        if (schools.indexOf(school) < 0 || !hasRank(school)) return false;
        if (gate.rank !== 'master') return true;
        var known = strings(field(field(state, 'spells'), 'known'));
        var master = field(field(table.spells, school), 'master');
        return !!known && Array.isArray(master) && known.some(function (name) {
          var desc = field(spellIds, name);
          return typeof name === 'string' && master.indexOf(name) >= 0 && typeof desc === 'string' &&
            /^[0-9a-f]{1,6}:[^:\r\n]+\.(?:esm|esp|esl)$/i.test(desc);
        });
      });
    } catch (error) { return false; }
  }
  return Object.freeze({validate: validate, allows: allows});
}
module.exports = {createQuestEligibility: createQuestEligibility};
