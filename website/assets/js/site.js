/* Mars HRMS website: navigation, reveal-on-scroll, contact form, sign-in by company code. */
(function () {
  'use strict';

  // ── Settings ─────────────────────────────────────────────────────────────
  var SITE = {
    email: 'support@marshrms.com',
    // WhatsApp numbers in international format without "+" or spaces. Empty list = buttons hidden.
    // An element with data-whatsapp="my" / "in" opens that number; an empty data-whatsapp opens the first.
    whatsapp: [
      { key: 'my', number: '60107767618',  label: 'Malaysia', display: '+60 10-776 7618' },
      { key: 'in', number: '919848872329', label: 'India',    display: '+91 98488 72329' }
    ],
    whatsappText: 'Hi Mars HRMS, I would like to know more / book a demo.'
  };

  // The app lives on company sub-domains of the same domain the site is on:
  // marshrms.com → <code>.marshrms.com, uat.marshrms.com → <code>.uat.marshrms.com, local → UAT.
  var host = location.hostname.replace(/^www\./, '');
  var appDomain = /marshrms\.com$|marstech\.tech$/.test(host) ? host : 'uat.marshrms.com';

  // ── Header: shadow when scrolled, mobile menu ────────────────────────────
  var header = document.querySelector('.site-header');
  function onScroll() { if (header) header.classList.toggle('scrolled', window.scrollY > 8); }
  window.addEventListener('scroll', onScroll, { passive: true });
  onScroll();

  var toggle = document.querySelector('.menu-toggle');
  if (toggle && header) {
    toggle.addEventListener('click', function () {
      var open = header.classList.toggle('open');
      toggle.setAttribute('aria-expanded', String(open));
      toggle.innerHTML = open ? '<i class="bi bi-x-lg"></i>' : '<i class="bi bi-list"></i>';
    });
    header.querySelectorAll('.nav-links a').forEach(function (a) {
      a.addEventListener('click', function () { header.classList.remove('open'); });
    });
  }

  // ── Reveal sections as they scroll into view ─────────────────────────────
  var items = document.querySelectorAll('.reveal');
  if ('IntersectionObserver' in window) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) { if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); } });
    }, { threshold: 0.12 });
    items.forEach(function (el) { io.observe(el); });
  } else {
    items.forEach(function (el) { el.classList.add('in'); });
  }

  // ── Footer year, email links, WhatsApp buttons ───────────────────────────
  document.querySelectorAll('[data-year]').forEach(function (el) { el.textContent = new Date().getFullYear(); });
  document.querySelectorAll('[data-email]').forEach(function (el) {
    el.setAttribute('href', 'mailto:' + SITE.email);
    var t = el.querySelector('[data-email-text]');
    if (t) t.textContent = SITE.email;
  });
  function waUrl(w) { return 'https://wa.me/' + w.number + '?text=' + encodeURIComponent(SITE.whatsappText); }
  function waFor(key) {
    for (var i = 0; i < SITE.whatsapp.length; i++) if (SITE.whatsapp[i].key === key) return SITE.whatsapp[i];
    return SITE.whatsapp[0];
  }
  var waMenu = null;
  document.querySelectorAll('[data-whatsapp]').forEach(function (el) {
    if (!SITE.whatsapp.length) { el.style.display = 'none'; return; }
    if (el.classList.contains('wa-float')) {
      el.classList.add('show');
      if (SITE.whatsapp.length > 1) {
        // Floating button: let the visitor choose the Malaysia or India number
        waMenu = document.createElement('div');
        waMenu.className = 'wa-menu';
        waMenu.setAttribute('role', 'menu');
        SITE.whatsapp.forEach(function (w) {
          var a = document.createElement('a');
          a.href = waUrl(w); a.target = '_blank'; a.rel = 'noopener'; a.setAttribute('role', 'menuitem');
          a.innerHTML = '<i class="bi bi-whatsapp"></i><span>WhatsApp ' + w.label + '<small>' + w.display + '</small></span>';
          waMenu.appendChild(a);
        });
        document.body.appendChild(waMenu);
        el.setAttribute('aria-haspopup', 'true');
        el.addEventListener('click', function (ev) { ev.preventDefault(); ev.stopPropagation(); waMenu.classList.toggle('open'); });
        document.addEventListener('click', function () { waMenu.classList.remove('open'); });
        return;
      }
    }
    el.setAttribute('href', waUrl(waFor(el.getAttribute('data-whatsapp'))));
    el.setAttribute('target', '_blank');
    el.setAttribute('rel', 'noopener');
  });

  // ── Contact / book a demo form ───────────────────────────────────────────
  var form = document.getElementById('contact-form');
  if (form) {
    var msg = form.querySelector('.form-msg');
    var btn = form.querySelector('button[type=submit]');
    form.addEventListener('submit', function (ev) {
      ev.preventDefault();
      var data = {};
      new FormData(form).forEach(function (v, k) { data[k] = String(v).trim(); });
      msg.className = 'form-msg';
      if (!data.name) { show('err', 'Please enter your name.'); return; }
      if (!data.email && !data.phone) { show('err', 'Please enter your email or phone number.'); return; }
      btn.disabled = true;
      var label = btn.innerHTML;
      btn.innerHTML = 'Sending…';
      fetch('/api/public/contact', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data)
      }).then(function (r) {
        return r.json().catch(function () { return {}; }).then(function (j) { return { ok: r.ok, status: r.status, body: j }; });
      }).then(function (r) {
        if (r.ok) {
          form.reset();
          show('ok', 'Thank you! We have received your message and will get back to you soon.');
        } else if (r.status === 429) {
          show('err', 'Too many messages from this connection. Please try again later, or email us.');
        } else {
          show('err', (r.body && r.body.message) || 'Sorry, the message could not be sent. Please email us instead.');
        }
      }).catch(function () {
        show('err', 'Sorry, the message could not be sent. Please check your connection or email us.');
      }).then(function () {
        btn.disabled = false;
        btn.innerHTML = label;
      });
    });
    function show(kind, text) { msg.className = 'form-msg ' + kind; msg.textContent = text; }

    // "Book a demo for my school" links prefill the type
    var params = new URLSearchParams(location.search);
    var kind = params.get('type');
    if (kind && form.elements.kind) form.elements.kind.value = kind;
  }

  // ── Sign in: pick the company → https://<code>.<domain>/login ────────────
  // The list (name + code of active companies) comes from GET /api/public/companies. The address,
  // live or UAT, is never shown. If the list can't load, a typed company code still works.
  var signin = document.getElementById('signin-form');
  if (signin) {
    var input = signin.querySelector('input[name=company]');
    var listEl = document.getElementById('company-list');
    var err = signin.querySelector('.form-msg');
    var companies = [], shown = [], active = -1, chosen = null;

    function esc(s) { return String(s).replace(/[&<>"']/g, function (c) { return '&#' + c.charCodeAt(0) + ';'; }); }
    function close() { listEl.hidden = true; input.setAttribute('aria-expanded', 'false'); active = -1; }
    function choose(c) {
      chosen = c; input.value = c.name; close();
      err.className = 'form-msg'; err.textContent = '';
    }
    function render() {
      var q = input.value.trim().toLowerCase();
      shown = companies.filter(function (c) { return !q || c.name.toLowerCase().indexOf(q) >= 0 || c.code.indexOf(q) >= 0; });
      if (!companies.length) { close(); return; }
      listEl.innerHTML = shown.length
        ? shown.map(function (c, i) {
            return '<li role="option" id="co-' + i + '" data-i="' + i + '"' + (i === active ? ' aria-selected="true" class="active"' : '') +
                   '><span class="co-av">' + esc(c.name.charAt(0).toUpperCase()) + '</span>' + esc(c.name) + '</li>';
          }).join('')
        : '<li class="none">No company or school matches "' + esc(input.value.trim()) + '"</li>';
      listEl.hidden = false;
      input.setAttribute('aria-expanded', 'true');
      if (active >= 0) input.setAttribute('aria-activedescendant', 'co-' + active); else input.removeAttribute('aria-activedescendant');
    }

    fetch('/api/public/companies', { headers: { Accept: 'application/json' } })
      .then(function (r) { return r.ok ? r.json() : []; })
      .then(function (list) {
        companies = (list || []).filter(function (c) { return c && c.code; })
          .map(function (c) { return { code: String(c.code), name: String(c.name || c.code) }; });
        var saved = '';
        try { saved = localStorage.getItem('marshrms.code') || ''; } catch (e) { /* private mode */ }
        var prev = companies.filter(function (c) { return c.code === saved; })[0];
        if (prev && !input.value) choose(prev);
        if (document.activeElement === input) render();
      })
      .catch(function () { /* no list: a typed code still works */ });

    input.addEventListener('input', function () { chosen = null; active = -1; render(); });
    input.addEventListener('focus', render);
    input.addEventListener('click', render);
    input.addEventListener('keydown', function (ev) {
      if (ev.key === 'ArrowDown' || ev.key === 'ArrowUp') {
        if (!shown.length) return;
        ev.preventDefault();
        active = ev.key === 'ArrowDown' ? Math.min(active + 1, shown.length - 1) : Math.max(active - 1, 0);
        render();
      } else if (ev.key === 'Enter' && !listEl.hidden && active >= 0 && shown[active]) {
        ev.preventDefault();
        choose(shown[active]);
      } else if (ev.key === 'Escape') {
        close();
      }
    });
    listEl.addEventListener('mousedown', function (ev) {
      var li = ev.target.closest('li[data-i]');
      if (li) { ev.preventDefault(); choose(shown[+li.getAttribute('data-i')]); }
    });
    document.addEventListener('click', function (ev) { if (!signin.contains(ev.target)) close(); });

    signin.addEventListener('submit', function (ev) {
      ev.preventDefault();
      var text = input.value.trim().toLowerCase();
      // A name typed in full (not clicked) counts as chosen too
      var c = chosen || companies.filter(function (x) { return x.name.toLowerCase() === text || x.code === text; })[0];
      if (!c && shown.length === 1 && text) c = shown[0];
      var code = c ? c.code : '';
      if (!code && !companies.length) {
        // The list didn't load: accept a typed company code
        var typed = text.replace(/\s+/g, '').replace(/^https?:\/\//, '').split('.')[0];
        if (/^[a-z0-9][a-z0-9-]{1,40}$/.test(typed)) code = typed;
      }
      if (!code) {
        err.className = 'form-msg err';
        err.textContent = companies.length
          ? 'Choose your company or school from the list. Your administrator can tell you which one.'
          : 'Enter your company or school code. Your administrator can tell you.';
        render();
        return;
      }
      try { localStorage.setItem('marshrms.code', code); } catch (e) { /* ignore */ }
      location.href = 'https://' + code + '.' + appDomain + '/login';
    });
  }
})();

/* Sliding cards: one card further every few seconds (paused under the mouse, a finger or keyboard
   focus, and while the tab is hidden), with arrows, dots, swipe and scroll. Loops back to the start. */
(function () {
  'use strict';
  var EVERY = 4500;
  var reduced = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  Array.prototype.forEach.call(document.querySelectorAll('[data-slider]'), function (slider) {
    var track = slider.querySelector('[data-track]');
    var cards = track ? track.children : [];
    if (!track || cards.length < 2) return;
    var dotsBox = slider.querySelector('[data-dots]');
    var paused = false;

    function step() { return cards[1].offsetLeft - cards[0].offsetLeft; }
    function index() { return Math.round(track.scrollLeft / step()); }
    function last() { return Math.max(0, Math.round((track.scrollWidth - track.clientWidth) / step())); }
    function go(i) {
      var max = last();
      if (i > max) i = 0;
      if (i < 0) i = max;
      track.scrollTo({ left: i * step(), behavior: reduced ? 'auto' : 'smooth' });
    }

    // Dots: one per position the track can stop at
    var dots = [];
    function buildDots() {
      if (!dotsBox) return;
      dotsBox.innerHTML = '';
      dots = [];
      for (var i = 0; i <= last(); i++) {
        var b = document.createElement('button');
        b.type = 'button';
        b.setAttribute('aria-label', 'Show card ' + (i + 1));
        b.addEventListener('click', go.bind(null, i));
        dotsBox.appendChild(b);
        dots.push(b);
      }
      mark();
    }
    function mark() {
      var at = Math.min(index(), dots.length - 1);
      dots.forEach(function (d, i) { d.classList.toggle('on', i === at); });
    }

    var prev = slider.querySelector('[data-prev]');
    var next = slider.querySelector('[data-next]');
    if (prev) prev.addEventListener('click', function () { go(index() - 1); });
    if (next) next.addEventListener('click', function () { go(index() + 1); });

    var scrollTimer;
    track.addEventListener('scroll', function () { clearTimeout(scrollTimer); scrollTimer = setTimeout(mark, 80); }, { passive: true });
    track.addEventListener('keydown', function (e) {
      if (e.key === 'ArrowRight') { e.preventDefault(); go(index() + 1); }
      if (e.key === 'ArrowLeft') { e.preventDefault(); go(index() - 1); }
    });

    slider.addEventListener('mouseenter', function () { paused = true; });
    slider.addEventListener('mouseleave', function () { paused = false; });
    slider.addEventListener('focusin', function () { paused = true; });
    slider.addEventListener('focusout', function () { paused = false; });
    track.addEventListener('touchstart', function () { paused = true; }, { passive: true });
    track.addEventListener('touchend', function () { setTimeout(function () { paused = false; }, 3000); }, { passive: true });

    var resizeTimer;
    window.addEventListener('resize', function () { clearTimeout(resizeTimer); resizeTimer = setTimeout(buildDots, 150); });
    buildDots();

    if (!reduced) {
      setInterval(function () {
        if (!paused && document.visibilityState === 'visible') go(index() + 1);
      }, EVERY);
    }
  });
})();
