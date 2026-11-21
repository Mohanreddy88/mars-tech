import { Component, OnDestroy, OnInit, ChangeDetectorRef, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Subscription } from 'rxjs';
import { SchoolService, Announcement, SchoolMe, utc } from '../../../../core/services/school.service';
import { ToastService } from '../../../../core/services/toast.service';
import { ConfirmModalComponent } from '../../../../shared/components/confirm-modal/confirm-modal.component';

/**
 * Announcements. The office posts to all parents or one class; a class teacher posts to
 * their own classes and sees how many parents have read each one. Parents see the ones for
 * the whole school and their children's classes; opening the page marks them read.
 */
@Component({
  selector: 'app-school-announcements',
  standalone: true,
  imports: [CommonModule, FormsModule, ConfirmModalComponent],
  templateUrl: './school-announcements.component.html',
  styleUrls: ['../../school-shared.scss', './school-announcements.component.scss']
})
export class SchoolAnnouncementsComponent implements OnInit, OnDestroy {
  private school = inject(SchoolService);
  private toast = inject(ToastService);
  private cdr = inject(ChangeDetectorRef);
  private subs = new Subscription();

  me: SchoolMe | null = null;
  items: Announcement[] = [];
  classes: { id: number; name: string }[] = [];
  loading = true;

  showCompose = false;
  form = { title: '', body: '', classId: null as number | null };
  file: File | null = null;
  posting = false;
  composeError = '';

  confirmDelete: Announcement | null = null;

  get isStaff(): boolean { return !!this.me && (this.me.isAdmin || this.me.isTeacher); }

  ngOnInit(): void {
    this.school.loadMe().subscribe(me => {
      this.me = me;
      if (me?.isAdmin) {
        this.school.getClasses().subscribe({ next: c => { this.classes = c.filter(x => x.isActive); this.cdr.markForCheck(); }, error: () => {} });
      } else if (me?.isTeacher) {
        this.classes = me.classes;
        this.form.classId = me.classes[0]?.id ?? null;
      }
      this.load();
    });
    // A new announcement arrives while the page is open
    this.subs.add(this.school.liveAnnouncement$.subscribe(() => this.load()));
  }

  ngOnDestroy(): void { this.subs.unsubscribe(); }

  load(): void {
    this.school.getAnnouncements().subscribe({
      next: list => {
        this.items = list;
        this.loading = false;
        this.cdr.markForCheck();
        // Parents: what's on screen now counts as read
        if (this.me?.isParent) list.filter(a => !a.isRead).forEach(a =>
          this.school.markAnnouncementRead(a.id).subscribe({ error: () => {} }));
      },
      error: err => {
        this.loading = false;
        this.toast.error('Load Failed', err?.error?.message ?? 'Could not load announcements.');
        this.cdr.markForCheck();
      }
    });
  }

  openCompose(): void {
    this.form = { title: '', body: '', classId: this.me?.isAdmin ? null : (this.classes[0]?.id ?? null) };
    this.file = null;
    this.composeError = '';
    this.showCompose = true;
  }

  onFile(event: Event): void {
    const f = (event.target as HTMLInputElement).files?.[0] ?? null;
    if (f && f.size > 5 * 1024 * 1024) { this.composeError = 'The file must be 5 MB or smaller.'; this.file = null; return; }
    this.composeError = '';
    this.file = f;
  }

  post(): void {
    if (!this.form.title.trim() || !this.form.body.trim()) { this.composeError = 'Write a title and the message.'; return; }
    this.posting = true;
    this.school.createAnnouncement(this.form.title.trim(), this.form.body.trim(), this.form.classId, this.file).subscribe({
      next: r => {
        this.posting = false;
        this.showCompose = false;
        this.toast.success('Announcement Posted', `Sent to ${r.sentTo} parent login${r.sentTo === 1 ? '' : 's'}.`);
        this.load();
      },
      error: err => {
        this.posting = false;
        this.composeError = err?.error?.message ?? 'Could not post.';
        this.cdr.markForCheck();
      }
    });
  }

  openAttachment(a: Announcement): void {
    this.school.openBlob(this.school.announcementAttachment(a.id));
  }

  remove(): void {
    const a = this.confirmDelete;
    this.confirmDelete = null;
    if (!a) return;
    this.school.deleteAnnouncement(a.id).subscribe({
      next: () => { this.toast.success('Deleted', a.title); this.load(); },
      error: err => this.toast.error('Delete Failed', err?.error?.message ?? 'Could not delete.')
    });
  }

  readonly utc = utc;

  audienceName(a: Announcement): string { return a.className ? `Class ${a.className}` : 'All parents'; }
}
