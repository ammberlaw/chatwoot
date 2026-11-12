/* global axios */
import { ref, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from './useAccount';

export function useHrSensitiveSession() {
  const { accountId } = useAccount();
  const { t } = useI18n();
  const active = ref(false);
  const checking = ref(true);
  const password = ref('');
  const error = ref('');
  const verifying = ref(false);
  let timer;
  let generation = 0;
  let alive = true;
  let interceptor;
  const url = () => `/api/v1/accounts/${accountId.value}/crm/sensitive_session`;
  const lock = () => {
    generation += 1;
    clearTimeout(timer);
    active.value = false;
    password.value = '';
    error.value = t('CRM.HR_WORKFLOW.SESSION_EXPIRED');
  };
  const accept = data => {
    clearTimeout(timer);
    active.value = data.active === true;
    if (!active.value) {
      return;
    }
    timer = setTimeout(lock, Math.max(0, Number(data.expires_in || 0)) * 1000);
  };
  const handleError = failure => {
    if (
      failure?.response?.status === 403 &&
      failure?.response?.data?.code === 'sensitive_verification_required'
    ) {
      lock();
      return true;
    }
    return false;
  };
  const check = async () => {
    generation += 1;
    const request = generation;
    try {
      const { data } = await axios.get(url());
      if (alive && request === generation) accept(data);
    } catch {
      if (alive && request === generation) {
        active.value = false;
      }
    } finally {
      if (alive && request === generation) checking.value = false;
    }
  };
  const unlock = async () => {
    if (!password.value || verifying.value) return;
    generation += 1;
    const request = generation;
    verifying.value = true;
    error.value = '';
    try {
      const { data } = await axios.post(url(), { password: password.value });
      if (alive && request === generation) {
        password.value = '';
        accept(data);
      }
    } catch (failure) {
      if (alive && request === generation)
        error.value = t(
          failure?.response?.status === 401
            ? 'CRM.HR_WORKFLOW.WRONG_PASSWORD'
            : 'CRM.HR_WORKFLOW.FAILED'
        );
    } finally {
      if (alive && request === generation) verifying.value = false;
    }
  };
  const onVisible = () => {
    if (document.visibilityState === 'visible' && active.value) check();
  };
  onMounted(() => {
    interceptor = axios.interceptors.response.use(undefined, failure => {
      if (
        failure?.config?.url?.includes(
          `/api/v1/accounts/${accountId.value}/crm/`
        )
      )
        handleError(failure);
      return Promise.reject(failure);
    });
    check();
    document.addEventListener('visibilitychange', onVisible);
  });
  onBeforeUnmount(() => {
    active.value = false;
    alive = false;
    generation += 1;
    clearTimeout(timer);
    axios.interceptors.response.eject(interceptor);
    document.removeEventListener('visibilitychange', onVisible);
  });
  return { active, checking, password, error, verifying, unlock, handleError };
}
