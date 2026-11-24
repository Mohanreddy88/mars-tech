import { ChangeDetectionStrategy, ChangeDetectorRef, Component, ElementRef, HostListener, OnDestroy, OnInit, ViewChild, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { HttpClient } from '@angular/common/http';
import { Router } from '@angular/router';
import { environment } from '../../../../environments/environment';

/** A highlight card from GET /api/dashboard/highlights. */
export interface HighlightCard {
  key: string;
  group: 'hr' | 'school';
  icon: string;
  tone: 'bad' | 'warn' | 'good' | 'info';
  title: string;
  text: string;
  page: string | null;
  action: string | null;
}

/** The page key of a card → this website's address. */
const PAGES: Record<string, string> = {
  'approvals': '/leave/requests?status=Pending',
  'approvals-attendance': '/attendance/approval',
  'payroll': '/payroll/generate',
  'pickup-people': '/school/pickup-people',
  'school-fees': '/school/fees',
  'school-messages': '/school/messages',
  'school-attendance': '/school/attendance',
  'chatbot': '/master/chatbot',
  'holidays': '/master/public-holidays',
  'employees': '/employees'
};

const ICONS: Record<string, string> = {
  leave: 'bi-calendar2-x', attendance: 'bi-clock-history', payroll: 'bi-cash-stack', pickup: 'bi-person-check',
  fees: 'bi-receipt', messages: 'bi-chat-dots', ai: 'bi-robot', children: 'bi-emoji-smile',
  holiday: 'bi-calendar-heart', birthday: 'bi-gift', done: 'bi-check2-circle'
};

/**
 * Sliding "highlights" at the top of the admin home, the same look as the public website slider:
 * several cards side by side moving on one at a time (paused under the mouse or a finger), with arrows, dots and swipe.
 * A card opens its page. The same cards as the app's admin home.
 */
@Component({
  selector: 'app-highlights-carousel',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './highlights-carousel.component.html',
  styleUrls: ['./highlights-carousel.component.scss'],
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class HighlightsCarouselComponent implements OnInit, OnDestroy {
  private http = inject(HttpClient);
  private router = inject(Router);
  private cdr = inject(ChangeDetectorRef);

  /** Time each card is shown. */
  private static readonly Every = 5000;

  @ViewChild('track') private track?: ElementRef<HTMLElement>;

  cards: HighlightCard[] = [];
  /** First card in view. */
  index = 0;
  /** Positions the track can stop at (cards minus the ones that fit beside the last). */
  stops = 0;
  private paused = false;
  private timer: ReturnType<typeof setInterval> | null = null;
  private refreshTimer: ReturnType<typeof setInterval> | null = null;
  private scrollTimer: ReturnType<typeof setTimeout> | null = null;

  ngOnInit(): void {
    this.load();
    this.timer = setInterval(() => {
      if (!this.paused && this.stops > 1 && document.visibilityState === 'visible') this.go(this.index + 1);
    }, HighlightsCarouselComponent.Every);
    // Keep the numbers current while the page is open
    this.refreshTimer = setInterval(() => { if (document.visibilityState === 'visible') this.load(); }, 120_000);
  }

  ngOnDestroy(): void {
    if (this.timer) clearInterval(this.timer);
    if (this.refreshTimer) clearInterval(this.refreshTimer);
    if (this.scrollTimer) clearTimeout(this.scrollTimer);
  }

  @HostListener('window:resize')
  measure(): void {
    const el = this.track?.nativeElement;
    const kids = el?.children;
    if (!el || !kids || kids.length === 0) { this.stops = 0; this.cdr.markForCheck(); return; }
    const step = this.step();
    this.stops = step > 0 ? Math.max(0, Math.round((el.scrollWidth - el.clientWidth) / step)) + 1 : 1;
    if (this.index >= this.stops) this.index = 0;
    this.cdr.markForCheck();
  }

  dotList(): number[] { return Array.from({ length: this.stops }, (_, i) => i); }

  toneLabel(c: HighlightCard): string {
    return c.tone === 'warn' ? 'To do' : c.tone === 'bad' ? 'Needs fixing' : c.tone === 'good' ? 'Good news' : 'For you';
  }

  onScroll(): void {
    if (this.scrollTimer) clearTimeout(this.scrollTimer);
    this.scrollTimer = setTimeout(() => {
      const el = this.track?.nativeElement;
      const step = this.step();
      if (!el || step <= 0) return;
      this.index = Math.min(Math.round(el.scrollLeft / step), Math.max(0, this.stops - 1));
      this.cdr.markForCheck();
    }, 80);
  }

  /** Distance from one card to the next. */
  private step(): number {
    const kids = this.track?.nativeElement.children;
    return kids && kids.length > 1 ? (kids[1] as HTMLElement).offsetLeft - (kids[0] as HTMLElement).offsetLeft : 0;
  }

  load(): void {
    this.http.get<HighlightCard[]>(`${environment.apiUrl}/dashboard/highlights`).subscribe({
      next: c => {
        this.cards = c;
        this.cdr.markForCheck();
        // Measure once the cards are on the page
        setTimeout(() => this.measure());
      },
      error: () => {}
    });
  }

  go(i: number): void {
    const n = this.stops;
    const el = this.track?.nativeElement;
    if (!n || !el) return;
    this.index = ((i % n) + n) % n;
    el.scrollTo({ left: this.index * this.step(), behavior: 'smooth' });
    this.cdr.markForCheck();
  }

  icon(c: HighlightCard): string { return ICONS[c.icon] ?? 'bi-info-circle'; }

  open(c: HighlightCard): void {
    const url = c.page ? PAGES[c.page] : null;
    if (url) this.router.navigateByUrl(url);
  }

  pause(on: boolean): void { this.paused = on; }

  /** After a swipe, wait a moment before moving on again. */
  touchEnd(): void { setTimeout(() => this.paused = false, 3000); }
}
