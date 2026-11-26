import { Component, OnInit, ChangeDetectorRef, inject } from '@angular/core';
import { CommonModule, Location } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { SchoolService } from '../../../../core/services/school.service';
import { SchoolExtrasService, TimetableSlot, TimetableSlotSave, WEEK_DAYS } from '../../../../core/services/school-extras.service';
import { ToastService } from '../../../../core/services/toast.service';
import { schoolToday, addDays } from '../../../../core/services/school-day.service';
import { ConfirmModalComponent } from '../../../../shared/components/confirm-modal/confirm-modal.component';
import { TimetableRecordComponent } from '../../components/timetable-record/timetable-record.component';

/**
 * School → Timetable: each class's week as day columns of periods. Class teachers fill in their
 * classes (add / edit a period
 * (time, subject, teacher, plan), or copy one day to other days); admins see every class, read-only.
 * Teachers also see their periods as "My timetable",
 * parents on their child's page.
 */
@Component({
  selector: 'app-school-timetable',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterLink, ConfirmModalComponent, TimetableRecordComponent],
  templateUrl: './school-timetable.component.html',
  styleUrls: ['../../school-shared.scss', './school-timetable.component.scss']
})
export class SchoolTimetableComponent implements OnInit {
  private school = inject(SchoolService);
  private extras = inject(SchoolExtrasService);
  private toast = inject(ToastService);
  private route = inject(ActivatedRoute);
  private router = inject(Router);
  private location = inject(Location);
  private cdr = inject(ChangeDetectorRef);

  readonly allDays = WEEK_DAYS;
  classes: { id: number; name: string }[] = [];
  /** Admins view the timetable; the class teachers fill it in. */
  readOnly = true;
  /** Admins: the weekly plan, or the daily record (any date, with the teachers' notes). */
  tab: 'plan' | 'record' = 'plan';
  /** Today as 1 = Monday … 7 = Sunday (school time). */
  readonly todayDow = ((d: number) => d === 0 ? 7 : d)(new Date(schoolToday() + 'T12:00:00').getDay());
  /** This week's Monday ("2026-11-23"): the plan repeats weekly, the dates just help people find their way. */
  readonly monday = addDays(schoolToday(), 1 - this.todayDow);
  readonly weekRange = `${this.fmt(this.monday, false)} – ${this.fmt(addDays(this.monday, 6), true)}`;

  /** "23 Nov" for a weekday (1 = Monday) of this week. */
  dateOf(day: number): string {
    return new Date(addDays(this.monday, day - 1) + 'T00:00:00Z').toLocaleDateString('en-GB', { day: 'numeric', month: 'short', timeZone: 'UTC' });
  }

  private fmt(ymd: string, year: boolean): string {
    return new Date(ymd + 'T00:00:00Z').toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short', ...(year ? { year: 'numeric' } : {}), timeZone: 'UTC' });
  }
  ready = false;
  teachers: { id: number; name: string }[] = [];
  classId: number | null = null;
  slots: TimetableSlot[] = [];
  loading = false;
  /** Show Saturday / Sunday columns. */
  weekend = false;

  // Period form
  showModal = false;
  editing: TimetableSlot | null = null;
  form: TimetableSlotSave = this.blank(1);
  error = '';
  saving = false;
  confirmDelete: TimetableSlot | null = null;

  // Copy a day
  showCopy = false;
  copyFrom = 1;
  copyTo: number[] = [];
  copying = false;

  get days() { return this.allDays.filter(d => d.n <= 5 || this.weekend || d.n === this.todayDow || this.slots.some(s => s.dayOfWeek === d.n)); }
  get className(): string { return this.classes.find(c => c.id === this.classId)?.name ?? ''; }
  slotsOn(day: number): TimetableSlot[] { return this.slots.filter(s => s.dayOfWeek === day); }

  ngOnInit(): void {
    const qp = this.route.snapshot.queryParamMap.get('classId');
    if (this.route.snapshot.queryParamMap.get('tab') === 'record') this.tab = 'record';
    this.school.loadMe().subscribe(me => {
      this.readOnly = !!me?.isAdmin || !me?.isTeacher;
      // Admins get every class, teachers only their own (the API filters /classes)
      this.school.getClasses().subscribe({
        next: c => {
          this.classes = c.filter(x => x.isActive);
          this.classId = qp && this.classes.some(x => x.id === +qp) ? +qp : this.classes[0]?.id ?? null;
          this.ready = true;
          this.load();
          this.cdr.markForCheck();
        },
        error: err => this.toast.error('Load Failed', err?.error?.message ?? 'Could not load classes.')
      });
      if (!this.readOnly)
        this.extras.timetableTeachers().subscribe({ next: t => { this.teachers = t; this.cdr.markForCheck(); }, error: () => {} });
    });
  }

