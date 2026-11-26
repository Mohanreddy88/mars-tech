import { Component, OnDestroy, OnInit, ChangeDetectorRef, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterModule } from '@angular/router';
import { HttpEventType } from '@angular/common/http';
import { Subscription } from 'rxjs';
import { SchoolService } from '../../../../core/services/school.service';
import { SchoolExtrasService, Story, StoryMedia } from '../../../../core/services/school-extras.service';
import { ToastService } from '../../../../core/services/toast.service';
import { ConfirmModalComponent } from '../../../../shared/components/confirm-modal/confirm-modal.component';

interface PendingFile { file: File; progress: number; error: string | null; done: boolean; preview: string | null; }

const MAX_PHOTO = 10 * 1024 * 1024;
const MAX_VIDEO = 100 * 1024 * 1024;

/**
 * Class stories — staff (School → Stories): post photos and videos to a class (the office also to
 * the whole school); parents (Parent portal → Stories): view and download them. A story is
 * created as a draft, files are uploaded one by one with progress, then it is published.
 */
@Component({
  selector: 'app-school-stories',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterModule, ConfirmModalComponent],
  templateUrl: './school-stories.component.html',
  styleUrls: ['../../school-shared.scss', './school-stories.component.scss']
})
export class SchoolStoriesComponent implements OnInit, OnDestroy {
  private school = inject(SchoolService);
  private extras = inject(SchoolExtrasService);
  private toast = inject(ToastService);
  private cdr = inject(ChangeDetectorRef);
  private subs = new Subscription();

  isParent = false;
  canPost = false;
  wholeSchool = false;
  classes: { id: number; name: string }[] = [];
  filterClassId: number | null = null;

  stories: Story[] = [];
  loading = true;
  loadingMore = false;
  hasMore = false;
  private readonly pageSize = 10;

  // Composer (new story, or adding to a draft)
  composing = false;
  draftId: number | null = null;
  classId: number | null = null;
  caption = '';
  files: PendingFile[] = [];
  working = false;
  composeError = '';

  // Viewer
  viewing: { story: Story; index: number } | null = null;
  confirmDeleteStory: Story | null = null;

  ngOnInit(): void {
    this.subs.add(this.school.loadMe().subscribe(me => {
      this.isParent = !!me?.isParent;
      if (!this.isParent) {
        this.extras.storyClasses().subscribe({
          next: r => {
            this.classes = r.classes;
            this.wholeSchool = r.wholeSchool;
            this.canPost = r.wholeSchool || r.classes.length > 0;
            this.cdr.markForCheck();
          },
          error: () => {}
        });
      }
      this.load();
    }));
  }

  ngOnDestroy(): void {
    this.subs.unsubscribe();
    this.files.forEach(f => f.preview && URL.revokeObjectURL(f.preview));
  }

  url(m: StoryMedia): string { return this.extras.mediaUrl(m.url); }
  downloadUrl(m: StoryMedia): string { return this.extras.mediaUrl(m.downloadUrl); }
  count(s: Story, kind: 'Photo' | 'Video'): number { return s.media.filter(m => m.kind === kind).length; }

  load(): void {
    this.loading = true;
    this.extras.stories(0, this.pageSize, this.filterClassId).subscribe({
      next: s => { this.stories = s; this.hasMore = s.length === this.pageSize; this.loading = false; this.cdr.markForCheck(); },
      error: err => { this.loading = false; this.toast.error('Load Failed', err?.error?.message ?? 'Could not load stories.'); this.cdr.markForCheck(); }
    });
  }

  more(): void {
    this.loadingMore = true;
    this.extras.stories(this.stories.length, this.pageSize, this.filterClassId).subscribe({
      next: s => { this.stories = [...this.stories, ...s]; this.hasMore = s.length === this.pageSize; this.loadingMore = false; this.cdr.markForCheck(); },
      error: () => { this.loadingMore = false; this.cdr.markForCheck(); }
    });
  }

  // ── Composer ──

  openNew(): void {
    this.draftId = null;
    this.classId = this.classes[0]?.id ?? null;
    this.caption = '';
    this.files = [];
    this.composeError = '';
    this.composing = true;
  }

  /** Continue a draft (add more files, then publish). */
  continueDraft(s: Story): void {
    this.draftId = s.id;
    this.classId = s.classId;
    this.caption = s.caption ?? '';
    this.files = [];
    this.composeError = '';
    this.composing = true;
  }

  closeComposer(): void {
    if (this.working) return;
    this.files.forEach(f => f.preview && URL.revokeObjectURL(f.preview));
    this.composing = false;
    if (this.draftId) this.load();
  }

