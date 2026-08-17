/**
 * 直接打印一个 DOM 节点：把它克隆到 body 下，用 @media print 只显示这份克隆、隐藏其余，
 * 再调起浏览器打印对话框。复用主文档已加载好的样式（不重新拉外链/CDN 的 CSS，
 * 避免生产上外链样式表未就绪打出无样式版），本地与生产行为一致。
 * @param {HTMLElement} el 要打印的节点（如提成表/考核表的只读容器）
 * @param {string} title 打印文档标题（浏览器打印页眉 / 另存 PDF 的默认文件名）
 */
export function printElement(el, title = '') {
  if (!el) return;

  const clone = el.cloneNode(true);

  // cloneNode 不复制用户当前输入的 input/textarea/select 值，逐一手动搬（否则打印成空框）。
  const srcFields = el.querySelectorAll('input, textarea, select');
  const dstFields = clone.querySelectorAll('input, textarea, select');
  srcFields.forEach((src, i) => {
    const dst = dstFields[i];
    if (!dst) return;
    if (src.tagName === 'SELECT') {
      dst.value = src.value;
    } else if (src.type === 'checkbox' || src.type === 'radio') {
      dst.checked = src.checked;
    } else if (src.tagName === 'TEXTAREA') {
      dst.textContent = src.value;
    } else {
      dst.setAttribute('value', src.value);
    }
  });

  // 克隆挂到 body 直下（脱离 backdrop-blur 等造成的定位/裁剪祖先）。
  const portal = document.createElement('div');
  portal.setAttribute('data-crm-print-portal', '');

  // 顶部品牌头：左上角 Wintouch 橙色字标（与 PI 单据同一 logo）。
  const header = document.createElement('div');
  header.className = 'flex items-center mb-4';
  const logo = document.createElement('img');
  logo.src = '/brand-assets/pi-logo.png';
  logo.alt = 'Wintouch';
  logo.className = 'h-9 w-auto';
  header.appendChild(logo);
  portal.appendChild(header);

  portal.appendChild(clone);
  document.body.appendChild(portal);

  // 屏幕上藏起这份克隆；打印时藏掉 body 其余直接子节点、只留克隆，并保留背景/渐变配色。
  const style = document.createElement('style');
  style.setAttribute('data-crm-print-style', '');
  style.textContent =
    '@media screen{[data-crm-print-portal]{display:none!important}}' +
    '@media print{body>*:not([data-crm-print-portal]){display:none!important}' +
    '[data-crm-print-portal]{display:block!important;padding:16px}' +
    '*{-webkit-print-color-adjust:exact!important;print-color-adjust:exact!important}}';
  document.head.appendChild(style);

  const prevTitle = document.title;
  if (title) document.title = title;

  let cleaned = false;
  const cleanup = () => {
    if (cleaned) return;
    cleaned = true;
    portal.remove();
    style.remove();
    document.title = prevTitle;
    window.removeEventListener('afterprint', cleanup);
  };
  window.addEventListener('afterprint', cleanup);

  // 等 portal 内图片（logo / 签名）加载完再打印，否则可能打印时 logo 还没出来。
  let printed = false;
  const doPrint = () => {
    if (printed) return;
    printed = true;
    window.print();
    // afterprint 在个别浏览器不触发时的兜底清理。
    setTimeout(cleanup, 60000);
  };
  const imgs = Array.from(portal.querySelectorAll('img'));
  const pending = imgs.filter(img => !img.complete);
  if (pending.length) {
    let n = pending.length;
    const onReady = () => {
      n -= 1;
      if (n <= 0) doPrint();
    };
    pending.forEach(img => {
      img.addEventListener('load', onReady);
      img.addEventListener('error', onReady);
    });
    setTimeout(doPrint, 3000); // 兜底：图片迟迟不回也别卡死
  } else {
    doPrint();
  }
}