  setTab(t: 'plan' | 'record'): void {
    this.tab = t;
    const q = t === 'record' ? 'tab=record' : (this.classId ? `classId=${this.classId}` : '');
    this.location.replaceState(this.router.url.split('?')[0], q);
  }

  /** Teachers edit a period; admins only look. */
  open(s: TimetableSlot): void {
    if (!this.readOnly) this.openEdit(s);
  }

  load(): void {
    if (!this.classId) { this.slots = []; return; }
    if (this.tab === 'plan') this.location.replaceState(this.router.url.split('?')[0], `classId=${this.classId}`);
    this.loading = true;
    this.extras.classTimetable(this.classId).subscribe({
      next: w => { this.slots = w.slots; this.loading = false; this.cdr.markForCheck(); },
      error: err => { this.loading = false; this.toast.error('Load Failed', err?.error?.message ?? 'Could not load the timetable.'); this.cdr.markForCheck(); }
    });
  }

  private blank(day: number): TimetableSlotSave {
    // Starts where the day's last period ends (or 09:00), one hour long
    const last = this.slots?.filter(s => s.dayOfWeek === day).at(-1);
    const start = last?.endTime ?? '09:00';
    const [h, m] = start.split(':').map(Number);
    const end = `${String(Math.min(h + 1, 23)).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
    return { classId: this.classId ?? 0, dayOfWeek: day, startTime: start, endTime: end, subject: '', teacherEmployeeId: null, notes: null };
  }

  openAdd(day: number): void {
    this.editing = null;
    this.form = this.blank(day);
    this.error = '';
    this.showModal = true;
  }

  openEdit(s: TimetableSlot): void {
    this.editing = s;
    this.form = { classId: s.classId, dayOfWeek: s.dayOfWeek, startTime: s.startTime, endTime: s.endTime,
                  subject: s.subject, teacherEmployeeId: s.teacherEmployeeId, notes: s.notes };
    this.error = '';
    this.showModal = true;
  }

  save(): void {
    if (!this.form.subject.trim()) { this.error = 'Enter what is taught (subject or activity).'; return; }
    if (!this.form.startTime || !this.form.endTime || this.form.endTime <= this.form.startTime) { this.error = 'The end time must be after the start time.'; return; }
    this.saving = true;
    this.error = '';
    const body = { ...this.form, classId: this.classId!, subject: this.form.subject.trim(), notes: this.form.notes?.trim() || null };
    const req = this.editing ? this.extras.updateSlot(this.editing.id, body) : this.extras.createSlot(body);
    req.subscribe({
      next: () => { this.saving = false; this.showModal = false; this.load(); },
      error: err => { this.saving = false; this.error = err?.error?.message ?? 'Could not save.'; this.cdr.markForCheck(); }
    });
  }

  /** Save and open a fresh form for the next period of the same day. */
  saveAndNext(): void {
    const day = this.form.dayOfWeek;
    const end = this.form.endTime;
    if (!this.form.subject.trim()) { this.error = 'Enter what is taught (subject or activity).'; return; }
    this.saving = true;
    const body = { ...this.form, classId: this.classId!, subject: this.form.subject.trim(), notes: this.form.notes?.trim() || null };
    this.extras.createSlot(body).subscribe({
      next: () => {
        this.saving = false;
        const [h, m] = end.split(':').map(Number);
        this.form = { ...this.blank(day), startTime: end, endTime: `${String(Math.min(h + 1, 23)).padStart(2, '0')}:${String(m).padStart(2, '0')}` };
        this.error = '';
        this.load();
      },
      error: err => { this.saving = false; this.error = err?.error?.message ?? 'Could not save.'; this.cdr.markForCheck(); }
    });
  }

  remove(): void {
    const s = this.confirmDelete;
    this.confirmDelete = null;
    if (!s) return;
    this.extras.deleteSlot(s.id).subscribe({
      next: () => { this.showModal = false; this.load(); },
      error: err => this.toast.error('Delete', err?.error?.message ?? 'Could not delete.')
    });
  }

  openCopy(): void {
    this.copyFrom = this.days.find(d => this.slotsOn(d.n).length)?.n ?? 1;
    this.copyTo = [];
    this.showCopy = true;
  }

  toggleCopyTo(day: number, on: boolean): void {
    this.copyTo = on ? [...this.copyTo, day] : this.copyTo.filter(d => d !== day);
  }

  copy(): void {
    if (!this.classId || !this.copyTo.length) return;
    this.copying = true;
    this.extras.copyDay(this.classId, this.copyFrom, this.copyTo).subscribe({
      next: r => { this.copying = false; this.showCopy = false; this.toast.success('Copied', `${r.copied} periods copied.`); this.load(); },
      error: err => { this.copying = false; this.toast.error('Copy', err?.error?.message ?? 'Could not copy.'); this.cdr.markForCheck(); }
    });
  }

  dayName(n: number): string { return this.allDays.find(d => d.n === n)?.long ?? ''; }
}
