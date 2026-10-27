import {makeSeed, ensureToday} from './domain.js';
const KEY='pillcheck:v1';
export function loadState() {
  const saved=localStorage.getItem(KEY);
  if (!saved) return makeSeed();
  const data=JSON.parse(saved);
  if (data.version!==1 || !Array.isArray(data.medications) || !Array.isArray(data.doses) || !Array.isArray(data.audit)) throw new Error('Saved records could not be read. Export the stored data before starting over.');
  return ensureToday(data);
}
export function saveState(data) { localStorage.setItem(KEY,JSON.stringify(data)); }
export function storedData() { return localStorage.getItem(KEY) || '{}'; }
