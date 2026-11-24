import Foundation

/// JavaScript the app adds to every briefing page: a "done" button on each
/// list item, and a note per section that lets dismissed items be shown and
/// restored. The page itself stays plain HTML; the generator only has to give
/// each item a `data-key`.
enum PageScript {
    /// Message handler names the script posts to.
    static let dismissHandler = "dismiss"
    static let restoreHandler = "restore"
    static let snoozeHandler = "snooze"
    static let copyHandler = "copy"

    /// Sections whose top-level list items can be dismissed. Matched on the
    /// section's h2 text, lower-cased.
    static let dismissableSections = [
        "urgent actions", "other conversations", "already handled or low priority", "papers to read",
    ]

    /// Runs once the document is loaded. Defines `window.briefing.applyDismissed(keys)`
    /// and wires the buttons.
    static let source = """
    (function () {
      if (window.briefing) { return; }
      var handlers = (window.webkit && window.webkit.messageHandlers) || {};
      function post(name, body) { if (handlers[name]) { handlers[name].postMessage(body); } }
      var SECTIONS = \(jsArray(dismissableSections));

      var style = document.createElement('style');
      style.textContent = [
        'li.dismissable { position: relative; padding-right: 34px; }',
        'li.dismissable .dismiss-btn { position: absolute; right: 0; top: 8px; width: 24px; height: 24px;',
        '  border: 1px solid var(--line, #2a2f3a); border-radius: 7px; background: transparent;',
        '  color: var(--ink-faint, #6b7280); font: 15px/1 -apple-system, sans-serif; cursor: pointer; padding: 0; }',
        'li.dismissable:first-child .dismiss-btn { top: -2px; }',
        'li.dismissable .snooze-btn { top: 38px; font-size: 13px; }',
        'li.dismissable:first-child .snooze-btn { top: 28px; }',
        'li.dismissed .snooze-btn { display: none; }',
        '.snooze-menu { margin-top: 6px; font-size: 12px; color: var(--ink-faint, #6b7280); }',
        '.snooze-menu a { cursor: pointer; margin-left: 6px; }',
        '.draft { white-space: pre-line; border-left: 2px solid var(--accent, #7aa2f7); padding: 6px 10px; margin-top: 6px;',
        '  color: var(--ink-soft, #9aa1ad); font-size: 13px; position: relative; }',
        '.copy-btn { margin-left: 8px; font-size: 12px; cursor: pointer; color: var(--accent, #7aa2f7); }',
        '#since-morning li { white-space: pre-line; }',
        '#since-morning li.gone { display: none; }',
        'li.dismissable .dismiss-btn:hover { color: var(--ink, #e6e8ee); border-color: var(--ink-faint, #6b7280); }',
        'li.dismissed { display: none; }',
        'section.show-dismissed li.dismissed { display: block; opacity: .45; }',
        'section.show-dismissed li.dismissed:first-child { padding-top: 10px; }',
        '.dismissed-note { color: var(--ink-faint, #6b7280); font-size: 12px; margin-top: 10px; }',
        '.dismissed-note a { cursor: pointer; }',
      ].join('\\n');
      document.head.appendChild(style);

      function clean(text) { return (text || '').replace(/\\s+/g, ' ').trim(); }
      function sectionOf(li) { return li.closest('section'); }
      function headingOf(section) {
        var h = section && section.querySelector('h2');
        return clean(h ? h.textContent : '');
      }
      function keyFor(li) {
        if (li.dataset.key) { return li.dataset.key; }
        var a = li.querySelector('a[href*="thread-f:"]');
        var m = a && a.href.match(/thread-f:(\\d+)/);
        if (m) { return 'mail:' + m[1]; }
        return 'title:' + textOf(li).toLowerCase().slice(0, 120);
      }
      // The item's own words: its bold title, else its text without the tag
      // and the when line.
      function textOf(li) {
        var t = li.querySelector('.t');
        if (t) { return clean(t.textContent); }
        var copy = li.cloneNode(true);
        copy.querySelectorAll('.tag, .when, .dismiss-btn, .snooze-menu').forEach(function (n) { n.remove(); });
        return clean(copy.textContent);
      }
      function titleFor(li) { return textOf(li).slice(0, 200); }
      function sourceFor(li) {
        var w = li.querySelector('.when');
        return clean(w ? w.textContent : '');
      }

      var items = [];
      document.querySelectorAll('section').forEach(function (section) {
        if (SECTIONS.indexOf(headingOf(section).toLowerCase()) < 0) { return; }
        section.querySelectorAll(':scope > ul:not(.plain) > li').forEach(function (li) {
          li.classList.add('dismissable');
          li.dataset.key = keyFor(li);
          var btn = document.createElement('button');
          btn.className = 'dismiss-btn';
          btn.type = 'button';
          li.appendChild(btn);
          btn.addEventListener('click', function (event) {
            event.preventDefault();
            closeMenu(li);
            if (li.classList.contains('dismissed')) {
              li.classList.remove('dismissed');
              post('\(restoreHandler)', { key: li.dataset.key });
            } else {
              li.classList.add('dismissed');
              post('\(dismissHandler)', details(li, section));
            }
            refresh(section);
          });
          var later = document.createElement('button');
          later.className = 'dismiss-btn snooze-btn';
          later.type = 'button';
          later.textContent = '\\u23F1';
          later.title = 'Not now: bring this back later';
          li.appendChild(later);
          later.addEventListener('click', function (event) {
            event.preventDefault();
            if (li.querySelector(':scope > .snooze-menu')) { closeMenu(li); return; }
            var menu = document.createElement('div');
            menu.className = 'snooze-menu';
            menu.appendChild(document.createTextNode('Bring back'));
            [['tomorrow', 'tomorrow'], ['week', 'next Monday']].forEach(function (choice) {
              var a = document.createElement('a');
              a.textContent = choice[1];
              a.addEventListener('click', function (e) {
                e.preventDefault();
                closeMenu(li);
                li.classList.add('dismissed');
                var body = details(li, section);
                body.length = choice[0];
                post('\(snoozeHandler)', body);
                refresh(section);
              });
              menu.appendChild(a);
            });
            li.appendChild(menu);
          });
          items.push(li);
        });
        refresh(section);
      });

      function details(li, section) {
        return { key: li.dataset.key, title: titleFor(li), source: sourceFor(li), section: headingOf(section) };
      }
      function closeMenu(li) {
        var m = li.querySelector(':scope > .snooze-menu');
        if (m) { m.remove(); }
      }

      function refresh(section) {
        var all = section.querySelectorAll(':scope > ul > li.dismissable');
        var gone = section.querySelectorAll(':scope > ul > li.dismissed');
        all.forEach(function (li) {
          var btn = li.querySelector('.dismiss-btn:not(.snooze-btn)');
          var done = li.classList.contains('dismissed');
          btn.textContent = done ? '\\u21A9' : '\\u00D7';
          btn.title = done ? 'Put this back on the briefing' : 'Done with this: keep it off the briefing';
        });
        var note = section.querySelector(':scope > .dismissed-note');
        if (gone.length === 0) {
          if (note) { note.remove(); }
          section.classList.remove('show-dismissed');
          return;
        }
        if (!note) {
          note = document.createElement('div');
          note.className = 'dismissed-note';
          section.appendChild(note);
        }
        var showing = section.classList.contains('show-dismissed');
        var word = gone.length === all.length ? 'All ' + gone.length : String(gone.length);
        note.innerHTML = '';
        note.appendChild(document.createTextNode(word + ' set aside \\u00B7 '));
        var toggle = document.createElement('a');
        toggle.textContent = showing ? 'Hide' : 'Show';
        toggle.addEventListener('click', function (event) {
          event.preventDefault();
          section.classList.toggle('show-dismissed');
          refresh(section);
        });
        note.appendChild(toggle);
      }

      function addCopyButtons(root) {
        root.querySelectorAll('.draft').forEach(function (d) {
          if (d.querySelector('.copy-btn')) { return; }
          var text = clean(d.textContent);
          var a = document.createElement('a');
          a.className = 'copy-btn';
          a.textContent = 'Copy';
          a.addEventListener('click', function (e) {
            e.preventDefault();
            post('\(copyHandler)', { text: d.dataset.text || text });
            a.textContent = 'Copied';
          });
          d.appendChild(a);
        });
      }
      addCopyButtons(document);

      // Today's daytime findings, newest first, above the first section.
      function showUpdates(list) {
        var old = document.getElementById('since-morning');
        if (old) { old.remove(); }
        if (!list || !list.length) { return; }
        var hidden = {};
        (window.briefing._hidden || []).forEach(function (k) { hidden[k] = true; });
        var sec = document.createElement('section');
        sec.id = 'since-morning';
        var h = document.createElement('h2');
        h.textContent = 'Since this morning';
        sec.appendChild(h);
        var ul = document.createElement('ul');
        list.slice().reverse().forEach(function (u) {
          var li = document.createElement('li');
          li.dataset.key = u.key || ('update:' + (u.time || '') + ':' + (u.title || ''));
          if (hidden[li.dataset.key]) { return; }
          li.classList.add('dismissable');
          if (u.tag) { var t = document.createElement('span'); t.className = 'tag'; t.textContent = u.tag; li.appendChild(t); li.appendChild(document.createTextNode(' ')); }
          var b = document.createElement('b'); b.className = 't'; b.textContent = u.title || ''; li.appendChild(b);
          if (u.text) { var p = document.createElement('div'); p.textContent = u.text; li.appendChild(p); }
          if (u.draft) { var dr = document.createElement('div'); dr.className = 'draft'; dr.textContent = u.draft; dr.dataset.text = u.draft; li.appendChild(dr); }
          if (u.link) { var a = document.createElement('a'); a.href = u.link; a.textContent = 'Open'; li.appendChild(a); }
          var w = document.createElement('div'); w.className = 'when'; w.textContent = (u.kind || '') + ' \\u00B7 ' + (u.time || ''); li.appendChild(w);
          var x = document.createElement('button'); x.className = 'dismiss-btn'; x.type = 'button'; x.textContent = '\\u00D7';
          x.addEventListener('click', function (e) {
            e.preventDefault();
            li.classList.add('gone');
            post('\(dismissHandler)', { key: li.dataset.key, title: u.title || '', source: (u.kind || '') + ' \\u00B7 ' + (u.time || ''), section: 'Since this morning' });
          });
          li.appendChild(x);
          ul.appendChild(li);
        });
        if (!ul.children.length) { return; }
        sec.appendChild(ul);
        addCopyButtons(sec);
        var first = document.querySelector('section');
        if (first) { first.parentNode.insertBefore(sec, first); } else { document.body.appendChild(sec); }
      }

      window.briefing = {
        showUpdates: showUpdates,
        applyDismissed: function (keys) {
          window.briefing._hidden = keys || [];
          var set = {};
          (keys || []).forEach(function (k) { set[k] = true; });
          var touched = [];
          items.forEach(function (li) {
            var dismissed = !!set[li.dataset.key];
            if (dismissed !== li.classList.contains('dismissed')) {
              li.classList.toggle('dismissed', dismissed);
              var s = sectionOf(li);
              if (touched.indexOf(s) < 0) { touched.push(s); }
            }
          });
          touched.forEach(refresh);
          return items.length;
        },
        keys: function () { return items.map(function (li) { return li.dataset.key; }); }
      };
    })();
    """

    /// The call that hides already-dismissed items after a load.
    static func applyCall(keys: [String]) -> String {
        "window.briefing && window.briefing.applyDismissed(\(jsArray(keys)));"
    }

    /// The call that draws "Since this morning" from the updates file.
    static func updatesCall(_ json: String) -> String {
        " window.briefing && window.briefing.showUpdates(\(json));"
    }

    static func jsArray(_ strings: [String]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: strings)) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
