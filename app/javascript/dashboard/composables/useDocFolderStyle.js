import { computed } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';

export const DOC_FOLDER_STYLES = [
  { id: 'default', label: 'DEFAULT', image: null },
  {
    id: 'black-glass',
    label: 'BLACK_GLASS',
    image: '/assets/images/dashboard/folders/black-glass.svg',
  },
  {
    id: 'black-cat',
    label: 'BLACK_CAT',
    image: '/assets/images/dashboard/folders/black-cat.png',
  },
  {
    id: 'pink-sheep',
    label: 'PINK_SHEEP',
    image: '/assets/images/dashboard/folders/pink-sheep.png',
  },
  {
    id: 'purple-jester',
    label: 'PURPLE_JESTER',
    image: '/assets/images/dashboard/folders/purple-jester.png',
  },
  {
    id: 'pink-bunny',
    label: 'PINK_BUNNY',
    image: '/assets/images/dashboard/folders/pink-bunny.png',
  },
  {
    id: 'yellow-puppy',
    label: 'YELLOW_PUPPY',
    image: '/assets/images/dashboard/folders/yellow-puppy.png',
  },
  {
    id: 'blue-puppy',
    label: 'BLUE_PUPPY',
    image: '/assets/images/dashboard/folders/blue-puppy.png',
  },
  {
    id: 'christmas',
    label: 'CHRISTMAS',
    image: '/assets/images/dashboard/folders/christmas.png',
  },
  {
    id: 'floral-daisy',
    label: 'FLORAL_DAISY',
    image: '/assets/images/dashboard/folders/floral-daisy.png',
    animated: true,
  },
  {
    id: 'floral-jasmine',
    label: 'FLORAL_JASMINE',
    image: '/assets/images/dashboard/folders/floral-jasmine.png',
    animated: true,
  },
  {
    id: 'floral-wisteria',
    label: 'FLORAL_WISTERIA',
    image: '/assets/images/dashboard/folders/floral-wisteria.png',
    animated: true,
  },
  {
    id: 'sketch-penguin',
    label: 'SKETCH_PENGUIN',
    image: '/assets/images/dashboard/folders/sketch-penguin.png',
  },
  {
    id: 'sketch-pudding',
    label: 'SKETCH_PUDDING',
    image: '/assets/images/dashboard/folders/sketch-pudding.png',
  },
];

export function useDocFolderStyle() {
  const uiSettings = useMapGetter('getUISettings');
  const { accountId } = useAccount();
  const folderStyle = computed(
    () =>
      DOC_FOLDER_STYLES.find(
        style => style.id === uiSettings.value.doc_folder_style
      ) || DOC_FOLDER_STYLES[0]
  );
  const folderStyleKey = (type, id) => `${accountId.value}:${type}:${id}`;
  const styleForFolder = key =>
    DOC_FOLDER_STYLES.find(
      style => style.id === uiSettings.value.doc_folder_styles?.[key]
    ) || folderStyle.value;
  return {
    folderStyleKey,
    styleForFolder,
    uiSettings,
    folderStyle,
    folderStyleImage: computed(() => folderStyle.value.image),
  };
}
