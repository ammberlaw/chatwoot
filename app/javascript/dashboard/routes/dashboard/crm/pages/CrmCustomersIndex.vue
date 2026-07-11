<script setup>
/* global axios */
import { ref, computed, onMounted, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useCrmCustomersStore } from 'dashboard/stores/crm/customers';

import Button from 'dashboard/components-next/button/Button.vue';
import CrmCustomerCreateDialog from 'dashboard/components-next/CRM/CrmCustomerCreateDialog.vue';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const { accountId, accountScopedRoute } = useAccount();
const customersStore = useCrmCustomersStore();

const actingId = ref(null);

const createDialogRef = ref(null);
const activeFilter = ref(route.query.filter || 'all');

const customers = computed(() => customersStore.getCustomers);
const uiFlags = computed(() => customersStore.getUIFlags);
const isFetching = computed(() => uiFlags.value.fetchingList);
const isCreating = computed(() => uiFlags.value.creatingItem);

const filterTabs = [
  { key: 'all', label: t('CRM.CUSTOMERS.FILTERS.ALL') },
  { key: 'mine', label: t('CRM.CUSTOMERS.FILTERS.MINE') },
  { key: 'private', label: t('CRM.CUSTOMERS.FILTERS.PRIVATE') },
  { key: 'public_pool', label: t('CRM.CUSTOMERS.FILTERS.PUBLIC_POOL') },
  { key: 'unassigned', label: t('CRM.CUSTOMERS.FILTERS.UNASSIGNED') },
];

const fetchCustomers = () => {
  const filter = activeFilter.value === 'all' ? undefined : activeFilter.value;
  customersStore.get({ page: 1, filter });
};

const setFilter = key => {
  activeFilter.value = key;
  fetchCustomers();
};

// 新建统一走「客户建档」引导页(带查重 + 自动归私海)；弹窗只用于编辑。
const goToIntake = () =>
  router.push(accountScopedRoute('crm_customer_intake_index'));
const openEditDialog = record => createDialogRef.value?.open(record);

const updateCustomer = async customer => {
  try {
    await customersStore.update(customer);
    createDialogRef.value?.onSuccess();
    useAlert(t('CRM.CUSTOMERS.EDIT.SUCCESS'));
  } catch {
    useAlert(t('CRM.CUSTOMERS.EDIT.ERROR'));
  }
};

const formatDate = value =>
  value ? new Date(value).toLocaleDateString() : '—';

const crmApi = () => `/api/v1/accounts/${accountId.value}/crm/customers`;

// 认领：公海客户归我私海；转公海：私海客户放回公海。行按钮，阻止冒泡避免触发编辑。
const claimCustomer = async customer => {
  actingId.value = customer.id;
  try {
    await axios.post(`${crmApi()}/${customer.id}/claim`);
    useAlert(t('CRM.CUSTOMERS.POOL.CLAIM_SUCCESS'));
    fetchCustomers();
  } catch (e) {
    useAlert(e.response?.data?.message || t('CRM.CUSTOMERS.POOL.CLAIM_ERROR'));
  } finally {
    actingId.value = null;
  }
};

const releaseCustomer = async customer => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('CRM.CUSTOMERS.POOL.RELEASE_CONFIRM', { name: customer.name }))) {
    return;
  }
  actingId.value = customer.id;
  try {
    await axios.post(`${crmApi()}/${customer.id}/release`);
    useAlert(t('CRM.CUSTOMERS.POOL.RELEASE_SUCCESS'));
    fetchCustomers();
  } catch (e) {
    useAlert(e.response?.data?.message || t('CRM.CUSTOMERS.POOL.RELEASE_ERROR'));
  } finally {
    actingId.value = null;
  }
};

// 软色胶囊：浅底 + 同色文字，仿 Twenty 标签观感。
// 用字面量类名(Tailwind 只编译源码里出现的完整类名，动态拼接会被漏掉)。
const PILL = {
  teal: 'bg-n-teal-3 text-n-teal-11',
  blue: 'bg-n-blue-3 text-n-blue-11',
  amber: 'bg-n-amber-3 text-n-amber-11',
  ruby: 'bg-n-ruby-3 text-n-ruby-11',
  iris: 'bg-n-iris-3 text-n-iris-11',
  slate: 'bg-n-slate-4 text-n-slate-11',
};
const AVATAR = {
  blue: 'bg-n-blue-9 text-white',
  teal: 'bg-n-teal-9 text-white',
  iris: 'bg-n-iris-9 text-white',
  amber: 'bg-n-amber-9 text-white',
  ruby: 'bg-n-ruby-9 text-white',
};
const pillCls = color => PILL[color] || PILL.slate;

