// 从阿里页面上取字段。分两层：
//   1) 学到的选择器——用户用「从页面取」点过一次，之后同类页面自动填（存 chrome.storage）；
//   2) 兜底启发式——没学过时按正则/标签猜，猜错了用户改一下就顺手把选择器学了。
// 阿里的后台 DOM 我们控制不了、也会变，所以不把任何选择器写死在代码里。
// 说明：内容脚本不支持 ES module，这里挂一个命名空间给 content.js 用。

var WTS = window.WTS || {};

(() => {
  // 阿里买家身份有两种写法，都要认：
  //   会员 ID——纯数字，如 120613876220。买家没填公司名时阿里用 NoCompanyName_<会员ID> 占位，
  //            「Ta的Alibaba买家主页」链接和页面 URL 里也带着它。这是最可靠的一种。
  //   loginId——两位国家码 + 数字，如 cn1234567890，老式页面上能看到。
  const ALIBABA_ID_RE = /\b([a-z]{2}\d{6,})\b/i;
  const NO_COMPANY_RE = /NoCompanyName[_-](\d{6,})/i;
  const ID_IN_URL_RE = /(?:memberId|buyerId|loginId|companyId|targetId|accountId)=([A-Za-z0-9_-]{6,})/i;
  // 公司名占位符：阿里在买家没填公司时塞的，拿去当客户名毫无意义
  const PLACEHOLDER_NAME_RE = /^(?:NA|N\/A|-|–|—|NoCompanyName[_-]?\d*)$/i;
  // 阿里自己的系统地址不算客户邮箱。要匹配整个域名后缀而不是紧跟 @ 的那一段，
  // 否则 service@notice.alibaba.com 这种带子域的会漏网被当成客户邮箱。
  const SYSTEM_MAIL_RE = /@(?:[a-z0-9-]+\.)*(?:alibaba|alibaba-inc|aliyun|alicdn|taobao|1688)\.[a-z.]+$/i;
  const EMAIL_RE = /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b/g;

  const text = el => (el?.innerText || el?.textContent || '').trim();

  // 「标签：值」结构取值。两种写法都要认：
  //   同一个元素里  <div>联系人：Marcus Webb</div>
  //   拆成两个元素  <span>联系人：</span><span>Marcus Webb</span>
  // 节点按文本长度从短到长看：外层容器的文字里也含标签词，但它的「下一个兄弟」
  // 是下一行而不是本行的值，先看小节点才不会取到隔壁字段去。
  const isLabel = (label, words) => {
    const k = label.replace(/[\s:：/、]/g, '').toLowerCase();
    return words.some(w => k.includes(w));
  };

  // 取到的值必须像个「值」：不能跨行，也不能把标签词本身裹在里面。
  // 阿里页面上「公司信息」这种小标题也含「公司」二字，会被当成标签，
  // 于是它后面整块区域（公司名称/官方网站/传真/经营地址…）被整个当成值取走。
  const looksLikeValue = (v, words) =>
    v && !/[\n\r]/.test(v) && !words.some(w => v.toLowerCase().includes(w));

  const byLabel = (words, pick) => {
    const nodes = [...document.querySelectorAll('span,div,label,dt,th,td,p,strong,b')]
      .filter(n => text(n).length <= 120)
      .sort((a, b) => text(a).length - text(b).length);

    for (const node of nodes) {
      const t = text(node);
      const inline = t.match(/^(.{1,16}?)[:：]\s*([\s\S]+)$/);
      if (inline && isLabel(inline[1], words)) {
        const v = pick(inline[2].trim());
        if (looksLikeValue(v, words)) return v;
      }
      if (t.length <= 16 && isLabel(t, words)) {
        for (const c of [node.nextElementSibling, node.parentElement?.nextElementSibling]) {
          const v = c ? pick(text(c)) : '';
          if (looksLikeValue(v, words)) return v;
        }
      }
    }
    return '';
  };

  const shortText = (min, max) => t => (t.length >= min && t.length <= max ? t : '');

  WTS.ALIBABA_ID_RE = ALIBABA_ID_RE;

  // 会员 ID 按可靠度依次找：占位公司名 → 买家主页等链接 → 当前 URL → 标签取值 → 全页正则
  const buyerId = () => {
    const placeholder = (document.body.innerText.match(NO_COMPANY_RE) || [])[1];
    if (placeholder) return placeholder;

    const fromLink = [...document.querySelectorAll('a[href]')]
      .map(a => (String(a.href).match(ID_IN_URL_RE) || [])[1])
      .find(Boolean);
    if (fromLink) return fromLink;

    const fromUrl = (location.href.match(ID_IN_URL_RE) || [])[1];
    if (fromUrl) return fromUrl;

    const labelled = byLabel(
      ['买家账号', '账号', '会员名', 'loginid', '买家id', '会员id'],
      t => (t.match(ALIBABA_ID_RE) || [])[1] || (t.match(/^\d{6,}$/) ? t : '')
    );
    return labelled || (document.body.innerText.match(ALIBABA_ID_RE) || [])[1] || '';
  };

  // 公司名是 NA / NoCompanyName_xxx 这种占位时不要用，退回买家显示名——
  // 建一条叫「NA」的客户在 CRM 里毫无意义，还会跟别的 NA 撞一块。
  const companyName = () => {
    const raw = byLabel(['公司名称', '公司', 'company'], shortText(2, 90));
    if (raw && !PLACEHOLDER_NAME_RE.test(raw)) return raw;
    return '';
  };

  // 买家显示名：页面上它就挨着「Ta的Alibaba买家主页」那个链接，没有任何标签可依。
  // 以那个链接为锚，往上取同一块里第一行不像标签的短文本。
  const buyerName = () => {
    const link = [...document.querySelectorAll('a[href]')].find(
      a => /买家主页|buyer.*profile/i.test(`${text(a)} ${a.href}`)
    );
    if (!link) return '';

    const around = [link.previousElementSibling, link.parentElement].filter(Boolean);
    for (const node of around) {
      const line = text(node).split(/[\n\r]/).map(x => x.trim()).find(x => x && x.length <= 40 && !/买家主页/.test(x));
      if (line && !PLACEHOLDER_NAME_RE.test(line)) return line;
    }
    return '';
  };

  WTS.guess = {
    alibaba_account: buyerId,
    contact_email: () => ((document.body.innerText.match(EMAIL_RE) || []).filter(e => !SYSTEM_MAIL_RE.test(e)))[0] || '',
    name: () => companyName() || buyerName() || byLabel(['联系人', '姓名', 'contactperson'], shortText(2, 40)),
    primary_contact_name: () => byLabel(['联系人', '姓名', 'contactperson'], shortText(2, 40)) || buyerName(),
    trade_country_raw: () => byLabel(['国家', '地区', 'country'], shortText(2, 40)),
  };

  // 给元素生成一条稳定的 CSS 选择器（优先 id，其次 nth-of-type 路径）。
  WTS.cssPath = el => {
    const parts = [];
    let node = el;
    while (node && node.nodeType === 1 && node !== document.body && parts.length < 8) {
      if (node.id) {
        parts.unshift(`#${CSS.escape(node.id)}`);
        break;
      }
      const tag = node.tagName.toLowerCase();
      const sibs = [...(node.parentElement?.children || [])].filter(c => c.tagName === node.tagName);
      parts.unshift(sibs.length > 1 ? `${tag}:nth-of-type(${sibs.indexOf(node) + 1})` : tag);
      node = node.parentElement;
    }
    return parts.join(' > ');
  };

  // 页面指纹：同一类页面共用一套学到的选择器（域名 + 路径里的数字抹掉）。
  WTS.pageKey = () => `${location.hostname}${location.pathname.replace(/\d+/g, 'N')}`;

  WTS.readSelector = sel => {
    try {
      return text(document.querySelector(sel));
    } catch {
      return '';
    }
  };
})();

window.WTS = WTS;
