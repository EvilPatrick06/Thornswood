'use strict';
// Role admission does not retire actors or write economy state.
function prepareMerchantRoleStage(population,catalog,stage,native) {
  const roles=['Smith','Woodworker','Tailor','Enchanter','Cook','Alchemist'];
  const holds={whiterun:'Whiterun',solitude:'Haafingar',riften:'the Rift',markarth:'the Reach',
    windhelm:'Eastmarch',morthal:'Hjaalmarch',dawnstar:'the Pale',winterhold:'Winterhold',
    falkreath:'Falkreath',ravenrock:'Solstheim'};
  const fail=()=>{throw new Error('Merchant role stage cannot be verified');};
  const object=value=>value!==null && typeof value==='object' && !Array.isArray(value);
  const own=(value,key)=>Object.prototype.hasOwnProperty.call(value,key);
  const identity=value=>typeof value==='string' && /^([1-9a-f][0-9a-f]{0,5}):[^:/\\\x00-\x1f\x7f]+\.(esm|esp|esl)$/i.test(value);
  // No supplied native callback can replace the source being admitted.
  [population,catalog,stage]=JSON.parse(JSON.stringify([population,catalog,stage]));
  if(!object(population) || !object(stage))fail();
  const retirement=population.merchantRoster!==undefined,count=retirement?60:249;
  if(retirement && (!object(population.merchantRoster) || population.merchantRoster.version!==1 ||
      !['existing','alpha'].includes(population.merchantRoster.worldMode) || Object.keys(population.merchantRoster).length!==2 ||
      JSON.stringify(population.merchantHistory)!==JSON.stringify(stage.history)))fail();
  if(!object(stage) || stage.version!==1 || !Array.isArray(stage.history) || stage.history.length!==249 ||
      !Array.isArray(stage.merchants) || stage.merchants.length!==60 || !object(stage.tables) ||
      !object(stage.types) || !object(catalog) || catalog.count!==count || !object(catalog.byRef) ||
      Object.keys(catalog.byRef).length!==count || !object(population) || !Array.isArray(population.keep) ||
      !native || typeof native.resolveMerchant!=='function' ||
      typeof native.resolveItem!=='function') fail();
  const rows=new Map(),history=new Map(),selected=new Map(),coverage=new Set();
  for(const row of population.keep) {
    if(!Array.isArray(row) || rows.has(row[0]))fail();
    rows.set(row[0],row);
  }
  for(const pair of stage.history) {
    if(!Array.isArray(pair) || pair.length!==2 || !pair.every(identity) || history.has(pair[0]))fail();
    const row=rows.get(pair[0]);
    if(!retirement && !row || row && (row[6]!=='trader' || row[1]!==pair[1] || !own(catalog.byRef,pair[0])))fail();
    history.set(pair[0],pair[1]);
  }
  if(population.keep.filter(row=>row[6]==='trader').length!==count ||
      Object.keys(catalog.byRef).some(ref=>!history.has(ref)))fail();
  for(const merchant of stage.merchants) {
    if(!object(merchant) || Object.keys(merchant).sort().join(',')!=='base,bookHold,hold,reference,role' ||
        history.get(merchant.reference)!==merchant.base || !rows.has(merchant.reference) ||
        !own(catalog.byRef,merchant.reference) || selected.has(merchant.reference) ||
        !roles.includes(merchant.role) || !own(holds,merchant.bookHold) || holds[merchant.bookHold]!==merchant.hold ||
        catalog.byRef[merchant.reference].hold!==merchant.hold ||
        catalog.byRef[merchant.reference].bookHold!==merchant.bookHold || coverage.has(merchant.bookHold+':'+merchant.role))fail();
    selected.set(merchant.reference,merchant);coverage.add(merchant.bookHold+':'+merchant.role);
  }
  const items=new Set(),directions=['buy','sell','supply'];
  if(Object.keys(stage.tables).length!==6 || roles.some(role=>!own(stage.tables,role)))fail();
  for(const role of roles) {
    const table=stage.tables[role];
    if(!object(table) || Object.keys(table).sort().join(',')!=='buy,sell,supply')fail();
    for(const direction of directions) {
      const values=table[direction];
      if(!Array.isArray(values) || new Set(values).size!==values.length)fail();
      for(const desc of values) {
        if(!identity(desc) || parseInt(desc,16)===15 && desc.split(':')[1].toLowerCase()==='skyrim.esm' || !own(stage.types,desc) ||
            !['ALCH','AMMO','ARMO','BOOK','INGR','KEYM','MISC','SCRL','SLGM','WEAP'].includes(stage.types[desc]))fail();
        items.add(desc);
      }
    }
    if(table.supply.some(desc=>!table.buy.includes(desc)))fail();
  }
  const resolved=new Map(),ids=new Map();
  function remember(desc,id) {
    if(!Number.isInteger(id) || id<=0 || id>=0xff000000 || ids.has(id) && ids.get(id)!==desc)fail();
    ids.set(id,desc);resolved.set(desc,id);return id;
  }
  for(const merchant of selected.values()) remember(merchant.reference,native.resolveMerchant(merchant.reference,merchant.base));
  for(const desc of items) {
    const id=remember(desc,native.resolveItem(desc,stage.types[desc]));if(id===15)fail();
  }
  const roleTables={};
  for(const role of roles) {
    roleTables[role]={};
    for(const direction of directions)roleTables[role][direction]=stage.tables[role][direction].map(desc=>resolved.get(desc));
  }
  population.merchantRoles={};
  for(const merchant of selected.values()) {
    Object.assign(catalog.byRef[merchant.reference],{name:merchant.role,role:merchant.role});
    rows.get(merchant.reference)[13]=merchant.role;
    population.merchantRoles[merchant.reference]=merchant.role;
  }
  return {population,catalog,roleTables};
}
module.exports={prepareMerchantRoleStage};
