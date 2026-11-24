import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable, forkJoin, map, of, switchMap, catchError } from 'rxjs';
import { environment } from '../../../environments/environment';

/** Colour themes of a banner (same keys as the API and the app). */
export const BANNER_THEMES = ['purple', 'blue', 'green', 'orange', 'pink', 'teal'] as const;
export type BannerTheme = typeof BANNER_THEMES[number];

/** Parent pages a banner button may open, with their label in the admin form. */
export const BANNER_PAGES: { key: string; label: string; url: string }[] = [
  { key: 'fees', label: 'Fees', url: '/parent/fees' },
  { key: 'messages', label: 'Messages', url: '/parent/messages' },
  { key: 'new-message', label: 'Message the school (new message)', url: '/parent/messages?new=1' },
  { key: 'announcements', label: 'Announcements', url: '/parent/announcements' },
  { key: 'account', label: 'My account', url: '/parent/account' }
];

/** A banner as the parent sees it. <c>imageUrl</c> is a local object URL (or null). */
export interface BannerView {
  id: number;
  title: string;
  text: string | null;
  buttonText: string | null;
  link: string | null;
  theme: string;
  imageUrl: string | null;
}

/** A banner in School → Banners (admins). */
export interface Banner {
  id: number;
  title: string;
  text: string | null;
  buttonText: string | null;
  link: string | null;
  theme: string;
  classId: number | null;
  className: string | null;
  startsOn: string | null;
  endsOn: string | null;
  isActive: boolean;
  sortOrder: number;
  createdByName: string;
  updatedAt: string;
  imageVersion: number | null;
  status: 'Live' | 'Scheduled' | 'Ended' | 'Off';
}

export interface BannerSave {
  title: string;
  text: string;
  buttonText: string;
  link: string;
  theme: string;
  classId: number | null;
  startsOn: string;
  endsOn: string;
  isActive: boolean;
  image: File | null;
  removeImage: boolean;
}

/** Parent home banners (School → Banners). Pictures need the login token, so they're fetched as blobs. */
@Injectable({ providedIn: 'root' })
export class BannersService {
  private http = inject(HttpClient);
  private api = `${environment.apiUrl}/school/banners`;
  /** "id:version" → object URL, kept for the session (a new picture has a new version). */
  private images = new Map<string, string>();

  /** The live banners for the signed-in parent, pictures loaded. */
  current(): Observable<BannerView[]> {
    return this.http.get<(Omit<BannerView, 'imageUrl'> & { imageVersion: number | null })[]>(`${this.api}/current`).pipe(
      switchMap(list => list.length === 0 ? of([]) : forkJoin(list.map(b => this.image(b.id, b.imageVersion).pipe(
        map(imageUrl => ({ id: b.id, title: b.title, text: b.text, buttonText: b.buttonText, link: b.link, theme: b.theme, imageUrl }))
      )))));
  }

  /** The picture's object URL (null when there's none or it can't be loaded). */
  image(id: number, version: number | null): Observable<string | null> {
    if (version == null) return of(null);
    const key = `${id}:${version}`;
    const cached = this.images.get(key);
    if (cached) return of(cached);
    return this.http.get(`${this.api}/${id}/image`, { params: { v: version }, responseType: 'blob' }).pipe(
      map(b => { const url = URL.createObjectURL(b); this.images.set(key, url); return url; }),
      catchError(() => of(null)));
  }

  getAll(): Observable<Banner[]> { return this.http.get<Banner[]>(this.api); }

  save(id: number | null, b: BannerSave): Observable<unknown> {
    const f = new FormData();
    f.append('title', b.title);
    f.append('text', b.text);
    f.append('buttonText', b.buttonText);
    f.append('link', b.link);
    f.append('theme', b.theme);
    if (b.classId != null) f.append('classId', String(b.classId));
    if (b.startsOn) f.append('startsOn', b.startsOn);
    if (b.endsOn) f.append('endsOn', b.endsOn);
    f.append('isActive', String(b.isActive));
    if (b.image) f.append('image', b.image, b.image.name);
    f.append('removeImage', String(b.removeImage));
    return id == null ? this.http.post(this.api, f) : this.http.put(`${this.api}/${id}`, f);
  }

  move(id: number, up: boolean): Observable<unknown> {
    return this.http.post(`${this.api}/${id}/move`, null, { params: { up } });
  }

  delete(id: number): Observable<unknown> { return this.http.delete(`${this.api}/${id}`); }

  /** Adds the general school cards (a day of learning, play areas, meals, teachers) as banners to edit. */
  addSamples(): Observable<{ added: number }> { return this.http.post<{ added: number }>(`${this.api}/samples`, null); }
}

/** Where a banner button goes on this website: a route, an outside address, or nothing. */
export function bannerTarget(link: string | null): { route?: string; href?: string } | null {
  if (!link) return null;
  if (link.startsWith('https://')) return { href: link };
  const page = BANNER_PAGES.find(p => p.key === link);
  return page ? { route: page.url } : null;
}
