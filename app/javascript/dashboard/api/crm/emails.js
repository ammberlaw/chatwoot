/* global axios */
import { buildCrmClient } from './_crmClient';

const client = buildCrmClient('emails');

// 左栏文件夹角标：各文件夹总数 + 未读数。
client.counts = () => axios.get(`${client.url}/counts`);

export default client;
