export interface SessionUsage { input: number; output: number; reasoning: number; cacheRead: number; cacheWrite: number; cost: number; }
export function emptyUsage(): SessionUsage { return { input: -1, output: -1, reasoning: -1, cacheRead: -1, cacheWrite: -1, cost: -1 }; }
export function usageValue(value: Object | undefined): number { return typeof value === 'number' && Number.isFinite(value) && Number(value) >= 0 ? Number(value) : -1; }
export function tokenLabel(value: number): string { return value < 0 ? '未提供' : String(Math.round(value)).replace(/\B(?=(\d{3})+(?!\d))/g, ','); }
export function costLabel(value: number): string { return value < 0 ? '未提供' : value === 0 ? '$0' : value < 0.000001 ? '<$0.000001' : '$' + value.toFixed(6); }
export interface CompactRecord { id: string; state: string; error: string; }
export function compactLabel(state: string): string {
  switch (state) { case 'submitting': return '正在提交'; case 'queued': return '已提交，等待执行'; case 'running': return '正在压缩'; case 'completed': return '压缩已完成'; case 'failed': return '压缩失败'; case 'unknown': return '结果待核对'; default: return '暂无压缩记录'; }
}
