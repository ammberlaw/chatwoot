import { defineStore } from 'pinia';

// 全局写信状态：写信窗常驻在 CRM 布局层（跨模块切换不卸载），任意 CRM 页面经此触发写信。
// open()/refresh() 用自增序号触发（避免同参数不重放）；prefill 见 CrmEmailComposeDialog#open。
export const useCrmComposeStore = defineStore('crmCompose', {
  state: () => ({ prefill: null, openSeq: 0, refreshSeq: 0 }),
  actions: {
    open(prefill = null) {
      this.prefill = prefill;
      this.openSeq += 1;
    },
    // 写信窗发信/存草稿后通知邮件列表刷新（列表监听 refreshSeq）。
    notifyRefresh() {
      this.refreshSeq += 1;
    },
  },
});
