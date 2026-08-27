<script setup>
// 单个供应商的采购单/合同版式，1:1 复刻公司原始模板（lib/purchase_order/*.xlsx）：
// 联合(wintouch)=采购订单·未税；联迪(liontek)=采购合同·含税(单价已×1.13)+公章。
// 抬头 logo、送货地址、条款、落款均按模板固定文案；动态部分(供应商/单号/日期/明细)由后端给。
// 离屏渲染供 html2canvas 截图导出 PDF；固定 A4 宽(794px)保证比例；不含成本/毛利/其他供应商。
import { computed } from 'vue';
import { WINTOUCH_LOGO, LIONTEK_LOGO, LIONTEK_SEAL } from './mesPoAssets';

const props = defineProps({
  data: { type: Object, required: true }, // 见 Mes::PoSupplierExport#supplier_payload
  poNo: { type: String, default: '' },
  date: { type: String, default: '' },
  deliveryDate: { type: String, default: '' }, // 采购单交货时间(YYYY-MM-DD)，填入「交货时间」条款
});

// 模板固定文案（抬头英文名/送货地址/条款/落款），按开票主体区分。
const TEMPLATES = {
  wintouch: {
    logo: WINTOUCH_LOGO,
    companyEn: 'SHENZHEN WINTOUCH ELECTRONICS CO.,LTD',
    noLabel: '采购订单号',
    delivery:
      '货交：东莞市大岭山镇莲峰新路2号 永辉·恒旺智谷2号门 3号电梯 4楼（联迪科技）  蒲小姐 181 2285 5547',
    ourLabel: '联合触控：',
    seal: null,
    terms: [
      '二、技术质量要求：严格按照我司装机标准规格做货，按采购订单的规格型号、颜色、数量等交货，否则我司有权拒收多出的数量或与订单不相符的货品。',
      '三、交货时间、地点：%DATE% 开始交货至我司工厂仓库，包装及运输费用均由供方承担；送货单必须有我司的采购订单号、产品名称、料号，否则我司仓库不予收货。',
      '四、验收：产品检测不良率超过整批货的5%，我司有权对整批物料做退货处理；检测出的不良品，供方需在2天内处理并返回良品并出不良报告，超出2天未处理做退货扣款处理。',
      '五、保证和索赔：供方应严格按照采购合同规定的时间交货，延迟一天扣除总货款1%（百分之一），超过7天我司有权单方面终止订单。',
      '六、经双方签字盖章后生效。甲、乙双方各持一份，具同等法律效力，本合同复印传真亦有效。',
    ],
  },
  liontek: {
    logo: LIONTEK_LOGO,
    companyEn: '',
    noLabel: '采购合同号',
    delivery:
      '送货地址：东莞市大岭山镇莲峰新路2号 永辉·恒旺智谷2号门 3号电梯 4楼（联迪科技）  蒲小姐 181 2285 5547',
    ourLabel: '联迪科技：',
    seal: LIONTEK_SEAL,
    terms: [
      '二、以上单价均为含税单价（含税13%），请提供相应的对账单、发票、购销合同及盖章送货单；',
      '三、技术质量要求：严格按照我司装机标准规格做货，按采购订单的规格型号、颜色、数量等交货，否则我司有权拒收多出的数量或与订单不相符的货品。',
      '四、交货时间、地点：%DATE% 开始交货至我司工厂仓库，包装及运输费用均由供方承担；送货单必须有我司的采购订单号、产品名称、料号，否则我司仓库不予收货。',
      '五、验收：产品检测不良率超过整批货的5%，我司有权对整批物料做退货处理；检测出的不良品，供方需在2天内处理并返回良品并出不良报告，超出2天未处理做退货扣款处理。',
      '六、保证和索赔：供方应严格按照采购合同规定的时间交货，延迟一天扣除总货款1%（百分之一），超过7天我司有权单方面终止订单。',
      '七、经双方签字盖章后生效。甲、乙双方各持一份，具同等法律效力，本合同复印传真亦有效。',
    ],
  },
};

const tpl = computed(
  () => TEMPLATES[props.data.bill_entity] || TEMPLATES.wintouch
);

// 交货时间填入「三/四、交货时间」条款；未填则留下划线占位。
const deliveryText = computed(() => {
  if (!props.deliveryDate) return '____年__月__日';
  const [y, m, d] = props.deliveryDate.split('-');
  return `${y}年${Number(m)}月${Number(d)}日`;
});
const renderedTerms = computed(() =>
  tpl.value.terms.map(t => t.replace('%DATE%', deliveryText.value))
);

const cell = 'border border-[#8a8a8a] px-1.5 py-1';
const th = `${cell} font-bold text-center`;
const td = `${cell} text-left break-all`;
const tdC = `${cell} text-center`;
const tdR = `${cell} text-right`;

const fmt = n => {
  if (n === null || n === undefined || n === '') return '';
  const num = Number(n);
  return Number.isInteger(num) ? String(num) : num.toFixed(2);
};
</script>

