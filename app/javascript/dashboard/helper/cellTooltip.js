// 表格格子悬停浮出完整内容。
//
// 反馈原话：「格子的内容还是不够看，鼠标箭头停留在哪个格子的时候，内容能显示出来
// （在并不拉动格子间距的情况下），并且这个显示，对所有单据的格子都适用」。
//
// 做法：在 document 上挂一个 mouseover（事件委托，一处生效全站），
// 鼠标进到某个格子时量一下它有没有被截断，被截断才补 title。
// 为什么不逐页加 :title：单据页几十张表、上百列，逐个加必然漏，漏的那几列正是人要看的。
//
// 只在「真的被截断」时补：不然每个格子都挂 tooltip，鼠标扫过一片全是气泡，反而吵。
const TRUNCATED = el => el.scrollWidth > el.clientWidth + 1;

const onOver = event => {
  const cell = event.target.closest?.('td, th');
  if (!cell) return;
  // 已经有 title 的（页面自己设过、更准确）不覆盖
  if (cell.hasAttribute('title')) return;

  // 截断可能发生在格子本身，也可能在里面那层 .truncate 上
  const target = TRUNCATED(cell)
    ? cell
    : Array.from(cell.querySelectorAll('*')).find(TRUNCATED);
  if (!target) return;

  const text = (cell.innerText || '').trim();
  // 空格子和只有一个「—」的不值当弹
  if (!text || text === '—') return;
  cell.setAttribute('title', text);
};

export const installCellTooltip = () => {
  document.addEventListener('mouseover', onOver, { passive: true });
};