  pick(input: HTMLInputElement): void {
    for (const file of Array.from(input.files ?? [])) {
      const video = file.type.startsWith('video/');
      const image = file.type.startsWith('image/');
      let error: string | null = null;
      if (!video && !image) error = 'Not a photo or video';
      else if (image && file.size > MAX_PHOTO) error = 'Photo over 10 MB';
      else if (video && file.size > MAX_VIDEO) error = 'Video over 100 MB';
      this.files.push({ file, progress: 0, error, done: false, preview: image && !error ? URL.createObjectURL(file) : null });
    }
    input.value = '';
  }

  removeFile(i: number): void {
    const f = this.files[i];
    if (f.preview) URL.revokeObjectURL(f.preview);
    this.files.splice(i, 1);
  }

  size(bytes: number): string { return bytes >= 1048576 ? (bytes / 1048576).toFixed(1) + ' MB' : Math.max(1, Math.round(bytes / 1024)) + ' KB'; }

  /** Create the draft (once), upload the files not yet uploaded, then publish. */
  async publish(): Promise<void> {
    const toSend = this.files.filter(f => !f.done && !f.error);
    if (!this.draftId && toSend.length === 0) { this.composeError = 'Add at least one photo or video.'; return; }
    if (!this.isParent && this.classId == null && !this.wholeSchool) { this.composeError = 'Choose a class.'; return; }
    this.working = true;
    this.composeError = '';
    try {
      if (!this.draftId) {
        this.draftId = (await this.toPromise(this.extras.createStory(this.classId, this.caption.trim() || null))).id;
      } else {
        await this.toPromise(this.extras.updateStory(this.draftId, this.classId, this.caption.trim() || null));
      }
      for (const f of toSend) await this.upload(this.draftId!, f);
      const failed = this.files.filter(f => f.error && !f.done).length;
      if (failed && this.files.every(f => !f.done)) {
        this.composeError = 'None of the files could be uploaded.';
        return;
      }
      const r = await this.toPromise(this.extras.publishStory(this.draftId!));
      this.toast.success('Story shared', r.sentTo ? `Sent to ${r.sentTo} parent${r.sentTo === 1 ? '' : 's'}.` : 'Published.');
      if (failed) this.toast.warning('Story', `${failed} file${failed === 1 ? '' : 's'} could not be uploaded.`);
      this.files.forEach(f => f.preview && URL.revokeObjectURL(f.preview));
      this.composing = false;
      this.load();
    } catch (err: any) {
      this.composeError = err?.error?.message ?? 'Could not share the story. Press Publish again to retry.';
    } finally {
      this.working = false;
      this.cdr.markForCheck();
    }
  }

  private upload(storyId: number, f: PendingFile): Promise<void> {
    return new Promise(resolve => {
      this.extras.addStoryMedia(storyId, f.file).subscribe({
        next: e => {
          if (e.type === HttpEventType.UploadProgress && e.total) { f.progress = Math.round(100 * e.loaded / e.total); this.cdr.markForCheck(); }
          if (e.type === HttpEventType.Response) { f.done = true; f.progress = 100; this.cdr.markForCheck(); }
        },
        error: err => { f.error = err?.error?.message ?? 'Upload failed'; this.cdr.markForCheck(); resolve(); },
        complete: () => resolve()
      });
    });
  }

  private toPromise<T>(o: import('rxjs').Observable<T>): Promise<T> {
    return new Promise((resolve, reject) => o.subscribe({ next: resolve, error: reject }));
  }

  // ── Viewer ──

  open(story: Story, index: number): void { this.viewing = { story, index }; }
  step(n: number): void {
    if (!this.viewing) return;
    const len = this.viewing.story.media.length;
    this.viewing = { ...this.viewing, index: (this.viewing.index + n + len) % len };
  }
  get current(): StoryMedia | null { return this.viewing ? this.viewing.story.media[this.viewing.index] ?? null : null; }

  deleteMedia(m: StoryMedia): void {
    const v = this.viewing;
    if (!v) return;
    this.extras.deleteStoryMedia(m.id).subscribe({
      next: () => {
        v.story.media = v.story.media.filter(x => x.id !== m.id);
        if (!v.story.media.length) this.viewing = null;
        else this.viewing = { story: v.story, index: Math.min(v.index, v.story.media.length - 1) };
        this.cdr.markForCheck();
      },
      error: err => this.toast.error('Delete', err?.error?.message ?? 'Could not delete.')
    });
  }

  deleteStory(): void {
    const s = this.confirmDeleteStory;
    this.confirmDeleteStory = null;
    if (!s) return;
    this.extras.deleteStory(s.id).subscribe({
      next: () => { this.stories = this.stories.filter(x => x.id !== s.id); this.toast.success('Deleted', 'The story was deleted.'); this.cdr.markForCheck(); },
      error: err => this.toast.error('Delete', err?.error?.message ?? 'Could not delete.')
    });
  }
}
