import { Component, OnInit, ChangeDetectorRef, inject } from '@angular/core';
import { CommonModule, Location } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterModule } from '@angular/router';
import { SchoolService, SchoolClass, Student, StudentSave, ParentRecord, SESSION_TYPES, ageText } from '../../../../core/services/school.service';
import { ToastService } from '../../../../core/services/toast.service';
import { ConfirmModalComponent } from '../../../../shared/components/confirm-modal/confirm-modal.component';
import { PhoneInputComponent } from '../../../../shared/components/phone-input/phone-input.component';
import { formatPhone, splitPhone, phoneProblem } from '../../../../shared/phone';

/**
 * School → Children. Admins add and edit children; a class teacher sees their own classes
 * here ("My Class", read-only) with the parents' contact details.
 */
@Component({
  selector: 'app-school-students',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterModule, ConfirmModalComponent, PhoneInputComponent],
  templateUrl: './school-students.component.html',
  styleUrls: ['../../school-shared.scss']
})
export class SchoolStudentsComponent implements OnInit {
  private school = inject(SchoolService);
  private toast = inject(ToastService);
  private route = inject(ActivatedRoute);
  private router = inject(Router);
  private location = inject(Location);
  private cdr = inject(ChangeDetectorRef);

  readonly sessionTypes = SESSION_TYPES;
  readonly age = ageText;
  readonly phone = formatPhone;

  isAdmin = false;
  classes: SchoolClass[] = [];
  students: Student[] = [];
  classId: number | null = null;
  includeInactive = false;
  search = '';
  loading = true;

  showModal = false;
  editing: Student | null = null;
  saving = false;
  modalError = '';
  /** "Already on the list" question from the API, answered with saveAnyway(). */
  duplicateQuestion = '';
  form: StudentSave = this.blank();

  confirmDelete: Student | null = null;

  /** All parents (admin), to link from the child form. */
  parents: ParentRecord[] = [];

  // One mother, one father (required unless "No … on record" is ticked), any guardians
  motherId: number | null = null;
  fatherId: number | null = null;
  noMother = false;
  noFather = false;
  guardianIds: number[] = [];
  parentErrors: Record<string, string> = {};

  /** The Mother and Father boxes (same markup for both). */
  readonly sides = [
    { rel: 'Mother', id: () => this.motherId, set: (v: number | null) => { this.motherId = v; this.parentErrors = {}; },
      none: () => this.noMother, setNone: (v: boolean) => { this.noMother = v; if (v) this.motherId = null; this.parentErrors = {}; } },
    { rel: 'Father', id: () => this.fatherId, set: (v: number | null) => { this.fatherId = v; this.parentErrors = {}; },
      none: () => this.noFather, setNone: (v: boolean) => { this.noFather = v; if (v) this.fatherId = null; this.parentErrors = {}; } }
  ];

  parentsFor(relationship: string, selected: number | null): ParentRecord[] {
    return this.parents.filter(p => p.relationship === relationship && (p.isActive || p.id === selected))
      .sort((a, b) => a.fullName.localeCompare(b.fullName));
  }

  get guardianChoices(): ParentRecord[] {
    return this.parents.filter(p => p.relationship === 'Guardian' && (p.isActive || this.guardianIds.includes(p.id)));
  }

  toggleGuardian(id: number, on: boolean): void {
    this.guardianIds = on ? [...this.guardianIds, id] : this.guardianIds.filter(x => x !== id);
  }

  childNames(p: ParentRecord): string { return p.children.map(c => c.fullName).join(', '); }

  // ── "+ New mother / father" without leaving the child ──
  quickAdd: string | null = null;
  quickName = '';
  quickPhone: string | null = null;
  quickEmail = '';
  quickSaving = false;

  startQuickAdd(relationship: string): void {
    this.quickAdd = relationship;
    this.quickName = '';
    this.quickPhone = null;
    this.quickEmail = '';
  }

