import { Component, OnDestroy, OnInit, ChangeDetectorRef, inject } from '@angular/core';
import { CommonModule, Location } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterModule } from '@angular/router';
import { Subscription } from 'rxjs';
import { SchoolService, SchoolClass } from '../../../../core/services/school.service';
import {
  SchoolDayService, AttendanceDay, AttendanceRow, ParentNoteInfo, DailyReportInfo, DailyReportSave,
  MEAL_AMOUNTS, MOODS, moodIcon, schoolToday, addDays, dayLabel
} from '../../../../core/services/school-day.service';
import { ToastService } from '../../../../core/services/toast.service';
import { formatPhone } from '../../../../shared/phone';

/**
 * School → Attendance & Daily Reports (class teachers and admins).
 * One list per class and day: check in, check out (who picked up), absent, the parents' notes,
 * and the daily report (meals, nap, mood, photos) that is sent to the parents.
 */
@Component({
  selector: 'app-school-attendance',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterModule],
  templateUrl: './school-attendance.component.html',
  styleUrls: ['../../school-shared.scss', './school-attendance.component.scss']
})
export class SchoolAttendanceComponent implements OnInit, OnDestroy {
  private school = inject(SchoolService);
  private day = inject(SchoolDayService);
  private toast = inject(ToastService);
  private route = inject(ActivatedRoute);
  private router = inject(Router);
  private location = inject(Location);
  private cdr = inject(ChangeDetectorRef);
  private subs = new Subscription();

  readonly meals = MEAL_AMOUNTS;
  readonly moods = MOODS;
  readonly moodIcon = moodIcon;
  readonly phone = formatPhone;
  readonly dayLabel = dayLabel;

  isAdmin = false;
  classes: SchoolClass[] = [];
  classId: number | null = null;
  date = schoolToday();
  today = schoolToday();
  data: AttendanceDay | null = null;
  loading = true;
  busy: number | null = null;          // studentId being saved
  search = '';

  // Check-out / absent / past check-in dialog
  dialog: { kind: 'in' | 'out' | 'absent'; row: AttendanceRow } | null = null;
  dialogTime = '';
  dialogPickup = '';
  dialogPickupOther = '';
  dialogReason = '';
  dialogError = '';

  // Daily report editor
  editing: AttendanceRow | null = null;
  report: DailyReportSave = this.blankReport();
  reportInfo: DailyReportInfo | null = null;
  photoUrls = new Map<number, string>();
  reportSaving = false;
  reportError = '';
  uploading = false;

  get rows(): AttendanceRow[] {
    const q = this.search.trim().toLowerCase();
    const rows = this.data?.rows ?? [];
    return q ? rows.filter(r => r.fullName.toLowerCase().includes(q)) : rows;
  }

  get isToday(): boolean { return this.date === this.today; }

  /** Reports written but not yet sent to parents. */
  get unpublished(): AttendanceRow[] { return (this.data?.rows ?? []).filter(r => r.report && !r.report.published); }

  ngOnInit(): void {
    const qp = this.route.snapshot.queryParamMap;
    if (qp.get('date')) this.date = qp.get('date')!.substring(0, 10);
    if (qp.get('classId')) this.classId = +qp.get('classId')!;

    this.subs.add(this.school.liveNote$.subscribe(() => this.load(true)));
    this.school.loadMe().subscribe(me => {
      this.isAdmin = !!me?.isAdmin;
      this.school.getClasses().subscribe({
        next: c => {
          this.classes = c.filter(x => x.isActive);
          if (!this.classId && !this.isAdmin && this.classes.length === 1) this.classId = this.classes[0].id;
          this.load();
        },
        error: () => this.load()
      });
    });
  }

  ngOnDestroy(): void {
    this.subs.unsubscribe();
    this.clearPhotos();
  }

  load(quiet = false): void {
    if (!quiet) this.loading = true;
    this.day.getAttendance(this.classId, this.date).subscribe({
      next: d => { this.data = d; this.today = d.today; this.loading = false; this.cdr.markForCheck(); },
      error: err => {
        this.loading = false;
        this.toast.error('Load Failed', err?.error?.message ?? 'Could not load the attendance.');
        this.cdr.markForCheck();
      }
    });
  }

  changed(): void {
    // Address bar only: a router navigation would rebuild the page
    const q = [`date=${this.date}`, this.classId ? `classId=${this.classId}` : ''].filter(Boolean).join('&');
    this.location.replaceState(this.router.url.split('?')[0], q);
    this.load();
  }

