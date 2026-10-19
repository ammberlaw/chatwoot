<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import BusinessCardAPI from 'dashboard/api/crm/businessCards';
import Button from 'dashboard/components-next/button/Button.vue';
import { COUNTRY_LABELS } from 'dashboard/routes/dashboard/crm/constants/countries';

// 展会名片：现场连拍，回头批量校对入库。
//
// 这页主要在**手机上**用——展会现场站着就把名片拍了，所以拍照按钮做得很大、
// 单列布局，桌面端只是把卡片排成两列。识别放后台跑，拍完立刻能拍下一张。

const cards = ref([]);
const loading = ref(false);
const uploading = ref(0);
const eventName = ref('');
const recentEvents = ref([]);
const fileInput = ref(null);
// 展开校对的那张卡（一次只展开一张，手机上同时展开两张没法看）
const editingId = ref(null);
const draft = ref({});
const saving = ref(false);
// 查重撞上时把命中的客户和当前卡记下来，弹确认条
const dupe = ref(null);

const FIELDS = [
  { key: 'company_name', label: '公司名', required: true },
  { key: 'contact_name', label: '联系人' },
  { key: 'job_title', label: '职位' },
  { key: 'contact_email', label: '邮箱', type: 'email' },
  { key: 'contact_phone', label: '电话', type: 'tel' },
  { key: 'whats_app', label: 'WhatsApp', type: 'tel' },
  { key: 'website', label: '网址' },
  { key: 'country', label: '国家', type: 'country' },
  { key: 'address', label: '地址' },
  { key: 'event_name', label: '展会' },
  { key: 'remark', label: '现场备注', type: 'textarea' },
];

const countryOptions = computed(() =>
  Object.entries(COUNTRY_LABELS).map(([value, label]) => ({ value, label }))
);

const inbox = computed(() => cards.value.filter(c => c.status !== 'CONFIRMED'));
const done = computed(() => cards.value.filter(c => c.status === 'CONFIRMED'));
const pendingCount = computed(
  () => cards.value.filter(c => c.status === 'PENDING').length
);

const load = async () => {
  loading.value = true;
  try {
    const { data } = await BusinessCardAPI.get({ per_page: 30 });
    cards.value = data.payload || [];
  } catch (e) {
    useAlert('名片列表没load出来，刷新试试');
  } finally {
    loading.value = false;
  }
};

const loadEvents = async () => {
  try {
    const { data } = await BusinessCardAPI.events();
    recentEvents.value = data.payload || [];
  } catch (e) {
    recentEvents.value = [];
  }
};

// 还有没识别完的就隔几秒拉一次。全部识别完就停——展会回来一屏几十张，
// 一直轮询既费电又白打后端。
let timer = null;
const syncPolling = () => {
  const needed = pendingCount.value > 0;
  if (needed && !timer) {
    timer = setInterval(async () => {
      await load();
      syncPolling();
    }, 4000);
  } else if (!needed && timer) {
    clearInterval(timer);
    timer = null;
  }
};

// 一次可以选多张：现场连拍先存相册，回头一次全传上来也是常见用法。
const onPick = async event => {
  const files = [...(event.target.files || [])];
  event.target.value = '';
  if (!files.length) return;

  uploading.value = files.length;
  // 串行上传：展会现场网络常常很差，并发几张反而都传不上去。
  const uploadOne = async file => {
    const form = new FormData();
    form.append('image', file);
    if (eventName.value.trim())
      form.append('event_name', eventName.value.trim());
    try {
      await BusinessCardAPI.createWithFiles(form);
    } catch (e) {
      useAlert(`「${file.name}」没传上去，回头在相册里重传一次`);
    }
    uploading.value -= 1;
  };
  await files.reduce(
    (chain, file) => chain.then(() => uploadOne(file)),
    Promise.resolve()
  );

  await load();
  await loadEvents();
  syncPolling();
};

