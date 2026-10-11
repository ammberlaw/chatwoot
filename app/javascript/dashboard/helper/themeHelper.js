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
// 公司统一配色＝雅黑，没选过的人默认给它。
export const DEFAULT_COLOR_PALETTE = 'classicBlack';
const PALETTE_CLASSES = {
  blue: 'theme-blue',
  classic: 'theme-classic',
  classicBlack: 'theme-classic-black',
  obsidian: 'theme-obsidian-flat',
};
export const COLOR_PALETTES = ['purple', ...Object.keys(PALETTE_CLASSES)];

// 一次性把所有人切到公司统一配色（雅黑）。
//
// 配色存在浏览器 localStorage 里，**改默认值只影响"从没选过的人"**——已经选过紫玻璃/经典灰
// 的那几位会一直停在旧配色上。这里用一个一次性标记把他们也切过来。
// 标记只写一次：切完之后他们仍然可以自己再改配色，不会每次打开都被按回雅黑。
// 服务端 ui_settings.ui_palette 同步由上线时的一次性 SQL 刷平（换设备/清缓存后也落雅黑）。
export const forceDefaultPaletteOnce = () => {
  if (LocalStorage.get(LOCAL_STORAGE_KEYS.COLOR_PALETTE_FORCED)) return;

  LocalStorage.set(LOCAL_STORAGE_KEYS.COLOR_PALETTE_FORCED, '1');
  LocalStorage.set(LOCAL_STORAGE_KEYS.COLOR_PALETTE, DEFAULT_COLOR_PALETTE);
};

export const applyColorPalette = palette => {
  const requested =
    palette ||
    LocalStorage.get(LOCAL_STORAGE_KEYS.COLOR_PALETTE) ||
    DEFAULT_COLOR_PALETTE;
  const selected = COLOR_PALETTES.includes(requested)
    ? requested
    : DEFAULT_COLOR_PALETTE;
  const { classList } = document.body;
  classList.remove(
    ...Object.values(PALETTE_CLASSES),
    'theme-obsidian',
    'theme-beebot',
    'theme-inkarc'
  );
  if (PALETTE_CLASSES[selected]) classList.add(PALETTE_CLASSES[selected]);
  // This independent variant inherits classic content and adds only a rail override.
  if (selected === 'classicBlack' || selected === 'obsidian') {
    classList.add('theme-classic', 'theme-classic-black');
  }
  return selected;
};
