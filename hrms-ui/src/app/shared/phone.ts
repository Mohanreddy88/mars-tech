/**
 * Phone numbers: stored as +<country><number> (e.g. +60123456789), shown in the local format
 * (012-345 6789). Malaysia is the default; the rules match the API's PhoneNumbers class.
 */

import { DIAL_CODES } from '../core/data/countries';

export interface PhoneCountry { code: string; label: string; }

/** Shown first, with flags: Malaysia, neighbours, and where staff and parents most often come from. */
const COMMON: { code: string; name: string; flag: string }[] = [
  { code: '60',  name: 'Malaysia',       flag: '🇲🇾' },
  { code: '65',  name: 'Singapore',      flag: '🇸🇬' },
  { code: '62',  name: 'Indonesia',      flag: '🇮🇩' },
  { code: '880', name: 'Bangladesh',     flag: '🇧🇩' },
  { code: '977', name: 'Nepal',          flag: '🇳🇵' },
  { code: '91',  name: 'India',          flag: '🇮🇳' },
  { code: '95',  name: 'Myanmar',        flag: '🇲🇲' },
  { code: '63',  name: 'Philippines',    flag: '🇵🇭' },
  { code: '92',  name: 'Pakistan',       flag: '🇵🇰' },
  { code: '84',  name: 'Vietnam',        flag: '🇻🇳' },
  { code: '66',  name: 'Thailand',       flag: '🇹🇭' },
  { code: '86',  name: 'China',          flag: '🇨🇳' },
  { code: '94',  name: 'Sri Lanka',      flag: '🇱🇰' },
  { code: '855', name: 'Cambodia',       flag: '🇰🇭' },
  { code: '673', name: 'Brunei',         flag: '🇧🇳' },
  { code: '852', name: 'Hong Kong',      flag: '🇭🇰' },
  { code: '81',  name: 'Japan',          flag: '🇯🇵' },
  { code: '82',  name: 'South Korea',    flag: '🇰🇷' },
  { code: '971', name: 'UAE',            flag: '🇦🇪' },
  { code: '966', name: 'Saudi Arabia',   flag: '🇸🇦' },
  { code: '61',  name: 'Australia',      flag: '🇦🇺' },
  { code: '44',  name: 'United Kingdom', flag: '🇬🇧' },
  { code: '1',   name: 'USA / Canada',   flag: '🇺🇸' },
];

/** Every country code: the common ones first, then the rest of the world (A–Z). */
export const PHONE_COUNTRIES: PhoneCountry[] = [
  ...COMMON.map(c => ({ code: c.code, label: `${c.flag} +${c.code}` })),
  ...DIAL_CODES.map(d => d.dial.substring(1)).filter(code => !COMMON.some(c => c.code === code))
    .map(code => ({ code, label: `+${code} ${DIAL_CODES.find(d => d.dial === '+' + code)!.label.substring(code.length + 2)}` })),
];

/** Name for the tooltip, e.g. "Malaysia". */
export const phoneCountryName = (code: string) =>
  COMMON.find(c => c.code === code)?.name ?? DIAL_CODES.find(d => d.dial === '+' + code)?.label.substring(code.length + 2) ?? '';

export const MALAYSIA = '60';

const digitsOf = (s: string) => s.replace(/\D/g, '');

/** Malaysian number without the leading 0 — same rule as the API. */
export function isMalaysian(n: string): boolean {
  if (!/^\d+$/.test(n)) return false;
  switch (n[0]) {
    case '1': return n.length === (n.startsWith('11') || n.startsWith('15') ? 10 : 9);
    case '3': return n.length === 9;
    default:  return n[0] >= '4' && n[0] <= '9' && n.length === 8;
  }
}

/** Splits a stored value into country code and national digits (no trunk 0). Legacy free text → Malaysia. */
export function splitPhone(value: string | null | undefined): { country: string; national: string } {
  const v = (value ?? '').trim();
  if (!v) return { country: MALAYSIA, national: '' };
  let d = digitsOf(v);
  if (v.startsWith('+') || v.startsWith('00')) {
    if (v.startsWith('00')) d = d.substring(2);
    // Longest matching code first (673 before 67…)
    const c = [...PHONE_COUNTRIES].sort((a, b) => b.code.length - a.code.length).find(x => d.startsWith(x.code));
    if (c) return { country: c.code, national: c.code === MALAYSIA ? stripTrunk(d.substring(c.code.length)) : d.substring(c.code.length) };
    return { country: '', national: d };
  }
  return { country: MALAYSIA, national: stripTrunk(d) };
}

const stripTrunk = (n: string) => n.startsWith('0') ? n.substring(1) : n;

/**
 * Employees keep the code and the number apart ("+60", "123456789"): joins them for the phone box.
 * An old number stored with its leading 0 ("0123456789") works too.
 */
export function joinPhone(code: string | null | undefined, number: string | null | undefined): string | null {
  const n = digitsOf(number ?? '');
  if (!n) return null;
  const c = digitsOf(code ?? '') || MALAYSIA;
  return `+${c}${c === MALAYSIA ? stripTrunk(n) : n}`;
}

/** The other way: "+60123456789" → { code: "+60", number: "123456789" }. */
export function phoneParts(value: string | null | undefined): { code: string; number: string } {
  const { country, national } = splitPhone(value);
  return { code: '+' + (country || MALAYSIA), number: national };
}

/** A problem with a stored value (null when fine or empty). */
export function phoneValueProblem(value: string | null | undefined): string | null {
  const { country, national } = splitPhone(value);
  return phoneProblem(country || MALAYSIA, national);
}

/** Local display of the national digits, also while typing: 012-345 6789, 011-2345 6789, 03-1234 5678, 088-123 456. */
export function formatNational(country: string, national: string): string {
  if (!national) return '';
  if (country !== MALAYSIA) return national.replace(/(\d{4})(?=\d)/g, '$1 ');
  const d = '0' + national;
  let parts: number[];
  if (national[0] === '1') parts = national.startsWith('11') || national.startsWith('15') ? [3, 4, 4] : [3, 3, 4];
  else if (national[0] === '3') parts = [2, 4, 4];
  else if (national[0] === '8') parts = [3, 3, 3];
  else parts = [2, 3, 4];
  const [a, b] = parts;
  let out = d.substring(0, a);
  if (d.length > a) out += '-' + d.substring(a, a + b);
  if (d.length > a + b) out += ' ' + d.substring(a + b);
  return out;
}

/** Display of a stored number: Malaysian ones locally (012-345 6789), others with their code (+65 8123 4567). */
export function formatPhone(value: string | null | undefined): string {
  if (!value) return '';
  const { country, national } = splitPhone(value);
  if (!country) return value;
  return country === MALAYSIA ? formatNational(country, national) : `+${country} ${formatNational(country, national)}`;
}

/** Problem with a typed number, or null when fine (empty is fine). */
export function phoneProblem(country: string, national: string): string | null {
  if (!national) return null;
  if (country === MALAYSIA) return isMalaysian(national) ? null : 'Malaysian numbers look like 012-345 6789 or 03-1234 5678.';
  const total = country.length + national.length;
  return total >= 8 && total <= 15 ? null : 'This number looks too short or too long.';
}
