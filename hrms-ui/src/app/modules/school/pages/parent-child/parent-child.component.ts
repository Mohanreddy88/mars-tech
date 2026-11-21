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
import { PhoneInputComponent } from '../../../../shared/components/phone-input/phone-input.component';
import { formatPhone } from '../../../../shared/phone';

/**
 * Parent portal → one child's day: arrival and home time (who picked up), the teacher's daily
 * report with photos, and the parent's absence / pickup notes.
 */
@Component({
  selector: 'app-parent-child',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterModule, PhoneInputComponent],
  templateUrl: './parent-child.component.html',
  styleUrls: ['../../school-shared.scss', './parent-child.component.scss']
})
export class ParentChildComponent implements OnInit, OnDestroy {
  private school = inject(SchoolService);
  private dayApi = inject(SchoolDayService);
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

  get isToday(): boolean { return this.date === this.today; }
  get child(): ChildSummary | undefined { return this.children.find(c => c.id === this.childId); }
  get upcomingNotes(): ParentNoteInfo[] { return this.notes.filter(n => !n.cancelled && n.toDate >= this.today); }

  ngOnInit(): void {
    this.childId = +(this.route.snapshot.paramMap.get('id') ?? 0);
    const d = this.route.snapshot.queryParamMap.get('date');
    if (d) this.date = d.substring(0, 10);

    this.subs.add(this.school.liveDay$.subscribe(e => { if (e.studentId === this.childId) { this.load(true); this.loadRecent(); } }));
    this.subs.add(this.school.liveNote$.subscribe(e => { if (e.studentId === this.childId) this.loadNotes(); }));
    this.school.loadMe().subscribe(me => {
      this.children = me?.children ?? [];
      if (!this.childId && this.children.length) this.childId = this.children[0].id;
      this.load();
      this.loadRecent();
      this.loadNotes();
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
    this.location.replaceState(`/parent/child/${id}`, `date=${this.date}`);
    this.load();
    this.loadRecent();
    this.loadNotes();
  }

  go(date: string): void {
    if (date > this.today) return;
    this.date = date;
    this.location.replaceState(`/parent/child/${this.childId}`, `date=${date}`);
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
