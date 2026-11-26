import { Component, EventEmitter, OnInit, Output, ChangeDetectorRef, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { SchoolService, SchoolClass, StudentSave, ParentRecord, SESSION_TYPES } from '../../../../core/services/school.service';
import { ToastService } from '../../../../core/services/toast.service';
import { PhoneInputComponent } from '../../../../shared/components/phone-input/phone-input.component';
import { splitPhone, phoneProblem } from '../../../../shared/phone';

type Side = 'Mother' | 'Father';
type Mode = 'existing' | 'new' | 'none';

interface ParentStep {
  mode: Mode;
  existingId: number | null;
  search: string;
  fullName: string;
  email: string | null;
  phone: string | null;
  /** Create the parent-app login and email the "Set my password" link. */
  invite: boolean;
  /** Set once the new parent is saved, so a retry doesn't add them twice. */
  createdId: number | null;
}

/**
 * School → Registrations → "New registration": a child and their mother and father in one go.
 * Step 1 child, step 2 parents (pick an existing parent — e.g. a sibling's — or add a new one,
 * optionally with a login invite), step 3 check and save. Saving adds new parents first, then the
 * child linked to them; parents already saved are remembered, so a retry never duplicates them.
 */
@Component({
  selector: 'app-registration-wizard',
  standalone: true,
  imports: [CommonModule, FormsModule, PhoneInputComponent],
  templateUrl: './registration-wizard.component.html',
  styleUrls: ['../../school-shared.scss', './registration-wizard.component.scss']
})
export class RegistrationWizardComponent implements OnInit {
  private school = inject(SchoolService);
  private toast = inject(ToastService);
  private cdr = inject(ChangeDetectorRef);

  /** Closed; `saved` is true when a child was registered. */
  @Output() closed = new EventEmitter<boolean>();

  readonly sessionTypes = SESSION_TYPES;
  readonly sides: Side[] = ['Mother', 'Father'];

  step = 1;
  classes: SchoolClass[] = [];
  parents: ParentRecord[] = [];
  error = '';
  duplicateQuestion = '';
  saving = false;

  child: StudentSave = {
    fullName: '', admissionNo: null, dateOfBirth: null, gender: null, classId: null,
    sessionType: 'Full day', joinedOn: null, medicalNotes: null, emergencyContactName: null,
    emergencyContactPhone: null, notes: null, isActive: true
  };

  side: Record<Side, ParentStep> = { Mother: this.blankParent(), Father: this.blankParent() };

  ngOnInit(): void {
    this.school.getClasses().subscribe({ next: c => { this.classes = c.filter(x => x.isActive); this.cdr.markForCheck(); }, error: () => {} });
    this.school.getParents().subscribe({ next: p => { this.parents = p.filter(x => x.isActive); this.cdr.markForCheck(); }, error: () => {} });
  }

  private blankParent(): ParentStep {
    return { mode: 'new', existingId: null, search: '', fullName: '', email: null, phone: null, invite: true, createdId: null };
  }

  /** Existing parents with this relationship, filtered by the search box (name, phone, email, child). */
  candidates(s: Side): ParentRecord[] {
    const q = this.side[s].search.trim().toLowerCase();
    return this.parents.filter(p => p.relationship === s && (!q
      || p.fullName.toLowerCase().includes(q) || (p.phone ?? '').includes(q) || (p.email ?? '').toLowerCase().includes(q)
      || p.children.some(c => c.fullName.toLowerCase().includes(q)))).slice(0, 8);
  }

  childNames(p: ParentRecord): string { return p.children.map(c => c.fullName).join(', '); }
  parentName(id: number | null): string { return this.parents.find(p => p.id === id)?.fullName ?? ''; }
  className(id: number | null): string { return this.classes.find(c => c.id === id)?.name ?? 'No class yet'; }

  next(): void {
    this.error = '';
    if (this.step === 1) {
      if (!this.child.fullName.trim()) { this.error = "Enter the child's name."; return; }
      const ph = splitPhone(this.child.emergencyContactPhone);
      const problem = phoneProblem(ph.country, ph.national);
      if (problem) { this.error = 'Emergency contact phone: ' + problem; return; }
    }
    if (this.step === 2) {
      for (const s of this.sides) {
        const p = this.side[s];
        if (p.mode === 'existing' && !p.existingId) { this.error = `Choose the ${s.toLowerCase()} from the list, or add a new one.`; return; }
        if (p.mode === 'new' && p.createdId == null) {
          if (!p.fullName.trim()) { this.error = `Enter the ${s.toLowerCase()}'s name.`; return; }
          const ph = splitPhone(p.phone);
          const problem = phoneProblem(ph.country, ph.national);
          if (problem) { this.error = `${s}'s phone: ${problem}`; return; }
          if (p.invite && !p.email?.trim()) { this.error = `Add the ${s.toLowerCase()}'s email for the login invite, or untick "Send app login".`; return; }
        }
      }
      if (this.side.Mother.mode === 'none' && this.side.Father.mode === 'none') {
        this.error = 'Add at least one parent (mother or father).'; return;
      }
    }
    this.step++;
  }

  back(): void { this.error = ''; this.duplicateQuestion = ''; this.step--; }

  save(allowDuplicate = false): void {
    this.error = '';
    this.duplicateQuestion = '';
    this.saving = true;
    this.saveParents(0, allowDuplicate);
  }

  /** New parents one by one (sides[i]), then the child. */
  private saveParents(i: number, allowDuplicate: boolean): void {
    if (i >= this.sides.length) { this.saveChild(allowDuplicate); return; }
    const s = this.sides[i];
    const p = this.side[s];
    if (p.mode !== 'new' || p.createdId != null) { this.saveParents(i + 1, allowDuplicate); return; }
    this.school.createParent({
      fullName: p.fullName.trim(), email: p.email?.trim() || null, phone: p.phone || null,
      relationship: s, isActive: true, studentIds: null, createLogin: p.invite && !!p.email?.trim()
    }).subscribe({
      next: r => { p.createdId = r.id; this.saveParents(i + 1, allowDuplicate); },
      error: err => this.fail(`${s}: ${err?.error?.message ?? 'could not be saved.'}`)
    });
  }

  private parentId(s: Side): number | null {
    const p = this.side[s];
    return p.mode === 'existing' ? p.existingId : p.mode === 'new' ? p.createdId : null;
  }

  private saveChild(allowDuplicate: boolean): void {
    const ids = this.sides.map(s => this.parentId(s)).filter((x): x is number => x != null);
    this.school.createStudent({
      ...this.child,
      fullName: this.child.fullName.trim(),
      dateOfBirth: this.child.dateOfBirth || null,
      joinedOn: this.child.joinedOn || null,
      classId: this.child.classId || null,
      parentIds: ids,
      noMotherOnRecord: this.side.Mother.mode === 'none',
      noFatherOnRecord: this.side.Father.mode === 'none',
      allowDuplicate
    }).subscribe({
      next: () => {
        this.saving = false;
        const invited = this.sides.filter(s => this.side[s].mode === 'new' && this.side[s].invite && this.side[s].email?.trim());
        this.toast.success('Registered', `${this.child.fullName.trim()} is registered`
          + (invited.length ? ` and the app login invite was emailed to the ${invited.map(s => s.toLowerCase()).join(' and ')}.` : '.'));
        this.closed.emit(true);
      },
      error: err => {
        if (err?.error?.duplicate) { this.saving = false; this.duplicateQuestion = err.error.message; this.cdr.markForCheck(); return; }
        this.fail(err?.error?.message ?? 'The child could not be saved.');
      }
    });
  }

  private fail(message: string): void {
    this.saving = false;
    const saved = this.sides.filter(s => this.side[s].mode === 'new' && this.side[s].createdId != null);
    this.error = message + (saved.length ? ` (The ${saved.map(s => s.toLowerCase()).join(' and ')} ${saved.length > 1 ? 'are' : 'is'} already saved — fix this and press Save again.)` : '');
    this.cdr.markForCheck();
  }

  close(): void {
    // Parents saved but no child: still a change worth reloading for
    this.closed.emit(this.sides.some(s => this.side[s].createdId != null));
  }
}
