import { buildMesClient } from './_mesClient';

// BOM 模版：把常用成品的用料明细存成模版，建 BOM 时一键套用。
const client = buildMesClient('bom_templates');

export default client;
