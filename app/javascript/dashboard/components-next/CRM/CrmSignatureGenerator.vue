<script setup>
/**
 * 邮件签名生成器：填结构化信息 + 选预设模板 → 自动生成邮件安全的 HTML 签名。
 * 生成的 HTML 一律用 table 布局 + 内联样式（Gmail/Outlook 会剥掉 class/flex/<style>）。
 * 自助式：每个业务员自己填、自己选样式，保存进签名库（crm_email_signatures）。
 */
import { ref, reactive, computed, watch } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';

const props = defineProps({
  show: { type: Boolean, default: false },
  prefill: { type: Object, default: () => ({}) },
});
const emit = defineEmits(['close', 'save']);

const TEMPLATES = [
  { id: 'serif', label: '商务衬线' },
  { id: 'brand', label: '品牌社交' },
  { id: 'twocol', label: '左右分栏' },
  { id: 'minimal', label: '极简左对齐' },
  { id: 'avatar', label: '头像卡片式' },
  { id: 'banner', label: 'Logo 横幅式' },
];

const templateId = ref('serif');

// 联系方式小图标（托管在 public/sig-icons，用当前域名，保存/发信时自动带上生产域名）。
const ICON_BASE = `${window.location.origin}/sig-icons`;
const accent = ref('#F5843C');
const sigName = ref('模板签名');
const isDefault = ref(false);

// 预设配色：一键切换文字/链接主题色 + 配套图标（图标是固定色图片，按配色选对应那套）。
const PRESETS = [
  { key: 'orange', color: '#F5843C', label: '暖橙' },
  { key: 'blue', color: '#2563EB', label: '商务蓝' },
];
const colorKey = ref('orange');
const iconSuffix = computed(() =>
  colorKey.value === 'orange' ? '' : `-${colorKey.value}`
);
const applyPreset = preset => {
  colorKey.value = preset.key;
  accent.value = preset.color;
};

const form = reactive({
  name: '',
  title: '',
  dept: '',
  company: '',
  mobile: '',
  tel: '',
  email: '',
  website: '',
  address: '',
  wechat: '',
  whatsapp: '',
  logoUrl: '',
  tagline: '',
  cities: '',
  linkedin: '',
  facebook: '',
  instagram: '',
});

// 打开时用账号资料自动带出（少打字）。
watch(
  () => props.show,
  open => {
    if (!open) return;
    const p = props.prefill || {};
    // 纯英文签名：优先带出英文名（CRM 英文名），没有再用姓名。
    form.name = form.name || p.enName || p.name || '';
    form.email = form.email || p.email || '';
    form.company = form.company || p.company || '';
  }
);