const GRADE_META = {
  COMPLETE: { label: '完善', color: 'teal' },
  GOOD: { label: '良好', color: 'blue' },
  FAIR: { label: '一般', color: 'amber' },
  POOR: { label: '待完善', color: 'ruby' },
};
const STATUS_META = {
  PROSPECT: { label: '潜在客户', color: 'slate' },
  FOLLOWING: { label: '跟进中', color: 'blue' },
  WON: { label: '成交客户', color: 'teal' },
  DORMANT: { label: '沉默客户', color: 'amber' },
  LOST: { label: '流失客户', color: 'ruby' },
};
const SOURCE_META = {
  ALIBABA: { label: '阿里巴巴国际站', color: 'amber' },
  WEBSITE: { label: '官网', color: 'blue' },
  EXHIBITION: { label: '展会', color: 'teal' },
  REFERRAL: { label: '转介绍', color: 'iris' },
  EMAIL: { label: '邮件开发', color: 'amber' },
  SOCIAL_MEDIA: { label: '社媒开发', color: 'ruby' },
  OTHER: { label: '其他', color: 'slate' },
};
const LEVEL_COLOR = { A: 'teal', B: 'blue', C: 'amber', D: 'slate' };
const REGION_META = {
  NORTH_AMERICA: { label: '北美', color: 'blue' },
  EUROPE: { label: '欧洲', color: 'iris' },
  SOUTH_AMERICA: { label: '南美', color: 'teal' },
  MIDDLE_EAST: { label: '中东', color: 'amber' },
  SOUTHEAST_ASIA: { label: '东南亚', color: 'ruby' },
  AFRICA: { label: '非洲', color: 'slate' },
  OTHER: { label: '其他', color: 'slate' },
};
// 国家 → 国旗+中文名（覆盖常用外贸目的国）
const COUNTRY_MAP = {
  USA: '🇺🇸 美国', GERMANY: '🇩🇪 德国', UK: '🇬🇧 英国', FRANCE: '🇫🇷 法国',
  ITALY: '🇮🇹 意大利', SPAIN: '🇪🇸 西班牙', CANADA: '🇨🇦 加拿大', AUSTRALIA: '🇦🇺 澳大利亚',
  JAPAN: '🇯🇵 日本', SOUTH_KOREA: '🇰🇷 韩国', INDIA: '🇮🇳 印度', RUSSIA: '🇷🇺 俄罗斯',
  BRAZIL: '🇧🇷 巴西', MEXICO: '🇲🇽 墨西哥', NETHERLANDS: '🇳🇱 荷兰', BELGIUM: '🇧🇪 比利时',
  UAE: '🇦🇪 阿联酋', SAUDI_ARABIA: '🇸🇦 沙特', SINGAPORE: '🇸🇬 新加坡', MALAYSIA: '🇲🇾 马来西亚',
  THAILAND: '🇹🇭 泰国', VIETNAM: '🇻🇳 越南', INDONESIA: '🇮🇩 印尼', PHILIPPINES: '🇵🇭 菲律宾',
  TURKEY: '🇹🇷 土耳其', SOUTH_AFRICA: '🇿🇦 南非', EGYPT: '🇪🇬 埃及', NIGERIA: '🇳🇬 尼日利亚',
  POLAND: '🇵🇱 波兰', SWEDEN: '🇸🇪 瑞典', TAIWAN: '🇹🇼 台湾', HONG_KONG: '🇭🇰 香港',
  PAKISTAN: '🇵🇰 巴基斯坦', BANGLADESH: '🇧🇩 孟加拉', OTHER: '🌍 其他',
};

