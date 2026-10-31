'use strict';

(() => {
  function setupNavigation() {
    const header = document.getElementById('siteHeader');
    const toggle = document.getElementById('mobileMenuToggle');
    const nav = document.getElementById('siteNav');
    if (!header || !toggle || !nav) return;
    const mobile = window.matchMedia('(max-width: 63.999rem)');
    const label = toggle.querySelector('.menu-label');
    let open = false;

    function setOpen(requested) {
      open = mobile.matches && requested;
      nav.hidden = mobile.matches && !open;
      toggle.hidden = !mobile.matches;
      toggle.setAttribute('aria-expanded', String(open));
      toggle.setAttribute('aria-label', open ? 'Close navigation' : 'Open navigation');
      if (label) label.textContent = open ? 'Close' : 'Menu';
    }

    const inside = target => header.contains(target) || nav.contains(target);

    toggle.addEventListener('click', () => setOpen(!open));
    nav.addEventListener('click', event => {
      if (event.target.closest('a')) setOpen(false);
    });
    document.addEventListener('keydown', event => {
      if (event.key === 'Escape' && open) {
        event.preventDefault();
        setOpen(false);
        toggle.focus();
      }
    });
    document.addEventListener('pointerdown', event => {
      if (open && !inside(event.target)) setOpen(false);
    });
    document.addEventListener('focusin', event => {
      if (open && !inside(event.target)) setOpen(false);
    });
    const resized = () => {
      const active = document.activeElement;
      setOpen(false);
      if (mobile.matches && nav.contains(active)) toggle.focus({ preventScroll: true });
      else if (!mobile.matches && active === toggle) nav.querySelector('a')?.focus({ preventScroll: true });
    };
    if (mobile.addEventListener) mobile.addEventListener('change', resized);
    else mobile.addListener(resized);
    setOpen(false);
  }

  function setupProgress() {
    const bar = document.getElementById('readProgress');
    if (!bar) return;
    let ticking = false;
    const update = () => {
      ticking = false;
      const scope = document.documentElement;
      const max = scope.scrollHeight - window.innerHeight;
      const ratio = max > 0 ? Math.min(1, Math.max(0, window.scrollY / max)) : 0;
      bar.style.width = (ratio * 100).toFixed(2) + '%';
    };
    const schedule = () => {
      if (ticking) return;
      ticking = true;
      window.requestAnimationFrame(update);
    };
    window.addEventListener('scroll', schedule, { passive: true });
    window.addEventListener('resize', schedule);
    update();
  }

  function setupReveal() {
    const items = [...document.querySelectorAll('.reveal')];
    if (!items.length) return;
    const reduce = window.matchMedia('(prefers-reduced-motion: reduce)');
    if (!('IntersectionObserver' in window) || reduce.matches) {
      items.forEach(item => item.classList.add('is-visible'));
      return;
    }
    const observer = new IntersectionObserver((entries, obs) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue;
        entry.target.classList.add('is-visible');
        obs.unobserve(entry.target);
      }
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.05 });
    for (const item of items) {
      if (item.getBoundingClientRect().top < window.innerHeight * 0.92) item.classList.add('is-visible');
      else {
        item.classList.add('reveal-pending');
        observer.observe(item);
      }
    }
  }

  function setupDemo() {
    const tabs = document.getElementById('demoTabs');
    if (!tabs) return;
    const buttons = [...tabs.querySelectorAll('[role="tab"]')];
    if (!buttons.length) return;

    function select(index, focus) {
      buttons.forEach((button, position) => {
        const active = position === index;
        button.setAttribute('aria-selected', String(active));
        button.tabIndex = active ? 0 : -1;
        const panel = document.getElementById(button.getAttribute('aria-controls'));
        if (panel) panel.hidden = !active;
      });
      if (focus) buttons[index].focus();
    }

    tabs.addEventListener('click', event => {
      const button = event.target.closest('[role="tab"]');
      if (!button) return;
      select(buttons.indexOf(button), false);
    });
    tabs.addEventListener('keydown', event => {
      const step = event.key === 'ArrowRight' ? 1 : event.key === 'ArrowLeft' ? -1 : 0;
      if (step) {
        const current = buttons.findIndex(button => button.getAttribute('aria-selected') === 'true');
        event.preventDefault();
        select((current + step + buttons.length) % buttons.length, true);
      } else if (event.key === 'Home' || event.key === 'End') {
        event.preventDefault();
        select(event.key === 'Home' ? 0 : buttons.length - 1, true);
      }
    });
    select(0, false);
    tabs.hidden = false;
  }

  function copyHint(id) {
    if (id === 'catalogLink') return 'Open the link to restore these filters.';
    if (id === 'loadstringCode') return 'Paste it into your executor.';
    if (id === 'uiLibCode' || id === 'sdkCode') return 'Paste it into your script.';
    return 'Paste it into UAI.';
  }

  function setupCopy() {
    const status = document.getElementById('copyStatus');
    let statusTimer;
    function announce(message, duration) {
      if (!status) return;
      window.clearTimeout(statusTimer);
      status.textContent = message;
      statusTimer = window.setTimeout(() => { status.textContent = ''; }, duration);
    }

    function selectText(target) {
      try {
        const focusTarget = target.closest('pre') || target;
        if (!focusTarget.hasAttribute('tabindex')) focusTarget.setAttribute('tabindex', '-1');
        focusTarget.focus({ preventScroll: true });
        const selection = window.getSelection();
        if (!selection) return false;
        const range = document.createRange();
        range.selectNodeContents(target);
        selection.removeAllRanges();
        selection.addRange(range);
        return true;
      } catch {
        return false;
      }
    }

    document.querySelectorAll('[data-copy]').forEach(button => {
      const target = document.getElementById(button.dataset.copy);
      const label = button.querySelector('[data-copy-label]');
      if (!target || !label) return;
      const defaultLabel = label.textContent;
      const name = button.dataset.copyName || 'Text';
      let resetTimer;
      let copying = false;
      button.addEventListener('click', async () => {
        if (copying) return;
        copying = true;
        window.clearTimeout(resetTimer);
        button.setAttribute('aria-busy', 'true');
        button.setAttribute('aria-disabled', 'true');
        label.textContent = 'Copying…';
        try {
          if (!navigator.clipboard?.writeText) throw new Error('Clipboard unavailable');
          await navigator.clipboard.writeText(target.textContent.trim());
          label.textContent = 'Copied';
          button.dataset.state = 'copied';
          announce(name + ' copied. ' + copyHint(button.dataset.copy), 4000);
        } catch {
          const selected = selectText(target);
          label.textContent = selected ? 'Text selected' : 'Copy manually';
          button.dataset.state = 'manual';
          announce(selected
            ? name + ' selected. Use Ctrl+C, ⌘C, or your device’s Copy command.'
            : 'Clipboard unavailable. Select the ' + name.toLowerCase() + ' text and copy it manually.', 10000);
        } finally {
          copying = false;
          button.removeAttribute('aria-busy');
          button.removeAttribute('aria-disabled');
          resetTimer = window.setTimeout(() => {
            label.textContent = defaultLabel;
            delete button.dataset.state;
          }, 2500);
        }
      });
      button.hidden = false;
    });
  }

  function setupCatalog() {
    const toolbar = document.getElementById('toolFilters');
    const search = document.getElementById('toolSearch');
    const category = document.getElementById('toolCategory');
    const clear = document.getElementById('clearFilters');
    const status = document.getElementById('catalogStatus');
    const empty = document.getElementById('catalogEmpty');
    const catalog = document.getElementById('toolCatalog');
    if (!toolbar || !search || !category || !clear || !status || !empty || !catalog) return;

    const groups = [...catalog.querySelectorAll('.tool-group')].map(element => {
      const label = element.querySelector('.tool-group-label').textContent;
      return {
        element, label, id: element.dataset.group, browsingOpen: element.open,
        count: element.querySelector('.tool-group-count'),
        rows: [...element.querySelectorAll('.tool-row')].map(row => ({
          element: row,
          text: (label + ' ' + row.textContent).toLowerCase(),
          risk: row.querySelector('.risk-danger') ? 'danger'
            : row.querySelector('.risk-write') ? 'write' : 'read',
        })),
      };
    });
    const total = groups.reduce((sum, group) => sum + group.rows.length, 0);
    const chips = [...document.querySelectorAll('#riskFilters .chip')];
    const share = document.getElementById('catalogShare');
    const link = document.getElementById('catalogLink');
    let filter = 'all';
    let filtering = false;
    let timer;

    function syncUrl() {
      const url = new URL(window.location.href);
      const shareUrl = new URL(window.location.href);
      shareUrl.search = '';
      const params = { toolQuery: search.value.trim(), toolGroup: category.value, toolRisk: filter === 'all' ? '' : filter };
      for (const [key, value] of Object.entries(params)) {
        if (value) { url.searchParams.set(key, value); shareUrl.searchParams.set(key, value); }
        else url.searchParams.delete(key);
      }
      shareUrl.hash = 'tools';
      if (link) link.textContent = shareUrl.href;
      // Replace the current entry so typing does not flood the Back button.
      if (url.href !== window.location.href) {
        try { window.history.replaceState(window.history.state, '', url); } catch { /* file previews may forbid history */ }
      }
    }

    function restoreUrl() {
      const params = new URL(window.location.href).searchParams;
      search.value = (params.get('toolQuery') || '').slice(0, 256);
      const wanted = params.get('toolGroup');
      category.value = groups.some(group => group.id === wanted) ? wanted : '';
      const risk = params.get('toolRisk');
      applyFilter(['read', 'write', 'danger'].includes(risk) ? risk : 'all');
    }

    function applyFilters() {
      window.clearTimeout(timer);
      const words = search.value.trim().toLowerCase().split(/\s+/).filter(Boolean);
      const active = words.length > 0 || category.value !== '' || filter !== 'all';
      let found = 0;
      let visibleGroups = 0;
      for (const group of groups) {
        if (active && !filtering) group.browsingOpen = group.element.open;
        let count = 0;
        for (const row of group.rows) {
          const matches = (!category.value || category.value === group.id) &&
            (filter === 'all' || filter === row.risk) &&
            words.every(word => row.text.includes(word));
          row.element.hidden = !matches;
          if (matches) count++;
        }
        group.element.hidden = count === 0;
        group.count.textContent = active
          ? count + ' / ' + group.rows.length + ' tools'
          : group.rows.length + ' tools';
        if (active) group.element.open = count > 0;
        else if (filtering) group.element.open = group.browsingOpen;
        found += count;
        if (count) visibleGroups++;
      }
      filtering = active;
      clear.disabled = !active;
      empty.hidden = found > 0;
      status.textContent = (active ? found + ' of ' + total : total) +
        (found === 1 && !active ? ' tool' : ' tools') + ' across ' + visibleGroups +
        (visibleGroups === 1 ? ' group' : ' groups');
      syncUrl();
    }

    function applyFilter(next) {
      filter = next;
      for (const chip of chips) {
        chip.setAttribute('aria-pressed', String(chip.dataset.risk === (next === 'all' ? '' : next)));
      }
      applyFilters();
    }

    search.addEventListener('input', () => {
      window.clearTimeout(timer);
      timer = window.setTimeout(applyFilters, 80);
    });
    category.addEventListener('change', applyFilters);
    clear.addEventListener('click', () => {
      search.value = '';
      category.value = '';
      filter = 'all';
      for (const chip of chips) chip.setAttribute('aria-pressed', String(chip.dataset.risk === ''));
      applyFilters();
      search.focus();
    });
    for (const chip of chips) chip.addEventListener('click', () => applyFilter(chip.dataset.risk || 'all'));
    document.getElementById('catalogExpandAll')?.addEventListener('click', () => {
      for (const group of groups) if (!group.element.hidden) group.element.open = true;
    });
    document.getElementById('catalogCollapseAll')?.addEventListener('click', () => {
      for (const group of groups) if (!group.element.hidden) group.element.open = false;
    });
    document.addEventListener('keydown', event => {
      if (event.key !== '/' || event.ctrlKey || event.metaKey || event.altKey || event.isComposing) return;
      const tag = document.activeElement?.tagName;
      if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || document.activeElement?.isContentEditable) return;
      event.preventDefault();
      search.focus();
    });
    search.addEventListener('keydown', event => {
      if (event.key !== 'Escape' || !search.value) return;
      event.preventDefault();
      event.stopPropagation();
      search.value = '';
      applyFilters();
    });
    window.addEventListener('pageshow', restoreUrl);
    window.addEventListener('popstate', restoreUrl);
    restoreUrl();
    toolbar.hidden = false;
    document.getElementById('riskFilters').hidden = false;
    document.getElementById('catalogActions').hidden = false;
    if (share) share.hidden = false;
  }


  function setupMotion() {
    const toggle = document.getElementById('motionToggle');
    const label = toggle?.querySelector('[data-motion-label]');
    const reduced = window.matchMedia('(prefers-reduced-motion: reduce)');
    let paused = reduced.matches;
    const video = document.querySelector('.showcase-media video');
    const recording = document.querySelector('.recording-details');

    const syncVideo = () => {
      if (!video) return;
      if (paused || document.hidden || !recording?.open) video.pause();
      else video.play()?.catch(() => {});
    };
    const publish = () => {
      document.body.classList.toggle('motion-paused', paused);
      if (toggle) toggle.setAttribute('aria-pressed', String(paused));
      if (label) label.textContent = paused ? 'Resume motion' : 'Pause motion';
      document.dispatchEvent(new CustomEvent('site-motion-change', { detail: { paused } }));
      syncVideo();
    };
    toggle?.addEventListener('click', () => { paused = !paused; publish(); });
    const preferenceChanged = () => { paused = reduced.matches; publish(); };
    if (reduced.addEventListener) reduced.addEventListener('change', preferenceChanged);
    else reduced.addListener(preferenceChanged);
    document.addEventListener('visibilitychange', () => {
      document.body.classList.toggle('document-hidden', document.hidden);
      syncVideo();
    });
    recording?.addEventListener('toggle', syncVideo);
    // Collapsed recordings never play invisibly. Native controls remain usable.
    if (video) {
      video.controls = true;
      video.autoplay = false;
      video.pause();
    }
    if (toggle) toggle.hidden = false;
    publish();
  }

  function setupHero() {
    const canvas = document.getElementById('heroCanvas');
    const stage = document.getElementById('heroStage');
    if (!canvas || !stage) return;
    let context;
    try { context = canvas.getContext('2d', { alpha: true }); } catch { return; }
    if (!context) return;
    let width = 0;
    let height = 0;
    let frame = 0;
    let elapsed = 0;
    let lastFrame = 0;
    let visible = true;
    let paused = document.body.classList.contains('motion-paused');
    let pointerX = 0;
    let pointerY = 0;
    let targetX = 0;
    let targetY = 0;
    const tau = Math.PI * 2;
    const surface = [];
    const major = 48;
    const minor = 14;
    // A bounded 672-point surface. No libraries, textures, GPU, or external assets.
    for (let ring = 0; ring < major; ring++) {
      const u = ring / major * tau;
      const points = [];
      for (let side = 0; side < minor; side++) {
        const v = side / minor * tau;
        const tube = .47 + Math.sin(u * 3) * .07;
        const radius = 1.52 + tube * Math.cos(v);
        points.push([radius * Math.cos(u), tube * Math.sin(v), radius * Math.sin(u)]);
      }
      surface.push(points);
    }

    function rotate(point, x, y, z) {
      const [px, py, pz] = point;
      const cx = Math.cos(x), sx = Math.sin(x);
      const cy = Math.cos(y), sy = Math.sin(y);
      const cz = Math.cos(z), sz = Math.sin(z);
      const ry = py * cx - pz * sx;
      const rz = py * sx + pz * cx;
      const rx = px * cy + rz * sy;
      const depth = -px * sy + rz * cy;
      return [rx * cz - ry * sz, rx * sz + ry * cz, depth];
    }
    function project(point) {
      const scale = Math.min(width, height) * .78 / (4.8 - point[2]);
      return { x: width * .5 + point[0] * scale, y: height * .5 + point[1] * scale, z: point[2] };
    }
    function path(points, color, lineWidth, close = false) {
      context.beginPath();
      points.forEach((point, index) => {
        if (index) context.lineTo(point.x, point.y);
        else context.moveTo(point.x, point.y);
      });
      if (close) context.closePath();
      context.strokeStyle = color;
      context.lineWidth = lineWidth;
      context.stroke();
    }

    function draw() {
      if (!width || !height) return;
      const time = elapsed * .001;
      const rx = .9 + Math.sin(time * .17) * .14 + pointerY * .12;
      const ry = time * .105 + pointerX * .14;
      const rz = -.47 + Math.sin(time * .13) * .12;
      context.clearRect(0, 0, width, height);
      const glow = context.createRadialGradient(width * .5, height * .5, 0, width * .5, height * .5, Math.min(width, height) * .45);
      glow.addColorStop(0, 'rgba(52, 52, 52, .11)');
      glow.addColorStop(.45, 'rgba(86, 86, 86, .055)');
      glow.addColorStop(1, 'rgba(160, 160, 160, 0)');
      context.fillStyle = glow;
      context.fillRect(0, 0, width, height);

      // Delicate orbital paths give the object a stable spatial reference.
      for (let orbit = 0; orbit < 3; orbit++) {
        const points = [];
        for (let step = 0; step <= 96; step++) {
          const angle = step / 96 * tau;
          const raw = [Math.cos(angle) * 2.47, Math.sin(angle) * 2.47, 0];
          points.push(project(rotate(raw, .8 + orbit * .64, .2 + orbit * .75, -.5)));
        }
        context.setLineDash(orbit === 1 ? [2, 7] : []);
        path(points, orbit === 1 ? '#2626264a' : '#66666640', .7);
        context.setLineDash([]);
        const phase = (time * .028 + orbit / 3) % 1 * tau;
        const dot = project(rotate([Math.cos(phase) * 2.47, Math.sin(phase) * 2.47, 0], .8 + orbit * .64, .2 + orbit * .75, -.5));
        context.beginPath();
        context.arc(dot.x, dot.y, 2.6, 0, tau);
        context.fillStyle = '#111111';
        context.fill();
      }

      const projected = surface.map(ring => ring.map(point => project(rotate(point, rx, ry, rz))));
      const curves = [];
      for (let ring = 0; ring < major; ring++) {
        const points = projected[ring];
        curves.push({ points, z: points.reduce((sum, p) => sum + p.z, 0) / minor, close: true });
      }
      for (let side = 0; side < minor; side += 2) {
        const points = projected.map(ring => ring[side]);
        curves.push({ points, z: points.reduce((sum, p) => sum + p.z, 0) / major, close: true });
      }
      curves.sort((a, b) => a.z - b.z);
      curves.forEach(curve => {
        const alpha = .19 + (curve.z + 2) / 4 * .44;
        path(curve.points, 'rgba(32, 32, 32, ' + alpha.toFixed(3) + ')', .75, true);
      });
      for (let ring = 0; ring < major; ring += 4) {
        for (let side = 0; side < minor; side += 3) {
          const dot = projected[ring][side];
          if (dot.z < -.5) continue;
          context.fillStyle = 'rgba(13, 13, 13, ' + (.35 + dot.z * .22).toFixed(3) + ')';
          context.fillRect(dot.x - .65, dot.y - .65, 1.3, 1.3);
        }
      }

      const vertices = [
        [-.57,-.57,-.57],[.57,-.57,-.57],[.57,.57,-.57],[-.57,.57,-.57],
        [-.57,-.57,.57],[.57,-.57,.57],[.57,.57,.57],[-.57,.57,.57],
      ].map(point => project(rotate(point, -.32 + pointerY * .1, .64 + time * .08 + pointerX * .1, -.16)));
      const faces = [[0,1,2,3],[4,7,6,5],[0,4,5,1],[3,2,6,7],[0,3,7,4],[1,5,6,2]]
        .map((ids, index) => ({ points: ids.map(id => vertices[id]), index, z: ids.reduce((sum, id) => sum + vertices[id].z, 0) / 4 }))
        .sort((a,b) => a.z-b.z);
      faces.forEach(face => {
        context.beginPath();
        face.points.forEach((point, index) => index ? context.lineTo(point.x, point.y) : context.moveTo(point.x, point.y));
        context.closePath();
        const gradient = context.createLinearGradient(width * .4, height * .35, width * .6, height * .65);
        gradient.addColorStop(0, face.z > 0 ? '#212121ed' : '#8a8a8ae6');
        gradient.addColorStop(1, face.z > 0 ? '#9c9c9ced' : '#c8c8c8ed');
        context.fillStyle = gradient;
        context.fill();
        context.strokeStyle = 'rgba(9, 9, 9, ' + (face.z > 0 ? '.7' : '.2') + ')';
        context.lineWidth = .9;
        context.stroke();
      });
    }

    const active = () => !paused && visible && !document.hidden;
    function animate(now) {
      frame = 0;
      if (!active()) return;
      if (!lastFrame) lastFrame = now;
      const delta = now - lastFrame;
      if (delta >= 1000 / 30) {
        elapsed += Math.min(delta, 70);
        lastFrame = now;
        pointerX += (targetX - pointerX) * .08;
        pointerY += (targetY - pointerY) * .08;
        draw();
      }
      frame = window.requestAnimationFrame(animate);
    }
    function sync() {
      if (frame) window.cancelAnimationFrame(frame);
      frame = 0;
      lastFrame = 0;
      if (active()) frame = window.requestAnimationFrame(animate);
    }
    function resize() {
      const bounds = canvas.getBoundingClientRect();
      width = bounds.width;
      height = bounds.height;
      const dpr = Math.min(window.devicePixelRatio || 1, width < 500 ? 1 : 1.5);
      canvas.width = Math.round(width * dpr);
      canvas.height = Math.round(height * dpr);
      context.setTransform(dpr, 0, 0, dpr, 0, 0);
      draw();
    }
    stage.addEventListener('pointermove', event => {
      if (paused || event.pointerType === 'touch') return;
      const bounds = stage.getBoundingClientRect();
      targetX = (event.clientX - bounds.left) / bounds.width * 2 - 1;
      targetY = (event.clientY - bounds.top) / bounds.height * 2 - 1;
    }, { passive: true });
    stage.addEventListener('pointerleave', () => { targetX = 0; targetY = 0; });
    document.addEventListener('site-motion-change', event => { paused = event.detail.paused; sync(); });
    document.addEventListener('visibilitychange', sync);
    let visibilityObserver;
    if ('IntersectionObserver' in window) {
      visibilityObserver = new IntersectionObserver(entries => { visible = entries[0].isIntersecting; sync(); }, { threshold: .01 });
      visibilityObserver.observe(stage);
    }
    let resizeObserver;
    if ('ResizeObserver' in window) {
      resizeObserver = new ResizeObserver(resize);
      resizeObserver.observe(stage);
    } else window.addEventListener('resize', resize, { passive: true });
    window.addEventListener('pagehide', () => { visible = false; sync(); });
    window.addEventListener('pageshow', () => {
      const bounds = stage.getBoundingClientRect();
      visible = bounds.bottom > 0 && bounds.top < window.innerHeight;
      sync();
    });
    resize();
    stage.classList.add('canvas-ready');
    sync();
  }

  function setupSectionTracking() {
    if (!('IntersectionObserver' in window)) return;
    const links = [...document.querySelectorAll('.site-nav a[href^="#"]')];
    const sections = links.map(link => document.querySelector(link.getAttribute('href'))).filter(Boolean);
    const observer = new IntersectionObserver(entries => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue;
        for (const link of links) {
          if (link.getAttribute('href') === '#' + entry.target.id) link.setAttribute('aria-current', 'location');
          else link.removeAttribute('aria-current');
        }
      }
    }, { rootMargin: '-20% 0px -65% 0px' });
    sections.forEach(section => observer.observe(section));
  }

  setupNavigation();
  setupProgress();
  setupReveal();
  setupDemo();
  setupCopy();
  setupCatalog();
  setupMotion();
  setupHero();
  setupSectionTracking();
})();