  shiftDay(n: number): void {
    const d = addDays(this.date, n);
    if (d > this.today) return;
    this.date = d;
    this.changed();
  }

  goToday(): void { this.date = this.today; this.changed(); }

  // ── Attendance ──

  checkIn(r: AttendanceRow): void {
    if (!this.isToday) { this.openDialog('in', r); return; }
    this.run(r, this.day.checkIn(r.studentId, this.date), `${r.fullName} checked in`);
  }

  openDialog(kind: 'in' | 'out' | 'absent', r: AttendanceRow): void {
    this.dialog = { kind, row: r };
    this.dialogError = '';
    this.dialogTime = this.isToday ? this.nowTime() : '';
    const pickup = r.notes.find(n => n.kind === 'Pickup');
    this.dialogPickup = pickup?.pickupName ? `${pickup.pickupName} (pickup note)` : (r.parents[0] ? this.parentLabel(r.parents[0]) : '');
    this.dialogPickupOther = '';
    const absence = r.notes.find(n => n.kind === 'Absence');
    this.dialogReason = absence?.message ?? (absence ? 'Parent reported absence' : '');
  }

  pickupChoices(r: AttendanceRow): string[] {
    const list = r.parents.map(p => this.parentLabel(p));
    for (const n of r.notes.filter(n => n.kind === 'Pickup' && n.pickupName)) list.unshift(`${n.pickupName} (pickup note)`);
    return [...new Set(list)];
  }

  parentLabel(p: { fullName: string; relationship: string }): string { return `${p.fullName} (${p.relationship})`; }

  confirmDialog(): void {
    const d = this.dialog;
    if (!d) return;
    if (!this.isToday && !this.dialogTime && d.kind !== 'absent') { this.dialogError = 'Enter the time.'; return; }
    const r = d.row;
    if (d.kind === 'in') {
      this.run(r, this.day.checkIn(r.studentId, this.date, this.dialogTime), `${r.fullName} checked in`, true);
    } else if (d.kind === 'out') {
      const who = (this.dialogPickup === '__other' ? this.dialogPickupOther : this.dialogPickup).replace(' (pickup note)', '').trim();
      if (!who) { this.dialogError = 'Who picked the child up?'; return; }
      this.run(r, this.day.checkOut(r.studentId, this.date, who, this.dialogTime), `${r.fullName} checked out`, true);
    } else {
      this.run(r, this.day.markAbsent(r.studentId, this.date, this.dialogReason.trim() || null), `${r.fullName} marked absent`, true);
    }
  }

  undo(r: AttendanceRow): void {
    this.run(r, this.day.clearAttendance(r.studentId, this.date), `${r.fullName}: attendance cleared`);
  }

  private run(r: AttendanceRow, req: any, done: string, fromDialog = false): void {
    this.busy = r.studentId;
    req.subscribe({
      next: () => {
        this.busy = null;
        if (fromDialog) this.dialog = null;
        this.toast.success('Saved', done);
        this.load(true);
      },
      error: (err: any) => {
        this.busy = null;
        const msg = err?.error?.message ?? 'Could not save.';
        if (fromDialog) this.dialogError = msg; else this.toast.error('Attendance', msg);
        this.cdr.markForCheck();
      }
    });
  }

  /** A parent said the child won't come (highlighted until the teacher marks the day). */
  hasAbsence(r: AttendanceRow): boolean { return r.notes.some(n => n.kind === 'Absence'); }

  seen(n: ParentNoteInfo): void {
    this.day.markNoteSeen(n.id).subscribe({ next: () => this.load(true), error: () => {} });
  }

  noteText(n: ParentNoteInfo): string {
    const range = n.fromDate === n.toDate ? '' : ` (${dayLabel(n.fromDate)} – ${dayLabel(n.toDate)})`;
    return n.kind === 'Absence'
      ? `Absent${range}${n.message ? ': ' + n.message : ''}`
      : `Pickup: ${n.pickupName}${n.pickupTime ? ' at ' + n.pickupTime : ''}${n.pickupPhone ? ' · ' + formatPhone(n.pickupPhone) : ''}${n.message ? ' — ' + n.message : ''}`;
  }

  // ── Daily report ──

