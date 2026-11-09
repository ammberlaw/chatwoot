/* global axios */
const endpoint = '/api/v1/profile/workspace_wallpaper';

export default {
  get() {
    return axios.get(endpoint);
  },
  update(file, { removeWallpaper = false, cardOpacity, headerColor } = {}) {
    const data = new FormData();
    if (file) data.append('wallpaper', file);
    if (removeWallpaper) data.append('remove_wallpaper', 'true');
    if (headerColor !== undefined) data.append('header_color', headerColor);
    if (cardOpacity) {
      if (cardOpacity.all !== undefined) {
        data.append('card_opacity[all]', cardOpacity.all);
      }
      if (cardOpacity.overrides) {
        Object.entries(cardOpacity.overrides).forEach(([id, opacity]) => {
          data.append(`card_opacity[overrides][${id}]`, opacity);
        });
      }
    }
    return axios.put(endpoint, data);
  },
  delete() {
    return axios.delete(endpoint);
  },
};