const esc = s =>
  String(s == null ? '' : s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');

const initials = computed(() => {
  const src = (form.name || '').trim();
  if (!src) return '·';
  const parts = src.split(/\s+/);
  if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
  return src.slice(0, 2).toUpperCase();
});

// 字体：只列邮件客户端都认的「邮件安全」字体（自定义/花体在 Gmail 会被替换）。
const SANS = "Arial,'Microsoft YaHei',Helvetica,sans-serif";
const SERIF = "Georgia,'Times New Roman',serif";
const FONTS = [
  { key: 'default', label: '跟随模板' },
  { key: 'sans', label: '无衬线（Arial）', stack: SANS },
  { key: 'serif', label: '衬线（Georgia）', stack: SERIF },
  {
    key: 'times',
    label: 'Times New Roman',
    stack: "'Times New Roman',Times,serif",
  },
  { key: 'verdana', label: 'Verdana', stack: 'Verdana,Geneva,sans-serif' },
  { key: 'tahoma', label: 'Tahoma', stack: 'Tahoma,Geneva,sans-serif' },
  {
    key: 'trebuchet',
    label: 'Trebuchet MS',
    stack: "'Trebuchet MS',Helvetica,sans-serif",
  },
];
const fontChoice = ref('default');
const fontOptions = computed(() =>
  FONTS.map(f => ({ value: f.key, label: f.label }))
);
const chosenStack = computed(
  () => FONTS.find(f => f.key === fontChoice.value)?.stack || SANS
);
const bodyFont = computed(
  () =>
    `font-family:${fontChoice.value === 'default' ? SANS : chosenStack.value}`
);
const serifStack = computed(
  () =>
    `font-family:${fontChoice.value === 'default' ? SERIF : chosenStack.value}`
);

// 一行联系方式：小标签(主题色) + 值(深色)，链接可点。
const contactRows = () => {
  const a = accent.value;
  const rows = [];
  const add = (label, value, href, underline) => {
    if (!value) return;
    const val = href
      ? `<a href="${esc(href)}" style="color:${
          underline ? a : '#333'
        };text-decoration:${underline ? 'underline' : 'none'};">${esc(value)}</a>`
      : esc(value);
    rows.push(
      `<tr><td style="padding:1px 10px 1px 0;color:${a};font-size:11px;white-space:nowrap;vertical-align:top;">${label}</td><td style="padding:1px 0;color:#333;font-size:12px;vertical-align:top;">${val}</td></tr>`
    );
  };
  add('Mobile', form.mobile);
  add('Tel', form.tel);
  add('Email', form.email, form.email ? `mailto:${form.email}` : '');
  add('Web', form.website, siteUrl(), true);
  add('WeChat', form.wechat);
  add('WhatsApp', form.whatsapp);
  add('Address', form.address);
  return rows.length
    ? `<table cellpadding="0" cellspacing="0" border="0" style="${bodyFont.value};">${rows.join('')}</table>`
    : '';
};

const titleLine = () => {
  const bits = [form.title, form.dept, form.company].filter(Boolean).map(esc);
  return bits.join(' · ');
};

// 带图标的联系方式行（商务衬线模板用）：小图标 + 值，表格布局邮件安全。
const iconRow = (icon, value, href, underline) => {
  if (!value) return '';
  // 链接：网址(underline)用主题色+下划线，突出可点；其余(邮箱)用深色。
  const inner = href
    ? `<a href="${esc(href)}" style="color:${
        underline ? accent.value : '#333'
      };text-decoration:${underline ? 'underline' : 'none'};">${esc(value)}</a>`
    : esc(value);
  return `<tr><td style="padding:4px 10px 4px 0;vertical-align:middle;line-height:0;"><img src="${ICON_BASE}/${icon}${iconSuffix.value}.png" width="18" height="18" style="display:block;border:0;" alt="" /></td><td style="padding:4px 0;vertical-align:middle;font-size:13px;color:#333;">${inner}</td></tr>`;
};

const buildSerif = () => {
  const serif = serifStack.value;
  const bigName = form.name;
  const site = form.website
    ? /^https?:\/\//.test(form.website)
      ? form.website
      : `https://${form.website}`
    : '';
  const rows = [
    iconRow(
      'mail',
      form.email,
      form.email ? `mailto:${form.email}` : '',
      false
    ),
    iconRow('phone', form.mobile, '', false),
    iconRow('phone', form.tel, '', false),
    iconRow('globe', form.website, site, true),
    iconRow('location', form.address, '', false),
  ].join('');
  return `<table cellpadding="0" cellspacing="0" border="0" style="${serif};color:#222;">
<tr><td style="font-size:22px;font-weight:bold;color:#1a1a1a;padding-bottom:4px;">${esc(
    bigName
  )}</td></tr>
${form.title ? `<tr><td style="font-size:14px;color:#333;padding-bottom:2px;">${esc(form.title)}</td></tr>` : ''}
${form.company ? `<tr><td style="font-size:14px;color:#333;">${esc(form.company)}</td></tr>` : ''}
<tr><td style="padding-top:14px;"><table cellpadding="0" cellspacing="0" border="0">${rows}</table></td></tr>
<tr><td>${socialIcons()}</td></tr>
</table>`;
};

const siteUrl = () =>
  form.website
    ? /^https?:\/\//.test(form.website)
      ? form.website
      : `https://${form.website}`
    : '';

// 社交图标行：每个圆形图标带超链接（LinkedIn/WhatsApp/Facebook/Instagram）。
const socialIcons = () => {
  const items = [];
  const add = (name, href) => {
    if (!href) return;
    items.push(
      `<a href="${esc(
        href
      )}" style="text-decoration:none;display:inline-block;margin-right:8px;"><img src="${ICON_BASE}/social-${name}.png" width="22" height="22" style="display:inline-block;border:0;" alt="${name}" /></a>`
    );
  };
  add(
    'whatsapp',
    form.whatsapp
      ? `https://wa.me/${String(form.whatsapp).replace(/[^0-9]/g, '')}`
      : ''
  );
  add('linkedin', form.linkedin);
  add('facebook', form.facebook);
  add('instagram', form.instagram);
  return items.length
    ? `<div style="padding-top:14px;">${items.join('')}</div>`
    : '';
};

// 标签式联系方式（品牌社交模板用）：左列主题色小标签 + 右列值。
const labeledContacts = () => {
  const a = accent.value;
  const rows = [];
  const add = (label, value, href, underline) => {
    if (!value) return;
    const val = href
      ? `<a href="${esc(href)}" style="color:${
          underline ? a : '#333'
        };text-decoration:${underline ? 'underline' : 'none'};">${esc(value)}</a>`
      : esc(value);
    rows.push(
      `<tr><td style="padding:2px 14px 2px 0;color:${a};font-size:12px;white-space:nowrap;vertical-align:top;">${label}</td><td style="padding:2px 0;color:#333;font-size:12px;vertical-align:top;">${val}</td></tr>`
    );
  };
  add('Mobile.', form.mobile);
  add('Tel.', form.tel);
  add('Email.', form.email, form.email ? `mailto:${form.email}` : '');
  add('Website.', form.website, siteUrl(), true);
  if ((form.mobile || form.tel || form.email || form.website) && form.address) {
    rows.push('<tr><td style="height:8px;"></td><td></td></tr>');
  }
  add('Address.', form.address);
  return rows.length
    ? `<table cellpadding="0" cellspacing="0" border="0" style="${bodyFont.value};">${rows.join(
        ''
      )}</table>`
    : '';
};

const buildBrand = () => {
  const a = accent.value;
  const nameTitle = [form.name, form.title]
    .filter(Boolean)
    .map(esc)
    .join(' · ');
  // 顶部：logo + 公司名 一行（公司名只出现一次），下面标语。
  const header = `<table cellpadding="0" cellspacing="0" border="0"><tr>
${
  form.logoUrl
    ? `<td style="padding-right:10px;vertical-align:middle;"><img src="${esc(
        form.logoUrl
      )}" width="42" height="42" style="display:block;border-radius:50%;object-fit:cover;" alt="" /></td>`
    : ''
}
<td style="vertical-align:middle;font-size:20px;font-weight:bold;color:${a};letter-spacing:0.5px;">${esc(
    form.company
  )}</td>