  blankReport(): DailyReportSave {
    return { breakfast: null, lunch: null, snack: null, napFrom: null, napTo: null, toilet: null, mood: null, activities: null, teacherNote: null };
  }

  openReport(r: AttendanceRow): void {
    this.editing = r;
    this.report = this.blankReport();
    this.reportInfo = null;
    this.reportError = '';
    this.clearPhotos();
    this.day.getDay(r.studentId, this.date).subscribe({
      next: d => {
        if (d.report) {
          this.reportInfo = d.report;
          const { breakfast, lunch, snack, napFrom, napTo, toilet, mood, activities, teacherNote } = d.report;
          this.report = { breakfast, lunch, snack, napFrom, napTo, toilet, mood, activities, teacherNote };
          this.loadPhotos(d.report);
        }
        this.cdr.markForCheck();
      },
      error: err => { this.reportError = err?.error?.message ?? 'Could not load the report.'; this.cdr.markForCheck(); }
    });
  }

  closeReport(): void {
    this.editing = null;
    this.clearPhotos();
  }

  pick(field: 'breakfast' | 'lunch' | 'snack' | 'mood', value: string): void {
    this.report[field] = this.report[field] === value ? null : value;
  }

  saveReport(publish: boolean): void {
    const r = this.editing;
    if (!r) return;
    this.reportSaving = true;
    this.reportError = '';
    this.day.saveReport(r.studentId, this.date, { ...this.report, publish }).subscribe({
      next: info => {
        this.reportSaving = false;
        this.reportInfo = info;
        this.toast.success(publish ? 'Sent to parents' : 'Saved', publish ? `${r.fullName}'s daily report was sent.` : `${r.fullName}'s report was saved as a draft.`);
        if (publish) this.closeReport();
        this.load(true);
      },
      error: err => { this.reportSaving = false; this.reportError = err?.error?.message ?? 'Could not save.'; this.cdr.markForCheck(); }
    });
  }

  addPhotos(input: HTMLInputElement): void {
    const r = this.editing;
    const files = Array.from(input.files ?? []);
    input.value = '';
    if (!r || files.length === 0) return;
    this.uploading = true;
    const next = (i: number) => {
      if (i >= files.length) {
        this.uploading = false;
        this.day.getDay(r.studentId, this.date).subscribe(d => { if (d.report) { this.reportInfo = d.report; this.loadPhotos(d.report); } this.load(true); });
        return;
      }
      this.day.addPhoto(r.studentId, this.date, files[i]).subscribe({
        next: () => next(i + 1),
        error: err => { this.uploading = false; this.reportError = err?.error?.message ?? 'Could not add the photo.'; this.cdr.markForCheck(); }
      });
    };
    next(0);
  }

  removePhoto(id: number): void {
    this.day.deletePhoto(id).subscribe({
      next: () => {
        if (this.reportInfo) this.reportInfo = { ...this.reportInfo, photos: this.reportInfo.photos.filter(p => p.id !== id) };
        const url = this.photoUrls.get(id);
        if (url) { URL.revokeObjectURL(url); this.photoUrls.delete(id); }
        this.load(true);
        this.cdr.markForCheck();
      },
      error: err => this.toast.error('Photo', err?.error?.message ?? 'Could not remove the photo.')
    });
  }

  openPhoto(id: number): void { this.school.openBlob(this.day.photo(id)); }

  private loadPhotos(r: DailyReportInfo): void {
    for (const p of r.photos) {
      if (this.photoUrls.has(p.id)) continue;
      this.day.photo(p.id).subscribe({
        next: b => { this.photoUrls.set(p.id, URL.createObjectURL(b)); this.cdr.markForCheck(); },
        error: () => {}
      });
    }
  }

  private clearPhotos(): void {
    this.photoUrls.forEach(u => URL.revokeObjectURL(u));
    this.photoUrls.clear();
  }

  publishAll(): void {
    const ids = this.unpublished.map(r => r.studentId);
    if (ids.length === 0) return;
    this.day.publish(this.date, ids).subscribe({
      next: r => { this.toast.success('Sent to parents', `${r.published} daily report${r.published === 1 ? '' : 's'} sent.`); this.load(true); },
      error: err => this.toast.error('Daily reports', err?.error?.message ?? 'Could not send.')
    });
  }

  private nowTime(): string {
    const d = new Date(Date.now() + 8 * 3600_000);
    return d.toISOString().substring(11, 16);
  }
}
