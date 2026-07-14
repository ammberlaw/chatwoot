import { buildCrmClient } from './_crmClient';

// CRM 成员权限：列出账号成员并分配 CRM 角色（仅管理员）。
export default buildCrmClient('members');
