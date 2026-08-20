import Auth from '../api/auth';
import { getActiveProductLine } from '../composables/useMesProductLine';

const parseErrorCode = error => Promise.reject(error);

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
    error => parseErrorCode(error)
  );
  return wootApi;
};
