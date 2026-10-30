import { ref } from 'vue';

/**
 * 「用户此刻正看着/勾着哪些记录」——给 AI 助手用。
 *
 * 为什么要这个：助手拿得到路由名，但拿不到页面组件里的状态。两种都踩过：
 *  · 邮件页打开某封信时，信的 ID 在 selectedEmail 里、不在 URL 上，
 *    用户说「帮我回复一下」，助手只能回「我这边看不到你停在哪儿」；
 *  · 客户列表勾了几家后打「为选定客户批量准备邮件草稿」，助手反问
 *    「你想给哪些客户」——用户默认它看得见自己勾了谁。
 *  （都是 2026-10-28/30 生产实例。）
 *
 * 模块级单例：助手球挂在全局外壳上，和各业务页不在同一棵组件树里，
 * 只能靠模块级状态传话。页面负责在选中/离开时登记与清除。
 */
const focus = ref(null); // { kind, id, label }
const selection = ref(null); // { kind, ids: [], labels: [] }

// 勾选最多带这么多条。几百条塞进提示词会把真正的问题挤掉，
// 而真要对几百条批量干活，该走页面上的批量操作，不是让助手一条条办。
const MAX_SELECTION = 30;

export function useAgentFocus() {
  // kind 用人话（「邮件」「客户」「订单」），会原样拼进给模型的提示里。
  const setAgentFocus = (kind, id, label) => {
    focus.value = id
      ? { kind, id: String(id), label: String(label || '') }
      : null;
  };
  const clearAgentFocus = () => {
    focus.value = null;
  };

  // ids 是勾中的主键，labels 是同序的显示名（客户名/邮件主题），用来让助手
  // 说人话复述一遍「你勾的是这几家」，而不是甩一串 ID 让人自己认。
  const setAgentSelection = (kind, ids, labels) => {
    const list = (ids || []).filter(Boolean).slice(0, MAX_SELECTION);
    selection.value = list.length
      ? {
          kind,
          ids: list.map(String),
          labels: (labels || [])
            .slice(0, MAX_SELECTION)
            .map(l => String(l || '')),
          total: (ids || []).length,
        }
      : null;
  };
  const clearAgentSelection = () => {
    selection.value = null;
  };

  return {
    agentFocus: focus,
    setAgentFocus,
    clearAgentFocus,
    agentSelection: selection,
    setAgentSelection,
    clearAgentSelection,
  };
}
