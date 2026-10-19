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
