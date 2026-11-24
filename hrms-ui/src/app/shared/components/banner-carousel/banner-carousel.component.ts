import {
  ChangeDetectionStrategy, ChangeDetectorRef, Component, ElementRef, HostListener, Input, OnChanges, OnDestroy, OnInit, ViewChild, inject
} from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router } from '@angular/router';
import { BannerView, bannerTarget } from '../../../core/services/banners.service';

/**
 * Slides at the top of the parent home: the school's banners and cards from the parent's own data
 * (fees, today at school, the teacher, prices, life at the school). Colourful cards side by side,
 * moving on one at a time (paused under the mouse or a finger), with arrows, dots and swipe — the
 * same look as the public website and the admin home. Also the preview in the admin's banner form.
 */
@Component({
  selector: 'app-banner-carousel',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './banner-carousel.component.html',
  styleUrls: ['./banner-carousel.component.scss'],
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class BannerCarouselComponent implements OnInit, OnChanges, OnDestroy {
  private router = inject(Router);
  private cdr = inject(ChangeDetectorRef);

  @ViewChild('track') private track?: ElementRef<HTMLElement>;

  @Input() banners: BannerView[] = [];
  @Input() autoplay = true;
  /** Preview: one card, the button does nothing. */
  @Input() preview = false;

  /** Time each position is shown. */
  private static readonly Every = 5000;

  index = 0;
  stops = 0;
  private paused = false;
  private timer: ReturnType<typeof setInterval> | null = null;
  private scrollTimer: ReturnType<typeof setTimeout> | null = null;

  ngOnInit(): void {
    if (this.autoplay)
      this.timer = setInterval(() => {
        if (!this.paused && this.stops > 1 && document.visibilityState === 'visible') this.go(this.index + 1);
      }, BannerCarouselComponent.Every);
  }

  ngOnChanges(): void { setTimeout(() => this.measure()); }

  ngOnDestroy(): void {
    if (this.timer) clearInterval(this.timer);
    if (this.scrollTimer) clearTimeout(this.scrollTimer);
  }

  @HostListener('window:resize')
  measure(): void {
    const el = this.track?.nativeElement;
    if (!el || el.children.length === 0) { this.stops = 0; this.cdr.markForCheck(); return; }
    const step = this.step();
    this.stops = step > 0 ? Math.max(0, Math.round((el.scrollWidth - el.clientWidth) / step)) + 1 : 1;
    if (this.index >= this.stops) this.index = 0;
    this.cdr.markForCheck();
  }

  dotList(): number[] { return Array.from({ length: this.stops }, (_, i) => i); }

  go(i: number): void {
    const n = this.stops;
    const el = this.track?.nativeElement;
    if (!n || !el) return;
    this.index = ((i % n) + n) % n;
    el.scrollTo({ left: this.index * this.step(), behavior: 'smooth' });
    this.cdr.markForCheck();
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

  external(b: BannerView): boolean { return !!b.link?.startsWith('https://'); }

  /** A picture-less card gets an icon that fits its link or theme. */
  iconFor(b: BannerView): string {
    switch (b.link) {
      case 'fees': return 'bi-receipt';
      case 'messages': case 'new-message': return 'bi-chat-heart';
      case 'announcements': return 'bi-megaphone';
      case 'account': return 'bi-person-vcard';
    }
    switch (b.theme) {
      case 'orange': return 'bi-palette';
      case 'pink': return 'bi-balloon';
      case 'blue': return 'bi-egg-fried';
      case 'green': return 'bi-emoji-smile';
      case 'teal': return 'bi-cash-coin';
      default: return 'bi-stars';
    }
  }

  open(b: BannerView): void {
    if (this.preview) return;
    const t = bannerTarget(b.link);
    if (t?.route) this.router.navigateByUrl(t.route);
    else if (t?.href) window.open(t.href, '_blank', 'noopener');
  }

  pause(on: boolean): void { this.paused = on; }

  /** After a swipe, wait a moment before moving on again. */
  touchEnd(): void { setTimeout(() => this.paused = false, 3000); }

  /** Distance from one card to the next. */
  private step(): number {
    const kids = this.track?.nativeElement.children;
    return kids && kids.length > 1 ? (kids[1] as HTMLElement).offsetLeft - (kids[0] as HTMLElement).offsetLeft : 0;
  }
}
