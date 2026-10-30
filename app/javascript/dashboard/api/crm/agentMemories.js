import ApiClient from '../ApiClient';

// AI 助手记住的事：公司规矩 + 自己的习惯。
// 只读和删——新的一条靠对话里跟助手说「记住…」产生，不在这里手敲。
class CrmAgentMemoriesApi extends ApiClient {
  constructor() {
    super('crm/ai/agent_memories', { accountScoped: true });
  }
}

export default new CrmAgentMemoriesApi();
