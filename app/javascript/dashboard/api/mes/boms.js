/* global axios */
import { buildMesClient } from './_mesClient';

const client = buildMesClient('boms');

// 下发草稿 BOM → 正式生效。
client.release = id => axios.post(`${client.url}/${id}/release`);

export default client;
