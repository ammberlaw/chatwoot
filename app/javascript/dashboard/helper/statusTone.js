// 全站单据状态的配色。
//
// 之前每个列表页各写一份字面量，同一个语义在不同页面能撞出不同颜色——比如 DRAFT
// 在多数页面是灰，在 ERP 凭证页是黄。颜色只该表达「这条记录处在什么状态」，
// 和它是哪种单据无关，所以收口到这里一处。
//
// 档位：
//   idle  还没人动过，或已退出流程   草稿、待确认、已撤销
//   flow  流程正在走                 待出货、发送中、样品中、外勤、未到期
//   busy  在跑但要盯着               生产中、待付款、即将到期、迟到、请假
//   done  做成了                     已付款、已成交、已出货、合格
//   final 流程真正走完的那一个        已完成
//   fail  没做成                     已取消、输单、不合格、旷工、逾期、已报废
//
// flow 用的是 n-flow-* 而不是 n-blue-*：经典灰主题把整条 blue 压成了中性灰
// （去掉画布渐变那种大面积的蓝），状态标签若跟着走 blue，就会和 idle 的灰撞色。
export const STATUS_TONE = {
  idle: 'bg-n-slate-3 text-n-slate-11',
  flow: 'bg-n-flow-3 text-n-flow-11',
  busy: 'bg-n-amber-3 text-n-amber-11',
  done: 'bg-n-teal-3 text-n-teal-11',
  final: 'bg-n-teal-9 text-white',
  fail: 'bg-n-ruby-3 text-n-ruby-11',
};

// 带色点的那种标签（表格里用得多，一个圆点比纯色块好认）
export const STATUS_DOT = {
  idle: 'bg-n-slate-9',
  flow: 'bg-n-flow-9',
  busy: 'bg-n-amber-9',
  done: 'bg-n-teal-9',
  final: 'bg-white',
  fail: 'bg-n-ruby-9',
};

// 作废单独一档，不并进 fail：作废不是「没做成」，是「这张单子不算数了」——
// 走红色太响，当事人以为出了事。灰 + 删除线本身已经把「不算数」说清楚了。
export const STATUS_VOID = `${STATUS_TONE.idle} line-through`;

export const statusTone = tone => STATUS_TONE[tone] || STATUS_TONE.idle;
export const statusDot = tone => STATUS_DOT[tone] || STATUS_DOT.idle;
