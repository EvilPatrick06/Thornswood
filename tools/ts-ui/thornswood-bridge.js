'use strict';
/*
  What the front expects, and what this browser actually has.

  The front is built against skymp's own client, which sets up a richer window
  than SkyrimPlatform does. In this build the bridge object is created in
  ProcessHandler.cpp and it carries exactly one thing:

      window.skyrimPlatform = { sendMessage: function () {} }

  Four gaps follow from that, and all four are silent.

  1. window.skymp, with .send for talking outward and .on for hearing back,
     does not exist. The front guards that one, so it fails quietly.

  2. window.chatMessages does not exist. The chat draws its list straight off
     that global rather than off its own props, so the first render throws.

  3. Nothing ever renders. App only draws the chat when it is "loggined", and
     nothing in the front ever sets that, so the real path is the widget list:
     the game pushes a list of things to draw and Constructor draws them.

  4. The chat widget's `send` has to be a function. Chat does

         if (send !== undefined) { send(message); }

     with no type check, so a string there is a silent throw inside a React
     callback and the box eats what you typed.

  And one thing that is not a gap in the front but a fact about the browser,
  which is the reason half of this file exists:

      While the browser holds the keyboard, no plugin can see a key.

  browser.setFocused(true) raises DInputHook::ChromeFocus, which withholds
  DirectInput from the game, and SkyrimPlatform's buttonEvent is built out of
  the game's own input. So the moment focus goes up, every plugin goes deaf,
  including the one that put focus up. CEF still gets keys, through a Windows
  raw input hook that does not care about any of this.

  That is why escape is handled here and answered back over sendMessage rather
  than being waited for on the game side. A plugin waiting for a key it cannot
  receive is somebody standing in Windhelm unable to move.
*/

