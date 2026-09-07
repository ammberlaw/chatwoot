// 客户来源彩色胶囊配色:与客户列表(CrmCustomersIndex)保持一致。
// 来源无固定色,按 code 哈希稳定取一个色,保证同一来源到处同色。
const PILL = {
  teal: 'bg-n-teal-3 text-n-teal-11',
  blue: 'bg-n-blue-3 text-n-blue-11',
  iris: 'bg-n-iris-3 text-n-iris-11',
  amber: 'bg-n-amber-3 text-n-amber-11',
  ruby: 'bg-n-ruby-3 text-n-ruby-11',
  violet: 'bg-n-violet-3 text-n-violet-11',
  slate: 'bg-n-slate-4 text-n-slate-11',
};

const SOURCE_COLORS = ['iris', 'blue', 'teal', 'ruby', 'amber', 'slate'];

export const sourceColor = code => {
  const s = String(code || '');
  let h = 0;
  for (let i = 0; i < s.length; i += 1) {
    h = (h + s.charCodeAt(i)) % SOURCE_COLORS.length;
  }
  return SOURCE_COLORS[h];
};

export const sourcePillClass = code => PILL[sourceColor(code)] || PILL.slate;