const gradeMeta = c => GRADE_META[c.completenessGrade] || null;
const statusMeta = c => STATUS_META[c.customerStatus] || null;
const sourceMeta = c => SOURCE_META[c.sourceChannel] || null;
const regionMeta = c => REGION_META[c.tradeRegion] || null;
const levelColor = level => LEVEL_COLOR[level] || 'slate';
const countryLabel = country => COUNTRY_MAP[country] || country || '—';

// 公司首字母头像色：按名称哈希取一个稳定色
const AVATAR_COLORS = ['blue', 'teal', 'iris', 'amber', 'ruby'];
const avatarCls = name => {
  const key = (name || '?').charCodeAt(0) || 0;
  return AVATAR[AVATAR_COLORS[key % AVATAR_COLORS.length]];
};
const initial = name => (name || '?').trim().charAt(0).toUpperCase();

const money = micros =>
  micros ? `¥${Math.round(micros / 1_000_000).toLocaleString()}` : '¥0';

onMounted(fetchCustomers);
watch(
  () => route.query.filter,
  value => {
    activeFilter.value = value || 'all';
    fetchCustomers();
  }
);
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-auto bg-n-background">
    <div
      class="flex items-center justify-between flex-shrink-0 px-6 py-4 border-b border-n-weak"
    >
      <h1 class="text-xl font-medium text-n-slate-12">
        {{ t('CRM.CUSTOMERS.HEADER') }}
      </h1>
      <Button
        :label="t('CRM.CUSTOMERS.NEW')"
        icon="i-lucide-plus"
        color="blue"
        @click="goToIntake"
      />
    </div>

    <div class="flex items-center gap-2 px-6 py-3 border-b border-n-weak">
      <Button
        v-for="tab in filterTabs"
        :key="tab.key"
        :label="tab.label"
        size="sm"
        :variant="activeFilter === tab.key ? 'solid' : 'faded'"
        :color="activeFilter === tab.key ? 'blue' : 'slate'"
        @click="setFilter(tab.key)"
      />
    </div>

    <div class="flex-1 px-6 py-4">
      <div
        v-if="isFetching"
        class="flex items-center justify-center p-8 text-base text-n-slate-11"
      >
        {{ t('CRM.CUSTOMERS.LOADING') }}
      </div>
      <div
        v-else-if="!customers.length"
        class="flex items-center justify-center p-8 text-base text-n-slate-11"
      >
        {{ t('CRM.CUSTOMERS.EMPTY') }}
      </div>
      <table v-else class="w-full text-sm text-left border-collapse">
        <thead class="text-n-slate-11">
          <tr class="border-b border-n-weak">
            <th class="px-3 py-2 font-medium whitespace-nowrap">
              {{ t('CRM.CUSTOMERS.TABLE.NAME') }}
            </th>
            <th class="px-3 py-2 font-medium whitespace-nowrap">
              {{ t('CRM.CUSTOMERS.TABLE.GRADE') }}
            </th>
            <th class="px-3 py-2 font-medium text-right whitespace-nowrap">
              {{ t('CRM.CUSTOMERS.TABLE.DEAL_AMOUNT') }}
            </th>
            <th class="px-3 py-2 font-medium text-right whitespace-nowrap">
              {{ t('CRM.CUSTOMERS.TABLE.DEAL_COUNT') }}
            </th>
            <th class="px-3 py-2 font-medium whitespace-nowrap">
              {{ t('CRM.CUSTOMERS.TABLE.STATUS') }}
            </th>
            <th class="px-3 py-2 font-medium whitespace-nowrap">
              {{ t('CRM.CUSTOMERS.TABLE.LEVEL') }}
            </th>
            <th class="px-3 py-2 font-medium whitespace-nowrap">
              {{ t('CRM.CUSTOMERS.TABLE.SOURCE') }}
            </th>
            <th class="px-3 py-2 font-medium whitespace-nowrap">
              {{ t('CRM.CUSTOMERS.TABLE.COUNTRY') }}
            </th>
            <th class="px-3 py-2 font-medium whitespace-nowrap">
              {{ t('CRM.CUSTOMERS.TABLE.REGION') }}
            </th>
            <th class="px-3 py-2 font-medium whitespace-nowrap">
              {{ t('CRM.CUSTOMERS.TABLE.OWNER') }}
            </th>
            <th class="px-3 py-2 font-medium text-right whitespace-nowrap">
              {{ t('CRM.CUSTOMERS.TABLE.ACTION') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="customer in customers"
            :key="customer.id"
            class="cursor-pointer border-b border-n-weak hover:bg-n-alpha-1"
            @click="openEditDialog(customer)"
          >
            <td class="px-3 py-2">
              <div class="flex items-center gap-2 whitespace-nowrap">
                <span
                  class="flex items-center justify-center flex-shrink-0 text-xs font-semibold rounded w-6 h-6"
                  :class="avatarCls(customer.name)"
                >
                  {{ initial(customer.name) }}
                </span>
                <span class="text-n-slate-12">{{ customer.name }}</span>
              </div>
            </td>
            <td class="px-3 py-2">
              <span
                v-if="gradeMeta(customer)"
                class="inline-flex items-center gap-1 px-2 py-0.5 rounded text-xs whitespace-nowrap"
                :class="pillCls(gradeMeta(customer).color)"
              >
                {{ gradeMeta(customer).label }}
                <span class="opacity-70">{{ customer.infoCompletenessScore }}</span>
              </span>
              <span v-else class="text-n-slate-10">—</span>
            </td>
            <td class="px-3 py-2 text-right text-n-slate-11 whitespace-nowrap">
              {{ money(customer.dealTotalAmountMicros) }}
            </td>
            <td class="px-3 py-2 text-right text-n-slate-11">
              {{ customer.dealOrderCount || 0 }}
            </td>
            <td class="px-3 py-2">
              <span
                v-if="statusMeta(customer)"
                class="inline-flex px-2 py-0.5 rounded text-xs whitespace-nowrap"
                :class="pillCls(statusMeta(customer).color)"
              >
                {{ statusMeta(customer).label }}
              </span>
              <span v-else class="text-n-slate-10">—</span>
            </td>
            <td class="px-3 py-2">
              <span
                v-if="customer.customerLevel"
                class="inline-flex items-center justify-center w-5 h-5 rounded text-xs font-medium"
                :class="pillCls(levelColor(customer.customerLevel))"
              >
                {{ customer.customerLevel }}
              </span>
              <span v-else class="text-n-slate-10">—</span>
            </td>
            <td class="px-3 py-2">
              <span
                v-if="sourceMeta(customer)"
                class="inline-flex px-2 py-0.5 rounded text-xs whitespace-nowrap"
                :class="pillCls(sourceMeta(customer).color)"
              >
                {{ sourceMeta(customer).label }}
              </span>
              <span v-else class="text-n-slate-10">—</span>
            </td>
            <td class="px-3 py-2 text-n-slate-11 whitespace-nowrap">
              {{ countryLabel(customer.tradeCountry) }}
            </td>
            <td class="px-3 py-2">
              <span
                v-if="regionMeta(customer)"
                class="inline-flex px-2 py-0.5 rounded text-xs whitespace-nowrap"
                :class="pillCls(regionMeta(customer).color)"
              >
                {{ regionMeta(customer).label }}
              </span>
              <span v-else class="text-n-slate-10">—</span>
            </td>
            <td class="px-3 py-2 text-n-slate-11 whitespace-nowrap">
              <span v-if="customer.isInPublicPool" class="text-n-sky-11">🌊 公海</span>
              <span v-else-if="customer.accountOwnerName">
                {{ customer.accountOwnerName }}
              </span>
              <span v-else class="text-n-slate-10">未分配</span>
            </td>
            <td class="px-3 py-2 text-right" @click.stop>
              <Button
                v-if="customer.isInPublicPool"
                :label="t('CRM.CUSTOMERS.POOL.CLAIM')"
                size="sm"
                color="blue"
                :is-loading="actingId === customer.id"
                @click="claimCustomer(customer)"
              />
              <Button
                v-else
                :label="t('CRM.CUSTOMERS.POOL.RELEASE')"
                size="sm"
                variant="faded"
                color="slate"
                :is-loading="actingId === customer.id"
                @click="releaseCustomer(customer)"
              />
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <CrmCustomerCreateDialog
      ref="createDialogRef"
      :is-loading="isCreating"
      @update="updateCustomer"
    />
  </div>
</template>
