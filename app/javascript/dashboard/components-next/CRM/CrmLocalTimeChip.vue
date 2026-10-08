<script setup>
// 客户当地时间：业务员发信/打电话前一眼看出对方现在几点、是不是上班时间。
//
// 三路取值，按可靠度排：
//   ① 客户档案的国家 —— 有完整时区规则，夏令时会自动跟着切。建档客户走这条。
//   ② 这封邮件 Date 头里的时区偏移 —— 对方电脑的真实时区，没建档也拿得到；
//      存的是来信那一刻的偏移，跨夏令时切换那几周会差 1 小时。
//   ③ 邮箱域名的国别后缀（.de/.fr…）—— 最粗，`.com` 推不出来，纯兜底。
// 一路都没有就整个不显示——不拿编的数据糊弄。
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { COUNTRY_LABELS } from 'dashboard/routes/dashboard/crm/constants/countries';
import {
  COUNTRY_TIMEZONES,
  TLD_COUNTRIES,
} from 'dashboard/routes/dashboard/crm/constants/countryTimezones';

const props = defineProps({
  country: { type: String, default: '' },
  // Date 头里的时区偏移（分钟）。0 是合法值（UTC+0），所以用 null 表示「没有」。
  offsetMinutes: { type: Number, default: null },
  // 对方邮箱地址，用来取域名后缀兜底。
  address: { type: String, default: '' },
});

// 每分钟走一次表：停留在一封邮件上十几分钟，显示的还是进来那一刻的时间就没意义了。
const now = ref(new Date());
let timer = null;
onMounted(() => {
  timer = setInterval(() => {
    now.value = new Date();
  }, 60 * 1000);
});
onBeforeUnmount(() => clearInterval(timer));

// 域名后缀兜底：先试两级（.com.au / .co.uk），再试最后一段。
const tldCountry = computed(() => {
  const domain = String(props.address).split('@')[1] || '';
  const bits = domain.toLowerCase().split('.').filter(Boolean);
  if (bits.length < 2) return '';
  return (
    TLD_COUNTRIES[bits.slice(-2).join('.')] || TLD_COUNTRIES[bits.at(-1)] || ''
  );
});

// 当前这一路是哪条：zone（档案国家）/ offset（来信时区）/ tld（域名后缀）。
const source = computed(() => {
  if (COUNTRY_TIMEZONES[props.country]) return 'zone';
  if (Number.isFinite(props.offsetMinutes)) return 'offset';
  return tldCountry.value ? 'tld' : '';
});

const zoneEntry = computed(() => {
  if (source.value === 'zone') return COUNTRY_TIMEZONES[props.country];
  if (source.value === 'tld') return COUNTRY_TIMEZONES[tldCountry.value];
  return null;
});

const countryName = code =>
  String(COUNTRY_LABELS[code] || '').replace(/[^一-龥]/g, '');

// 跨时区大国用 zoneLabel（如「美国东部」），免得被当成全国统一时间。
const zoneName = computed(() => {
  if (source.value === 'zone') {
    return zoneEntry.value.zoneLabel || countryName(props.country);
  }
  if (source.value === 'tld') {
    return zoneEntry.value.zoneLabel || countryName(tldCountry.value);
  }
  return '客户当地';
});

// 按时区规则算（①③）：Intl 自带夏令时。
const fromZone = () => {
  const fmt = new Intl.DateTimeFormat('zh-CN', {
    timeZone: zoneEntry.value.zone,
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
    weekday: 'short',
    timeZoneName: 'longOffset',
  });
  const f = Object.fromEntries(
    fmt.formatToParts(now.value).map(x => [x.type, x.value])
  );
  return {
    date: `${f.month}-${f.day}`,
    time: `${f.hour}:${f.minute}`,
    // longOffset 给的是 GMT+08:00，统一成习惯写法 UTC+8 / UTC-4:30
    offset: String(f.timeZoneName || '')
      .replace('GMT', 'UTC')
      .replace(/([+-])0?(\d+):00$/, '$1$2')
      .replace(/([+-])0?(\d+):(\d+)$/, '$1$2:$3'),
    hour: Number(f.hour),
    weekend: ['六', '日'].some(d => String(f.weekday).includes(d)),
  };
};

// 按固定偏移算（②）：UTC 时间直接加偏移，不涉及时区规则。
const fromOffset = () => {
  const m = props.offsetMinutes;
  const shifted = new Date(now.value.getTime() + m * 60 * 1000);
  const two = n => String(n).padStart(2, '0');
  const sign = m < 0 ? '-' : '+';
  const abs = Math.abs(m);
  const hh = Math.floor(abs / 60);
  const mm = abs % 60;
  return {
    date: `${two(shifted.getUTCMonth() + 1)}-${two(shifted.getUTCDate())}`,
    time: `${two(shifted.getUTCHours())}:${two(shifted.getUTCMinutes())}`,
    offset: `UTC${sign}${hh}${mm ? `:${two(mm)}` : ''}`,
    hour: shifted.getUTCHours(),
    weekend: [0, 6].includes(shifted.getUTCDay()),
  };
};

const parts = computed(() => {
  if (!source.value) return null;
  return source.value === 'offset' ? fromOffset() : fromZone();
});

// 上班时间口径：当地周一至周五 09:00–18:00。各国作息差别很大（中东周五休、
// 欧洲五点下班），这里只做粗判，够用来决定「现在要不要打这个电话」。
const WORK_START = 9;
const WORK_END = 18;
const state = computed(() => {
  const p = parts.value;
  const working = !p.weekend && p.hour >= WORK_START && p.hour < WORK_END;
  return working
    ? { label: '工作时间', cls: 'text-n-teal-11' }
    : { label: '休息时间', cls: 'text-n-slate-10' };
});

// 悬停写明这个时间是怎么来的——推算和确认信息不能看着一样。
const SOURCE_TIPS = {
  zone: code => `按客户档案的国家（${countryName(code)}）推算`,
  offset: () => '按这封邮件里带的发件人时区推算（跨夏令时切换时可能差 1 小时）',
  tld: code => `按邮箱域名后缀猜的国家（${countryName(code)}），仅供参考`,
};
const title = computed(() => {
  const code = source.value === 'tld' ? tldCountry.value : props.country;
  const how = SOURCE_TIPS[source.value]?.(code) || '';
  const zone = zoneEntry.value ? ` · ${zoneEntry.value.zone}` : '';
  return `客户当地时间：${how}${zone}`;
});
</script>

<template>
  <span
    v-if="parts"
    :title="title"
    class="inline-flex items-center gap-2 px-2.5 py-1 text-xs rounded-full whitespace-nowrap bg-n-alpha-1 text-n-slate-11"
  >
    <span>{{ zoneName }}</span>
    <span class="font-semibold tabular-nums text-n-slate-12">
      {{ parts.date }} {{ parts.time }}
    </span>
    <span class="text-n-slate-10">{{ parts.offset }}</span>
    <span :class="state.cls">{{ state.label }}</span>
    <!-- 非档案国家推出来的加个问号，提醒这是推算不是确认信息 -->
    <span v-if="source !== 'zone'" class="text-n-slate-9">?</span>
  </span>
  <!-- 三路都取不到时渲染一个 display:none 的空节点：它不是 flex item，
       不会在那一行里撑出一个 gap（直接 v-if 在根节点上又会触发 vue/no-root-v-if）。 -->
  <span v-else class="hidden" />
</template>
