// 定制生产订单规格字段（按产品线）。照客户实际模板整理。
// type: text 单行 | textarea 多行 | checks 多选 | dualo 默认/其他+规格 | section 分组标题
export const TABLET_FIELDS = [
  { section: '客户信息' },
  { key: 'country', label: '国家', type: 'text' },
  { key: 'customer', label: '客户', type: 'text' },
  {
    key: 'shipDate',
    label: '发货时间',
    type: 'text',
    placeholder: '如：下单后30天（8月20日）',
  },
  { section: '硬件规格' },
  { key: 'cpu', label: 'CPU', type: 'text' },
  { key: 'ram', label: 'RAM', type: 'text' },
  { key: 'rom', label: 'ROM', type: 'text' },
  { key: 'os', label: '系统', type: 'text' },
  { key: 'bluetooth', label: '蓝牙', type: 'text' },
  { key: 'port', label: '接口', type: 'text' },
  {
    key: 'network',
    label: '网络',
    type: 'checks',
    options: ['WIFI', '4G', '3G'],
  },
  { key: 'screenSize', label: '屏幕尺寸', type: 'text' },
  { key: 'resolution', label: '分辨率', type: 'text' },
  { key: 'camera', label: '摄像头', type: 'text' },
  { key: 'battery', label: '电池', type: 'text' },
  { key: 'screenType', label: '屏幕类型', type: 'text' },
  { section: '定制项' },
  {
    key: 'logo',
    label: 'LOGO',
    type: 'checks',
    options: ['开机logo', '彩盒', '机身'],
  },
  {
    key: 'manual',
    label: '说明书语言',
    type: 'text',
    placeholder: '如：英文+越南语',
  },
  { key: 'preinstall', label: '预安装软件', type: 'text' },
  { key: 'caseColors', label: '皮套颜色和数量', type: 'textarea' },
  { key: 'accessories', label: '配件', type: 'textarea' },
  { key: 'customNotes', label: '备注（定制要求）', type: 'textarea' },
];

export const DISPLAY_FIELDS = [
  { section: '订单信息' },
  { key: 'model', label: '型号', type: 'text' },
  { key: 'replyDate', label: '生产回复交期', type: 'text' },
  { key: 'requirements', label: '产品要求', type: 'textarea' },
  { section: '配置' },
  { key: 'mainboard', label: '主板配置', type: 'dualo' },
  { key: 'powerCord', label: '电源线', type: 'dualo', defaultHint: '欧规' },
  {
    key: 'adapter',
    label: '适配器',
    type: 'dualo',
    defaultHint: '12V 2.5A 直头',
  },
  {
    key: 'signalCable',
    label: '信号线',
    type: 'dualo',
    defaultHint: 'HDMI 1.5m 直头',
  },
  { key: 'touchCable', label: '触摸线', type: 'dualo', defaultHint: '1m 直头' },
  {
    key: 'bracket',
    label: '支架/底座',
    type: 'dualo',
    defaultHint: '侧边枝条',
  },
  { key: 'carton', label: '纸箱', type: 'dualo', defaultHint: '普通纸箱' },
  { key: 'machineLabel', label: '机器label', type: 'text' },
  { key: 'shippingMark', label: '标签/唛头', type: 'dualo' },
  { key: 'other', label: '其他', type: 'textarea' },
];

export const SPEC_TEMPLATES = {
  TABLET: { label: '平板电脑', fields: TABLET_FIELDS },
  DISPLAY: { label: '显示器/商显', fields: DISPLAY_FIELDS },
};

export const specFieldsFor = template =>
  SPEC_TEMPLATES[template]?.fields || TABLET_FIELDS;

// 按模板初始化一张空规格（各字段给对应空值），确保所有 key 存在、绑定不报错。
export const blankSpec = template => {
  const spec = { template };
  specFieldsFor(template).forEach(f => {
    if (f.section) return;
    if (f.type === 'checks') spec[f.key] = [];
    else if (f.type === 'dualo') spec[f.key] = { mode: '默认', spec: '' };
    else spec[f.key] = '';
  });
  return spec;
};
