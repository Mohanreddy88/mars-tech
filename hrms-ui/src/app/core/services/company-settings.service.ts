import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { BehaviorSubject, Observable, tap } from 'rxjs';
import { environment } from '../../../environments/environment';

/** Branding shown before login (login page) and in the sidebar. */
export interface CompanyBranding {
  displayName: string;
  legalName: string | null;
  brandColor: string;
  logoUrl: string | null;
  isConfigured: boolean;
}

/** All fields, for the Company Settings page (admin only). */
export interface CompanySettings {
  legalName: string;
  displayName: string;
  registrationNo: string | null;
  employerTaxNo: string | null;
  taxBranch: string | null;
  address: string | null;
  phone: string | null;
  website: string | null;
  hrOfficerName: string | null;
  hrOfficerPosition: string | null;
  brandColor: string;
  logoUrl: string | null;
  isConfigured: boolean;
  updatedAt: string;
}

export type CompanySettingsUpdate = Omit<CompanySettings, 'logoUrl' | 'isConfigured' | 'updatedAt'>;

@Injectable({ providedIn: 'root' })
export class CompanySettingsService {
  private apiUrl = `${environment.apiUrl}/company-settings`;

  /** Latest branding; components subscribe so a save updates the sidebar at once. */
  private brandingSubject = new BehaviorSubject<CompanyBranding | null>(null);
  readonly branding$ = this.brandingSubject.asObservable();
  private loaded = false;

  constructor(private http: HttpClient) {}

  /** Load branding once (call again with force=true after a change). */
  loadBranding(force = false): void {
    if (this.loaded && !force) return;
    this.loaded = true;
    this.http.get<CompanyBranding>(`${this.apiUrl}/public`).subscribe({
      next: b => this.brandingSubject.next({ ...b, logoUrl: this.absolute(b.logoUrl) }),
      error: () => { this.loaded = false; }
    });
  }

  get(): Observable<CompanySettings> {
    return this.http.get<CompanySettings>(this.apiUrl);
  }

  update(settings: CompanySettingsUpdate): Observable<CompanySettings> {
    return this.http.put<CompanySettings>(this.apiUrl, settings).pipe(tap(() => this.loadBranding(true)));
  }

  uploadLogo(file: File): Observable<CompanySettings> {
    const form = new FormData();
    form.append('file', file);
    return this.http.post<CompanySettings>(`${this.apiUrl}/logo`, form).pipe(tap(() => this.loadBranding(true)));
  }

  deleteLogo(): Observable<CompanySettings> {
    return this.http.delete<CompanySettings>(`${this.apiUrl}/logo`).pipe(tap(() => this.loadBranding(true)));
  }

  /**
   * The API returns "/api/company-settings/logo?v=…". In production the UI and API share
   * an origin; in local dev the API runs elsewhere, so prefix the API host.
   */
  absolute(url: string | null): string | null {
    if (!url) return null;
    const apiBase = environment.apiUrl.replace(/\/api\/?$/, '');
    return apiBase.startsWith('http') ? apiBase + url : url;
  }
}
