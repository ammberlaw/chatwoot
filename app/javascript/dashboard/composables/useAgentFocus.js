import { ref } from 'vue';

/**
 * 「用户此刻正看着哪条记录」——给 AI 助手用。
 *
 * 为什么要这个：助手拿得到路由名，但拿不到页面组件里的状态。邮件页打开某封信时，
 * 信的 ID 在 selectedEmail 里、不在 URL 上，于是用户说「帮我回复一下」，
 * 助手只能回「我这边看不到你停在哪儿」（2026-10-30 生产实例）。
 *
 * 模块级单例：助手球挂在全局外壳上，和各业务页不在同一棵组件树里，
 * 只能靠模块级状态传话。页面负责在选中/离开时登记与清除。
 */
const focus = ref(null); // { kind, id, label }

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
  return { agentFocus: focus, setAgentFocus, clearAgentFocus };
}
