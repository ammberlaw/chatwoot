/**
 * 直接打印一个 DOM 节点。生产上外链 <link> 的 app CSS 在打印媒体下不生效（只有内联样式生效），
 * 所以这里把元素当前的计算样式内联进克隆，完全不依赖外部样式表，保证打印带样式。
 * 用 @media print 只显示克隆、隐藏页面其余；复用主文档已加载的字体。
 * @param {HTMLElement} el 要打印的节点（如提成表/考核表的只读容器）
 * @param {string} title 打印文档标题（浏览器打印页眉 / 另存 PDF 的默认文件名）
 */

// 内联的视觉属性白名单：只搬「颜色/字体/边框/间距/弹性布局」等，
// 不搬 width/height/position 等尺寸定位（避免把屏幕像素宽度焊死导致打印溢出）。
const PRINT_PROPS = [
  'color', 'background-color', 'background-image', 'background-size',
  'background-position', 'background-repeat', 'background-clip',
  '-webkit-background-clip', '-webkit-text-fill-color',
  'font-family', 'font-size', 'font-weight', 'font-style', 'line-height',
  'letter-spacing', 'text-align', 'text-decoration', 'text-transform',
  'white-space', 'vertical-align', 'text-overflow', 'word-break',
  'padding-top', 'padding-right', 'padding-bottom', 'padding-left',
  'margin-top', 'margin-right', 'margin-bottom', 'margin-left',
  'border-top-width', 'border-right-width', 'border-bottom-width', 'border-left-width',
  'border-top-style', 'border-right-style', 'border-bottom-style', 'border-left-style',
  'border-top-color', 'border-right-color', 'border-bottom-color', 'border-left-color',
  'border-top-left-radius', 'border-top-right-radius',
  'border-bottom-left-radius', 'border-bottom-right-radius',
  'display', 'flex-direction', 'flex-wrap', 'align-items', 'align-self',
  'justify-content', 'gap', 'flex-grow', 'flex-shrink', 'flex-basis',
  'table-layout', 'border-collapse', 'border-spacing',
  'box-shadow', 'opacity', 'overflow',
];

function inlineComputedStyles(src, dst) {
  const srcNodes = [src, ...src.querySelectorAll('*')];
  const dstNodes = [dst, ...dst.querySelectorAll('*')];
  srcNodes.forEach((s, i) => {
    const d = dstNodes[i];
    if (!d || d.nodeType !== 1) return;
    const cs = window.getComputedStyle(s);
    let style = d.getAttribute('style') || '';
    PRINT_PROPS.forEach(prop => {
      const val = cs.getPropertyValue(prop);
      if (val && val !== 'none' && val !== 'normal') style += `${prop}:${val};`;
    });
    d.setAttribute('style', style);
  });
}

export function printElement(el, title = '') {
  if (!el) return;

  const clone = el.cloneNode(true);

  // cloneNode 不复制用户当前输入的 input/textarea/select 值，逐一手动搬（否则打印成空框）。
  const srcFields = el.querySelectorAll('input, textarea, select');
  const dstFields = clone.querySelectorAll('input, textarea, select');
  srcFields.forEach((src, i) => {
    const dst = dstFields[i];
    if (!dst) return;
    if (src.tagName === 'SELECT') dst.value = src.value;
    else if (src.type === 'checkbox' || src.type === 'radio') dst.checked = src.checked;
    else if (src.tagName === 'TEXTAREA') dst.textContent = src.value;
    else dst.setAttribute('value', src.value);
  });

  // 把计算样式内联进克隆（趁原节点在屏幕上已渲染，getComputedStyle 拿得到真实值）。
  inlineComputedStyles(el, clone);

  // 克隆挂到 body 直下（脱离 backdrop-blur 等造成的定位/裁剪祖先）。
  const portal = document.createElement('div');
  portal.setAttribute('data-crm-print-portal', '');

  // 顶部品牌头：左上角 Wintouch 橙色字标（与 PI 单据同一 logo），尺寸用内联样式保证生效。
  const header = document.createElement('div');
  header.setAttribute('style', 'display:flex;align-items:center;margin-bottom:16px;');
  const logo = document.createElement('img');
  logo.src = '/brand-assets/pi-logo.png';
  logo.alt = 'Wintouch';
  logo.setAttribute('style', 'height:40px;width:auto;');
  header.appendChild(logo);
  portal.appendChild(header);

  portal.appendChild(clone);
  document.body.appendChild(portal);

  // 屏幕上藏起克隆；打印时藏掉 body 其余直接子节点、只留克隆，并保留背景/渐变配色。
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

  // 等 portal 内图片（logo / 签名）加载完再打印。
  let printed = false;
  const doPrint = () => {
    if (printed) return;
    printed = true;
    window.print();
    setTimeout(cleanup, 60000); // afterprint 不触发时兜底清理
  };
  const pending = Array.from(portal.querySelectorAll('img')).filter(
    img => !img.complete
  );
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
    setTimeout(doPrint, 3000);
  } else {
    doPrint();
  }
}
