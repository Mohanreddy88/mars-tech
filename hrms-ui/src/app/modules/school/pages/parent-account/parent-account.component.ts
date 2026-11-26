import { Component, OnInit, ChangeDetectorRef, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterModule } from '@angular/router';
import { SchoolService, ParentAccount, PickupPerson } from '../../../../core/services/school.service';
import { SchoolDayService, ParentNoteInfo, NoteSave, dayLabel, schoolToday } from '../../../../core/services/school-day.service';
import { ToastService } from '../../../../core/services/toast.service';
import { PhoneInputComponent } from '../../../../shared/components/phone-input/phone-input.component';
import { formatPhone, splitPhone, phoneProblem } from '../../../../shared/phone';
import { SchoolAvatarComponent } from '../../../../shared/components/school-avatar/school-avatar.component';
import { PhotoPickerComponent } from '../../../../shared/components/school-avatar/photo-picker.component';

type AccountChild = ParentAccount['children'][number];

/**
 * Parent portal → My Account (same as the app's Account tab): personal information (the phone
 * can be changed), child details (read only), contacts — parents and guardians as "Authorized
 * pick-up", plus pick-up people the parent adds, who count once the office approves — and
 * temporary pickup passes.
 */
@Component({
  selector: 'app-parent-account',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterModule, PhoneInputComponent, SchoolAvatarComponent, PhotoPickerComponent],
  templateUrl: './parent-account.component.html',
  styleUrls: ['../../school-shared.scss', './parent-account.component.scss']
})
export class ParentAccountComponent implements OnInit {
  private school = inject(SchoolService);
  private dayApi = inject(SchoolDayService);
  private toast = inject(ToastService);
  private cdr = inject(ChangeDetectorRef);

  readonly phone = formatPhone;
  readonly dayLabel = dayLabel;

  account: ParentAccount | null = null;
  loading = true;
  passes: ParentNoteInfo[] = [];
  openChild: AccountChild | null = null;

  // Phone
  editingPhone = false;
  newPhone: string | null = null;
  phoneSaving = false;
  phoneError = '';

  // Add pick-up person
  showAdd = false;
  add = { fullName: '', relationship: '', phone: null as string | null, note: '' };
  addKids: number[] = [];
  addSaving = false;
  addError = '';
  readonly suggestions = ['Grandmother', 'Grandfather', 'Aunt', 'Uncle', 'Driver', 'Nanny', 'Family friend'];

  // Temporary pickup pass
  passChildId: number | null = null;
  pass: NoteSave | null = null;
  passSaving = false;
  passError = '';

  ngOnInit(): void { this.load(); }

  load(): void {
    this.school.getAccount().subscribe({
      next: a => { this.account = a; this.loading = false; this.cdr.markForCheck(); },
      error: err => { this.loading = false; this.toast.error('Account', err?.error?.message ?? 'Could not load your account.'); this.cdr.markForCheck(); }
    });
    this.loadPasses();
  }

  loadPasses(): void {
    const today = schoolToday();
    this.dayApi.getNotes().subscribe({
      next: n => { this.passes = n.filter(x => x.kind === 'Pickup' && !x.cancelled && x.toDate >= today); this.cdr.markForCheck(); },
      error: () => {}
    });
  }

  childName(id: number): string { return this.account?.children.find(c => c.id === id)?.fullName ?? ''; }

  /** Parents and guardians once each, with which children (when there are several). */
  get contacts(): { c: AccountChild['contacts'][number]; kids: string[] }[] {
    const map = new Map<number, { c: AccountChild['contacts'][number]; kids: string[] }>();
    for (const ch of this.account?.children ?? [])
      for (const c of ch.contacts) {
        const e = map.get(c.id) ?? { c, kids: [] };
        e.kids.push(ch.fullName);
        map.set(c.id, e);
      }
    return [...map.values()];
  }

  get people(): (PickupPerson & { child: string })[] {
    return (this.account?.children ?? []).flatMap(ch => ch.pickupPeople.map(p => ({ ...p, child: ch.fullName })));
  }

