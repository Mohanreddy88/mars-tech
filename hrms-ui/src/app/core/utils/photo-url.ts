import { environment } from '../../../environments/environment';

/**
 * Browser address of an uploaded profile photo.
 * The API stores "/uploads/<company>/profiles/<file>" (older records: "/uploads/profiles/<file>" or just "<file>").
 *   production: nginx serves uploads under /api/uploads/…   (same site)
 *   local dev : the API serves them at <api host>/uploads/…
 */
export function photoUrl(value: string | null | undefined): string | null {
  if (!value) return null;
  if (/^(https?:|data:|blob:)/.test(value)) return value;          // already a full address / local preview
  const path = value.startsWith('/') ? value : `/uploads/profiles/${value}`;
  const api = environment.apiUrl;                                   // "/api" or "http://localhost:64559/api"
  return api.startsWith('http') ? api.replace(/\/api\/?$/, '') + path : '/api' + path;
}
