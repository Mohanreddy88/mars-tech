import { Component, Input, OnInit, ChangeDetectorRef, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router, RouterModule } from '@angular/router';
import { SchoolService, ParentRecord, ParentSave, Student, RELATIONSHIPS } from '../../../../core/services/school.service';
import { ToastService } from '../../../../core/services/toast.service';
import { ConfirmModalComponent } from '../../../../shared/components/confirm-modal/confirm-modal.component';
import { PhoneInputComponent } from '../../../../shared/components/phone-input/phone-input.component';
import { formatPhone, splitPhone, phoneProblem } from '../../../../shared/phone';
import { SchoolAvatarComponent } from '../../../../shared/components/school-avatar/school-avatar.component';
import { PhotoPickerComponent } from '../../../../shared/components/school-avatar/photo-picker.component';

const phoneProblemOf = (v: string) => { const p = splitPhone(v); return phoneProblem(p.country, p.national); };

/**
 * School → Parents (admin). Each parent is linked to their children and can get a login:
 * the parent receives a "Set my password" email and signs in to the parent portal.
 */
@Component({
  selector: 'app-school-parents',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterModule, ConfirmModalComponent, PhoneInputComponent, SchoolAvatarComponent, PhotoPickerComponent],
  templateUrl: './school-parents.component.html',
  styleUrls: ['../../school-shared.scss']
})
export class SchoolParentsComponent implements OnInit {
  /** Shown as a tab inside School → Registrations (no page title). */
  @Input() embedded = false;

  private school = inject(SchoolService);
  private toast = inject(ToastService);
  private cdr = inject(ChangeDetectorRef);
  private router = inject(Router);

  readonly relationships = RELATIONSHIPS;
  readonly phone = formatPhone;

  parents: ParentRecord[] = [];
  students: Student[] = [];
  search = '';
  loading = true;

  showModal = false;
  editing: ParentRecord | null = null;
  saving = false;
  modalError = '';
  form: ParentSave = this.blank();

  confirmDelete: ParentRecord | null = null;
  inviting: number | null = null;

  get filtered(): ParentRecord[] {
    const q = this.search.trim().toLowerCase();
    if (!q) return this.parents;
    return this.parents.filter(p =>
      p.fullName.toLowerCase().includes(q) || (p.email ?? '').toLowerCase().includes(q)
      || (p.phone ?? '').includes(q) || p.children.some(c => c.fullName.toLowerCase().includes(q)));
  }

  /** "Mohan (Father)" — the child's other parents, so a wrong link stands out. */
  otherNames(c: ParentRecord['children'][number]): string {
    return (c.otherParents ?? []).map(o => `${o.fullName} (${o.relationship})`).join(', ');
  }

  withText(c: ParentRecord['children'][number]): string {
    return c.otherParents?.length ? `with ${this.otherNames(c)}` : 'no other parent';
  }

  /** After adding a mother or father: "Set up the family now?" (opens Families with them chosen). */
  familyPrompt: { id: number; name: string; relationship: string } | null = null;

  get familyPromptText(): string {
    const p = this.familyPrompt;
    if (!p) return '';
    const other = p.relationship === 'Mother' ? 'father' : 'mother';
    return `Choose the ${other} of ${p.name}'s children (or tick "No ${other} on record") and add the children.`;
  }

  setUpFamily(): void {
    const p = this.familyPrompt;
    this.familyPrompt = null;
    if (!p) return;
    this.router.navigate(['/school/registrations/families'], {
      queryParams: { add: 1, [p.relationship === 'Mother' ? 'motherId' : 'fatherId']: p.id }
    });
  }

  /** Parents without a login yet, for the "invite all" hint. */
  get withoutLogin(): number { return this.parents.filter(p => p.isActive && !p.hasLogin).length; }

  ngOnInit(): void {
    this.load();
    this.reloadStudents();
  }

  /** Children with their linked parents (for "linked to …" in the form). */
  reloadStudents(): void {
    this.school.getStudents(null, true).subscribe({ next: s => { this.students = s; this.cdr.markForCheck(); }, error: () => {} });
  }

  load(): void {
    this.loading = true;
    this.school.getParents().subscribe({
      next: p => { this.parents = p; this.loading = false; this.cdr.markForCheck(); },
      error: err => {
        this.loading = false;
        this.toast.error('Load Failed', err?.error?.message ?? 'Could not load parents.');
        this.cdr.markForCheck();
      }
    });
  }

  blank(): ParentSave {
    return { fullName: '', email: null, phone: null, relationship: 'Mother', isActive: true, studentIds: null, createLogin: true };
  }

  openCreate(): void {
    this.editing = null;
    this.form = this.blank();
    this.modalError = '';
    this.showModal = true;
  }

  /** New photo saved from the edit form: show it in the list straight away. */
  photoChanged(id: number, version: string | null): void {
    const p = this.parents.find(x => x.id === id);
    if (p) p.photoUpdatedAt = version;
    if (this.editing?.id === id) this.editing.photoUpdatedAt = version;
    this.cdr.markForCheck();
  }

  openEdit(p: ParentRecord): void {
    this.editing = p;
    this.form = {
      fullName: p.fullName, email: p.email, phone: p.phone, relationship: p.relationship, isActive: p.isActive,
      studentIds: null, createLogin: false, password: ''
    };
    this.modalError = '';
    this.showModal = true;
  }



  save(): void {
    if (!this.form.fullName.trim()) { this.modalError = "Enter the parent's name."; return; }
    if (this.form.phone && phoneProblemOf(this.form.phone)) { this.modalError = 'Check the phone number: ' + phoneProblemOf(this.form.phone); return; }
    if (this.form.createLogin && !this.form.email?.trim()) { this.modalError = 'An email address is needed for the login.'; return; }
    if (this.form.password && this.form.password.length < 8) { this.modalError = 'The password must be at least 8 characters.'; return; }
    this.saving = true;
    const body: ParentSave = {
      ...this.form,
      fullName: this.form.fullName.trim(),
      email: this.form.email?.trim() || null,
      phone: this.form.phone?.trim() || null,
      password: this.form.password || null
    };
    const req = this.editing ? this.school.updateParent(this.editing.id, body) : this.school.createParent(body);
    req.subscribe({
      next: r => {
        this.saving = false;
        this.showModal = false;
        this.toast.success(this.editing ? 'Parent Updated' : 'Parent Added', r.message ? `${body.fullName}: ${r.message}.` : body.fullName);
        this.load();
        this.reloadStudents();
        // A new mother or father: offer to set up the family straight away
        if (!this.editing && body.relationship !== 'Guardian') {
          this.familyPrompt = { id: r.id, name: body.fullName, relationship: body.relationship };
        }
      },
      error: err => {
        this.saving = false;
        this.modalError = err?.error?.message ?? 'Could not save.';
        this.cdr.markForCheck();
      }
    });
  }

  invite(p: ParentRecord): void {
    this.inviting = p.id;
    this.school.inviteParent(p.id).subscribe({
      next: r => { this.inviting = null; this.toast.success('Login', r.message); this.load(); },
      error: err => { this.inviting = null; this.toast.error('Login', err?.error?.message ?? 'Could not send the email.'); this.cdr.markForCheck(); }
    });
  }

  remove(): void {
    const p = this.confirmDelete;
    this.confirmDelete = null;
    if (!p) return;
    this.school.deleteParent(p.id).subscribe({
      next: () => { this.toast.success('Deleted', `${p.fullName} was removed.`); this.load(); },
      error: err => this.toast.error('Delete Failed', err?.error?.message ?? 'Could not delete.')
    });
  }
}
