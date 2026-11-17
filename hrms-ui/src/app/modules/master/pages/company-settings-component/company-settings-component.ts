import { Component, OnInit, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import {
  CompanySettingsService, CompanySettings, CompanySettingsUpdate
} from '../../../../core/services/company-settings.service';
import { ToastService } from '../../../../core/services/toast.service';

/** Company Settings: the employer's name, logo and statutory numbers used on payslips, EA forms and emails. */
@Component({
  selector: 'app-company-settings',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './company-settings-component.html',
  styleUrls: ['./company-settings-component.scss']
})
export class CompanySettingsComponent implements OnInit {
  loading = true;
  saving = false;
  uploading = false;
  error = '';
  isConfigured = false;
  logoUrl: string | null = null;

  form: CompanySettingsUpdate = this.empty();

  readonly maxLogoBytes = 1024 * 1024;

  constructor(
    private settings: CompanySettingsService,
    private toast: ToastService,
    private cdr: ChangeDetectorRef
  ) {}

  ngOnInit(): void {
    this.settings.get().subscribe({
      next: s => { this.apply(s); this.loading = false; this.cdr.detectChanges(); },
      error: err => {
        this.error = err?.error?.message || 'Could not load company settings.';
        this.loading = false;
        this.cdr.detectChanges();
      }
    });
  }

  /** Initials shown in the preview when no logo is uploaded. */
  get initials(): string {
    const name = this.form.displayName || this.form.legalName || '';
    return name.split(/\s+/).filter(Boolean).slice(0, 2).map(w => w[0].toUpperCase()).join('') || '?';
  }

  get colorValid(): boolean {
    return /^#[0-9A-Fa-f]{6}$/.test(this.form.brandColor);
  }

  save(): void {
    this.error = '';
    if (!this.form.legalName.trim()) { this.error = 'Enter the company legal name.'; return; }
    if (!this.colorValid) { this.error = 'Brand colour must look like #C62828.'; return; }

    this.saving = true;
    this.settings.update(this.form).subscribe({
      next: s => {
        this.apply(s);
        this.saving = false;
        this.toast.success('Company settings saved', 'Payslips, EA forms and emails now use these details.');
        this.cdr.detectChanges();
      },
      error: err => {
        this.saving = false;
        this.error = this.messageFrom(err, 'Could not save company settings.');
        this.cdr.detectChanges();
      }
    });
  }

  onLogoSelected(event: Event): void {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    input.value = '';               // allow choosing the same file again
    if (!file) return;

    if (!['image/png', 'image/jpeg'].includes(file.type)) {
      this.toast.error('Logo not uploaded', 'Choose a PNG or JPEG image.');
      return;
    }
    if (file.size > this.maxLogoBytes) {
      this.toast.error('Logo not uploaded', 'The logo must be 1 MB or smaller.');
      return;
    }

    this.uploading = true;
    this.settings.uploadLogo(file).subscribe({
      next: s => {
        this.logoUrl = this.settings.absolute(s.logoUrl);
        this.uploading = false;
        this.toast.success('Logo uploaded', 'It now appears on payslips and the login page.');
        this.cdr.detectChanges();
      },
      error: err => {
        this.uploading = false;
        this.toast.error('Logo not uploaded', this.messageFrom(err, 'Upload failed.'));
        this.cdr.detectChanges();
      }
    });
  }

  removeLogo(): void {
    this.uploading = true;
    this.settings.deleteLogo().subscribe({
      next: () => {
        this.logoUrl = null;
        this.uploading = false;
        this.toast.success('Logo removed');
        this.cdr.detectChanges();
      },
      error: err => {
        this.uploading = false;
        this.toast.error('Logo not removed', this.messageFrom(err, 'Please try again.'));
        this.cdr.detectChanges();
      }
    });
  }

  private apply(s: CompanySettings): void {
    this.form = {
      legalName: s.legalName ?? '',
      displayName: s.displayName ?? '',
      registrationNo: s.registrationNo,
      employerTaxNo: s.employerTaxNo,
      taxBranch: s.taxBranch,
      address: s.address,
      phone: s.phone,
      website: s.website,
      hrOfficerName: s.hrOfficerName,
      hrOfficerPosition: s.hrOfficerPosition,
      brandColor: s.brandColor || '#C62828'
    };
    this.isConfigured = s.isConfigured;
    this.logoUrl = this.settings.absolute(s.logoUrl);
  }

  private empty(): CompanySettingsUpdate {
    return {
      legalName: '', displayName: '', registrationNo: null, employerTaxNo: null, taxBranch: null,
      address: null, phone: null, website: null, hrOfficerName: null, hrOfficerPosition: null,
      brandColor: '#C62828'
    };
  }

  /** First validation message from an ASP.NET error response, else the fallback. */
  private messageFrom(err: any, fallback: string): string {
    const e = err?.error;
    if (e?.errors) {
      const first = Object.values(e.errors as Record<string, string[]>)[0];
      if (first?.length) return first[0];
    }
    return e?.message || fallback;
  }
}
