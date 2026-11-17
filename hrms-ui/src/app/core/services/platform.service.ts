import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';
import { environment } from '../../../environments/environment';

/** True on the Super Admin portal host (admin.marshrms.com, admin.uat.marshrms.com, admin.localhost). */
export function isPlatformHost(): boolean {
  return typeof window !== 'undefined' && window.location.hostname.split('.')[0] === 'admin';
}

/** A client company as listed in the portal. */
export interface PlatformTenant {
  slug: string;
  name: string;
  status: 'active' | 'suspended' | 'provisioning';
  databaseName: string;
  contactEmail: string | null;
  createdAt: string;
  suspendedAt: string | null;
  url: string;
  isRoot: boolean;
  legalName: string | null;
  registrationNo: string | null;
  employerTaxNo: string | null;
  brandColor: string;
  logoUrl: string | null;
  employees: number | null;
  users: number | null;
  error: string | null;
}

export interface CreateTenantRequest {
  slug: string;
  legalName: string;
  displayName: string;
  registrationNo: string | null;
  employerTaxNo: string | null;
  brandColor: string;
  adminName: string;
  adminEmail: string;
  adminUsername: string;
  sendWelcomeEmail: boolean;
}

export interface CreateTenantResult {
  tenant: PlatformTenant;
  adminUsername: string;
  temporaryPassword: string;
  emailQueued: boolean;
}

export interface UpdateTenantRequest {
  displayName: string;
  legalName: string;
  registrationNo: string | null;
  employerTaxNo: string | null;
  brandColor: string;
  contactEmail: string | null;
}

export interface PlatformAuditEntry {
  at: string;
  actor: string;
  action: string;
  tenantSlug: string | null;
  details: string | null;
}

@Injectable({ providedIn: 'root' })
export class PlatformService {
  private api = `${environment.apiUrl}/platform`;

  constructor(private http: HttpClient) {}

  list(): Observable<PlatformTenant[]> {
    return this.http.get<PlatformTenant[]>(`${this.api}/tenants`);
  }

  checkSlug(slug: string): Observable<{ available: boolean; message: string | null; url: string | null }> {
    return this.http.get<{ available: boolean; message: string | null; url: string | null }>(
      `${this.api}/check-slug`, { params: { slug } });
  }

  create(req: CreateTenantRequest): Observable<CreateTenantResult> {
    return this.http.post<CreateTenantResult>(`${this.api}/tenants`, req);
  }

  update(slug: string, req: UpdateTenantRequest): Observable<PlatformTenant> {
    return this.http.put<PlatformTenant>(`${this.api}/tenants/${slug}`, req);
  }

  suspend(slug: string): Observable<PlatformTenant> {
    return this.http.post<PlatformTenant>(`${this.api}/tenants/${slug}/suspend`, {});
  }

  activate(slug: string): Observable<PlatformTenant> {
    return this.http.post<PlatformTenant>(`${this.api}/tenants/${slug}/activate`, {});
  }

  uploadLogo(slug: string, file: File): Observable<PlatformTenant> {
    const form = new FormData();
    form.append('file', file);
    return this.http.post<PlatformTenant>(`${this.api}/tenants/${slug}/logo`, form);
  }

  deleteLogo(slug: string): Observable<PlatformTenant> {
    return this.http.delete<PlatformTenant>(`${this.api}/tenants/${slug}/logo`);
  }

  audit(): Observable<PlatformAuditEntry[]> {
    return this.http.get<PlatformAuditEntry[]>(`${this.api}/audit`);
  }

  changePassword(currentPassword: string, newPassword: string): Observable<{ message: string }> {
    return this.http.post<{ message: string }>(`${this.api}/auth/change-password`, { currentPassword, newPassword });
  }

  /** Logo URLs are API-relative; in local dev the API runs on another origin. */
  absolute(url: string | null): string | null {
    if (!url) return null;
    const apiBase = environment.apiUrl.replace(/\/api\/?$/, '');
    return apiBase.startsWith('http') ? apiBase + url : url;
  }
}
