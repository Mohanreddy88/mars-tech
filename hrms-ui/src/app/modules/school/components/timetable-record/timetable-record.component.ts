import { Component, Input, OnChanges, ChangeDetectorRef, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { SchoolExtrasService, TimetableRecord, TimetableRecordPeriod } from '../../../../core/services/school-extras.service';
import { schoolToday, addDays } from '../../../../core/services/school-day.service';
import { ToastService } from '../../../../core/services/toast.service';

type RecordDay = TimetableRecord['days'][number];

/**
 * Timetable → Daily record (admins): what each class had on any date and the teachers'
 * "what we covered" notes. Week view (Mon–Sun columns) or day view (one date in time order);
 * arrows move a week / a day, the date box jumps to any month.
 */
@Component({
  selector: 'app-timetable-record',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="record-bar">
      <select [(ngModel)]="classId" (ngModelChange)="load()" aria-label="Class">
        <option [ngValue]="null">All classes</option>
        @for (c of classes; track c.id) { <option [ngValue]="c.id">{{ c.name }}</option> }
      </select>

      <div class="seg" role="tablist" aria-label="View">
        <button type="button" role="tab" [class.on]="mode === 'week'" (click)="setMode('week')">Week</button>
        <button type="button" role="tab" [class.on]="mode === 'day'" (click)="setMode('day')">Day</button>
      </div>

      <div class="nav">
        <button class="btn btn-sm btn-outline-secondary" (click)="move(-1)" [attr.aria-label]="mode === 'week' ? 'Previous week' : 'Previous day'"><i class="bi bi-chevron-left"></i></button>
        <strong class="range">{{ rangeLabel }}</strong>
        <button class="btn btn-sm btn-outline-secondary" (click)="move(1)" [attr.aria-label]="mode === 'week' ? 'Next week' : 'Next day'"><i class="bi bi-chevron-right"></i></button>
      </div>

      <label class="jump">Go to <input type="date" [ngModel]="date" (ngModelChange)="jump($event)" aria-label="Go to date" /></label>
      @if (!isCurrent) {
        <button class="btn btn-sm btn-link" (click)="jump(today)">{{ mode === 'week' ? 'This week' : 'Today' }}</button>
      }
    </div>

    @if (data && data.summary.periods > 0) {
      <div class="summary">
        <i class="bi bi-journal-check"></i>
        Notes written: <strong>{{ data.summary.written }} of {{ data.summary.periods }}</strong> periods
        <span class="bar"><span [style.width.%]="100 * data.summary.written / data.summary.periods"></span></span>
      </div>
    }

    @if (loading && !data) {
      <div class="text-center py-5"><div class="spinner-border text-primary"></div></div>
    } @else if (data && mode === 'week') {
      <div class="week" [style.grid-template-columns]="'repeat(' + weekDays.length + ', minmax(180px, 1fr))'">
        @for (d of weekDays; track d.date) {
          <div class="day-col" [class.today]="d.date === today" [class.future]="d.date > today">
            <div class="day-head">
              <div>{{ dayName(d.date) }} @if (d.date === today) { <em class="today-tag">Today</em> }</div>
              <small>{{ d.periods.length }}</small>
            </div>
            @for (p of d.periods; track p.slotId) {
              <div class="period" [class.has-note]="!!p.note">
                <span class="time">{{ p.startTime }}–{{ p.endTime }}</span>
                <strong>{{ p.subject }}</strong>
                <span class="who">{{ classId ? '' : p.className + ' · ' }}{{ p.teacherName ?? 'Class teacher' }}</span>
                @if (p.note) {
                  <div class="note">{{ p.note }}<small>— {{ p.noteBy }}</small></div>
                } @else if (d.date <= today) {
                  <div class="no-note">No note written</div>
                } @else {
                  <div class="no-note">Planned</div>
                }
              </div>
            } @empty { <span class="none">No periods</span> }
          </div>
        }
      </div>
    } @else if (data && mode === 'day') {
      @if (!data.days[0]?.periods?.length) {
        <div class="table-card empty-state">
          <i class="bi bi-calendar-x"></i>
          <h5>No periods on {{ dayName(date) }}</h5>
          <p>Nothing was on the timetable that day{{ classId ? ' for this class' : '' }}.</p>
        </div>
      } @else {
        <div class="table-card">
          <table class="table align-middle mb-0">
            <thead><tr><th>Time</th>@if (!classId) { <th>Class</th> }<th>Subject</th><th>Teacher</th><th>What we covered</th></tr></thead>
            <tbody>
              @for (p of data.days[0].periods; track p.slotId) {
                <tr>
                  <td class="nowrap"><strong>{{ p.startTime }}</strong>–{{ p.endTime }}</td>
                  @if (!classId) { <td>{{ p.className }}</td> }
                  <td>{{ p.subject }}</td>
                  <td>{{ p.teacherName ?? 'Class teacher' }}</td>
                  <td>
                    @if (p.note) { <div class="note-text">{{ p.note }}</div><div class="cell-sub">{{ p.noteBy }} · {{ p.noteAt | date:'d MMM, h:mm a' }}</div> }
                    @else if (date <= today) { <span class="text-muted">No note written</span> }
                    @else { <span class="text-muted">Planned</span> }
                  </td>
                </tr>
              }
            </tbody>
          </table>
        </div>
      }
    }
  `,
  styles: [`
    .record-bar { display: flex; flex-wrap: wrap; gap: 10px; align-items: center; margin-bottom: 12px;
      select, input[type=date] { border: 1px solid #d1d5db; border-radius: 8px; padding: 6px 10px; font-size: 14px; } }
    .seg { display: inline-flex; border: 1px solid #d1d5db; border-radius: 8px; overflow: hidden;
      button { border: none; background: white; padding: 6px 14px; font-weight: 600; font-size: 14px; color: #374151; cursor: pointer; }
      button.on { background: #2563eb; color: white; } }
    .nav { display: inline-flex; align-items: center; gap: 8px; }
    .range { min-width: 210px; text-align: center; color: #1e3a8a; }
    .jump { display: inline-flex; align-items: center; gap: 6px; font-size: 13px; color: #6b7280; }
    .summary { display: flex; align-items: center; gap: 8px; background: #f0fdf4; border: 1px solid #bbf7d0; border-radius: 10px; padding: 8px 12px; margin-bottom: 12px; font-size: 14px; color: #166534;
      .bar { flex: 0 0 140px; height: 8px; background: #dcfce7; border-radius: 4px; overflow: hidden; span { display: block; height: 100%; background: #16a34a; } } }
    .week { display: grid; gap: 10px; overflow-x: auto; padding-bottom: 8px; }
    .day-col { background: #f9fafb; border: 1px solid #e5e7eb; border-radius: 12px; padding: 8px; display: flex; flex-direction: column; gap: 6px; min-height: 140px;
      &.today { border-color: #16a34a; background: #f0fdf4; }
      &.future { opacity: .85; }
      .day-head { font-weight: 700; color: #1f2937; font-size: 14px; padding: 2px 4px 6px; display: flex; justify-content: space-between; small { color: #6b7280; } } }
    .today-tag { font-style: normal; font-size: 11px; font-weight: 700; color: white; background: #16a34a; border-radius: 10px; padding: 1px 8px; margin-left: 4px; }
    .period { background: white; border-left: 4px solid #cbd5e1; border-radius: 8px; padding: 8px 10px; box-shadow: 0 1px 2px rgba(0,0,0,.08); display: flex; flex-direction: column; gap: 1px;
      &.has-note { border-left-color: #f59e0b; }
      .time { font-size: 12px; color: #2563eb; font-weight: 700; }
      strong { font-size: 14px; color: #1f2937; }
      .who { font-size: 12px; color: #6b7280; } }
    .note { margin-top: 4px; background: #fffbeb; border-radius: 6px; padding: 6px 8px; font-size: 13px; color: #374151; white-space: pre-line;
      small { display: block; color: #92400e; margin-top: 2px; } }
    .no-note { margin-top: 4px; font-size: 12px; color: #9ca3af; font-style: italic; }
    .none { font-size: 12px; color: #9ca3af; padding: 4px; }
    .nowrap { white-space: nowrap; }
    .note-text { white-space: pre-line; }
  `]
})
export class TimetableRecordComponent implements OnChanges {
  private extras = inject(SchoolExtrasService);
  private toast = inject(ToastService);
  private cdr = inject(ChangeDetectorRef);

  @Input() classes: { id: number; name: string }[] = [];

  readonly today = schoolToday();
  classId: number | null = null;
  mode: 'week' | 'day' = 'week';
  /** Any date in the week shown (week view) or the date shown (day view). */
  date = this.today;
  data: TimetableRecord | null = null;
  loading = false;
  private loaded = false;

  ngOnChanges(): void {
    if (!this.loaded) { this.loaded = true; this.load(); }
  }

  private static dow(ymd: string): number { const d = new Date(ymd + 'T00:00:00Z').getUTCDay(); return d === 0 ? 7 : d; }
  private get monday(): string { return addDays(this.date, 1 - TimetableRecordComponent.dow(this.date)); }
  private get from(): string { return this.mode === 'week' ? this.monday : this.date; }
  private get to(): string { return this.mode === 'week' ? addDays(this.monday, 6) : this.date; }

  get isCurrent(): boolean {
    return this.mode === 'week' ? this.monday === addDays(this.today, 1 - TimetableRecordComponent.dow(this.today)) : this.date === this.today;
  }

  get rangeLabel(): string {
    if (this.mode === 'day') return this.fmt(this.date, { weekday: 'long', day: 'numeric', month: 'short', year: 'numeric' });
    return `${this.fmt(this.from, { day: 'numeric', month: 'short' })} – ${this.fmt(this.to, { day: 'numeric', month: 'short', year: 'numeric' })}`;
  }

  /** Mon–Fri always; Sat / Sun only when they have periods. */
  get weekDays(): RecordDay[] {
    return (this.data?.days ?? []).filter(d => d.dayOfWeek <= 5 || d.periods.length > 0);
  }

  dayName(ymd: string): string { return this.fmt(ymd, { weekday: 'short', day: 'numeric', month: 'short' }); }

  private fmt(ymd: string, o: Intl.DateTimeFormatOptions): string {
    return new Date(ymd + 'T00:00:00Z').toLocaleDateString('en-GB', { ...o, timeZone: 'UTC' });
  }

  setMode(m: 'week' | 'day'): void {
    if (this.mode === m) return;
    this.mode = m;
    // Day view opens on today when this week is shown, else on that week's Monday
    if (m === 'day' && !(this.date >= this.from && this.date <= this.to)) this.date = this.monday;
    this.load();
  }

  move(n: number): void { this.date = addDays(this.date, n * (this.mode === 'week' ? 7 : 1)); this.load(); }

  jump(d: string): void { if (d) { this.date = d; this.load(); } }

  load(): void {
    this.loading = true;
    this.extras.timetableRecord(this.classId, this.from, this.to).subscribe({
      next: r => { this.data = r; this.loading = false; this.cdr.markForCheck(); },
      error: err => { this.loading = false; this.toast.error('Load Failed', err?.error?.message ?? 'Could not load the daily record.'); this.cdr.markForCheck(); }
    });
  }

  trackPeriod(_: number, p: TimetableRecordPeriod): number { return p.slotId; }
}
