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

  function setupCounters() {
    const nodes = [...document.querySelectorAll('[data-count]')];
    if (!nodes.length) return;
    const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    const run = element => {
      const target = Number(element.dataset.count);
      if (!Number.isFinite(target)) return;
      if (reduce || !('requestAnimationFrame' in window)) {
        element.textContent = String(target);
        return;
      }
      const start = window.performance.now();
      const step = now => {
        const progress = Math.min(1, (now - start) / 900);
        const eased = 1 - Math.pow(1 - progress, 3);
        element.textContent = String(Math.round(target * eased));
        if (progress < 1) window.requestAnimationFrame(step);
        else element.textContent = String(target);
      };
      window.requestAnimationFrame(step);
    };
    if (!('IntersectionObserver' in window)) {
      nodes.forEach(run);
      return;
    }
    const observer = new IntersectionObserver((entries, obs) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue;
        run(entry.target);
        obs.unobserve(entry.target);
      }
    }, { threshold: 0.4 });
    nodes.forEach(node => observer.observe(node));
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
          risk: row.classList.contains('risk-danger') ? 'danger'
            : row.classList.contains('risk-write') ? 'write' : 'read',
        })),
      };
    });
    const total = groups.reduce((sum, group) => sum + group.rows.length, 0);
    const chips = [...document.querySelectorAll('#riskFilters .chip')];
    let filter = 'all';
    let filtering = false;
    let timer;

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
      if (event.key !== '/' || event.ctrlKey || event.metaKey || event.altKey) return;
      const tag = document.activeElement?.tagName;
      if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || document.activeElement?.isContentEditable) return;
      event.preventDefault();
      search.focus();
    });
    search.addEventListener('keydown', event => {
      if (event.key !== 'Escape' || !search.value) return;
      event.stopPropagation();
      search.value = '';
      applyFilters();
    });
    window.addEventListener('pageshow', applyFilters);
    applyFilters();
    toolbar.hidden = false;
    document.getElementById('riskFilters').hidden = false;
    document.getElementById('catalogActions').hidden = false;
  }

  function setupScrollSpy() {
    const nav = document.getElementById('siteNav');
    const pill = document.getElementById('navPill');
    if (!nav) return;
    const links = new Map();
    for (const link of nav.querySelectorAll('a[href^="#"]')) {
      const id = link.getAttribute('href').slice(1);
      const section = document.getElementById(id);
      if (section) links.set(id, { link, section });
    }
    if (!links.size) return;

    function movePill(targetLink) {
      if (!pill || !targetLink) {
        if (pill) pill.style.opacity = '0';
        return;
      }
      const navRect = nav.getBoundingClientRect();
      const linkRect = targetLink.getBoundingClientRect();
      if (linkRect.width === 0 || linkRect.height === 0 || window.innerWidth < 1024) {
        pill.style.opacity = '0';
        return;
      }
      const left = linkRect.left - navRect.left;
      const top = linkRect.top - navRect.top;
      pill.style.width = linkRect.width + 'px';
      pill.style.height = linkRect.height + 'px';
      pill.style.transform = `translate3d(${left}px, ${top}px, 0)`;
      pill.style.opacity = '1';
    }

    let activeId = null;

    function setActive(id) {
      if (activeId === id) return;
      activeId = id;
      let activeLink = null;
      for (const [linkId, entry] of links) {
        if (linkId === id) {
          entry.link.setAttribute('aria-current', 'true');
          activeLink = entry.link;
        } else {
          entry.link.removeAttribute('aria-current');
        }
      }
      movePill(activeLink);
    }

    for (const [, entry] of links) {
      entry.link.addEventListener('pointerenter', () => movePill(entry.link));
      entry.link.addEventListener('pointerleave', () => {
        const currentLink = activeId ? links.get(activeId)?.link : null;
        movePill(currentLink);
      });
      entry.link.addEventListener('click', () => {
        const id = entry.link.getAttribute('href').slice(1);
        setActive(id);
      });
    }

    window.addEventListener('resize', () => {
      const currentLink = activeId ? links.get(activeId)?.link : null;
      movePill(currentLink);
    }, { passive: true });

    if ('IntersectionObserver' in window) {
      const visible = new Set();
      const observer = new IntersectionObserver(entries => {
        for (const entry of entries) {
          if (entry.isIntersecting) visible.add(entry.target.id);
          else visible.delete(entry.target.id);
        }
        let current = null;
        for (const [id] of links) {
          if (visible.has(id)) { current = id; break; }
        }
        setActive(current);
      }, { rootMargin: '-25% 0px -65% 0px' });
      for (const { section } of links.values()) observer.observe(section);
    }

    const hash = window.location.hash.slice(1);
    if (hash && links.has(hash)) {
      setActive(hash);
    }
  }

  function setupCardMotion() {
    const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (reduce) return;
    const cards = document.querySelectorAll('.tile, .prompt-card, .code-card, .doc-pillar-card, .doc-table-card');
    cards.forEach(card => {
      card.addEventListener('pointermove', event => {
        const rect = card.getBoundingClientRect();
        const x = event.clientX - rect.left;
        const y = event.clientY - rect.top;
        card.style.setProperty('--mouse-x', x + 'px');
        card.style.setProperty('--mouse-y', y + 'px');
      }, { passive: true });
    });
  }

  function setupShowcaseVideo() {
    const video = document.querySelector('.showcase-media video');
    if (!video) return;
    video.removeAttribute('controls');
    video.controls = false;
    const playPromise = video.play();
    if (playPromise !== undefined) {
      playPromise.catch(() => {});
    }
  }

  setupNavigation();
  setupProgress();
  setupReveal();
  setupCounters();
  setupDemo();
  setupCopy();
  setupCatalog();
  setupScrollSpy();
  setupCardMotion();
  setupShowcaseVideo();
})();
