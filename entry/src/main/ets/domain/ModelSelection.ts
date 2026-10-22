import { ModelItem } from './Core';

// Search the complete server catalog; the view controls how many rows are rendered.
export function matchingModels(models: ModelItem[], query: string, current: string = ''): ModelItem[] {
  const terms = query.trim().toLowerCase().split(/\s+/).filter((term: string) => !!term);
  const seen = new Set<string>();
  const result = models.filter((model: ModelItem) => {
    if (seen.has(model.id)) { return false; } seen.add(model.id);
    const text = (model.id + ' ' + model.label).toLowerCase();
    return terms.every((term: string) => text.indexOf(term) >= 0);
  });
  if (!terms.length && current) {
    const selected = result.findIndex((model: ModelItem) => model.id === current);
    if (selected > 0) { result.unshift(result.splice(selected, 1)[0]); }
  }
  return result;
}
export function modelInputs(model: ModelItem): string {
  const inputs = ['文本'];
  if ((model.input || []).indexOf('image') >= 0) { inputs.push('图片'); }
  if ((model.input || []).indexOf('pdf') >= 0) { inputs.push('PDF'); }
  return inputs.join(' · ');
}

// A small server-backed shortlist; the full searchable catalog is always reachable.
export function quickModels(models: ModelItem[], current: string): ModelItem[] {
  const catalog = matchingModels(models, '', current);
  const selected: ModelItem[] = [];
  const add = (model: ModelItem | undefined): void => {
    if (model && selected.length < 3 && !selected.some((item: ModelItem) => item.id === model.id)) { selected.push(model); }
  };
  add(catalog.find((model: ModelItem) => model.id === current));
  add(catalog.find((model: ModelItem) => /mimo/i.test(model.id + ' ' + model.label)));
  add(catalog.find((model: ModelItem) => /deepseek/i.test(model.id + ' ' + model.label)));
  for (const model of catalog) { if (selected.length >= 3) { break; } add(model); }
  return selected;
}

export interface ModelPreferences { enabled: string[]; favorites: string[]; recent: string[]; }
export function emptyModelPreferences(): ModelPreferences { return { enabled: [], favorites: [], recent: [] }; }
function modelIDs(values: string[] | undefined): string[] {
  if (!Array.isArray(values)) { return []; }
  return Array.from(new Set(values.filter((id: string) => typeof id === 'string' && id.length <= 512 && id.indexOf('/') > 0 && !id.endsWith('/') && !id.includes('#')))).slice(0, 5000);
}
export function normalizeModelPreferences(value: ModelPreferences | undefined): ModelPreferences {
  if (!value) { return emptyModelPreferences(); }
  const enabled = modelIDs(value.enabled); const available = new Set(enabled);
  return { enabled: enabled, favorites: modelIDs(value.favorites).filter((id: string) => available.has(id)), recent: modelIDs(value.recent).slice(0, 30) };
}
export function enabledModels(models: ModelItem[], preferences: ModelPreferences): ModelItem[] {
  const ids = new Set(preferences.enabled);
  return matchingModels(models, '').filter((model: ModelItem) => ids.has(model.id) && model.available !== false);
}
export function favoriteModels(models: ModelItem[], preferences: ModelPreferences): ModelItem[] {
  const enabled = enabledModels(models, preferences);
  return preferences.favorites.map((id: string) => enabled.find((model: ModelItem) => model.id === id)).filter((model: ModelItem | undefined) => !!model) as ModelItem[];
}
export function recentModels(models: ModelItem[], preferences: ModelPreferences): ModelItem[] {
  const enabled = enabledModels(models, preferences); const favorites = new Set(preferences.favorites);
  return preferences.recent.filter((id: string) => !favorites.has(id)).map((id: string) => enabled.find((model: ModelItem) => model.id === id)).filter((model: ModelItem | undefined) => !!model).slice(0, 2) as ModelItem[];
}
export function setModelEnabled(preferences: ModelPreferences, id: string, enabled: boolean): ModelPreferences {
  return normalizeModelPreferences({ enabled: enabled ? preferences.enabled.concat(id) : preferences.enabled.filter((key: string) => key !== id),
    favorites: enabled ? preferences.favorites : preferences.favorites.filter((key: string) => key !== id), recent: preferences.recent });
}
export function setModelFavorite(preferences: ModelPreferences, id: string, favorite: boolean): ModelPreferences {
  return normalizeModelPreferences({ enabled: favorite ? preferences.enabled.concat(id) : preferences.enabled,
    favorites: favorite ? preferences.favorites.concat(id) : preferences.favorites.filter((key: string) => key !== id), recent: preferences.recent });
}
export function rememberModel(preferences: ModelPreferences, id: string): ModelPreferences {
  return normalizeModelPreferences({ enabled: preferences.enabled, favorites: preferences.favorites, recent: [id].concat(preferences.recent.filter((key: string) => key !== id)) });
}
export function variantLabel(id: string): string {
  switch (id) {
    case '': return '默认'; case 'none': return '关闭'; case 'minimal': return '最少'; case 'low': return '轻量';
    case 'medium': return '标准'; case 'high': return '进阶'; case 'xhigh': return '极高'; case 'max': return '极致';
    case 'adaptive': return '自适应'; case 'thinking': return '思考'; case 'fast': return '快速'; default: return id;
  }
}
