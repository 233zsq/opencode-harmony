// OpenCode v2.0.29 leaves undefined optional fields in tool permission metadata.
// Normalize that shared object before it enters the pending queue / strict JSON codec.
export function normalizeMetadata(metadata) {
  const ancestors = new WeakSet();
  function visit(value) {
    if (value === null || typeof value === 'string' || typeof value === 'boolean') return;
    if (typeof value === 'number' && Number.isFinite(value)) return;
    if (!value || typeof value !== 'object') throw new TypeError('Permission metadata must be JSON');
    if (ancestors.has(value)) throw new TypeError('Permission metadata must be acyclic JSON');
    if (!Array.isArray(value) && Object.getPrototypeOf(value) !== Object.prototype && Object.getPrototypeOf(value) !== null) {
      throw new TypeError('Permission metadata must contain plain JSON objects');
    }
    ancestors.add(value);
    if (Array.isArray(value)) {
      for (let index = 0; index < value.length; index++) {
        if (value[index] === undefined) value[index] = null;
        else visit(value[index]);
      }
    } else {
      for (const key of Object.keys(value)) {
        if (value[key] === undefined) delete value[key];
        else visit(value[key]);
      }
    }
    ancestors.delete(value);
  }
  if (metadata !== undefined) visit(metadata);
}
export default {
  id: 'harmony.permission-json',
  async setup(context) {
    await context.permission.hook('evaluate', event => normalizeMetadata(event.metadata));
  }
};
