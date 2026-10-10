import { LocalStorage } from 'shared/helpers/localStorage';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';

export const setColorTheme = isOSOnDarkMode => {
  const selectedColorScheme =
    LocalStorage.get(LOCAL_STORAGE_KEYS.COLOR_SCHEME) || 'auto';
  if (
    (selectedColorScheme === 'auto' && isOSOnDarkMode) ||
    selectedColorScheme === 'dark'
  ) {
    document.body.classList.add('dark');
    document.documentElement.style.setProperty('color-scheme', 'dark');
  } else {
    document.body.classList.remove('dark');
    document.documentElement.style.setProperty('color-scheme', 'light');
  }
};

// 配色主题（与深浅模式正交）：紫玻璃走 :root（无 class），其余各挂 body.theme-*。
// 没选过配色的人默认给经典灰。
export const DEFAULT_COLOR_PALETTE = 'classic';
const PALETTE_CLASSES = {
  blue: 'theme-blue',
  beebot: 'theme-beebot',
  classic: 'theme-classic',
  classicBlack: 'theme-classic-black',
  obsidian: 'theme-obsidian',
  inkarc: 'theme-inkarc',
};
export const COLOR_PALETTES = ['purple', ...Object.keys(PALETTE_CLASSES)];

export const applyColorPalette = palette => {
  const selected =
    palette ||
    LocalStorage.get(LOCAL_STORAGE_KEYS.COLOR_PALETTE) ||
    DEFAULT_COLOR_PALETTE;
  const { classList } = document.body;
  classList.remove(...Object.values(PALETTE_CLASSES));
  if (PALETTE_CLASSES[selected]) classList.add(PALETTE_CLASSES[selected]);
  // This independent variant inherits classic content and adds only a rail override.
  if (selected === 'classicBlack') classList.add('theme-classic');
  return selected;
};