</tr></table>`;
  const tagline = form.tagline
    ? `<div style="font-size:12px;font-style:italic;color:#999;padding-top:3px;">${esc(
        form.tagline
      )}</div>`
    : '';
  const cities = form.cities
    ? `<div style="font-size:12px;font-style:italic;color:#bbb;padding-top:6px;">${esc(
        form.cities
      )}</div>`
    : '';
  return `<table cellpadding="0" cellspacing="0" border="0" style="${bodyFont.value};color:#222;">
<tr><td>${header}${tagline}</td></tr>
${nameTitle ? `<tr><td style="font-size:12px;color:#777;padding-top:8px;">${nameTitle}</td></tr>` : ''}
${cities ? `<tr><td>${cities}</td></tr>` : ''}
<tr><td style="padding-top:14px;">${labeledContacts()}</td></tr>
<tr><td>${socialIcons()}</td></tr>
</table>`;
};

const buildTwoCol = () => {
  const a = accent.value;
  const bigName = form.name;
  const logo = form.logoUrl
    ? `<img src="${esc(
        form.logoUrl
      )}" width="72" height="72" style="display:block;border-radius:8px;object-fit:cover;" alt="" />`
    : `<div style="width:72px;height:72px;border-radius:50%;background:${a};color:#fff;font-size:24px;font-weight:bold;text-align:center;line-height:72px;${bodyFont.value};">${esc(
        initials.value
      )}</div>`;
  const rows = [
    iconRow('phone', form.mobile || form.tel, '', false),
    iconRow(
      'mail',
      form.email,
      form.email ? `mailto:${form.email}` : '',
      false
    ),
    iconRow('location', form.address, '', false),
    iconRow('globe', form.website, siteUrl(), true),
  ].join('');
  return `<table cellpadding="0" cellspacing="0" border="0" style="${bodyFont.value};color:#222;">
<tr>
<td style="vertical-align:top;padding-right:18px;width:130px;">
${logo}
<div style="font-size:12px;color:#888;padding-top:10px;line-height:1.4;">${esc(
    form.company
  )}</div>
</td>
<td style="vertical-align:top;border-left:2px solid #e5e5e5;padding-left:18px;">
<div style="font-size:20px;font-weight:bold;color:#1a1a1a;padding-bottom:10px;">${esc(
    bigName
  )}</div>
<table cellpadding="0" cellspacing="0" border="0">${rows}</table>
${socialIcons()}
</td>
</tr>
</table>`;
};

