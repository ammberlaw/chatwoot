// 阿里后台页面上的浮窗：先告诉你这个买家有没有被同事建过档，再一键建到 wintouchspace。
// 整个面板放进 shadow DOM，跟阿里自己的样式互不干扰。

(() => {
  const { guess, cssPath, pageKey, readSelector, toCountry } = window.WTS;

  const FIELDS = [
    { key: 'alibaba_account', label: '阿里买家 ID', required: true },
    { key: 'name', label: '公司名称', required: true },
    { key: 'contact_email', label: '联系邮箱' },
    { key: 'primary_contact_name', label: '主要联系人' },
    { key: 'trade_country', label: '国家地区' },
  ];

  const send = (type, payload) => chrome.runtime.sendMessage({ type, payload });
  const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const day = iso => (iso ? new Date(iso).toLocaleDateString('zh-CN') : '');

  // ── 面板骨架 ──────────────────────────────────────────────
  const host = document.createElement('div');
  host.style.cssText = 'position:fixed;z-index:2147483647;right:20px;bottom:20px;';
  const root = host.attachShadow({ mode: 'open' });
  root.innerHTML = `
    <style>
      :host, * { box-sizing: border-box; }
      .launcher { width:48px;height:48px;border-radius:50%;border:0;cursor:pointer;
        background:#ffc53d;color:#1a1c20;font-weight:700;font-size:15px;
        box-shadow:0 4px 14px rgba(0,0,0,.18); }
      .panel { display:none;width:340px;background:#fff;border-radius:14px;overflow:hidden;
        box-shadow:0 10px 40px rgba(0,0,0,.22);
        font:13px/1.55 -apple-system,"PingFang SC",system-ui,sans-serif;color:#1f2430; }
      .panel.open { display:block; }
      header { display:flex;align-items:center;justify-content:space-between;
        padding:11px 14px;background:#1f2430;color:#fff;font-weight:600;font-size:13px; }
      header button { background:transparent;border:0;color:#fff;font-size:17px;cursor:pointer;line-height:1; }
      .body { padding:12px 14px 14px;max-height:72vh;overflow:auto; }
      .banner { padding:9px 11px;border-radius:8px;margin-bottom:11px;font-size:12.5px; }
      .banner.hit { background:#fde8e8;color:#a02c2c; }
      .banner.mine { background:#fff4d6;color:#7a5a00; }
      .banner.free { background:#e4f3e0;color:#37702f; }
      .banner.wait { background:#eef0f3;color:#5b6172; }
      .row { margin-bottom:9px; }
      .row label { display:block;font-size:11.5px;color:#6b7280;margin-bottom:3px; }
      .req { color:#d64545; }
      .ctl { display:flex;gap:5px; }
      .ctl input { flex:1;min-width:0;padding:6px 8px;font-size:12.5px;
        border:1px solid #d6d8dd;border-radius:6px;font-family:inherit; }
      .ctl input:focus { outline:2px solid #ffc53d;outline-offset:-1px;border-color:#ffc53d; }
      .pick { flex:0 0 auto;padding:0 8px;font-size:11.5px;border:1px solid #d6d8dd;
        border-radius:6px;background:#f7f7f8;cursor:pointer;font-family:inherit;color:#4b5161; }
      .pick:hover { background:#ececee; }
      .note { font-size:11.5px;color:#6b7280;margin:2px 0 11px; }
      .submit { width:100%;padding:9px;margin-top:4px;font-size:13px;font-weight:600;
        border:0;border-radius:8px;background:#ffc53d;color:#1a1c20;cursor:pointer;font-family:inherit; }
      .submit:disabled { opacity:.5;cursor:default; }
      .msg { margin-top:9px;font-size:12.5px; }
      .msg.err { color:#a02c2c; }
      .msg.ok { color:#37702f; }
      a { color:#1f6feb; }
    </style>
    <button class="launcher" title="wintouchspace 建档助手">建档</button>
    <div class="panel">
      <header><span>wintouchspace 建档</span><button class="close">×</button></header>
      <div class="body">
        <div class="banner wait">正在读取页面…</div>
        <div class="fields"></div>
        <div class="note"></div>
        <button class="submit">建档到 wintouchspace</button>
        <div class="msg"></div>
      </div>
    </div>`;
  document.body.appendChild(host);

  const tip = document.createElement('div');
  tip.style.cssText =
    'display:none;position:fixed;z-index:2147483647;left:50%;top:14px;transform:translateX(-50%);' +
    'background:#1f2430;color:#ffc53d;padding:9px 18px;border-radius:999px;pointer-events:none;' +
    'font:13px/1.4 -apple-system,"PingFang SC",system-ui,sans-serif;box-shadow:0 4px 16px rgba(0,0,0,.28);';
  document.body.appendChild(tip);

  const $ = s => root.querySelector(s);
  const panel = $('.panel');
  const banner = $('.banner');
  const msg = $('.msg');

  $('.fields').innerHTML = FIELDS.map(
    f => `<div class="row">
            <label>${esc(f.label)}${f.required ? ' <span class="req">*</span>' : ''}</label>
            <div class="ctl">
              <input data-key="${f.key}" />
              <button class="pick" data-pick="${f.key}" title="点这里再点页面上的文字，以后这类页面就自动填">从页面取</button>
            </div>
          </div>`
  ).join('');

  const inputs = () => [...root.querySelectorAll('input[data-key]')];
  const values = () => Object.fromEntries(inputs().map(i => [i.dataset.key, i.value.trim()]));
  const setValue = (key, v) => {
    const el = root.querySelector(`input[data-key="${key}"]`);
    if (el && v) el.value = v;
  };

  // ── 取值：先用学过的选择器，再退回启发式 ────────────────────
  const learnedKey = 'selectors';
  const loadLearned = async () => ((await chrome.storage.local.get(learnedKey))[learnedKey] || {})[pageKey()] || {};

  const fill = async () => {
    const learned = await loadLearned();
    for (const f of FIELDS) {
      const raw = learned[f.key] ? readSelector(learned[f.key]) : '';
      if (f.key === 'trade_country') {
        setValue(f.key, toCountry(raw || guess.trade_country_raw()));
      } else {
        setValue(f.key, raw || guess[f.key]?.() || '');
      }
    }
  };

  // ── 查重 ─────────────────────────────────────────────────
  let lastQueried = '';
  const refreshDupe = async () => {
    const v = values();
    const sig = `${v.alibaba_account}|${v.contact_email}|${v.name}`;
    if (sig === lastQueried) return;
    lastQueried = sig;

    if (!v.alibaba_account && !v.contact_email && !v.name) {
      banner.className = 'banner wait';
      banner.textContent = '页面上没认出买家信息，手动填或用「从页面取」。';
      return;
    }

    const res = await send('checkDuplicate', v);
    if (!res?.ok) {
      banner.className = 'banner wait';
      banner.textContent = res?.error || '查重失败';
      return;
    }

    const d = res.data;
    const hit = d.alibaba_hit || d.email_hit;
    if (hit) {
      const how = d.alibaba_hit ? '阿里账号' : '邮箱';
      banner.className = `banner ${hit.is_mine ? 'mine' : 'hit'}`;
      banner.innerHTML = hit.is_mine
        ? `✅ 这是<b>你自己</b>的客户：${esc(hit.name)}（${esc(hit.customer_code)}），${day(hit.created_at)} 建的档。`
        : `⛔ 已被 <b>${esc(hit.owner)}</b> 建档：${esc(hit.name)}（${esc(hit.customer_code)}），${day(hit.created_at)} · 按${how}命中。`;
      return;
    }

    if (d.name_hits?.length) {
      banner.className = 'banner mine';
      banner.innerHTML =
        `⚠️ 公司名相近的已有 ${d.name_hits.length} 个，确认不是同一家再建：<br>` +
        d.name_hits.map(h => `· ${esc(h.name)}（${esc(h.owner)}）`).join('<br>');
      return;
    }

    banner.className = 'banner free';
    banner.textContent = '✅ 全公司都还没建过这个买家，可以建档。';
  };

  // ── 「从页面取」：点一次学一条选择器 ────────────────────────
  // 阿里的页面到处是链接和自己的点击处理，直接监听 click 会被它抢先跑掉（甚至跳走页面）。
  // 所以把整串鼠标事件在**捕获阶段挂到 window 上**截下来——捕获路径是 window → document → …，
  // 页面自己那些（通常挂在 document 或元素上的）处理器一律排在后面。注意必须是 window：
  // 同一个节点上的监听器按注册先后跑，页面先加载、它的 document 捕获监听就排在我们前面，
  // stopPropagation 拦不住同节点的兄弟，只有 stopImmediatePropagation + 更早的节点才行。
  // 取值落在 mousedown 上，preventDefault 顺带挡掉链接跳转。
  const PICK_EVENTS = ['pointerdown', 'mousedown', 'mouseup', 'click', 'auxclick', 'contextmenu'];
  let picking = null;
  let hovered = null;

  const outline = el => {
    if (hovered) hovered.style.outline = hovered.dataset.wtsPrevOutline || '';
    hovered = el;
    if (el) {
      el.dataset.wtsPrevOutline = el.style.outline;
      el.style.outline = '2px solid #ffc53d';
    }
  };
  const onMove = e => outline(e.target);

  // 按下就取值。注意不能只认 mousedown：pointerdown 上一旦 preventDefault，
  // 浏览器就不再派发兼容用的 mousedown/mouseup 了，只认 mousedown 会永远等不到。
  // 所以谁先到用谁，用 picking 置空来保证一次手势只取一次。
  const PRESS = new Set(['pointerdown', 'mousedown']);
  const swallow = async e => {
    e.preventDefault();
    e.stopPropagation();
    if (typeof e.stopImmediatePropagation === 'function') e.stopImmediatePropagation();
    if (!PRESS.has(e.type) || !picking) return;

    const key = picking;
    picking = null;
    const el = e.target;
    const value = (el.innerText || el.textContent || '').trim();
    const store = (await chrome.storage.local.get(learnedKey))[learnedKey] || {};
    store[pageKey()] = { ...(store[pageKey()] || {}), [key]: cssPath(el) };
    await chrome.storage.local.set({ [learnedKey]: store });
    setValue(key, key === 'trade_country' ? toCountry(value) : value);
    stopPick();
    refreshDupe();
  };

  const detachGuards = () =>
    PICK_EVENTS.forEach(t => window.removeEventListener(t, swallow, true));

  const stopPick = ({ immediate = false } = {}) => {
    outline(null);
    document.removeEventListener('mousemove', onMove, true);
    picking = null;
    tip.style.display = 'none';
    panel.classList.add('open');
    // 取值落在按下那一刻，但这一下手势还没走完——pointerup / mouseup / click 还在后头。
    // 立刻撤掉拦截器，收尾的 click 就会漏给页面，把链接点开甚至跳走。多留一会儿，
    // 期间 picking 已置空，swallow 只拦不取。
    if (immediate) detachGuards();
    else setTimeout(detachGuards, 600);
  };

  const startPick = key => {
    picking = key;
    // 收起面板让开视线，但顶部留一条提示——不然面板一消失不知道该干嘛
    panel.classList.remove('open');
    tip.textContent = `点击页面上的文字，取「${FIELDS.find(f => f.key === key).label}」 · Esc 取消`;
    tip.style.display = 'block';
    document.addEventListener('mousemove', onMove, true);
    PICK_EVENTS.forEach(t => window.addEventListener(t, swallow, true));
  };

  // ── 事件绑定 ─────────────────────────────────────────────
  $('.launcher').addEventListener('click', async () => {
    panel.classList.toggle('open');
    if (panel.classList.contains('open')) {
      await fill();
      refreshDupe();
    }
  });
  $('.close').addEventListener('click', () => panel.classList.remove('open'));
  root.addEventListener('click', e => {
    const key = e.target.dataset?.pick;
    if (key) startPick(key);
  });
  inputs().forEach(i => i.addEventListener('change', refreshDupe));
  document.addEventListener('keydown', e => {
    if (e.key === 'Escape' && picking) stopPick({ immediate: true });
  });

  $('.submit').addEventListener('click', async () => {
    const v = values();
    msg.className = 'msg';
    msg.textContent = '';
    if (!v.alibaba_account || !v.name) {
      msg.className = 'msg err';
      msg.textContent = '阿里买家账号和公司名称都要填。';
      return;
    }
    $('.submit').disabled = true;
    const res = await send('createCustomer', v);
    $('.submit').disabled = false;
    if (!res?.ok) {
      msg.className = 'msg err';
      msg.textContent = `建档失败：${res?.error || '未知错误'}`;
      return;
    }
    const c = res.data.payload || res.data;
    msg.className = 'msg ok';
    msg.innerHTML = `✅ 已建档 ${esc(c.customer_code || '')}，已归到你名下。`;
    lastQueried = '';
    refreshDupe();
  });

  $('.note').textContent = '阿里藏了买家邮箱时这里会是空的——先建档，之后阿里的询盘邮件进了邮件中心会自动补上联系人。';
})();
