import { Component, OnDestroy, OnInit, ChangeDetectorRef, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { SchoolService, SchoolClass } from '../../../../core/services/school.service';
import { ToastService } from '../../../../core/services/toast.service';
import { BANNER_PAGES, BANNER_THEMES, Banner, BannerSave, BannerView, BannersService } from '../../../../core/services/banners.service';
import { BannerCarouselComponent } from '../../../../shared/components/banner-carousel/banner-carousel.component';

/** What the button of the banner opens, in the form. */
type ButtonKind = 'none' | 'page' | 'web';

interface BannerFormState extends BannerSave {
  id: number | null;
  buttonKind: ButtonKind;
  page: string;
  web: string;
  /** The picture shown in the preview (the saved one or the newly chosen file). */
  imageUrl: string | null;
}

/**
 * School → Banners (admins): advert-style slides at the top of the parent home on the website
 * and in the app — "Holiday camp, register now". Colour, picture, a button to a parent page or a
 * web address, for every parent or one class, between dates. Same as the app.
 */
@Component({
  selector: 'app-school-banners',
  standalone: true,
  imports: [CommonModule, FormsModule, BannerCarouselComponent],
  templateUrl: './school-banners.component.html',
  styleUrls: ['../../school-shared.scss', './school-banners.component.scss']
})
export class SchoolBannersComponent implements OnInit, OnDestroy {
  private api = inject(BannersService);
  private school = inject(SchoolService);
  private toast = inject(ToastService);
  private cdr = inject(ChangeDetectorRef);

  readonly themes = BANNER_THEMES;
  readonly pages = BANNER_PAGES;

  banners: Banner[] = [];
  classes: SchoolClass[] = [];
  images: Record<number, string | null> = {};
  loading = true;
  busy = false;
  form: BannerFormState | null = null;
  deleting: Banner | null = null;
  private localUrl: string | null = null;

  ngOnInit(): void {
    this.load();
    this.school.getClasses().subscribe({ next: c => { this.classes = c.filter(x => x.isActive !== false); this.cdr.markForCheck(); }, error: () => {} });
  }

  ngOnDestroy(): void { this.dropLocalUrl(); }

  load(): void {
    this.loading = true;
    this.api.getAll().subscribe({
      next: list => {
        this.banners = list;
        this.loading = false;
        for (const b of list)
          this.api.image(b.id, b.imageVersion).subscribe(u => { this.images[b.id] = u; this.cdr.markForCheck(); });
        this.cdr.markForCheck();
      },
      error: err => {
        this.loading = false;
        this.toast.error('Load Failed', err?.error?.message ?? 'Could not load the banners.');
        this.cdr.markForCheck();
      }
    });
  }

  audience(b: Banner): string { return b.className ? `${b.className} parents` : 'All parents'; }

  linkLabel(b: Banner): string {
    if (!b.link) return '';
    return this.pages.find(p => p.key === b.link)?.label ?? b.link;
  }

  // ── Form ──

  add(): void {
    this.dropLocalUrl();
    this.form = {
      id: null, title: '', text: '', buttonText: '', link: '', theme: 'purple', classId: null,
      startsOn: '', endsOn: '', isActive: true, image: null, removeImage: false,
      buttonKind: 'none', page: 'fees', web: '', imageUrl: null
    };
  }

  edit(b: Banner): void {
    this.dropLocalUrl();
    const web = !!b.link?.startsWith('https://');
    this.form = {
      id: b.id, title: b.title, text: b.text ?? '', buttonText: b.buttonText ?? '', link: b.link ?? '', theme: b.theme,
      classId: b.classId, startsOn: b.startsOn?.substring(0, 10) ?? '', endsOn: b.endsOn?.substring(0, 10) ?? '',
      isActive: b.isActive, image: null, removeImage: false,
      buttonKind: !b.link ? 'none' : web ? 'web' : 'page',
      page: !web && b.link ? b.link : 'fees', web: web ? b.link! : '',
      imageUrl: this.images[b.id] ?? null
    };
  }

  close(): void { this.dropLocalUrl(); this.form = null; }

  /** The form as one banner for the live preview. */
  preview(f: BannerFormState): BannerView[] {
    const link = this.linkOf(f);
    return [{
      id: 0, title: f.title.trim() || 'Your headline', text: f.text.trim() || null,
      buttonText: link ? (f.buttonText.trim() || 'Find out more') : null, link, theme: f.theme, imageUrl: f.imageUrl
    }];
  }

  pickImage(e: Event): void {
    const input = e.target as HTMLInputElement;
    const file = input.files?.[0];
    input.value = '';
    if (!file || !this.form) return;
    if (!/^image\/(jpeg|png)$/.test(file.type)) { this.toast.error('Picture', 'Choose a JPG or PNG picture.'); return; }
    if (file.size > 3 * 1024 * 1024) { this.toast.error('Picture', 'The picture must be 3 MB or smaller.'); return; }
    this.dropLocalUrl();
    this.localUrl = URL.createObjectURL(file);
    this.form.image = file;
    this.form.removeImage = false;
    this.form.imageUrl = this.localUrl;
  }

  removeImage(): void {
    if (!this.form) return;
    this.dropLocalUrl();
    this.form.image = null;
    this.form.removeImage = true;
    this.form.imageUrl = null;
  }

  save(): void {
    const f = this.form;
    if (!f) return;
    if (!f.title.trim()) { this.toast.error('Banner', 'Enter a headline.'); return; }
    if (f.buttonKind === 'web' && !f.web.trim().startsWith('https://')) {
      this.toast.error('Banner', 'The web address must start with https://'); return;
    }
    const link = this.linkOf(f) ?? '';
    this.busy = true;
    this.api.save(f.id, { ...f, link, buttonText: link ? f.buttonText : '' }).subscribe({
      next: () => {
        this.busy = false;
        this.toast.success('Saved', f.id ? 'The banner was updated.' : 'The banner was added.');
        this.close();
        this.load();
      },
      error: err => { this.busy = false; this.toast.error('Banner', err?.error?.message ?? 'Could not save.'); this.cdr.markForCheck(); }
    });
  }

  // ── List actions ──

  move(b: Banner, up: boolean): void {
    this.api.move(b.id, up).subscribe({ next: () => this.load(), error: () => this.toast.error('Banner', 'Could not move it.') });
  }

  toggle(b: Banner): void {
    this.api.save(b.id, {
      title: b.title, text: b.text ?? '', buttonText: b.buttonText ?? '', link: b.link ?? '', theme: b.theme,
      classId: b.classId, startsOn: b.startsOn?.substring(0, 10) ?? '', endsOn: b.endsOn?.substring(0, 10) ?? '',
      isActive: !b.isActive, image: null, removeImage: false
    }).subscribe({
      next: () => { this.toast.success(b.isActive ? 'Switched off' : 'Switched on', `"${b.title}"`); this.load(); },
      error: err => this.toast.error('Banner', err?.error?.message ?? 'Could not save.')
    });
  }

  confirmDelete(): void {
    const b = this.deleting;
    if (!b) return;
    this.busy = true;
    this.api.delete(b.id).subscribe({
      next: () => { this.busy = false; this.deleting = null; this.toast.success('Deleted', `"${b.title}" was deleted.`); this.load(); },
      error: err => { this.busy = false; this.toast.error('Delete', err?.error?.message ?? 'Could not delete.'); this.cdr.markForCheck(); }
    });
  }

  private linkOf(f: BannerFormState): string | null {
    if (f.buttonKind === 'page') return f.page;
    if (f.buttonKind === 'web') return f.web.trim() || null;
    return null;
  }

  private dropLocalUrl(): void {
    if (this.localUrl) URL.revokeObjectURL(this.localUrl);
    this.localUrl = null;
  }
}
