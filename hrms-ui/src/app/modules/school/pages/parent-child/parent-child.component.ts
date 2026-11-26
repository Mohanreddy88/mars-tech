import { Component, OnDestroy, OnInit, ChangeDetectorRef, inject } from '@angular/core';
import { CommonModule, Location } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterModule } from '@angular/router';
import { Subscription } from 'rxjs';
import { SchoolService, ChildSummary, utc } from '../../../../core/services/school.service';
import {
  SchoolDayService, ChildDay, ParentNoteInfo, NoteSave, moodIcon, schoolToday, addDays, dayLabel
} from '../../../../core/services/school-day.service';
import { ToastService } from '../../../../core/services/toast.service';
import { SchoolExtrasService, TimetableWeek } from '../../../../core/services/school-extras.service';
import { TimetableViewComponent } from '../../components/timetable-view/timetable-view.component';
import { PhoneInputComponent } from '../../../../shared/components/phone-input/phone-input.component';
import { formatPhone } from '../../../../shared/phone';

/**
 * Parent portal → one child's day: arrival and home time (who picked up), the teacher's daily
 * report with photos, and the parent's absence / pickup notes.
 */
@Component({
  selector: 'app-parent-child',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterModule, PhoneInputComponent, TimetableViewComponent],
  templateUrl: './parent-child.component.html',
  styleUrls: ['../../school-shared.scss', './parent-child.component.scss']
})
export class ParentChildComponent implements OnInit, OnDestroy {
  private school = inject(SchoolService);
  private dayApi = inject(SchoolDayService);
  private extras = inject(SchoolExtrasService);
  private toast = inject(ToastService);
  private route = inject(ActivatedRoute);
  private router = inject(Router);
  private location = inject(Location);
  private cdr = inject(ChangeDetectorRef);
  private subs = new Subscription();

  readonly moodIcon = moodIcon;
  readonly dayLabel = dayLabel;
  readonly phone = formatPhone;
  readonly utc = utc;

  childId = 0;
  children: ChildSummary[] = [];
  date = schoolToday();
  today = schoolToday();
  data: ChildDay | null = null;
  loading = true;
  recent: { date: string; status: string | null; report: boolean }[] = [];
  notes: ParentNoteInfo[] = [];
  photoUrls = new Map<number, string>();

  // Note form
  noteKind: 'Absence' | 'Pickup' | null = null;
  note: NoteSave = this.blankNote('Absence');
  noteSaving = false;
  noteError = '';

  /** Which part of the child's day is shown (same four as the app's home tiles). */
  view: 'today' | 'report' | 'attendance' | 'notes' | 'timetable' = 'today';
  readonly views: { key: 'today' | 'report' | 'attendance' | 'notes' | 'timetable'; label: string; icon: string }[] = [
    { key: 'today', label: 'Today', icon: 'bi-sun' },
    { key: 'report', label: 'Daily report', icon: 'bi-journal-heart' },
    { key: 'attendance', label: 'Attendance', icon: 'bi-calendar-check' },
    { key: 'notes', label: 'Absence / pickup', icon: 'bi-pencil-square' },
    { key: 'timetable', label: 'Timetable', icon: 'bi-clock-history' }
  ];

  setView(v: 'today' | 'report' | 'attendance' | 'notes' | 'timetable'): void {
    this.view = v;
    this.location.replaceState(`/parent/child/${this.childId}`, `date=${this.date}&view=${v}`);
    if (v === 'attendance') this.loadMonth();
    if (v === 'timetable') this.loadTimetable();
  }

  // ── Timetable (the child's class week, with today's "what we covered" notes) ──
  timetable: TimetableWeek | null = null;
  timetableLoading = false;

  loadTimetable(): void {
    if (!this.childId) return;
    this.timetableLoading = true;
    this.extras.childTimetable(this.childId).subscribe({
      next: w => { this.timetable = w; this.timetableLoading = false; this.cdr.markForCheck(); },
      error: () => { this.timetableLoading = false; this.cdr.markForCheck(); }
    });
  }

  // ── Attendance month ──
  month = schoolToday().substring(0, 7);  // "2026-11"
  monthDays: { date: string; status: string | null; report: boolean }[] = [];

