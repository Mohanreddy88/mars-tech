import { Component, EventEmitter, Input, OnChanges, Output, ChangeDetectorRef, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { SchoolExtrasService, TimetableSlot, TimetableWeek, WEEK_DAYS } from '../../../../core/services/school-extras.service';
import { ToastService } from '../../../../core/services/toast.service';

/**
 * A week's timetable shown one day at a time (day chips), periods in time order with the teacher
 * and the "what we covered" note. Today's periods (or the chosen date's) can get a note when the
 * user may write one. Used by the parent's child page and the teacher's "My timetable".
 */
@Component({
  selector: 'app-timetable-view',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './timetable-view.component.html',
  styleUrls: ['./timetable-view.component.scss']
})
export class TimetableViewComponent implements OnChanges {
  private extras = inject(SchoolExtrasService);
  private toast = inject(ToastService);
  private cdr = inject(ChangeDetectorRef);

  @Input({ required: true }) week: TimetableWeek | null = null;
  /** Show the class name on each period (teacher view across classes). */
  @Input() showClass = false;
  @Output() logSaved = new EventEmitter<void>();

  readonly days = WEEK_DAYS;
  day = 1;
  /** Slot being noted, and its text. */
  noting: number | null = null;
  noteText = '';
  saving = false;

  /** Weekdays plus any weekend day that has periods. */
  get shownDays() {
    const used = new Set(this.week?.slots.map(s => s.dayOfWeek) ?? []);
    return this.days.filter(d => d.n <= 5 || used.has(d.n));
  }

  get daySlots(): TimetableSlot[] { return this.week?.slots.filter(s => s.dayOfWeek === this.day) ?? []; }

  /** The week's date is this weekday: notes can be written (not for other days). */
  get isLogDay(): boolean { return !!this.week && this.week.dayOfWeek === this.day; }

  ngOnChanges(): void {
    if (this.week) this.day = this.week.dayOfWeek <= 7 ? this.week.dayOfWeek : 1;
    if (!this.shownDays.some(d => d.n === this.day)) this.day = 1;
  }

  isNow(s: TimetableSlot): boolean {
    if (!this.week || s.dayOfWeek !== this.week.dayOfWeek) return false;
    const now = new Date();
    const hm = `${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}`;
    return this.week.date === this.todayYmd() && s.startTime <= hm && hm < s.endTime;
  }

  private todayYmd(): string {
    const d = new Date();
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  }

  startNote(s: TimetableSlot): void {
    this.noting = s.id;
    this.noteText = s.log?.note ?? '';
  }

  saveNote(s: TimetableSlot): void {
    if (!this.week) return;
    this.saving = true;
    this.extras.saveLog(s.id, this.week.date, this.noteText).subscribe({
      next: log => {
        this.saving = false;
        this.noting = null;
        s.log = this.noteText.trim() ? log : null;
        this.logSaved.emit();
        this.cdr.markForCheck();
      },
      error: err => { this.saving = false; this.toast.error('Note', err?.error?.message ?? 'Could not save the note.'); this.cdr.markForCheck(); }
    });
  }
}
