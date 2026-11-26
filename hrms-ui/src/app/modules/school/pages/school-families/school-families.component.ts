import { Component, Input, OnInit, ChangeDetectorRef, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, RouterModule } from '@angular/router';
import { SchoolService, Family, ParentRecord, Student } from '../../../../core/services/school.service';
import { ToastService } from '../../../../core/services/toast.service';
import { formatPhone } from '../../../../shared/phone';

/**
 * School → Families (admin): a mother and father and their children together. Saving sets the
 * same mother and father on every child. Half-brothers and sisters are two families that share a
 * parent (Rudvik → Mounika + Mohan, Arjun → Mounika + Narsi). Single parents: "No father on record".
 * Same as the app's Families screen.
 */
@Component({
  selector: 'app-school-families',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterModule],
  templateUrl: './school-families.component.html',
  styleUrls: ['../../school-shared.scss']
})
export class SchoolFamiliesComponent implements OnInit {
  /** Shown as a tab inside School → Registrations (no page title). */
  @Input() embedded = false;

  private school = inject(SchoolService);
  private toast = inject(ToastService);
  private route = inject(ActivatedRoute);
  private cdr = inject(ChangeDetectorRef);

  readonly phone = formatPhone;

  families: Family[] = [];
  parents: ParentRecord[] = [];
  students: Student[] = [];
  loading = true;
  search = '';
  onlyIncomplete = false;

  // Add / edit
  showModal = false;
  editing: Family | null = null;
  motherId: number | null = null;
  fatherId: number | null = null;
  noMother = false;
  noFather = false;
  childIds: number[] = [];
  addChildId: number | null = null;
  saving = false;
  modalError = '';
  parentErrors: Record<string, string> = {};

  /** A mother or father missing and nobody confirmed it ("No … on record"). */
  incomplete(f: Family): boolean { return (!f.mother && !f.noMother) || (!f.father && !f.noFather); }

  get incompleteCount(): number { return this.families.filter(f => this.incomplete(f)).length; }

  get filtered(): Family[] {
    const q = this.search.trim().toLowerCase();
    return this.families.filter(f =>
      (!this.onlyIncomplete || this.incomplete(f)) &&
      (!q || (f.mother?.fullName ?? '').toLowerCase().includes(q) || (f.father?.fullName ?? '').toLowerCase().includes(q)
        || f.children.some(c => c.fullName.toLowerCase().includes(q))));
  }

  ngOnInit(): void {
    this.load();
    this.school.getParents().subscribe({ next: p => { this.parents = p; this.openFromLink(); this.cdr.markForCheck(); }, error: () => {} });
    this.school.getStudents(null, false).subscribe({ next: s => { this.students = s; this.cdr.markForCheck(); }, error: () => {} });
  }

  /** From the Parents page: "Set up the family now?" → ?add=1&motherId=… */
  private openFromLink(): void {
    const q = this.route.snapshot.queryParamMap;
    if (q.get('add') !== '1' || this.showModal) return;
    this.openCreate();
    this.motherId = q.get('motherId') ? +q.get('motherId')! : null;
    this.fatherId = q.get('fatherId') ? +q.get('fatherId')! : null;
  }

  load(): void {
    this.loading = true;
    this.school.getFamilies().subscribe({
      next: f => { this.families = f; this.loading = false; this.cdr.markForCheck(); },
      error: err => {
        this.loading = false;
        this.toast.error('Load Failed', err?.error?.message ?? 'Could not load the families.');
        this.cdr.markForCheck();
      }
    });
  }

  parentsFor(relationship: string, selected: number | null): ParentRecord[] {
    return this.parents.filter(p => p.relationship === relationship && (p.isActive || p.id === selected))
      .sort((a, b) => a.fullName.localeCompare(b.fullName));
  }

  childNames(p: ParentRecord): string { return p.children.map(c => c.fullName).join(', '); }

  /** "Mounika, Mohan" — a child's current parents, to tell children apart in the picker. */
  parentNames(s: Student): string { return s.parents.map(p => p.fullName).join(', '); }

  /** Mother then father of a family, with whether each is "none on record". */
  sidesOf(f: Family): { p: Family['mother']; none: boolean }[] {
    return [{ p: f.mother, none: f.noMother }, { p: f.father, none: f.noFather }];
  }

  student(id: number): Student | undefined { return this.students.find(s => s.id === id); }

