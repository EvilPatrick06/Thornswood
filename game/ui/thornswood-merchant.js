'use strict';
/*
  The guild trader panel.

  The server owns the purse, the shelf and the price. This page only draws
  what /merchant already checked and sends the same command back. It cannot
  move gold or goods. People cannot join the guild from here.
*/
(function () {
  if (window.thornswoodMerchant) { return; }
  var ID = 'ts-merchant';
  var data = null;
  var shown = false;
  var root = null;
  var gemChoices = {};

  function tell(what) {
    try { window.skyrimPlatform.sendMessage('thornswood-front', 'merchant:' + what); }
    catch (e) { }
  }
  function net(line) {
    try {
      if (window.thornswoodNet && window.thornswoodNet.say) {
        window.thornswoodNet.say(line);
        return true;
      }
    } catch (e) { }
    return false;
  }
  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  var CSS = [
    '#' + ID + '{position:fixed;inset:0;z-index:2147483000;display:none;',
    '  background:radial-gradient(ellipse at center,rgba(0,0,0,.50) 0%,rgba(0,0,0,.72) 100%);',
    '  font-family:"Palatino Linotype",Palatino,Georgia,serif;color:#d9cfb4}',
    '#' + ID + '.on{display:grid;place-items:center}',
    '#' + ID + ' .panel{width:760px;max-width:calc(100vw - 48px);max-height:calc(100vh - 48px);',
    '  display:grid;grid-template-rows:auto 1fr auto;background:rgba(11,10,8,.94);',
    '  border:1px solid rgba(198,170,109,.42);outline:1px solid rgba(198,170,109,.14);',
    '  outline-offset:4px;box-shadow:0 24px 80px rgba(0,0,0,.7);overflow:hidden}',
    '#' + ID + ' h2{margin:0;padding:18px 24px 14px;font-size:26px;font-weight:normal;',
    '  color:#f6e9c8;border-bottom:1px solid rgba(198,170,109,.22)}',
    '#' + ID + ' .body{overflow:auto;padding:14px 18px;font-size:16px}',
    '#' + ID + ' .note{color:rgba(217,207,180,.75);font-style:italic;margin:0 0 12px}',
    '#' + ID + ' .line{display:flex;gap:8px;align-items:center;flex-wrap:wrap;padding:10px 12px;',
    '  border:1px solid rgba(198,170,109,.30);background:rgba(0,0,0,.20);margin-bottom:8px}',
    '#' + ID + ' .nm{flex:1;min-width:140px}',
    '#' + ID + ' h3{font-size:20px;font-weight:normal;color:#f6e9c8;margin:16px 0 10px}',
    '#' + ID + ' .quest-copy{flex:1;min-width:240px}',
    '#' + ID + ' .quest-copy p{margin:4px 0;font-size:14px;line-height:1.5}',
    '#' + ID + ' select{font:inherit;color:#f6e9c8;background:#17140f;border:1px solid #ac9564;padding:6px;max-width:100%}',
    '#' + ID + ' button{font-family:inherit;cursor:pointer;border:1px solid rgba(198,170,109,.55);',
    '  background:rgba(0,0,0,.25);color:#e9d19b;padding:5px 10px;font-size:15px;line-height:20px;',
    '  letter-spacing:.14em;text-transform:uppercase}',
    '#' + ID + ' button:disabled{opacity:.45}',
    '#' + ID + ' .foot{padding:12px 20px;border-top:1px solid rgba(198,170,109,.22);',
    '  display:flex;gap:12px;align-items:center}'
  ].join('\n');

  function build() {
    if (root) { return root; }
    var style = document.createElement('style');
    style.textContent = CSS;
    document.head.appendChild(style);
    root = document.createElement('div');
    root.id = ID;
    root.innerHTML = '<div class="panel" role="dialog" aria-modal="true" aria-labelledby="' + ID + '-title"><h2 id="' + ID + '-title">Trader</h2>' +
      '<div class="body" id="' + ID + '-body"></div>' +
      '<div class="foot"><span id="' + ID + '-purse"></span><span style="flex:1"></span>' +
      '<button id="' + ID + '-close">Step back</button></div></div>';
    document.body.appendChild(root);
    root.querySelector('#' + ID + '-close').onclick = function () { net('/merchant close'); close(); };
    document.addEventListener('keydown', function (ev) {
      if (!shown) { return; }
      if (ev.key === 'Escape') { ev.preventDefault(); net('/merchant close'); close(); }
    });
    return root;
  }
  function draw() {
    build();
    if (!data || data.open === false) { close(); return; }
    root.className = 'on';
    shown = true;
    root.querySelector('#' + ID + '-title').textContent =
      (data.trader || 'Trader') + (data.place ? ' at ' + data.place : '');
    root.querySelector('#' + ID + '-purse').textContent = 'Purse ' + (data.purse == null ? '' : data.purse);
    var body = '';
    if (data.note) body += '<p class="note" role="status">' + esc(data.note) + '</p>';
    var quests = data.quests || [];
    if (quests.length) body += '<h3>Work from the guild</h3>';
    for (var q = 0; q < quests.length; q++) {
      var quest = quests[q];
      var location = typeof quest.locations === 'string' ? quest.locations : Object.keys(quest.locations || {}).map(function(gem){
        return gem + ': ' + quest.locations[gem];
      }).join('; ');
      if (quest.gem && quest.locations && typeof quest.locations === 'object') location = quest.locations[quest.gem] || location;
      var status = quest.state === 'open' ? ('Drawn ' + quest.drawn + ' of ' + quest.holds + (quest.gem ? ', ' + quest.gem : '')) :
        quest.state === 'cooldown' ? ('Returns in ' + quest.waitMinutes + ' minutes') : quest.state === 'locked' ? ('Requires ' + quest.who) : 'Available';
      body += '<div class="line"><div class="quest-copy"><strong>' + esc(quest.name) + '</strong>' +
        '<p>' + esc(location) + '</p><p>Draw up to ' + esc(quest.holds) + ', return ' + esc(quest.ask) +
        ' to finish, and keep the rest. Returns after ' + esc(quest.hours) + ' hours.</p><p>' + esc(status) + '</p></div>';
      if (quest.state === 'open') {
        body += '<button data-quest="' + esc(quest.id) + '" data-action="return"' + (quest.canReturn ? '' : ' disabled') + '>Turn in work</button>' +
          '<button data-quest="' + esc(quest.id) + '" data-action="abandon"' + (quest.canAbandon ? '' : ' disabled') + '>Give back and leave</button>';
      } else {
        var gems = quest.gems || [], chosen = gemChoices[quest.id] || '';
        if (gems.length) {
          body += '<select data-gem="' + esc(quest.id) + '" aria-label="Gem for ' + esc(quest.name) + '"' + (quest.canTake ? '' : ' disabled') + '><option value="">Choose a gem</option>';
          for (var g = 0; g < gems.length; g++) body += '<option value="' + esc(gems[g]) + '"' + (chosen === gems[g] ? ' selected' : '') + '>' + esc(gems[g]) + '</option>';
          body += '</select>';
        }
        body += '<button data-quest="' + esc(quest.id) + '" data-action="take" data-ready="' + (quest.canTake ? 'yes' : 'no') + '"' +
          (quest.canTake && (!gems.length || chosen) ? '' : ' disabled') + '>Take work</button>';
      }
      body += '</div>';
    }
    if (quests.length) body += '<h3>Trade</h3>';
    var rows = data.offers || [];
    if (!rows.length) body += '<p class="note">No submitted price.</p>';
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i];
      var buy = row.buy == null ? 'no buy' : (row.buy + ' buy');
      var sell = row.sell == null ? 'no sell' : (row.sell + ' sell');
      body += '<div class="line"><span class="nm">' + esc(row.name) + '</span>' +
        '<span>' + esc(buy) + '</span><span>' + esc(sell) + '</span>' +
        '<span>shelf ' + esc(row.stock || 0) + '</span>' +
        '<button data-verb="sell" data-name="' + esc(row.name) + '"' + (data.transfer && row.buy != null ? '' : ' disabled') + '>Sell</button>' +
        '<button data-verb="buy" data-name="' + esc(row.name) + '"' + (data.transfer && row.sell != null && row.stock > 0 ? '' : ' disabled') + '>Buy</button>' +
        '</div>';
    }
    var supply = data.supply || [];
    for (var s = 0; s < supply.length; s++) {
      if (!supply[s].ready) continue;
      body += '<div class="line"><span class="nm">Supply ' + esc(supply[s].count) + ' ' + esc(supply[s].name) +
        ' for ' + esc(supply[s].pay) + '</span>' +
        '<button data-verb="supply" data-name="' + esc(supply[s].name) + '"' + (data.transfer ? '' : ' disabled') + '>Turn in</button></div>';
    }
    var host = root.querySelector('#' + ID + '-body');
    host.innerHTML = body;
    var buttons = host.querySelectorAll('button');
    for (var b = 0; b < buttons.length; b++) {
      buttons[b].onclick = function (ev) {
        var el = ev.currentTarget;
        var questId = el.getAttribute('data-quest');
        if (questId) {
          el.disabled = true;
          var sent = net('/merchant quest ' + el.getAttribute('data-action') + ' ' + questId +
            (gemChoices[questId] ? ' ' + gemChoices[questId] : ''));
          if (!sent) el.disabled = false;
          return;
        }
        var verb = el.getAttribute('data-verb');
        var name = el.getAttribute('data-name');
        if (verb === 'supply') net('/merchant supply ' + name);
        else net('/merchant ' + verb + ' 1 ' + name);
      };
    }
    var selects = host.querySelectorAll('select[data-gem]');
    for (var c = 0; c < selects.length; c++) {
      selects[c].onchange = function(ev) {
        var el = ev.currentTarget, id = el.getAttribute('data-gem');
        gemChoices[id] = el.value;
        var take = host.querySelector('button[data-quest="' + id + '"][data-action="take"]');
        if (take) take.disabled = take.getAttribute('data-ready') !== 'yes' || !el.value;
      };
    }
    tell('opened');
  }
  function open() { draw(); }
  function close() {
    if (root) root.className = '';
    if (shown) tell('closed');
    shown = false;
  }
  function setData(next) {
    data = next || null;
    if (!data || data.open === false) close();
    else draw();
  }
  window.thornswoodMerchant = { open: open, close: close, setData: setData, isOpen: function () { return shown; } };
  tell('ready');
})();
