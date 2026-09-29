import Auth from '../api/auth';
import { getActiveProductLine } from '../composables/useMesProductLine';
import { clearCookiesOnLogout } from '../store/utils/api';

const parseErrorCode = error => Promise.reject(error);

// 会话失效兜底：登录态没了就清掉本地并跳登录页，免得侧边栏那几个定时轮询带着死 token
// 一直打 401（用户还以为自己登录着，只看见莫名其妙的报错飘过）。
//
// ⚠️ 不能见 401 就踢人：后端把 **权限不足** 也渲染成 401（Pundit 走 render_unauthorized），
// 比如财务没有出库权限，侧边栏轮询 MES 审批箱就会收到 401——按 401 踢人的话，
// 财务一进系统就被登出。两者只能靠响应体区分，且必须用白名单（认不准就别动）：
//   未登录   → {"errors":["You need to sign in or sign up before continuing."]}
//   权限不足 → {"error":"You are not authorized to do this action"}
const AUTH_ENDPOINTS = /\/auth\/(sign_in|sign_out|password)/;
let sessionExpiryHandled = false;

// 只认 devise_token_auth 的未登录信号；其余 401（含权限不足）一律不当作掉登录。
const isSignedOutResponse = data => {
  const errors = data?.errors;
  if (!Array.isArray(errors)) return false;
  return errors.some(e => /sign in|sign up|登录/i.test(String(e)));
};

const handleSessionExpiry = error => {
  if (sessionExpiryHandled) return;
  if (error?.response?.status !== 401) return;
  if (AUTH_ENDPOINTS.test(error?.config?.url || '')) return;
  if (!isSignedOutResponse(error?.response?.data)) return;
  // 本来就没登录（登录页自身的请求）不跳，避免循环。
  if (!Auth.hasAuthCookie()) return;

  sessionExpiryHandled = true;
  clearCookiesOnLogout();
};

export default axios => {
  const { apiHost = '' } = window.chatwootConfig || {};
  const wootApi = axios.create({ baseURL: `${apiHost}/` });
  // Add Auth Headers to requests if logged in
  if (Auth.hasAuthCookie()) {
    const {
      'access-token': accessToken,
      'token-type': tokenType,
      client,
      expiry,
      uid,
    } = Auth.getAuthData();
    Object.assign(wootApi.defaults.headers.common, {
      'access-token': accessToken,
      'token-type': tokenType,
      client,
      expiry,
      uid,
    });
  }
  // 产品线分流：给所有 MES 请求自动注入当前切换的 product_line（空=全部，不注入）。
  wootApi.interceptors.request.use(config => {
    const line = getActiveProductLine();
    if (line && /\/mes\//.test(config.url || '')) {
      config.params = { ...(config.params || {}), product_line: line };
    }
    return config;
  });
  // Response parsing interceptor
  wootApi.interceptors.response.use(
    response => response,
    error => {
      handleSessionExpiry(error);
      return parseErrorCode(error);
    }
  );
  return wootApi;
};
