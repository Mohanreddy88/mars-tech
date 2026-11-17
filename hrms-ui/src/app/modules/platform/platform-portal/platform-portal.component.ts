import { Component, OnInit, OnDestroy, ChangeDetectorRef, HostListener } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Subject, Subscription, debounceTime, distinctUntilChanged, switchMap, of, catchError } from 'rxjs';
import { AuthService } from '../../../core/services/auth.service';
import {
  PlatformService, PlatformTenant, CreateTenantRequest, CreateTenantResult, PlatformAuditEntry
} from '../../../core/services/platform.service';

type Tab = 'companies' | 'activity' | 'account';

interface Wizard {
  step: number;                // 0 Company, 1 Branding, 2 Admin, 3 Review
  req: CreateTenantRequest;
  slugTouched: boolean;
  slugStatus: 'idle' | 'checking' | 'ok' | 'bad';
  slugMessage: string;
  logoFile: File | null;
  logoPreview: string | null;
  creating: boolean;
  error: string;
  result: CreateTenantResult | null;
  logoWarning: string;
}

interface EditDraft {
  slug: string;
  url: string;
  displayName: string;
  legalName: string;
  registrationNo: string;
  employerTaxNo: string;
  brandColor: string;
  contactEmail: string;
  logoUrl: string | null;
  saving: boolean;
  uploading: boolean;
  error: string;
}

/** Super Admin portal: every client company, each with its own address and database. */
@Component({
  selector: 'app-platform-portal',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './platform-portal.component.html',
  styleUrl: './platform-portal.component.scss'
})
export class PlatformPortalComponent implements OnInit, OnDestroy {
  readonly colors = ['#0E7490', '#2563EB', '#65A30D', '#C2410C', '#C62828', '#BE185D', '#7C3AED', '#475569'];
  readonly steps = ['Company', 'Branding', 'Admin user', 'Review'];

  tab: Tab = 'companies';
  username = '';

  tenants: PlatformTenant[] = [];
  loading = true;
  loadError = '';
  confirmSlug: string | null = null;     // inline "Suspend?" row
  busySlug: string | null = null;

  wiz: Wizard | null = null;
  edit: EditDraft | null = null;

  audit: PlatformAuditEntry[] = [];
  auditLoading = false;

  pw = { current: '', next: '', confirm: '', saving: false, error: '', done: '' };

  toast = '';
  private toastTimer?: ReturnType<typeof setTimeout>;
  private slug$ = new Subject<string>();
  private sub?: Subscription;

  constructor(private platform: PlatformService, private auth: AuthService, private cdr: ChangeDetectorRef) {}

  ngOnInit(): void {
    this.username = this.auth.getUsername() ?? '';
    this.load();

    // Live "is this address free?" check while typing in the wizard
    this.sub = this.slug$.pipe(
      debounceTime(300),
      distinctUntilChanged(),
      switchMap(slug => slug.length < 2
        ? of({ available: false, message: 'Use at least 2 characters.', url: null })
        : this.platform.checkSlug(slug).pipe(catchError(() => of({ available: false, message: 'Could not check this address.', url: null }))))
    ).subscribe(r => {
      if (!this.wiz) return;
      this.wiz.slugStatus = r.available ? 'ok' : 'bad';
      this.wiz.slugMessage = r.available ? '' : (r.message ?? '');
      this.cdr.detectChanges();
    });
  }

  ngOnDestroy(): void {
    this.sub?.unsubscribe();
    clearTimeout(this.toastTimer);
  }

  // ── figures ──────────────────────────────────────────────
  get activeCount(): number { return this.tenants.filter(t => t.status === 'active').length; }
  get employeeTotal(): number { return this.tenants.reduce((a, t) => a + (t.employees ?? 0), 0); }