const startEdit = card => {
  editingId.value = card.id;
  draft.value = FIELDS.reduce((acc, f) => {
    acc[f.key] = card[f.key] || '';
    return acc;
  }, {});
};
const cancelEdit = () => {
  editingId.value = null;
  draft.value = {};
};

const save = async card => {
  saving.value = true;
  try {
    const { data } = await BusinessCardAPI.update(card.id, {
      business_card: draft.value,
    });
    Object.assign(card, data);
    cancelEdit();
    useAlert('已保存');
  } catch (e) {
    useAlert(e?.response?.data?.error || '保存失败');
  } finally {
    saving.value = false;
  }
};

// 确认入库。撞到重复客户后端回 409，这里把那条客户亮出来让人自己选：
// 挂到那家去，还是确实是两家公司、照样新建。
const confirm = async (card, params = {}) => {
  saving.value = true;
  try {
    const { data } = await BusinessCardAPI.confirm(card.id, params);
    Object.assign(card, data);
    dupe.value = null;
    cancelEdit();
    useAlert(params.link_customer_id ? '已挂到那家客户下' : '已建客户');
  } catch (e) {
    const hit = e?.response?.data?.duplicate;
    if (e?.response?.status === 409 && hit) dupe.value = { card, hit };
    else useAlert(e?.response?.data?.error || '建客户失败');
  } finally {
    saving.value = false;
  }
};

const discard = async card => {
  try {
    await BusinessCardAPI.delete(card.id);
    cards.value = cards.value.filter(c => c.id !== card.id);
  } catch (e) {
    useAlert('删不掉，刷新试试');
  }
};

const statusLabel = card => {
  if (card.status === 'PENDING')
    return { text: '识别中…', cls: 'text-n-amber-11' };
  if (card.status === 'CONFIRMED')
    return { text: '已建客户', cls: 'text-n-teal-11' };
  if (card.parse_error)
    return { text: '没识别出来，手工填', cls: 'text-n-ruby-11' };
  return { text: '待校对', cls: 'text-n-slate-11' };
};

const summary = card =>
  [card.contact_name, card.job_title, card.contact_email]
    .filter(Boolean)
    .join(' · ') || '（没识别出联系人）';