(function () {
  // ------------------------------------------------ the /skill quit spam --
  // The front ships a skills menu and a test menu, neither of which this
  // server uses, and both of them do this on mount:
  //
  //     window.addEventListener('skymp5-client:browserUnfocused', quitHandler);
  //
  // with a quitHandler whose last line is send('/skill quit'). The client
  // raises that event every time browser focus drops, and focus drops every
  // time somebody finishes typing, so every closed chat box wrote "/skill
  // quit" into the room.
  //
  // Dropped at registration rather than unhooked afterwards, because the
  // handler is a closure inside a React component and there is no reference to
  // it to remove. This file is a plain script in <head> and the bundle is
  // deferred, so this runs first and the listener is never added at all.
  var addListener = window.addEventListener.bind(window);
  var DEAF_TO = ['skymp5-client:browserUnfocused'];
  window.addEventListener = function (type, fn, opts) {
    if (DEAF_TO.indexOf(type) !== -1) { return; }
    return addListener(type, fn, opts);
  };

  var sp = (window.skyrimPlatform = window.skyrimPlatform || {});

  if (typeof sp.sendMessage !== 'function') {
    // Opened outside the game. Keep the page alive rather than throwing on
    // every call, so the front can be looked at in an ordinary browser.
    sp.sendMessage = function () {
      try {
        console.log('[bridge] sendMessage outside the game:',
                    Array.prototype.slice.call(arguments));
      } catch (e) { }
    };
  }

  function tell(what) {
    try { sp.sendMessage('thornswood-front', what); } catch (e) { }
  }

  // The chat reads this global directly in getList. It has to exist before the
  // first render, not merely before the first message.
  if (!Array.isArray(window.chatMessages)) window.chatMessages = [];

  // --------------------------------------------------------------- skymp ---
  // window.mp.send in the front funnels into window.skymp.send({type, data}),
  // and everything coming back is a Redux action handed to the 'message'
  // listener. Both directions go over sendMessage, the only channel there is.
  if (!window.skymp) {
    var handlers = {};

    window.skymp = {
      send: function (obj) {
        try { sp.sendMessage('thornswood-ui', JSON.stringify(obj)); }
        catch (e) {
          try { console.log('[bridge] send failed: ' + e); } catch (e2) { }
        }
      },
      on: function (name, fn) {
        if (typeof fn !== 'function') return;
        (handlers[name] = handlers[name] || []).push(fn);
      },
      off: function (name, fn) {
        var l = handlers[name];
        if (!l) return;
        var i = l.indexOf(fn);
        if (i !== -1) l.splice(i, 1);
      },
      dispatch: function (name, arg) {
        var l = handlers[name];
        if (!l) return;
        for (var i = 0; i < l.length; i++) {
          try { l[i](arg); } catch (e) {
            try { console.log('[bridge] handler threw: ' + e); } catch (e2) { }
          }
        }
      }
    };
  }

  // ---------------------------------------------------------------- typing --
  // Whether the person is deliberately talking, as opposed to playing.
  //
  // This matters more than it looks. TPInputService injects every keystroke
  // into this page whenever the browser is *visible*, focused or not, so while
  // you are running around Whiterun every W, A, S and D is also being typed
  // into whatever holds DOM focus in here. The chat box takes DOM focus on
  // mount and takes it again on every new message, so without this the box
  // quietly fills up with movement keys and sends them the next time you press
  // enter.
  window.thornswoodTyping = false;

  // When the box was opened, so the key that opened it can be ignored.
  //
  // This is the trap underneath both the chat and the emote wheel. CEF is fed
  // every keystroke whenever the browser is visible, focused or not, by
  // TPInputService. So the Enter that the plugin reads as "open the chat" is
  // also delivered to this page a moment later, where the handler below reads
  // it as "send and close". The box opened and shut inside one keypress, which
  // from the outside is a chat that does nothing at all, and the log showing
  // typing=yes every time while every press still says "asking the page".
  //
  // Ignoring the first 400ms is the whole fix. Nobody types a line that fast,
  // and a held key repeats slower than that.
  var openedAt = 0;

  var beat = null;

  function input() {
    return document.getElementById('chatInput');
  }

  function startBeat() {
    if (beat) return;
    // A heartbeat rather than a promise that this page stays alive. If it
    // stops, the game side lowers focus by itself after a few seconds, so a
    // chat box that has crashed or was never drawn cannot leave somebody
    // unable to move.
    beat = setInterval(function () {
      if (!window.thornswoodTyping) { stopBeat(); return; }
      tell('typing');
    }, 4000);
  }

  function stopBeat() {
    if (!beat) return;
    clearInterval(beat);
    beat = null;
  }

  /**
   * Put the caret in the chat box, and say whether that worked.
   *
   * The game side asks for this and waits for the answer before handing the
   * keyboard over. Answering "no box here" is the whole point: pressing enter
   * with nothing to type into used to raise focus anyway, which took the
   * keyboard and the mouse away with nothing on screen to give them back.
   */
  function focusInput() {
    var el = input();
    if (!el) {
      window.thornswoodTyping = false;
      tell('typing-fail');
      return false;
    }
    window.thornswoodTyping = true;
    openedAt = Date.now();
    lastKey = Date.now();
    try { el.focus(); } catch (e) { }
    tell('typing-on');
    startBeat();
    return true;
  }

  function blurInput() {
    var was = window.thornswoodTyping;
    window.thornswoodTyping = false;
    stopBeat();
    var el = input();
    if (el) { try { el.blur(); } catch (e) { } }
    try {
      if (document.activeElement && document.activeElement.blur) {
        document.activeElement.blur();
      }
    } catch (e) { }
    if (was) tell('typing-off');
  }

  // Anything that reaches the document while you are not talking is a game key
  // that leaked in, so it is stopped before React sees it. Capture phase,
  // because the chat's own listener is on the input.
  document.addEventListener('keydown', function (e) {
    if (window.thornswoodTyping) return;
    e.stopPropagation();
  }, true);
  document.addEventListener('keypress', function (e) {
    if (window.thornswoodTyping) return;
    e.stopPropagation();
    e.preventDefault();
  }, true);

  /*
   * Capture phase, with the blur deferred.
   *
   * This was on the bubble phase, so that the chat's own enter handler had
   * already sent the line before the box closed. That is the right ordering
   * and the wrong mechanism: a handler on the input is free to call
   * stopPropagation, and the chat's does, so the event never bubbled back up
   * to the document and the box was never closed. Focus stayed claimed, and
   * with focus up the game gets no input at all, so the whole screen locks:
   *
   *     [front] focus claimed by chat (holding: chat)
   *     [front] chat state: widgets=yes box=yes typing=yes lines=1
   *
   * and nothing after it, forever.
   *
   * Capture runs from the document down to the target, so it happens before
   * anything on the input can stop it, and nothing can prevent it. Ordering is
   * kept by not blurring here: setTimeout(0) runs after the whole synchronous
   * dispatch, so the chat has already sent the line by the time the box shuts.
   */
  document.addEventListener('keydown', function (e) {
    if (!window.thornswoodTyping) return;
    var k = e.key;
    if (k === 'Escape' || e.keyCode === 27) { setTimeout(blurInput, 0); return; }
    if ((k === 'Enter' || e.keyCode === 13) && !e.shiftKey) {
      // Not the one that opened the box. See the note on openedAt.
      if (Date.now() - openedAt < 400) { return; }
      setTimeout(blurInput, 0);
    }
  }, true);

  /*
   * And a way out that needs no key at all.
   *
   * Everything above assumes keystrokes reach this page. While the box is open
   * the game is starved of input by design, so if that assumption is ever
   * wrong the person is not inconvenienced, they are stuck: no movement, no
   * menus, no way to close what they opened.
   *
   * So the box gives itself up after a while of nobody typing into it. Twenty
   * seconds is far longer than any gap in the middle of writing a line and far
   * shorter than the time it takes to decide the game has crashed.
   */
  var IDLE_MS = 20000;
  var lastKey = 0;

  document.addEventListener('keydown', function () {
    if (window.thornswoodTyping) { lastKey = Date.now(); }
  }, true);

  setInterval(function () {
    if (!window.thornswoodTyping) { return; }
    if (!lastKey) { lastKey = Date.now(); return; }
    if (Date.now() - lastKey < IDLE_MS) { return; }
    tell('typing-idle');
    blurInput();
  }, 2000);

  // ---------------------------------------------------------------- chat ---
  var WIDGET = {
    type: 'chat',
    messages: [],
    placeholder: 'Say something',
    isInputHidden: false,
    // Must be a function. See note 4 at the top.
    send: function (text) {
      try {
        if (window.thornswoodNet && window.thornswoodNet.say) {
          window.thornswoodNet.say(text);
          return;
        }

        // thornswood-chat.js is fetched by the page and this widget is drawn
        // before it lands, so for the first second or two of a session there is
        // nothing to send through. Throwing the line away and saying so was the
        // wrong answer to that: whoever typed it has to type it again, and the
        // reason given, not connected, is not even true. Held instead, and sent
        // the moment the socket file is in.
        held.push(String(text));
        while (held.length > 20) held.shift();
        drain();
      } catch (e) {
        try { console.log('[bridge] send threw: ' + e); } catch (e2) { }
      }
    }
  };

  function widgets() {
    return window.skyrimPlatform && window.skyrimPlatform.widgets;
  }

  // Lines typed before the chat's own script finished loading.
  var held = [];
  var draining = null;

  function drain() {
    if (!held.length) {
      if (draining) { clearInterval(draining); draining = null; }
      return;
    }
    if (window.thornswoodNet && window.thornswoodNet.say) {
      while (held.length) { window.thornswoodNet.say(held.shift()); }
      if (draining) { clearInterval(draining); draining = null; }
      return;
    }
    if (!draining) { draining = setInterval(drain, 400); }
  }

  // A message is a list of coloured runs rather than a string, and every run
  // needs a type array: the renderer calls .join on it and .includes on it, so
  // leaving it out is a crash rather than a default.
  function run(text, color, type) {
    return {
      text: String(text),
      color: color || '#e8e3d8',
      opacity: 1,
      type: type || []
    };
  }

  /**
   * Hide the non-rp filter.
   *
   * Not a setting anybody here wants. This whole server is the roleplay, so a
   * tick box that hides half of it is a way to miss messages by accident.
   *
   * Done in the page rather than in the front's own source because the front is
   * a built bundle: an edit there is undone by the next rebuild, and the markup
   * is stable (ChatCheckbox renders an input carrying the id, then a label for
   * it, inside a promoted-checkbox div).
   */
  function hideNonRp() {
    try {
      var box = document.getElementById('nonrp');
      if (!box) return;
      var host = box.parentNode;
      if (host && host.style) host.style.display = 'none';
    } catch (e) { }
  }

  // Everything under the input goes.
  //
  // The last attempt hid one div and assumed the dice were inside it. They are
  // not. Read out of build.js, the render is:
  //
  //     <div className="chat-main">
  //       <ResizableBox id="handle" className="list"> ... </ResizableBox>
  //       <div/>                                   (a spacer)
  //       <div className="input">
  //         <div className="chat-input"> <span id="chatInput"/> </div>
  //         <div className="chat-checkboxes">
  //           <ChatCheckbox id='nonrp'/>
  //           <ChatCheckbox id='settings'/>
  //           <ChatCheckbox id='moveChat'/>
  //           <span className="chat-message-limit shout-limit"/>   0/100
  //           <span className="chat-message-limit"/>               0/2000
  //         </div>
  //       </div>
  //       {isInputHidden ? null : <Dices/>}       <- a SIBLING of .input
  //     </div>
  //
  // So the pouch and its coin were never covered by the old rule, which is why
  // they were still there while the tick boxes went. Dices renders
  // .chat-dices, and each icon inside it carries the class 'dice'.
  //
  // Hidden here rather than in the front's own source because the front is a
  // built bundle: an edit there is undone by the next rebuild.
  var HIDE = [
    '#chat .chat-checkboxes',
    '#chat .chat-dices',
    '#chat .dice',
    '#chat .chat-corner',
    '#nonrp', 'label[for="nonrp"]'
  ];

  var css = document.createElement('style');
  css.id = 'thornswood-chat-trim';
  css.textContent = [
    HIDE.join(',') + '{display:none !important}',

    // Up off the bars.
    //
    // The front puts the chat at bottom:30px, which is underneath SkyHUD's
    // health, stamina and magicka. 180 clears them and still leaves the chat
    // in the corner where people look for it.
    '#chat{bottom:180px !important;left:26px !important}',

    // And see through.
    //
    // The input is a black slab at 75% by default, which is most of what is
    // on screen while you are standing still. Every message already carries a
    // heavy text shadow, so the words hold up against snow without anything
    // behind them.
    '#chat .chat-input{background-color:transparent !important;' +
      'border-radius:0 !important;box-shadow:none !important}',

    // The resize arrow, top right of the message list. It drags the box
    // bigger, which is a thing nobody asked for and a thing that puts a
    // cursor on screen in the middle of playing.
    '#chat .chat-corner,#chat .react-resizable-handle{display:none !important}',

    /* No scrollbar, and no scrolling.
     *
     * The message list is a fixed window onto the last few lines and it
     * already follows the newest one. A scrollbar on it is a control that only
     * works with a mouse, and reaching for the mouse while playing means
     * taking the keyboard off the game. The old lines are not lost, there is
     * just no way to drag back to them, which is the right trade for a chat
     * you read over your shoulder. */
    '#chat .chat-messages,#chat .chat-body,#chat ul,#chat ol{' +
      'overflow:hidden !important;scrollbar-width:none !important}',
    '#chat ::-webkit-scrollbar{width:0 !important;height:0 !important;display:none !important}',

    /* And no mouse cursor anywhere on this page.
     *
     * The browser draws its own pointer over the game, and because the chat
     * input is text it draws an I-beam: a blinking bar sitting in the middle
     * of the floor with nothing to do with the game. The game draws whatever
     * pointer it wants when it wants one. This page never needs to draw one,
     * because everything it offers has a key. */
    'html,body,#chat,#chat *{cursor:none !important}'
  ].join('\n');
  (document.head || document.documentElement).appendChild(css);

  // Hidden by the sheet above, and the sheet kept in the page.
  //
  // This used to take the nodes out of the document as well, from a
  // MutationObserver on the whole document with subtree set, so every change
  // anywhere in the page ran it: each line of chat, and every other overlay
  // that redraws, such as the party strip, which thornswood-party.js rewrites
  // every 200 ms while you are in a party. Each run was six querySelectorAll
  // over the whole document, and each node it pulled out from under React was
  // one more change that ran it again. To Do List entry 270: "This is the code
  // between the person and every frame of the game".
  //
  // The removal was there in case this file's <style> did not outlive
  // whatever style-loader does with the bundle's own. Read out of the fork
  // (skymp5-front's webpack.config.ts and its chat styles): style-loader runs
  // with its defaults, which append the bundle's sheets to <head> and take
  // away only the ones they added, and none of the front's display rules for
  // these elements is !important, so the rules above hold for as long as this
  // <style> is in the page. That is the one thing watched now: the children
  // of <head>, with no subtree, which change when a sheet or an overlay's
  // script goes in, a handful of times a session. If this one has gone it
  // goes straight back; otherwise the cost is one property read, and a change
  // anywhere else in the page runs nothing. The front's nodes stay where
  // React put them.
  function keepSheet() {
    try {
      if (!css.parentNode && document.head) { document.head.appendChild(css); }
    } catch (e) { }
  }

  try {
    if (document.head) {
      new MutationObserver(keepSheet).observe(document.head, { childList: true });
    }
  } catch (e) { }

  var shown = false;
  var tries = 0;

  function draw() {
    var w = widgets();
    if (!w) return false;
    // A new array every time on purpose: the front decides whether to redraw
    // by identity, so pushing the same array back changes nothing on screen.
    w.set([WIDGET]);
    setTimeout(function () {
      hideNonRp();
      keepSheet();
      if (!window.thornswoodTyping) blurInput();
    }, 0);
    return true;
  }

  window.thornswoodChat = {
    line: run,
    focusInput: focusInput,
    blurInput: blurInput,

    /**
     * Put the chat on screen, retrying until the front is ready for it.
     *
     * window.skyrimPlatform.widgets is built by the front's own index.js, which
     * is a two and a half megabyte deferred bundle. Asking before that has run
     * used to fail silently and never be asked again, which looks exactly like
     * a chat that was never installed.
     */
    show: function () {
      if (shown) { return draw(); }
      if (draw()) {
        shown = true;
        // The game side waits for this before it will hand over the keyboard
        // on the first press. After it, enter is immediate.
        tell('chat is up');
        return true;
      }
      if (tries++ > 60) {
        if (tries === 61) tell('the front never built its widget list, so there is no chat box');
        return false;
      }
      setTimeout(window.thornswoodChat.show, 500);
      return false;
    },

    hide: function () {
      var w = widgets();
      if (!w) return false;
      w.set([]);
      return true;
    },

    /**
     * Add one message. Takes either a plain string or a list of runs, so the
     * game side can send something coloured without knowing the shape.
     */
    add: function (parts, category) {
      var text;
      if (typeof parts === 'string') {
        text = [run(parts)];
      } else if (Array.isArray(parts)) {
        text = parts.map(function (p) {
          return typeof p === 'string' ? run(p) : run(p.text, p.color, p.type);
        });
      } else {
        return false;
      }

      window.chatMessages.push({
        category: category || 'plain',
        opacity: 1,
        text: text
      });
      while (window.chatMessages.length > 50) window.chatMessages.shift();

      draw();
      try { window.needToScroll = true; } catch (e) { }
      try { if (window.scrollToLastMessage) window.scrollToLastMessage(); } catch (e) { }
      return true;
    },

    clear: function () {
      window.chatMessages.length = 0;
      draw();
    },

    /** What the game side asks for when something looks wrong. */
    state: function () {
      var el = input();
      tell('chat state: widgets=' + (widgets() ? 'yes' : 'no') +
           ' box=' + (el ? 'yes' : 'no') +
           ' typing=' + (window.thornswoodTyping ? 'yes' : 'no') +
           ' lines=' + window.chatMessages.length);
    }
  };

  // The overlay composites over the game, so anything behind the widgets has
  // to be genuinely transparent. The front's stylesheet assumes a window.
  function clear() {
    try {
      document.documentElement.style.background = 'transparent';
      if (document.body) document.body.style.background = 'transparent';
    } catch (e) { }
  }
  clear();
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', clear);
  }

  tell('bridge is up');
})();