  initials(name: string | null | undefined): string {
    return (name ?? '').split(/\s+/).filter(Boolean).slice(0, 2).map(w => w[0].toUpperCase()).join('') || '?';
  }
  logo(t: { logoUrl: string | null }): string | null { return this.platform.absolute(t.logoUrl); }
  host(url: string): string { return url.replace(/^https?:\/\//, ''); }

  // ── navigation ───────────────────────────────────────────
  setTab(tab: Tab): void {
    this.tab = tab;
    this.confirmSlug = null;
    if (tab === 'activity') this.loadAudit();
    if (tab === 'companies') this.load();
  }

  logout(): void { this.auth.logout(); }

  // ── companies ────────────────────────────────────────────
  load(): void {
    this.loading = true;
    this.loadError = '';
    this.platform.list().subscribe({
      next: list => { this.tenants = list; this.loading = false; this.cdr.detectChanges(); },
      error: err => {
        this.loading = false;
        this.loadError = err?.error?.message ?? 'Could not load companies.';
        this.cdr.detectChanges();
      }
    });
  }

  askSuspend(t: PlatformTenant): void { this.confirmSlug = t.slug; }
  cancelConfirm(): void { this.confirmSlug = null; }

  suspend(t: PlatformTenant): void { this.setStatus(t, 'suspend'); }
  activate(t: PlatformTenant): void { this.setStatus(t, 'activate'); }

  private setStatus(t: PlatformTenant, action: 'suspend' | 'activate'): void {
    this.busySlug = t.slug;
    const call = action === 'suspend' ? this.platform.suspend(t.slug) : this.platform.activate(t.slug);
    call.subscribe({
      next: updated => {
        this.replace(updated);
        this.busySlug = null;
        this.confirmSlug = null;
        this.showToast(action === 'suspend'
          ? `${t.name} suspended. Their users can't log in until you activate them.`
          : `${t.name} is active again.`);
      },
      error: err => {
        this.busySlug = null;
        this.showToast(err?.error?.message ?? 'That did not work. Please try again.');
      }
    });
  }

  private replace(updated: PlatformTenant): void {
    this.tenants = this.tenants.map(x => x.slug === updated.slug ? updated : x);
    this.cdr.detectChanges();
  }

  // ── new company wizard ───────────────────────────────────
  openWizard(): void {
    this.wiz = {
      step: 0,
      req: {
        slug: '', legalName: '', displayName: '', registrationNo: null, employerTaxNo: null,
        brandColor: this.colors[0], adminName: '', adminEmail: '', adminUsername: 'admin', sendWelcomeEmail: true
      },
      slugTouched: false, slugStatus: 'idle', slugMessage: '',
      logoFile: null, logoPreview: null,
      creating: false, error: '', result: null, logoWarning: ''
    };
  }

  closeWizard(): void {
    if (this.wiz?.creating) return;
    const created = !!this.wiz?.result;
    if (this.wiz?.logoPreview) URL.revokeObjectURL(this.wiz.logoPreview);
    this.wiz = null;
    if (created) this.load();
  }

  /** Suggest the address and short name from the legal name until the user edits them. */
  onLegalNameChange(): void {
    const w = this.wiz!;
    const short = this.shortName(w.req.legalName);
    if (!w.slugTouched) {
      w.req.slug = short.toLowerCase().split(/\s+/)[0]?.replace(/[^a-z0-9-]/g, '').slice(0, 30) ?? '';
      this.checkSlug();
    }
    w.req.displayName = short;
  }

  onSlugInput(): void {
    const w = this.wiz!;
    w.slugTouched = true;
    w.req.slug = w.req.slug.toLowerCase().replace(/[^a-z0-9-]/g, '').slice(0, 30);
    this.checkSlug();
  }

  private checkSlug(): void {
    const w = this.wiz!;
    w.slugStatus = w.req.slug ? 'checking' : 'idle';
    w.slugMessage = '';
    this.slug$.next(w.req.slug);
  }

  slugHost(slug: string): string {
    const base = window.location.hostname.replace(/^admin\./, '');
    return `${slug || 'yourcompany'}.${base}`;
  }

  pickColor(c: string): void {
    if (this.wiz) this.wiz.req.brandColor = c;
    if (this.edit) this.edit.brandColor = c;
  }

  validColor(c: string): boolean { return /^#[0-9A-Fa-f]{6}$/.test(c); }

  onWizardLogo(event: Event): void {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    input.value = '';
    if (!file || !this.wiz) return;
    const problem = this.checkLogoFile(file);
    if (problem) { this.showToast(problem); return; }
    if (this.wiz.logoPreview) URL.revokeObjectURL(this.wiz.logoPreview);
    this.wiz.logoFile = file;
    this.wiz.logoPreview = URL.createObjectURL(file);
  }

  clearWizardLogo(): void {
    if (!this.wiz) return;
    if (this.wiz.logoPreview) URL.revokeObjectURL(this.wiz.logoPreview);
    this.wiz.logoFile = null;
    this.wiz.logoPreview = null;
  }

  next(): void {
    const w = this.wiz!;
    w.error = '';
    if (w.step === 0) {
      if (w.req.legalName.trim().length < 2) { w.error = "Enter the company's legal name."; return; }
      if (w.slugStatus !== 'ok') { w.error = w.slugMessage || 'Choose a web address that is free.'; return; }
      if (!w.req.displayName.trim()) w.req.displayName = this.shortName(w.req.legalName);
    }
    if (w.step === 1 && !this.validColor(w.req.brandColor)) { w.error = 'Brand colour must look like #0E7490.'; return; }
    if (w.step === 2) {
      if (!/^\S+@\S+\.\S+$/.test(w.req.adminEmail.trim())) { w.error = "Enter the admin's email address."; return; }
      if (!/^[A-Za-z0-9._-]{3,50}$/.test(w.req.adminUsername.trim())) {
        w.error = 'Username: at least 3 letters, numbers, dots, dashes or underscores.'; return;
      }
    }
    if (w.step < 3) { w.step++; return; }
    this.create();
  }

  back(): void { if (this.wiz && this.wiz.step > 0) { this.wiz.error = ''; this.wiz.step--; } }

  private create(): void {
    const w = this.wiz!;
    w.creating = true;
    const req: CreateTenantRequest = {
      ...w.req,
      legalName: w.req.legalName.trim(),
      displayName: w.req.displayName.trim(),
      registrationNo: w.req.registrationNo?.trim() || null,
      employerTaxNo: w.req.employerTaxNo?.trim() || null,
      adminName: w.req.adminName.trim(),
      adminEmail: w.req.adminEmail.trim(),
      adminUsername: w.req.adminUsername.trim()
    };
    this.platform.create(req).subscribe({
      next: result => {
        if (!w.logoFile) { this.finishCreate(w, result); return; }
        this.platform.uploadLogo(result.tenant.slug, w.logoFile).subscribe({
          next: t => this.finishCreate(w, { ...result, tenant: t }),
          error: err => {
            w.logoWarning = `The company was created, but the logo was not uploaded (${err?.error?.message ?? 'error'}). Add it with Edit.`;
            this.finishCreate(w, result);
          }
        });
      },
      error: err => {
        w.creating = false;
        w.error = this.messageFrom(err, 'The company could not be created.');
        // Address problems belong to step 1
        if (err?.error?.field === 'slug') { w.step = 0; w.slugStatus = 'bad'; w.slugMessage = w.error; }
        this.cdr.detectChanges();
      }
    });
  }

  private finishCreate(w: Wizard, result: CreateTenantResult): void {
    w.creating = false;
    w.result = result;
    this.cdr.detectChanges();
  }

  copy(text: string): void {
    navigator.clipboard?.writeText(text).then(
      () => this.showToast('Copied'),
      () => this.showToast('Select the text and copy it')
    );
  }

  // ── edit drawer ──────────────────────────────────────────
  openEdit(t: PlatformTenant): void {
    this.confirmSlug = null;
    this.edit = {
      slug: t.slug, url: t.url,
      displayName: t.name, legalName: t.legalName ?? '',
      registrationNo: t.registrationNo ?? '', employerTaxNo: t.employerTaxNo ?? '',
      brandColor: t.brandColor || this.colors[0], contactEmail: t.contactEmail ?? '',
      logoUrl: t.logoUrl, saving: false, uploading: false, error: ''
    };
  }

  closeEdit(): void { if (!this.edit?.saving) this.edit = null; }

  saveEdit(): void {
    const e = this.edit!;
    e.error = '';
    if (e.displayName.trim().length < 2) { e.error = 'Enter a display name.'; return; }
    if (e.legalName.trim().length < 2) { e.error = 'Enter the legal name.'; return; }
    if (!this.validColor(e.brandColor)) { e.error = 'Brand colour must look like #0E7490.'; return; }
    e.saving = true;
    this.platform.update(e.slug, {
      displayName: e.displayName.trim(), legalName: e.legalName.trim(),
      registrationNo: e.registrationNo.trim() || null, employerTaxNo: e.employerTaxNo.trim() || null,
      brandColor: e.brandColor, contactEmail: e.contactEmail.trim() || null
    }).subscribe({
      next: t => {
        this.replace(t);
        this.edit = null;
        this.showToast('Saved. Payslips and emails use the new details.');
      },
      error: err => { e.saving = false; e.error = this.messageFrom(err, 'Could not save.'); this.cdr.detectChanges(); }
    });
  }

  onEditLogo(event: Event): void {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    input.value = '';
    const e = this.edit;
    if (!file || !e) return;
    const problem = this.checkLogoFile(file);
    if (problem) { this.showToast(problem); return; }
    e.uploading = true;
    this.platform.uploadLogo(e.slug, file).subscribe({
      next: t => { e.uploading = false; e.logoUrl = t.logoUrl; this.replace(t); this.showToast('Logo uploaded'); },
      error: err => { e.uploading = false; this.showToast(this.messageFrom(err, 'Logo not uploaded.')); }
    });
  }

  removeLogo(): void {
    const e = this.edit!;
    e.uploading = true;
    this.platform.deleteLogo(e.slug).subscribe({
      next: t => { e.uploading = false; e.logoUrl = null; this.replace(t); this.showToast('Logo removed'); },
      error: err => { e.uploading = false; this.showToast(this.messageFrom(err, 'Logo not removed.')); }
    });
  }

  // ── activity ─────────────────────────────────────────────
  loadAudit(): void {
    this.auditLoading = true;
    this.platform.audit().subscribe({
      next: a => { this.audit = a; this.auditLoading = false; this.cdr.detectChanges(); },
      error: () => { this.auditLoading = false; this.cdr.detectChanges(); }
    });
  }

  // ── account ──────────────────────────────────────────────
  changePassword(): void {
    const p = this.pw;
    p.error = ''; p.done = '';
    if (p.next.length < 10) { p.error = 'Use at least 10 characters for the new password.'; return; }
    if (p.next !== p.confirm) { p.error = 'The two new passwords do not match.'; return; }
    p.saving = true;
    this.platform.changePassword(p.current, p.next).subscribe({
      next: () => {
        this.pw = { current: '', next: '', confirm: '', saving: false, error: '', done: 'Password changed.' };
        this.cdr.detectChanges();
      },
      error: err => { p.saving = false; p.error = this.messageFrom(err, 'Could not change the password.'); this.cdr.detectChanges(); }
    });
  }

  // ── helpers ──────────────────────────────────────────────
  @HostListener('document:keydown.escape')
  onEscape(): void {
    if (this.edit) this.closeEdit();
    else if (this.wiz && !this.wiz.creating) this.closeWizard();
  }

  private shortName(legal: string): string {
    return legal.trim().replace(/\s+(Sdn\.?\s*Bhd\.?|Berhad|Bhd\.?|Pte\.?\s*Ltd\.?|Ltd\.?|PLT)$/i, '').trim();
  }

  private checkLogoFile(file: File): string | null {
    if (!['image/png', 'image/jpeg'].includes(file.type)) return 'Choose a PNG or JPEG image.';
    if (file.size > 1024 * 1024) return 'The logo must be 1 MB or smaller.';
    return null;
  }

  private showToast(msg: string): void {
    this.toast = msg;
    this.cdr.detectChanges();
    clearTimeout(this.toastTimer);
    this.toastTimer = setTimeout(() => { this.toast = ''; this.cdr.detectChanges(); }, 3000);
  }

  private messageFrom(err: any, fallback: string): string {
    const e = err?.error;
    if (e?.errors) {
      const first = Object.values(e.errors as Record<string, string[]>)[0];
      if (first?.length) return first[0];
    }
    return e?.message || fallback;
  }
}