const buildMinimal = () => {
  const a = accent.value;
  return `<table cellpadding="0" cellspacing="0" border="0" style="${bodyFont.value};color:#333;">
<tr><td style="font-size:16px;font-weight:bold;color:#1a1a1a;padding-bottom:2px;">${esc(
    form.name
  )}</td></tr>
<tr><td style="color:#666;font-size:12px;padding-bottom:8px;">${titleLine()}</td></tr>
<tr><td style="border-top:2px solid ${a};padding-top:8px;">${contactRows()}</td></tr>
<tr><td>${socialIcons()}</td></tr>
</table>`;
};

const buildAvatar = () => {
  const a = accent.value;
  const left = form.logoUrl
    ? `<img src="${esc(
        form.logoUrl
      )}" width="58" height="58" style="display:block;border-radius:8px;object-fit:cover;" alt="" />`
    : `<div style="width:58px;height:58px;border-radius:50%;background:${a};color:#fff;font-size:20px;font-weight:bold;text-align:center;line-height:58px;${bodyFont.value};">${esc(
        initials.value
      )}</div>`;
  return `<table cellpadding="0" cellspacing="0" border="0" style="${bodyFont.value};color:#333;">
<tr>
<td style="vertical-align:top;padding-right:14px;">${left}</td>
<td style="vertical-align:top;border-left:3px solid ${a};padding-left:14px;">
<div style="font-size:15px;font-weight:bold;color:#1a1a1a;">${esc(
    form.name
  )}</div>
<div style="color:#666;font-size:12px;padding:2px 0 8px;">${titleLine()}</div>
${contactRows()}
${socialIcons()}
</td>
</tr>
</table>`;
};

const buildBanner = () => {
  const a = accent.value;
  const head = form.logoUrl
    ? `<img src="${esc(
        form.logoUrl
      )}" height="40" style="display:block;" alt="" />`
    : `<span style="font-size:18px;font-weight:bold;color:${a};">${esc(
        form.company
      )}</span>`;
  return `<table cellpadding="0" cellspacing="0" border="0" style="${bodyFont.value};color:#333;">
<tr><td style="padding-bottom:8px;">${head}</td></tr>
<tr><td style="font-size:15px;font-weight:bold;color:#1a1a1a;">${esc(
    form.name
  )}</td></tr>
<tr><td style="color:#666;font-size:12px;padding-bottom:8px;">${titleLine()}</td></tr>
<tr><td style="border-top:2px solid ${a};padding-top:8px;">${contactRows()}</td></tr>
<tr><td>${socialIcons()}</td></tr>
</table>`;
};

const generatedHtml = computed(() => {
  if (templateId.value === 'serif') return buildSerif();
  if (templateId.value === 'brand') return buildBrand();
  if (templateId.value === 'twocol') return buildTwoCol();
  if (templateId.value === 'avatar') return buildAvatar();
  if (templateId.value === 'banner') return buildBanner();
  return buildMinimal();
});

