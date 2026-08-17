/**
 * 直接打印一个 DOM 节点：克隆进隐藏 iframe，拷贝当前页样式表后调起浏览器打印对话框。
 * 用隐藏 iframe（而非弹新窗口）避免被弹窗拦截，打印完自动移除。
 * @param {HTMLElement} el 要打印的节点（如提成表/考核表的只读容器）
 * @param {string} title 打印文档标题（浏览器打印页眉 / 另存 PDF 的默认文件名）
 */
export function printElement(el, title = '') {
  if (!el) return;

  const iframe = document.createElement('iframe');
  // 放视口外、零尺寸但仍参与渲染（display:none 会让部分浏览器不渲染而打印空白）
  iframe.setAttribute(
    'style',
    'position:fixed;right:0;bottom:0;width:0;height:0;border:0;'
  );
  document.body.appendChild(iframe);

  const doc = iframe.contentWindow.document;
  doc.open();
  doc.write('<!doctype html><html><head></head><body></body></html>');
  doc.close();
  if (title) doc.title = title;

  // iframe 是 about:blank，先注入 <base> 让被拷样式表/图片里的相对链接按主站解析
  // （否则生产的外链 CSS/字体解析不到，打出无样式版）。
  const base = doc.createElement('base');
  base.href = document.baseURI;
  doc.head.appendChild(base);

  // 拷贝当前页所有样式（<link rel=stylesheet> 外链 + <style> 内联），让 Tailwind 类在 iframe 内生效。
  document
    .querySelectorAll('link[rel="stylesheet"], style')
    .forEach(node => doc.head.appendChild(node.cloneNode(true)));

  // 打印时保留背景/渐变配色（浏览器默认会省略背景色），并去掉页边距外的空隙。
  const printStyle = doc.createElement('style');
  printStyle.textContent =
    '@media print{*{-webkit-print-color-adjust:exact;print-color-adjust:exact}}' +
    'body{margin:0;padding:16px;background:#fff}';
  doc.head.appendChild(printStyle);

  doc.body.appendChild(el.cloneNode(true));

  let done = false;
  const trigger = () => {
    if (done) return;
    done = true;
    iframe.contentWindow.focus();
    iframe.contentWindow.print();
    // 打印对话框同步阻塞；关闭后再清理 iframe
    setTimeout(() => iframe.remove(), 1000);
  };

  // 等外链样式表 + 图片都就绪再打印：生产用 <link> 外链 CSS（含 CDN），异步加载，
  // 不等它 load 完就 print 会打出无样式版（本地 dev 是内联 <style>，本就瞬时生效不受影响）。
  const links = Array.from(doc.querySelectorAll('link[rel="stylesheet"]'));
  const imgs = Array.from(doc.images || []);
  const waitables = [...links, ...imgs];
  if (waitables.length) {
    let pending = waitables.length;
    const onReady = () => {
      pending -= 1;
      if (pending <= 0) setTimeout(trigger, 150);
    };
    waitables.forEach(node => {
      // 图片看 complete；样式表看 sheet 是否已就绪，否则挂 load/error 事件。
      const ready =
        node.tagName === 'IMG' ? node.complete : Boolean(node.sheet);
      if (ready) onReady();
      else {
        node.addEventListener('load', onReady);
        node.addEventListener('error', onReady);
      }
    });
    setTimeout(trigger, 4000); // 兜底：外链迟迟不回也别卡死
  } else {
    setTimeout(trigger, 300);
  }
}