  saveQuickParent(relationship: string): void {
    const email = this.quickEmail.trim() || null;
    this.quickSaving = true;
    this.school.createParent({
      fullName: this.quickName.trim(), email, phone: this.quickPhone || null, relationship,
      isActive: true, studentIds: null, createLogin: !!email
    }).subscribe({
      next: r => {
        this.quickSaving = false;
        this.quickAdd = null;
        this.school.getParents().subscribe(p => {
          this.parents = p;
          if (relationship === 'Mother') this.motherId = r.id; else this.fatherId = r.id;
          this.cdr.markForCheck();
        });
        if (r.message) this.toast.success('Parent Added', r.message);
      },
      error: err => {
        this.quickSaving = false;
        this.modalError = err?.error?.message ?? 'Could not add the parent.';
        this.cdr.markForCheck();
      }
    });
  }

  private setParentsFrom(s: Student | null): void {
    const ps = s?.parents ?? [];
    this.motherId = ps.find(p => p.relationship === 'Mother')?.id ?? null;
    this.fatherId = ps.find(p => p.relationship === 'Father')?.id ?? null;
    this.guardianIds = ps.filter(p => p.relationship === 'Guardian').map(p => p.id);
    this.noMother = !!s?.noMotherOnRecord;
    this.noFather = !!s?.noFatherOnRecord;
    this.parentErrors = {};
    this.quickAdd = null;
  }

  get filtered(): Student[] {
    const q = this.search.trim().toLowerCase();
    if (!q) return this.students;
    return this.students.filter(s =>
      s.fullName.toLowerCase().includes(q)
      || (s.admissionNo ?? '').toLowerCase().includes(q)
      || s.parents.some(p => p.fullName.toLowerCase().includes(q) || (p.phone ?? '').includes(q)));
  }

  ngOnInit(): void {
    const qp = this.route.snapshot.queryParamMap.get('classId');
    this.classId = qp ? +qp : null;
    this.school.loadMe().subscribe(me => {
      this.isAdmin = !!me?.isAdmin;
      if (this.isAdmin) this.loadParents();
      this.school.getClasses().subscribe({
        next: c => {
          this.classes = c;
          // A teacher with a single class sees it straight away
          if (!this.classId && !this.isAdmin && c.length === 1) this.classId = c[0].id;
          this.load();
        },
        error: err => { this.loading = false; this.toast.error('Load Failed', err?.error?.message ?? 'Could not load classes.'); this.cdr.markForCheck(); }
      });
    });
  }

  load(): void {
    this.loading = true;
    this.school.getStudents(this.classId, this.includeInactive).subscribe({
      next: s => { this.students = s; this.loading = false; this.cdr.markForCheck(); },
      error: err => {
        this.loading = false;
        this.toast.error('Load Failed', err?.error?.message ?? 'Could not load children.');
        this.cdr.markForCheck();
      }
    });
  }

  loadParents(): void {
    this.school.getParents().subscribe({ next: p => { this.parents = p; this.cdr.markForCheck(); }, error: () => {} });
  }

  onClassChange(): void {
    // Address bar only: a router navigation would rebuild the page (NoReuseStrategy)
    this.location.replaceState(this.router.url.split('?')[0], this.classId ? `classId=${this.classId}` : '');
    this.load();
  }

  blank(): StudentSave {
    return {
      fullName: '', admissionNo: null, dateOfBirth: null, gender: null, classId: this.classId ?? null,
      sessionType: 'Full day', joinedOn: null, medicalNotes: null, emergencyContactName: null,
      emergencyContactPhone: null, notes: null, isActive: true, parentIds: []
    };
  }

  openCreate(): void {
    this.editing = null;
    this.form = this.blank();
    this.setParentsFrom(null);
    this.modalError = '';
    this.duplicateQuestion = '';
    this.showModal = true;
  }

