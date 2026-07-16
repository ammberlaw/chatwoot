import { buildCrmClient } from './_crmClient';

// CRM 销售团队：建队/改队/设组长/分配组员（写操作仅超管与管理员）。
export default buildCrmClient('teams');
