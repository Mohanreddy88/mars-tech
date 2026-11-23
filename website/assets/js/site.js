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

  // ── Sign in: company code → https://<code>.<domain> ──────────────────────
  var signin = document.getElementById('signin-form');
  if (signin) {
    var suffix = signin.querySelector('[data-domain]');
    if (suffix) suffix.textContent = '.' + appDomain;
    var input = signin.querySelector('input[name=code]');
    var err = signin.querySelector('.form-msg');
    var saved = '';
    try { saved = localStorage.getItem('marshrms.code') || ''; } catch (e) { /* private mode */ }
    if (saved && input && !input.value) input.value = saved;
    signin.addEventListener('submit', function (ev) {
      ev.preventDefault();
      var code = (input.value || '').trim().toLowerCase().replace(/\s+/g, '');
      code = code.replace(/^https?:\/\//, '').split('.')[0];
      if (!/^[a-z0-9][a-z0-9-]{1,40}$/.test(code)) {
        err.className = 'form-msg err';
        err.textContent = 'Enter your company or school code, e.g. "goldenkids". Your administrator can tell you.';
        return;
      }
      try { localStorage.setItem('marshrms.code', code); } catch (e) { /* ignore */ }
      location.href = 'https://' + code + '.' + appDomain + '/login';
    });
  }
})();
