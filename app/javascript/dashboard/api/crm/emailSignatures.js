import { buildCrmClient } from './_crmClient';

// 个性签名库：与发信邮箱解耦，一人可建多条命名签名，写邮件时下拉插入。
export default buildCrmClient('email_signatures');