// 纯文本回退版（无 HTML 的客户端）。
const generatedText = computed(() => {
  const lines = [];
  lines.push(form.name);
  const tl = [form.title, form.dept, form.company].filter(Boolean).join(' · ');
  if (tl) lines.push(tl);
  const c = [
    form.mobile && `手机 ${form.mobile}`,
    form.tel && `电话 ${form.tel}`,
    form.email && `邮箱 ${form.email}`,
    form.website && `网站 ${form.website}`,
    form.wechat && `微信 ${form.wechat}`,
    form.whatsapp && `WhatsApp ${form.whatsapp}`,
    form.address && `地址 ${form.address}`,
  ].filter(Boolean);
  return lines.concat(c).join('\n');
});

const canSave = computed(() => form.name.trim() && sigName.value.trim());

const onSave = () => {
  if (!canSave.value) return;
  emit('save', {
    name: sigName.value.trim(),
    bodyHtml: generatedHtml.value,
    body: generatedText.value,
    isDefault: isDefault.value,
  });
};

// 遮罩关闭：只有「按下」和「松开」都发生在遮罩本身才算点外面关闭。
// 否则在输入框里拖选文字、鼠标松到遮罩上会被误判成点外面而关掉弹窗。
const downOnBackdrop = ref(false);
const onBackdropDown = e => {
  downOnBackdrop.value = e.target === e.currentTarget;
};
const onBackdropUp = e => {
  if (downOnBackdrop.value && e.target === e.currentTarget) emit('close');
  downOnBackdrop.value = false;
};
</script>

