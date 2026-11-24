import { ChangeDetectionStrategy, ChangeDetectorRef, Component, OnDestroy, OnInit, inject } from '@angular/core';
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
 * Sliding "highlights" at the top of the admin home: one card at a time, moving on every few
 * seconds (paused while the mouse is over it or a finger is on it), with arrows, dots and swipe.
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

  cards: HighlightCard[] = [];
  index = 0;
  private paused = false;
  private timer: ReturnType<typeof setInterval> | null = null;
  private refreshTimer: ReturnType<typeof setInterval> | null = null;
  private touchX: number | null = null;

  ngOnInit(): void {
    this.load();
    this.timer = setInterval(() => { if (!this.paused && this.cards.length > 1) this.go(this.index + 1); }, HighlightsCarouselComponent.Every);
    // Keep the numbers current while the page is open
    this.refreshTimer = setInterval(() => { if (document.visibilityState === 'visible') this.load(); }, 120_000);
  }

  ngOnDestroy(): void {
    if (this.timer) clearInterval(this.timer);
    if (this.refreshTimer) clearInterval(this.refreshTimer);
  }

  load(): void {
    this.http.get<HighlightCard[]>(`${environment.apiUrl}/dashboard/highlights`).subscribe({
      next: c => {
        this.cards = c;
        if (this.index >= c.length) this.index = 0;
        this.cdr.markForCheck();
      },
      error: () => {}
    });
  }

  go(i: number): void {
    const n = this.cards.length;
    if (!n) return;
    this.index = ((i % n) + n) % n;
    this.cdr.markForCheck();
  }

  icon(c: HighlightCard): string { return ICONS[c.icon] ?? 'bi-info-circle'; }

  open(c: HighlightCard): void {
    const url = c.page ? PAGES[c.page] : null;
    if (url) this.router.navigateByUrl(url);
  }

  pause(on: boolean): void { this.paused = on; }

  touchStart(e: TouchEvent): void { this.touchX = e.touches[0]?.clientX ?? null; this.paused = true; }

  touchEnd(e: TouchEvent): void {
    const start = this.touchX;
    this.touchX = null;
    this.paused = false;
    const end = e.changedTouches[0]?.clientX;
    if (start == null || end == null || Math.abs(end - start) < 40) return;
    this.go(this.index + (end < start ? 1 : -1));
  }
}