<template>
  <div
    class="po-doc w-[794px] px-10 py-9 box-border bg-white text-[#1a1c20] font-[SimSun,Songti_SC,serif]"
  >
    <!-- 抬头：左 logo + 居中公司名/英文名 -->
    <div class="relative mb-1">
      <img
        :src="tpl.logo"
        alt="logo"
        class="absolute left-0 top-1 h-[42px] w-auto"
      />
      <div
        class="text-[21px] font-bold tracking-[6px] text-center text-[#1a1c20]"
      >
        {{ data.company }}
      </div>
      <div
        v-if="tpl.companyEn"
        class="text-[11px] tracking-[2px] text-center text-[#333] mt-0.5"
      >
        {{ tpl.companyEn }}
      </div>
    </div>
    <div
      class="text-[19px] font-bold tracking-[10px] text-center mt-1.5 mb-2.5"
    >
      {{ data.title }}
    </div>

    <!-- 信息区（外框，两列）-->
    <table
      class="w-full text-[12.5px] leading-[1.7] border border-[#8a8a8a] border-collapse"
    >
      <tbody>
        <tr>
          <td class="w-[64%] px-2 py-1 align-top border border-[#8a8a8a]">
            供应商：{{ data.name }}
          </td>
          <td class="px-2 py-1 align-top border border-[#8a8a8a]">
            {{ tpl.noLabel }}：{{ poNo }}
          </td>
        </tr>
        <tr>
          <td class="px-2 py-1 align-top border border-[#8a8a8a]">
            联系人：{{ data.contact_name || '' }}
          </td>
          <td class="px-2 py-1 align-top border border-[#8a8a8a]">
            采购日期：{{ date }}
          </td>
        </tr>
        <tr>
          <td class="px-2 py-1 align-top border border-[#8a8a8a]">
            地址：{{ data.address || '' }}
          </td>
          <td class="px-2 py-1 align-top border border-[#8a8a8a]">
            币别：{{ data.currency }}
          </td>
        </tr>
        <tr>
          <td class="px-2 py-1 align-top border border-[#8a8a8a]" colspan="2">
            交货地点：送货到东莞工厂仓库
          </td>
        </tr>
      </tbody>
    </table>

    <div class="mt-2 mb-1 text-[12.5px] font-medium">
      一、产品名称、规格、数量、单价、金额等
    </div>

    <!-- 明细表 -->
    <table class="w-full text-[12px] border-collapse table-fixed">
      <thead>
        <tr class="bg-[#f2f2f4]">
          <th :class="th" class="w-[34px]">序号</th>
          <th :class="th" class="w-[86px]">我司料号</th>
          <th :class="th">产品名称</th>
          <th :class="th" class="w-[120px]">规格</th>
          <th :class="th" class="w-[38px]">单位</th>
          <th :class="th" class="w-[52px]">数量</th>
          <th :class="th" class="w-[72px]">
            {{ data.taxed ? '含税单价' : '未税单价' }}
          </th>
          <th :class="th" class="w-[80px]">
            {{ data.taxed ? '含税金额' : '未税金额' }}
          </th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="row in data.items" :key="row.index">
          <td :class="tdC">{{ row.index }}</td>
          <td :class="td">{{ row.code || '' }}</td>
          <td :class="td">{{ row.name || '' }}</td>
          <td :class="td">{{ row.spec || '' }}</td>
          <td :class="tdC">{{ row.unit || '' }}</td>
          <td :class="tdR">{{ fmt(row.qty) }}</td>
          <td :class="tdR">{{ fmt(row.price) }}</td>
          <td :class="tdR">{{ fmt(row.amount) }}</td>
        </tr>
        <tr class="font-bold bg-[#fafafb]">
          <td :class="tdC" colspan="5">合计</td>
          <td :class="tdR">{{ fmt(data.total_qty) }}</td>
          <td :class="td" />
          <td :class="tdR">{{ fmt(data.total_amount) }}</td>
        </tr>
      </tbody>
    </table>

    <!-- 送货地址 + 备注/条款 -->
    <div class="mt-2 text-[11.5px] leading-[1.75] text-[#222]">
      <div>{{ tpl.delivery }}</div>
      <div class="mt-1">备注：</div>
      <div v-for="(term, i) in renderedTerms" :key="i" class="mt-0.5">
        {{ term }}
      </div>
    </div>

    <!-- 落款 + 公章 -->
    <div class="relative flex justify-between mt-8 text-[12.5px]">
      <div>
        {{ tpl.ourLabel }}
        <div class="mt-6">日期：{{ date }}</div>
      </div>
      <div class="relative pr-4">
        供应商：
        <img
          v-if="tpl.seal"
          :src="tpl.seal"
          alt="seal"
          class="absolute -top-8 right-0 w-[112px] h-auto opacity-90"
        />
      </div>
    </div>
  </div>
</template>