  get monthLabel(): string {
    const [y, m] = this.month.split('-').map(Number);
    return new Date(y, m - 1, 1).toLocaleDateString(undefined, { month: 'long', year: 'numeric' });
  }

  /** The month's grid: leading blanks (weeks start Monday), then each day with its mark. */
  get monthGrid(): ({ date: string; day: number; status: string | null; future: boolean; weekend: boolean } | null)[] {
    const [y, m] = this.month.split('-').map(Number);
    const first = new Date(y, m - 1, 1);
    const days = new Date(y, m, 0).getDate();
    const lead = (first.getDay() + 6) % 7;
    const byDate = new Map(this.monthDays.map(d => [d.date, d]));
    const cells: ({ date: string; day: number; status: string | null; future: boolean; weekend: boolean } | null)[] = Array(lead).fill(null);
    for (let d = 1; d <= days; d++) {
      const date = `${this.month}-${String(d).padStart(2, '0')}`;
      const dow = new Date(y, m - 1, d).getDay();
      cells.push({ date, day: d, status: byDate.get(date)?.status ?? null, future: date > this.today, weekend: dow === 0 || dow === 6 });
    }
    return cells;
  }

  get monthPresent(): number { return this.monthDays.filter(d => d.status === 'Present').length; }
  get monthAbsent(): number { return this.monthDays.filter(d => d.status === 'Absent').length; }
  get isCurrentMonth(): boolean { return this.month >= this.today.substring(0, 7); }

  shiftMonth(n: number): void {
    const [y, m] = this.month.split('-').map(Number);
    const d = new Date(y, m - 1 + n, 1);
    this.month = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
    this.loadMonth();
  }

  loadMonth(): void {
    if (!this.childId) return;
    const [y, m] = this.month.split('-').map(Number);
    const last = `${this.month}-${String(new Date(y, m, 0).getDate()).padStart(2, '0')}`;
    this.dayApi.getDays(this.childId, `${this.month}-01`, last < this.today ? last : this.today).subscribe({
      next: d => { this.monthDays = d; this.cdr.markForCheck(); }, error: () => {}
    });
  }

  /** Tap a day in the month: open that day. */
  openDay(date: string): void { this.date = date; this.setView('today'); this.load(); }

  get earlierNotes(): ParentNoteInfo[] { return this.notes.filter(n => n.cancelled || n.toDate < this.today); }

  /** Another pickup only makes sense on a day the child is at school. */
  get absentOnPickupDay(): ParentNoteInfo | undefined {
    if (this.noteKind !== 'Pickup') return undefined;
    const d = this.note.fromDate;
    return this.notes.find(n => n.kind === 'Absence' && !n.cancelled && n.fromDate <= d && n.toDate >= d);
  }

  get isToday(): boolean { return this.date === this.today; }
  get child(): ChildSummary | undefined { return this.children.find(c => c.id === this.childId); }
  get upcomingNotes(): ParentNoteInfo[] { return this.notes.filter(n => !n.cancelled && n.toDate >= this.today); }

  ngOnInit(): void {
    this.childId = +(this.route.snapshot.paramMap.get('id') ?? 0);
    const d = this.route.snapshot.queryParamMap.get('date');
    if (d) this.date = d.substring(0, 10);
    const v = this.route.snapshot.queryParamMap.get('view');
    if (v === 'report' || v === 'attendance' || v === 'notes' || v === 'timetable') this.view = v;

    this.subs.add(this.school.liveDay$.subscribe(e => { if (e.studentId === this.childId) { this.load(true); this.loadRecent(); } }));
    this.subs.add(this.school.liveNote$.subscribe(e => { if (e.studentId === this.childId) this.loadNotes(); }));
    this.school.loadMe().subscribe(me => {
      this.children = me?.children ?? [];
      if (!this.childId && this.children.length) this.childId = this.children[0].id;
      this.load();
      this.loadRecent();
      this.loadNotes();
      if (this.view === 'attendance') this.loadMonth();
      if (this.view === 'timetable') this.loadTimetable();
    });
  }

  ngOnDestroy(): void {
    this.subs.unsubscribe();
    this.clearPhotos();
  }