onMounted(async () => {
  await Promise.all([load(), loadEvents()]);
  syncPolling();
});
onUnmounted(() => timer && clearInterval(timer));
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-hidden bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div
      class="flex flex-col flex-shrink-0 gap-2 px-4 pt-4 pb-1.5 sm:px-[26px] sm:pt-[18px]"
    >
      <h1
        class="text-[22px] font-bold tracking-[-0.01em] text-n-slate-12 [.theme-classic_&]:!text-heading-1 [.theme-classic_&]:!font-semibold"
      >
        展会名片
      </h1>
      <p class="text-label-small text-n-slate-11">
        现场只管连拍，识别在后台跑；回头在这页校对、确认建客户。
      </p>
    </div>

    <div class="flex-1 min-h-0 px-4 pb-4 overflow-y-auto sm:px-[26px]">
      <!-- 拍照区：手机上这块是主角，所以按钮做得很大 -->
      <div class="p-4 mb-4 border rounded-2xl border-n-weak bg-n-solid-1/70">
        <label class="block mb-1.5 text-label text-n-slate-12">
          这批名片是哪个展会收的
        </label>
        <input
          v-model="eventName"
          type="text"
          placeholder="例如：2026 广交会 / Canton Fair 2026"
          class="w-full h-10 px-3 mb-2 text-sm border rounded-lg outline-none reset-base border-n-weak bg-n-solid-1 text-n-slate-12"
        />
        <div v-if="recentEvents.length" class="flex flex-wrap gap-1.5 mb-3">
          <button
            v-for="name in recentEvents"
            :key="name"
            type="button"
            class="px-2.5 py-1 text-label-small rounded-full reset-base bg-n-alpha-2 text-n-slate-11 hover:bg-n-iris-3"
            @click="eventName = name"
          >
            {{ name }}
          </button>
        </div>

        <!-- capture=environment：手机上点一下直接调起后置摄像头，不用先进相册。
             multiple 是给「现场先拍进相册、回头一次全传」那种用法留的。 -->
        <input
          ref="fileInput"
          type="file"
          accept="image/*"
          capture="environment"
          multiple
          class="hidden"
          @change="onPick"
        />
        <button
          type="button"
          :disabled="uploading > 0"
          class="flex items-center justify-center w-full gap-2 text-base font-semibold text-white rounded-xl reset-base h-14 bg-n-iris-9 hover:bg-n-iris-10 disabled:opacity-60"
          @click="fileInput?.click()"
        >
          <span class="i-lucide-camera size-5 shrink-0" />
          {{ uploading > 0 ? `上传中…还剩 ${uploading} 张` : '拍名片' }}
        </button>
      </div>

      <!-- 查重撞上：把命中的那家亮出来，由人决定挂过去还是另建 -->
      <div
        v-if="dupe"
        class="p-3 mb-4 border rounded-xl border-n-amber-7 bg-n-amber-2"
      >
        <div class="mb-1 text-label text-n-slate-12">
          库里已经有一家很像的客户
        </div>
        <div class="mb-2 text-label-small text-n-slate-11">
          {{ dupe.hit.name }}
          <template v-if="dupe.hit.customer_code">
            · {{ dupe.hit.customer_code }}
          </template>
          <template v-if="dupe.hit.owner_name">
            · 负责人 {{ dupe.hit.owner_name }}
          </template>
        </div>
        <div class="flex flex-wrap gap-2">
          <Button
            label="就是这家，挂过去"
            color="teal"
            size="sm"
            :is-loading="saving"
            @click="confirm(dupe.card, { link_customer_id: dupe.hit.id })"
          />
          <Button
            label="不是同一家，照样新建"
            variant="outline"
            size="sm"
            :is-loading="saving"
            @click="confirm(dupe.card, { force: true })"
          />
          <Button
            label="先放着"
            variant="ghost"
            size="sm"
            @click="dupe = null"
          />
        </div>
      </div>

      <div
        v-if="loading && !cards.length"
        class="py-10 text-center text-n-slate-11"
      >
        载入中…
      </div>
      <div
        v-else-if="!cards.length"
        class="py-10 text-center text-label-small text-n-slate-11"
      >
        还没有名片。上面点「拍名片」开始。
      </div>

      <!-- 待整理 -->
      <div v-if="inbox.length" class="mb-5">
        <h2 class="mb-2 text-heading-3 text-n-slate-12">
          待整理（{{ inbox.length }}）
        </h2>
        <div class="grid grid-cols-1 gap-3 lg:grid-cols-2">
          <div
            v-for="card in inbox"
            :key="card.id"
            class="overflow-hidden border rounded-xl border-n-weak bg-n-solid-1/70"
          >
            <div class="flex gap-3 p-3">
              <img
                v-if="card.image_url"
                :src="card.image_url"
                alt="名片照片"
                class="object-cover w-24 h-16 border rounded-lg shrink-0 border-n-weak"
              />
              <div class="flex-1 min-w-0">
                <div class="truncate text-heading-3 text-n-slate-12">
                  {{ card.company_name || '（没识别出公司名）' }}
                </div>
                <div class="truncate text-label-small text-n-slate-11">
                  {{ summary(card) }}
                </div>
                <div
                  class="mt-1 text-label-small"
                  :class="statusLabel(card).cls"
                >
                  {{ statusLabel(card).text }}
                  <template v-if="card.event_name">
                    · {{ card.event_name }}
                  </template>
                </div>
              </div>
            </div>

            <div
              v-if="editingId !== card.id"
              class="flex flex-wrap gap-2 px-3 pb-3"
            >
              <Button
                label="校对"
                variant="outline"
                size="sm"
                :disabled="card.status === 'PENDING'"
                @click="startEdit(card)"
              />
              <Button
                label="建客户"
                color="teal"
                size="sm"
                :disabled="card.status === 'PENDING' || !card.company_name"
                :is-loading="saving"
                @click="confirm(card)"
              />
              <Button
                label="丢弃"
                variant="ghost"
                color="ruby"
                size="sm"
                @click="discard(card)"
              />
            </div>

            <!-- 校对表单：识别错了就地改，原文摆在下面对照 -->
            <div v-else class="px-3 pb-3 border-t border-n-weak">
              <div class="grid grid-cols-1 gap-2 mt-3 sm:grid-cols-2">
                <div
                  v-for="f in FIELDS"
                  :key="f.key"
                  :class="f.type === 'textarea' ? 'sm:col-span-2' : ''"
                >
                  <label class="block mb-1 text-label-small text-n-slate-11">
                    {{ f.label }}
                    <span v-if="f.required" class="text-n-ruby-11">*</span>
                  </label>
                  <textarea
                    v-if="f.type === 'textarea'"
                    v-model="draft[f.key]"
                    rows="2"
                    placeholder="聊了什么、要什么货、报了什么价"
                    class="w-full px-2 py-1.5 text-sm border rounded-lg outline-none reset-base border-n-weak bg-n-solid-1 text-n-slate-12"
                  />
                  <select
                    v-else-if="f.type === 'country'"
                    v-model="draft[f.key]"
                    class="w-full h-9 px-2 text-sm border rounded-lg outline-none reset-base border-n-weak bg-n-solid-1 text-n-slate-12"
                  >
                    <option value="">（未填）</option>
                    <option
                      v-for="opt in countryOptions"
                      :key="opt.value"
                      :value="opt.value"
                    >
                      {{ opt.label }}
                    </option>
                  </select>
                  <input
                    v-else
                    v-model="draft[f.key]"
                    :type="f.type || 'text'"
                    class="w-full h-9 px-2 text-sm border rounded-lg outline-none reset-base border-n-weak bg-n-solid-1 text-n-slate-12"
                  />
                </div>
              </div>

              <details v-if="card.raw_text" class="mt-2">
                <summary
                  class="cursor-pointer text-label-small text-n-slate-11"
                >
                  看识别原文
                </summary>
                <pre
                  class="p-2 mt-1 overflow-x-auto text-xs whitespace-pre-wrap rounded-lg bg-n-alpha-1 text-n-slate-11"
                  >{{ card.raw_text }}</pre>
              </details>
              <div
                v-if="card.parse_error"
                class="mt-2 text-label-small text-n-ruby-11"
              >
                {{ card.parse_error }}
              </div>

              <div class="flex flex-wrap gap-2 mt-3">
                <Button
                  label="保存"
                  size="sm"
                  :is-loading="saving"
                  @click="save(card)"
                />
                <Button
                  label="保存并建客户"
                  color="teal"
                  size="sm"
                  :is-loading="saving"
                  @click="save(card).then(() => confirm(card))"
                />
                <Button
                  label="取消"
                  variant="ghost"
                  size="sm"
                  @click="cancelEdit"
                />
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- 已入库：只留一行，证明这张处理过了 -->
      <div v-if="done.length">
        <h2 class="mb-2 text-heading-3 text-n-slate-12">
          已建客户（{{ done.length }}）
        </h2>
        <div class="flex flex-col gap-1.5">
          <div
            v-for="card in done"
            :key="card.id"
            class="flex items-center gap-2 px-3 py-2 border rounded-lg border-n-weak bg-n-solid-1/50"
          >
            <span class="i-lucide-check text-n-teal-11 size-4 shrink-0" />
            <span
              class="flex-1 min-w-0 truncate text-label-small text-n-slate-12"
            >
              {{ card.company_name }}
              <template v-if="card.customer_name">
                → {{ card.customer_name }}
              </template>
            </span>
            <span
              v-if="card.event_name"
              class="text-label-small text-n-slate-10 shrink-0"
            >
              {{ card.event_name }}
            </span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
