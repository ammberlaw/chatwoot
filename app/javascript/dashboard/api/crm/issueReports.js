import { buildCrmClient } from './_crmClient';

// 业务员在 AI 助手里报上来的问题单：列出来、标处理进度（超管/副管）。
// 新的一条由助手的 report_issue 工具产生，不在这里手敲。
export default buildCrmClient('issue_reports');