<template>
  <Teleport to="body">
    <div
      v-if="show"
      class="fixed inset-0 z-[9999] flex items-center justify-center bg-black/40 p-4"
      @mousedown="onBackdropDown"
      @mouseup="onBackdropUp"
    >
      <div
        class="flex flex-col w-full max-w-4xl bg-n-solid-2 rounded-2xl shadow-xl max-h-[90vh] overflow-hidden"
      >
        <!-- 头 -->
        <div
          class="flex items-center justify-between px-5 py-3.5 border-b border-n-weak shrink-0"
        >
          <h2 class="text-base font-semibold text-n-slate-12">
            用模板生成签名
          </h2>
          <button
            class="text-n-slate-11 hover:text-n-slate-12"
            @click="emit('close')"
          >
            <Icon icon="i-lucide-x" class="size-5" />
          </button>
        </div>

        <div class="flex flex-1 min-h-0 divide-x divide-n-weak">
          <!-- 左：表单 -->
          <div class="w-[42%] shrink-0 overflow-y-auto p-5 flex flex-col gap-3">
            <!-- 模板切换 -->
            <div>
              <label class="block mb-1 text-heading-3 text-n-slate-12"
                >模板</label
              >
              <div class="flex flex-wrap gap-1.5">
                <button
                  v-for="tpl in TEMPLATES"
                  :key="tpl.id"
                  class="px-2.5 py-1.5 text-xs rounded-lg border transition-colors"
                  :class="
                    templateId === tpl.id
                      ? 'border-n-iris-9 bg-n-iris-3 text-n-iris-12 font-medium'
                      : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'
                  "
                  @click="templateId = tpl.id"
                >
                  {{ tpl.label }}
                </button>
              </div>
            </div>

            <div class="flex items-center gap-2 flex-wrap">
              <label class="text-heading-3 text-n-slate-12">主题色</label>
              <button
                v-for="preset in PRESETS"
                :key="preset.key"
                class="px-2.5 py-1 text-xs rounded-lg border transition-colors flex items-center gap-1.5"
                :class="
                  colorKey === preset.key
                    ? 'border-n-slate-8 bg-n-alpha-2 text-n-slate-12 font-medium'
                    : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'
                "
                @click="applyPreset(preset)"
              >
                <span
                  class="inline-block rounded-full size-3"
                  :style="{ background: preset.color }"
                />
                {{ preset.label }}
              </button>
              <span class="mx-1 text-xs text-n-slate-10">或</span>
              <input
                v-model="accent"
                type="color"
                class="w-8 h-8 p-0 bg-transparent border rounded cursor-pointer border-n-weak"
                title="自定义颜色（仅改文字/链接色，图标沿用所选配色）"
              />
            </div>

            <div class="flex items-center gap-2">
              <label class="text-heading-3 text-n-slate-12 shrink-0"
                >字体</label
              >
              <SelectCard
                v-model="fontChoice"
                :options="fontOptions"
                align="left"
                trigger-class="min-w-[180px]"
              />
              <span class="text-xs text-n-slate-10">邮件安全字体</span>
            </div>

            <Input
              v-model="form.name"
              label="姓名（英文）"
              placeholder="Amber Law"
            />
            <div class="grid grid-cols-2 gap-2">
              <Input
                v-model="form.title"
                label="职位"
                placeholder="Sales Manager"
              />
              <Input v-model="form.dept" label="部门" placeholder="外贸一部" />
            </div>
            <Input
              v-model="form.company"
              label="公司"
              placeholder="United Touch Technology Co., Ltd."
            />
            <div class="grid grid-cols-2 gap-2">
              <Input
                v-model="form.mobile"
                label="手机"
                placeholder="138-0000-0000"
              />
              <Input
                v-model="form.tel"
                label="座机"
                placeholder="020-0000000"
              />
            </div>
            <Input
              v-model="form.email"
              label="邮箱"
              placeholder="sam@wintouch.com"
            />
            <Input
              v-model="form.website"
              label="网站"
              placeholder="www.wintouch.com"
            />
            <Input
              v-model="form.address"
              label="地址"
              placeholder="Room 808, Building A, Shenzhen…"
            />
            <div class="grid grid-cols-2 gap-2">
              <Input v-model="form.wechat" label="微信" placeholder="wxid…" />
              <Input
                v-model="form.whatsapp"
                label="WhatsApp"
                placeholder="+86…"
              />
            </div>
            <Input
              v-model="form.logoUrl"
              label="Logo / 头像图片链接（选填）"
              placeholder="https://…"
            />

            <div class="pt-1 mt-1 border-t border-n-weak">
              <p class="mb-2 text-xs text-n-slate-10">
                选填 · 社交图标（领英等）填了会显示在所有模板；标语 /
                城市用于「品牌社交」模板
              </p>
              <div class="flex flex-col gap-2">
                <Input v-model="form.tagline" label="标语（选填）" />
                <Input
                  v-model="form.cities"
                  label="城市 / 据点（选填）"
                  placeholder="e.g. Shenzhen, Hangzhou, Shanghai, Ningbo"
                />
                <Input
                  v-model="form.linkedin"
                  label="LinkedIn 链接"
                  placeholder="https://www.linkedin.com/in/…"
                />
                <div class="grid grid-cols-2 gap-2">
                  <Input
                    v-model="form.facebook"
                    label="Facebook"
                    placeholder="https://facebook.com/…"
                  />
                  <Input
                    v-model="form.instagram"
                    label="Instagram"
                    placeholder="https://instagram.com/…"
                  />
                </div>
              </div>
            </div>
          </div>

          <!-- 右：预览 + 保存 -->
          <div class="flex-1 flex flex-col min-w-0 p-5 gap-3 bg-n-alpha-1">
            <label class="text-heading-3 text-n-slate-12">实时预览</label>
            <div
              class="flex-1 min-h-0 overflow-auto p-5 bg-white border rounded-xl border-n-weak"
            >
              <!-- eslint-disable-next-line vue/no-v-html -->
              <div v-html="generatedHtml" />
            </div>

            <Input v-model="sigName" label="签名名称" />
            <label
              class="inline-flex items-center gap-2 text-sm cursor-pointer text-n-slate-12"
            >
              <input
                v-model="isDefault"
                type="checkbox"
                class="rounded border-n-weak text-n-iris-9 focus:ring-n-iris-9"
              />
              设为默认签名（新邮件自动带出）
            </label>
          </div>
        </div>

        <!-- 底 -->
        <div
          class="flex items-center justify-end gap-2 px-5 py-3 border-t border-n-weak shrink-0"
        >
          <Button
            label="取消"
            variant="outline"
            color="slate"
            @click="emit('close')"
          />
          <Button
            label="生成并保存"
            color="iris"
            :disabled="!canSave"
            @click="onSave"
          />
        </div>
      </div>
    </div>
  </Teleport>
</template>
