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