  get many(): boolean { return (this.account?.children.length ?? 0) > 1; }

  // ── Phone ──
  startPhone(): void { this.newPhone = this.account?.parent.phone ?? null; this.phoneError = ''; this.editingPhone = true; }

  savePhone(): void {
    const p = splitPhone(this.newPhone);
    const problem = phoneProblem(p.country, p.national);
    if (!this.newPhone || problem) { this.phoneError = problem ?? 'Enter your phone number.'; return; }
    this.phoneSaving = true;
    this.school.setMyPhone(this.newPhone).subscribe({
      next: () => { this.phoneSaving = false; this.editingPhone = false; this.toast.success('Saved', 'Your phone number was updated.'); this.load(); },
      error: err => { this.phoneSaving = false; this.phoneError = err?.error?.message ?? 'Could not save.'; this.cdr.markForCheck(); }
    });
  }

  // ── Pick-up people ──
  startAdd(): void {
    this.add = { fullName: '', relationship: '', phone: null, note: '' };
    this.addKids = (this.account?.children ?? []).map(c => c.id);
    this.addError = '';
    this.showAdd = true;
  }

  toggleKid(id: number, on: boolean): void { this.addKids = on ? [...this.addKids, id] : this.addKids.filter(x => x !== id); }

  saveAdd(): void {
    if (!this.addKids.length) { this.addError = 'Choose the child(ren) they may collect.'; return; }
    this.addSaving = true;
    this.addError = '';
    this.school.addPickupPerson({
      studentIds: this.addKids, fullName: this.add.fullName.trim(), relationship: this.add.relationship.trim(),
      phone: this.add.phone ?? '', note: this.add.note.trim() || null
    }).subscribe({
      next: () => { this.addSaving = false; this.showAdd = false; this.toast.success('Sent', 'Sent to the school office for approval.'); this.load(); },
      error: err => { this.addSaving = false; this.addError = err?.error?.message ?? 'Could not send.'; this.cdr.markForCheck(); }
    });
  }

  removePerson(p: PickupPerson): void {
    const msg = p.status === 'Pending' ? `Withdraw the request for ${p.fullName}?` : `Remove ${p.fullName} from your list?`;
    if (!confirm(msg)) return;
    this.school.removePickupPerson(p.id).subscribe({
      next: () => { this.toast.success('Removed', p.fullName); this.load(); },
      error: err => this.toast.error('Remove', err?.error?.message ?? 'Could not remove.')
    });
  }

  // ── Temporary pickup pass (the "Other pickup" note) ──
  startPass(): void {
    const kids = this.account?.children ?? [];
    this.passChildId = kids.length === 1 ? kids[0].id : null;
    const day = schoolToday();
    this.pass = { studentId: this.passChildId ?? 0, kind: 'Pickup', fromDate: day, toDate: null, pickupName: null, pickupPhone: null, pickupTime: null, message: null };
    this.passError = '';
  }

  savePass(): void {
    const p = this.pass;
    if (!p) return;
    if (!this.passChildId) { this.passError = 'Choose the child.'; return; }
    if (!p.pickupName?.trim()) { this.passError = 'Who will pick your child up?'; return; }
    this.passSaving = true;
    this.passError = '';
    this.dayApi.createNote({ ...p, studentId: this.passChildId, toDate: null }).subscribe({
      next: () => { this.passSaving = false; this.pass = null; this.toast.success('Sent to the school', 'The teacher has been told who will pick up.'); this.loadPasses(); },
      error: err => { this.passSaving = false; this.passError = err?.error?.message ?? 'Could not send.'; this.cdr.markForCheck(); }
    });
  }

  withdraw(n: ParentNoteInfo): void {
    this.dayApi.cancelNote(n.id).subscribe({
      next: () => { this.toast.success('Withdrawn', 'The pickup pass was withdrawn.'); this.loadPasses(); },
      error: err => this.toast.error('Pickup pass', err?.error?.message ?? 'Could not withdraw.')
    });
  }

  date(d: string | null): string { return d ? dayLabel(d.substring(0, 10)) : '—'; }
}
