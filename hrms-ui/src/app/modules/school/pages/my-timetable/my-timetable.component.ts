import { Component, OnInit, ChangeDetectorRef, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';
import { SchoolService } from '../../../../core/services/school.service';
import { SchoolExtrasService, TimetableWeek } from '../../../../core/services/school-extras.service';
import { schoolToday, addDays, dayLabel } from '../../../../core/services/school-day.service';
import { ToastService } from '../../../../core/services/toast.service';
import { TimetableViewComponent } from '../../components/timetable-view/timetable-view.component';

/**
 * My Timetable (employees, school features on): the periods I teach across classes, one day at a
 * time, and a "what we covered" note per period for today or an earlier day.
 */
@Component({
  selector: 'app-my-timetable',
  standalone: true,
  imports: [CommonModule, RouterLink, TimetableViewComponent],
  template: `
    <div class="school-page">
      <div class="page-header">
        <div>
          <h3>My Timetable <span class="title-sub">· my day</span></h3>
          <p>What you teach, hour by hour. Add a short note on what the children covered — parents see it on their child's timetable.</p>
        </div>
        @if (isTeacher) {
          <div class="header-actions"><a class="btn btn-outline-primary" routerLink="/school/timetable"><i class="bi bi-calendar3-week"></i> Edit weekly plan</a></div>
        }
      </div>

      <div class="day-nav">
        <button class="btn btn-sm btn-outline-secondary" (click)="shift(-7)" aria-label="Previous week"><i class="bi bi-chevron-double-left"></i></button>
        <button class="btn btn-sm btn-outline-secondary" (click)="shift(-1)" aria-label="Previous day"><i class="bi bi-chevron-left"></i></button>
        <strong>{{ relative() }}{{ label(date) }}</strong>
        <button class="btn btn-sm btn-outline-secondary" (click)="shift(1)" aria-label="Next day"><i class="bi bi-chevron-right"></i></button>
        @if (date !== today) { <button class="btn btn-sm btn-link" (click)="go(today)">Today</button> }
      </div>
      <p class="cell-sub mb-3">@if (date === today) { Write what the children covered for today's periods. } @else if (date < today) { Earlier days are read-only. } @else { Coming up — notes can be written on the day. }</p>

      @if (loading && !week) {
        <div class="text-center py-5"><div class="spinner-border text-primary"></div></div>
      } @else if (week && week.slots.length === 0) {
        <div class="table-card empty-state">
          <i class="bi bi-clock-history"></i>
          <h5>No periods yet</h5>
          <p>Class teachers set up their class's periods under School → Class Timetable. Periods where you are the teacher (or your class's periods with no teacher named) appear here.</p>
          @if (isTeacher) { <a class="btn btn-primary mt-2" routerLink="/school/timetable"><i class="bi bi-calendar3-week"></i> Set up the weekly plan</a> }
        </div>
      } @else if (week) {
        <app-timetable-view [week]="week" [showClass]="true" />
      }
    </div>`,
  styleUrls: ['../../school-shared.scss'],
  styles: [`.title-sub { font-size: 15px; font-weight: 500; color: #6b7280; }
    .day-nav { display: flex; align-items: center; gap: 8px; margin-bottom: 6px; flex-wrap: wrap; strong { min-width: 180px; text-align: center; } }`]
})
export class MyTimetableComponent implements OnInit {
  private extras = inject(SchoolExtrasService);
  private toast = inject(ToastService);
  private cdr = inject(ChangeDetectorRef);

  readonly today = schoolToday();
  readonly label = dayLabel;
  date = this.today;
  week: TimetableWeek | null = null;
  loading = false;
  /** Class teachers set up their class's timetable. */
  isTeacher = false;
  private school = inject(SchoolService);

  ngOnInit(): void {
    this.load();
    this.school.loadMe().subscribe(me => { this.isTeacher = !!me?.isTeacher && !me.isAdmin; this.cdr.markForCheck(); });
  }

  shift(n: number): void {
    this.go(addDays(this.date, n));
  }

  /** "Today, " / "Yesterday, " / "Tomorrow, " before the date. */
  relative(): string {
    if (this.date === this.today) return 'Today, ';
    if (this.date === addDays(this.today, -1)) return 'Yesterday, ';
    if (this.date === addDays(this.today, 1)) return 'Tomorrow, ';
    return '';
  }

  go(d: string): void { this.date = d; this.load(); }

  load(): void {
    this.loading = true;
    this.extras.myTimetable(this.date).subscribe({
      next: w => { this.week = w; this.loading = false; this.cdr.markForCheck(); },
      error: err => { this.loading = false; this.toast.error('Load Failed', err?.error?.message ?? 'Could not load your timetable.'); this.cdr.markForCheck(); }
    });
  }
}
