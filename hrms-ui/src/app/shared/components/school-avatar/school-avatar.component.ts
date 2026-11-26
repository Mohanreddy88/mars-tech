import { Component, Input, OnChanges, ChangeDetectionStrategy, ChangeDetectorRef, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Subscription } from 'rxjs';
import { SchoolExtrasService } from '../../../core/services/school-extras.service';

/**
 * Round profile photo of a child or parent (loaded with the login token), or their initials
 * when there is no photo. `version` is the record's photoUpdatedAt (null = no photo).
 */
@Component({
  selector: 'app-school-avatar',
  standalone: true,
  imports: [CommonModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <span class="avatar" [style.width.px]="size" [style.height.px]="size" [style.font-size.px]="size * 0.4"
          [class.parent]="kind === 'parents'" [attr.title]="name">
      @if (url) { <img [src]="url" [alt]="name" /> } @else { {{ initials }} }
    </span>`,
  styles: [`
    :host { display: inline-flex; flex-shrink: 0; }
    .avatar {
      border-radius: 50%; overflow: hidden; display: inline-flex; align-items: center; justify-content: center;
      background: #dbeafe; color: #1d4ed8; font-weight: 700; letter-spacing: .02em; user-select: none;
    }
    .avatar.parent { background: #fce7f3; color: #be185d; }
    img { width: 100%; height: 100%; object-fit: cover; }
  `]
})
export class SchoolAvatarComponent implements OnChanges {
  private extras = inject(SchoolExtrasService);
  private cdr = inject(ChangeDetectorRef);
  private sub?: Subscription;

  @Input({ required: true }) kind: 'students' | 'parents' = 'students';
  @Input({ required: true }) id = 0;
  @Input() version: string | null | undefined = null;
  @Input() name = '';
  @Input() size = 36;

  url: string | null = null;

  get initials(): string {
    const parts = this.name.trim().split(/\s+/).filter(Boolean);
    return ((parts[0]?.[0] ?? '') + (parts.length > 1 ? parts[parts.length - 1][0] : '')).toUpperCase() || '?';
  }

  ngOnChanges(): void {
    this.sub?.unsubscribe();
    this.url = null;
    this.sub = this.extras.photo(this.kind, this.id, this.version).subscribe(u => { this.url = u; this.cdr.markForCheck(); });
  }
}