  load(quiet = false): void {
    if (!this.childId) { this.loading = false; return; }
    if (!quiet) this.loading = true;
    this.dayApi.getDay(this.childId, this.date).subscribe({
      next: d => {
        this.data = d;
        this.today = d.today;
        this.loading = false;
        this.clearPhotos();
        for (const p of d.report?.photos ?? [])
          this.dayApi.photo(p.id).subscribe({ next: b => { this.photoUrls.set(p.id, URL.createObjectURL(b)); this.cdr.markForCheck(); }, error: () => {} });
        this.cdr.markForCheck();
      },
      error: err => {
        this.loading = false;
        this.toast.error('Load Failed', err?.error?.message ?? 'Could not load the day.');
        this.cdr.markForCheck();
      }
    });
  }

  loadRecent(): void {
    if (!this.childId) return;
    this.dayApi.getDays(this.childId).subscribe({ next: d => { this.recent = d.slice(0, 14); this.cdr.markForCheck(); }, error: () => {} });
  }

  loadNotes(): void {
    if (!this.childId) return;
    this.dayApi.getNotes(this.childId).subscribe({ next: n => { this.notes = n; this.cdr.markForCheck(); }, error: () => {} });
  }

  switchChild(id: number): void {
    this.childId = id;
    this.location.replaceState(`/parent/child/${id}`, `date=${this.date}&view=${this.view}`);
    if (this.view === 'attendance') this.loadMonth();
    if (this.view === 'timetable') this.loadTimetable();
    this.load();
    this.loadRecent();
    this.loadNotes();
  }

  go(date: string): void {
    if (date > this.today) return;
    this.date = date;
    this.location.replaceState(`/parent/child/${this.childId}`, `date=${date}&view=${this.view}`);
    this.load();
  }

  shift(n: number): void { this.go(addDays(this.date, n)); }

  openPhoto(id: number): void { this.school.openBlob(this.dayApi.photo(id)); }

  private clearPhotos(): void {
    this.photoUrls.forEach(u => URL.revokeObjectURL(u));
    this.photoUrls.clear();
  }

  // ── Notes ──

  blankNote(kind: 'Absence' | 'Pickup'): NoteSave {
    const day = this.today;
    return { studentId: this.childId, kind, fromDate: day, toDate: day, pickupName: null, pickupPhone: null, pickupTime: null, message: null };
  }

  openNote(kind: 'Absence' | 'Pickup'): void {
    this.noteKind = kind;
    this.note = this.blankNote(kind);
    this.noteError = '';
  }

  saveNote(): void {
    const n = this.note;
    if (n.kind === 'Pickup' && !n.pickupName?.trim()) { this.noteError = 'Who will pick your child up?'; return; }
    if (this.absentOnPickupDay) { this.noteError = 'You reported your child absent on that day, so no pickup is needed. Choose another day, or withdraw the absence first.'; return; }
    if (n.kind === 'Absence' && n.toDate && n.toDate < n.fromDate) { this.noteError = 'The last day must be on or after the first day.'; return; }
    this.noteSaving = true;
    this.noteError = '';
    this.dayApi.createNote({ ...n, studentId: this.childId, toDate: n.kind === 'Absence' ? (n.toDate || n.fromDate) : null }).subscribe({
      next: () => {
        this.noteSaving = false;
        this.noteKind = null;
        this.toast.success('Sent to the school', n.kind === 'Absence' ? 'The teacher has been told about the absence.' : 'The teacher has been told who will pick up.');
        this.loadNotes();
        this.load(true);
      },
      error: err => { this.noteSaving = false; this.noteError = err?.error?.message ?? 'Could not send.'; this.cdr.markForCheck(); }
    });
  }

  cancelNote(n: ParentNoteInfo): void {
    this.dayApi.cancelNote(n.id).subscribe({
      next: () => { this.toast.success('Withdrawn', 'The note was withdrawn.'); this.loadNotes(); this.load(true); },
      error: err => this.toast.error('Note', err?.error?.message ?? 'Could not withdraw the note.')
    });
  }

  noteWhen(n: ParentNoteInfo): string {
    return n.fromDate === n.toDate ? dayLabel(n.fromDate) : `${dayLabel(n.fromDate)} – ${dayLabel(n.toDate)}`;
  }

  napText(from: string | null, to: string | null): string {
    if (!from && !to) return 'No nap';
    return `${from ?? '?'} – ${to ?? '?'}`;
  }
}