  get addableChildren(): Student[] {
    return this.students.filter(s => !this.childIds.includes(s.id)).sort((a, b) => a.fullName.localeCompare(b.fullName));
  }

  /** What will change for this child, e.g. "father Narsi → Mohan". */
  change(id: number): string | null {
    const s = this.student(id);
    if (!s) return null;
    const parts: string[] = [];
    const side = (rel: string, chosen: number | null, none: boolean) => {
      const now = s.parents.find(p => p.relationship === rel);
      if (none && now) { parts.push(`${rel.toLowerCase()} ${now.fullName} removed`); return; }
      if (!chosen || now?.id === chosen) return;
      const name = this.parents.find(p => p.id === chosen)?.fullName ?? '?';
      parts.push(now ? `${rel.toLowerCase()} ${now.fullName} → ${name}` : `${rel.toLowerCase()}: ${name}`);
    };
    side('Mother', this.motherId, this.noMother);
    side('Father', this.fatherId, this.noFather);
    return parts.length ? parts.join(', ') : null;
  }

  openCreate(): void {
    this.editing = null;
    this.motherId = this.fatherId = null;
    this.noMother = this.noFather = false;
    this.childIds = [];
    this.addChildId = null;
    this.modalError = '';
    this.parentErrors = {};
    this.showModal = true;
  }

  openEdit(f: Family): void {
    this.editing = f;
    this.motherId = f.mother?.id ?? null;
    this.fatherId = f.father?.id ?? null;
    this.noMother = f.noMother;
    this.noFather = f.noFather;
    this.childIds = f.children.map(c => c.id);
    this.addChildId = null;
    this.modalError = '';
    this.parentErrors = {};
    this.showModal = true;
  }

  setNone(rel: 'Mother' | 'Father', v: boolean): void {
    if (rel === 'Mother') { this.noMother = v; if (v) this.motherId = null; }
    else { this.noFather = v; if (v) this.fatherId = null; }
    this.parentErrors = {};
  }

  addChild(): void {
    if (this.addChildId && !this.childIds.includes(this.addChildId)) this.childIds = [...this.childIds, this.addChildId];
    this.addChildId = null;
  }

  removeChild(id: number): void { this.childIds = this.childIds.filter(x => x !== id); }

  save(): void {
    this.parentErrors = {};
    if (!this.motherId && !this.noMother) this.parentErrors['Mother'] = 'Choose the mother, or tick "No mother on record".';
    if (!this.fatherId && !this.noFather) this.parentErrors['Father'] = 'Choose the father, or tick "No father on record".';
    if (Object.keys(this.parentErrors).length) { this.modalError = 'Please complete the parents.'; return; }
    if (!this.motherId && !this.fatherId) { this.modalError = 'A family needs at least a mother or a father.'; return; }
    const original = this.editing?.children.map(c => c.id) ?? [];
    if (this.childIds.length === 0 && original.length === 0) { this.modalError = 'Add at least one child.'; return; }
    this.modalError = '';
    this.saving = true;

    // Children taken out are unlinked from the parents this family had when it was opened
    const removed = original.filter(id => !this.childIds.includes(id));
    const f = this.editing;
    const sameParents = !!f && (f.mother?.id ?? null) === this.motherId && (f.father?.id ?? null) === this.fatherId;
    const saveMain = () => this.school.saveFamily({
      motherId: this.motherId, fatherId: this.fatherId, studentIds: this.childIds,
      removeStudentIds: sameParents ? removed : [], noMother: this.noMother, noFather: this.noFather
    }).subscribe({ next: () => this.done(), error: err => this.failed(err) });

    if (removed.length && f && (f.mother || f.father) && !sameParents) {
      this.school.saveFamily({
        motherId: f.mother?.id ?? null, fatherId: f.father?.id ?? null, studentIds: [], removeStudentIds: removed,
        noMother: false, noFather: false
      }).subscribe({ next: () => saveMain(), error: err => this.failed(err) });
    } else {
      saveMain();
    }
  }

  private done(): void {
    this.saving = false;
    this.showModal = false;
    this.toast.success('Family Saved', 'The children now have these parents.');
    this.load();
    this.school.getStudents(null, false).subscribe({ next: s => { this.students = s; this.cdr.markForCheck(); }, error: () => {} });
  }

  private failed(err: any): void {
    this.saving = false;
    this.modalError = err?.error?.message ?? 'Could not save the family.';
    this.cdr.markForCheck();
  }
}