  openEdit(s: Student): void {
    this.editing = s;
    this.form = {
      fullName: s.fullName, admissionNo: s.admissionNo, dateOfBirth: s.dateOfBirth?.substring(0, 10) ?? null,
      gender: s.gender, classId: s.classId, sessionType: s.sessionType, joinedOn: s.joinedOn?.substring(0, 10) ?? null,
      medicalNotes: s.medicalNotes, emergencyContactName: s.emergencyContactName,
      emergencyContactPhone: s.emergencyContactPhone, notes: s.notes, isActive: s.isActive,
      parentIds: s.parents.map(p => p.id)
    };
    this.setParentsFrom(s);
    this.modalError = '';
    this.duplicateQuestion = '';
    this.showModal = true;
  }

  saveAnyway(): void { this.save(true); }

  save(allowDuplicate = false): void {
    if (!this.form.fullName.trim()) { this.modalError = "Enter the child's name."; return; }
    const ph = splitPhone(this.form.emergencyContactPhone);
    const problem = phoneProblem(ph.country, ph.national);
    if (problem) { this.modalError = 'Emergency contact phone: ' + problem; return; }
    // Both parents, unless "No mother / father on record" is ticked (single parent)
    this.parentErrors = {};
    if (!this.motherId && !this.noMother) this.parentErrors['Mother'] = 'Choose the mother, or tick "No mother on record".';
    if (!this.fatherId && !this.noFather) this.parentErrors['Father'] = 'Choose the father, or tick "No father on record".';
    if (Object.keys(this.parentErrors).length) { this.modalError = 'Please complete the parents.'; return; }
    this.modalError = '';
    this.duplicateQuestion = '';
    this.saving = true;
    const body: StudentSave = {
      ...this.form,
      fullName: this.form.fullName.trim(),
      dateOfBirth: this.form.dateOfBirth || null,
      joinedOn: this.form.joinedOn || null,
      classId: this.form.classId || null,
      parentIds: [...(this.motherId ? [this.motherId] : []), ...(this.fatherId ? [this.fatherId] : []), ...this.guardianIds],
      noMotherOnRecord: this.noMother,
      noFatherOnRecord: this.noFather,
      allowDuplicate
    };
    const req = this.editing ? this.school.updateStudent(this.editing.id, body) : this.school.createStudent(body);
    req.subscribe({
      next: () => {
        this.saving = false;
        this.showModal = false;
        this.toast.success(this.editing ? 'Child Updated' : 'Child Added',
          this.editing || body.parentIds?.length ? body.fullName
            : `${body.fullName} was added. You can link the parents now (Edit) or under School → Parents.`);
        this.load();
        this.loadParents();
      },
      error: err => {
        this.saving = false;
        if (err?.error?.duplicate) this.duplicateQuestion = err.error.message;
        else this.modalError = err?.error?.message ?? 'Could not save.';
        this.cdr.markForCheck();
      }
    });
  }

  remove(): void {
    const s = this.confirmDelete;
    this.confirmDelete = null;
    if (!s) return;
    this.school.deleteStudent(s.id).subscribe({
      next: () => { this.toast.success('Deleted', `${s.fullName} was removed.`); this.load(); },
      error: err => this.toast.error('Delete Failed', err?.error?.message ?? 'Could not delete.')
    });
  }

  /** Opens (or starts) the thread with this child's parents. */
  message(s: Student, kind: 'Teacher' | 'Office'): void {
    this.school.openConversation(s.id, kind).subscribe({
      next: c => this.router.navigate(['/school/messages'], { queryParams: { c: c.id } }),
      error: err => this.toast.error('Messages', err?.error?.message ?? 'Could not open the conversation.')
    });
  }

  /** Admins message as the office unless they are this class's teacher. */
  messageKind(s: Student): 'Teacher' | 'Office' {
    const me = this.school.me;
    return me && !me.isAdmin ? 'Teacher'
      : me?.classes.some(c => c.id === s.classId) ? 'Teacher' : 'Office';
  }
}
