import { Component, OnDestroy, OnInit, ChangeDetectorRef, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router, RouterModule } from '@angular/router';
import { Subscription } from 'rxjs';
import { SchoolService, SchoolMe, Announcement, ChildSummary, ageText, utc } from '../../../../core/services/school.service';
import { CompanySettingsService, CompanyBranding } from '../../../../core/services/company-settings.service';
import { ToastService } from '../../../../core/services/toast.service';

/** Parent portal home: my children, quick messages to the teacher/office, latest announcements. */
@Component({
  selector: 'app-parent-home',
  standalone: true,
  imports: [CommonModule, RouterModule],
  templateUrl: './parent-home.component.html',
  styleUrls: ['../../school-shared.scss', './parent-home.component.scss']
})
export class ParentHomeComponent implements OnInit, OnDestroy {
  private school = inject(SchoolService);
  private companySettings = inject(CompanySettingsService);
  private toast = inject(ToastService);
  private router = inject(Router);
  private cdr = inject(ChangeDetectorRef);
  private subs = new Subscription();

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
      if (me?.enabled) this.loadAnnouncements();
      this.cdr.markForCheck();
    });
  }

  ngOnDestroy(): void { this.subs.unsubscribe(); }

  loadAnnouncements(): void {
    this.school.getAnnouncements().subscribe({
      next: a => { this.announcements = a.slice(0, 3); this.cdr.markForCheck(); },
      error: () => {}
    });
  }

  message(child: ChildSummary, kind: 'Teacher' | 'Office'): void {
    this.opening = `${child.id}-${kind}`;
    this.school.openConversation(child.id, kind).subscribe({
      next: c => { this.opening = null; this.router.navigate(['/parent/messages'], { queryParams: { c: c.id } }); },
      error: err => {
        this.opening = null;
        this.toast.error('Messages', err?.error?.message ?? 'Could not open the conversation.');
        this.cdr.markForCheck();
      }
    });
  }

  greeting(): string {
    const h = new Date().getHours();
    return h < 12 ? 'Good morning' : h < 18 ? 'Good afternoon' : 'Good evening';
  }
}
