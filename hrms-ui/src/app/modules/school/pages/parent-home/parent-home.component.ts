import { Component, OnDestroy, OnInit, ChangeDetectorRef, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router, RouterModule } from '@angular/router';
import { Subscription } from 'rxjs';
import { SchoolService, SchoolMe, Announcement, ChildSummary, ageText, utc } from '../../../../core/services/school.service';
import { CompanySettingsService, CompanyBranding } from '../../../../core/services/company-settings.service';
import { ToastService } from '../../../../core/services/toast.service';
import { BannersService, BannerView } from '../../../../core/services/banners.service';
import { BannerCarouselComponent } from '../../../../shared/components/banner-carousel/banner-carousel.component';

/** Parent portal home: the school's banners, my children, quick messages to the teacher/office, latest announcements. */
@Component({
  selector: 'app-parent-home',
  standalone: true,
  imports: [CommonModule, RouterModule, BannerCarouselComponent],
  templateUrl: './parent-home.component.html',
  styleUrls: ['../../school-shared.scss', './parent-home.component.scss']
})
export class ParentHomeComponent implements OnInit, OnDestroy {
  private school = inject(SchoolService);
  private companySettings = inject(CompanySettingsService);
  private toast = inject(ToastService);
  private router = inject(Router);
  private cdr = inject(ChangeDetectorRef);
  private bannersApi = inject(BannersService);
  private subs = new Subscription();

  banners: BannerView[] = [];

  readonly age = ageText;
  readonly utc = utc;

  me: SchoolMe | null = null;
  branding: CompanyBranding | null = null;
  announcements: Announcement[] = [];
  unreadMessages = 0;
  loading = true;
  opening: string | null = null;

  ngOnInit(): void {
    this.subs.add(this.companySettings.branding$.subscribe(b => { this.branding = b; this.cdr.markForCheck(); }));
    this.companySettings.loadBranding();
    this.subs.add(this.school.unreadMessages$.subscribe(n => { this.unreadMessages = n; this.cdr.markForCheck(); }));
    this.subs.add(this.school.liveAnnouncement$.subscribe(() => this.loadAnnouncements()));

    this.school.loadMe(true).subscribe(me => {
      this.me = me;
      this.loading = false;
      if (me?.enabled) { this.loadAnnouncements(); this.loadBanners(); }
      this.cdr.markForCheck();
    });
  }

  loadBanners(): void {
    this.bannersApi.current().subscribe({
      next: b => { this.banners = b; this.cdr.markForCheck(); },
      error: () => {}
    });
  }

  ngOnDestroy(): void { this.subs.unsubscribe(); }

  loadAnnouncements(): void {
    this.school.getAnnouncements().subscribe({
      next: a => { this.announcements = a.slice(0, 3); this.cdr.markForCheck(); },
      error: () => {}
    });
  }

  /** Starts a new conversation about the child (Messages opens the form, prefilled). */
  message(child: ChildSummary, kind: 'Teacher' | 'Office'): void {
    this.router.navigate(['/parent/messages'], { queryParams: { new: 1, child: child.id, kind } });
  }

  greeting(): string {
    const h = new Date().getHours();
    return h < 12 ? 'Good morning' : h < 18 ? 'Good afternoon' : 'Good evening';
  }
}
