import { ChangeDetectionStrategy, ChangeDetectorRef, Component, Input, OnChanges, OnDestroy, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router } from '@angular/router';
import { BannerView, bannerTarget } from '../../../core/services/banners.service';

/**
 * Advert-style banners at the top of the parent home (School → Banners): one at a time, sliding
 * on every few seconds (paused under the mouse or a finger), with arrows, dots and swipe. A banner's
 * button opens a parent page, or an outside address in a new tab. Also the live preview in the
 * admin's banner form (autoplay off). Same look as the app.
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

  @Input() banners: BannerView[] = [];
  @Input() autoplay = true;
  /** Preview: the button does nothing. */
  @Input() preview = false;

  /** Time each banner is shown. */
  private static readonly Every = 6000;

  index = 0;
  private paused = false;
  private timer: ReturnType<typeof setInterval> | null = null;
  private touchX: number | null = null;

  ngOnInit(): void {
    if (this.autoplay)
      this.timer = setInterval(() => { if (!this.paused && this.banners.length > 1) this.go(this.index + 1); }, BannerCarouselComponent.Every);
  }

  ngOnChanges(): void { if (this.index >= this.banners.length) this.index = 0; }

  ngOnDestroy(): void { if (this.timer) clearInterval(this.timer); }

  go(i: number): void {
    const n = this.banners.length;
    if (!n) return;
    this.index = ((i % n) + n) % n;
    this.cdr.markForCheck();
  }

  external(b: BannerView): boolean { return !!b.link?.startsWith('https://'); }

  open(b: BannerView): void {
    if (this.preview) return;
    const t = bannerTarget(b.link);
    if (t?.route) this.router.navigateByUrl(t.route);
    else if (t?.href) window.open(t.href, '_blank', 'noopener');
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
