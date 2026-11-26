import { Component, EventEmitter, Input, Output, ChangeDetectorRef, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { SchoolExtrasService } from '../../../core/services/school-extras.service';
import { ToastService } from '../../../core/services/toast.service';
import { SchoolAvatarComponent } from './school-avatar.component';

/**
 * Profile photo with "Change photo" / "Remove" for a child or parent (used in the admin forms and
 * the parent portal). Emits the new photoUpdatedAt (null when removed) so the list can refresh.
 */
@Component({
  selector: 'app-photo-picker',
  standalone: true,
  imports: [CommonModule, SchoolAvatarComponent],
  template: `
    <div class="photo-picker">
      <app-school-avatar [kind]="kind" [id]="id" [version]="version" [name]="name" [size]="size" />
      <div class="actions">
        <label class="btn btn-sm btn-outline-primary mb-0" [class.disabled]="busy">
          @if (busy) { <span class="spinner-border spinner-border-sm me-1"></span> }
          <i class="bi bi-camera"></i> {{ version ? 'Change photo' : 'Add photo' }}
          <input type="file" accept="image/jpeg,image/png" hidden (change)="pick($any($event.target))" [disabled]="busy" />
        </label>
        @if (version) {
          <button type="button" class="btn btn-sm btn-link text-danger" (click)="remove()" [disabled]="busy">Remove</button>
        }
        <div class="hint">JPG or PNG, up to 5 MB.</div>
      </div>
    </div>`,
  styles: [`
    .photo-picker { display: flex; align-items: center; gap: 14px; }
    .actions { display: flex; flex-wrap: wrap; align-items: center; gap: 4px; }
    .hint { width: 100%; font-size: 12px; color: #6b7280; }
  `]
})
export class PhotoPickerComponent {
  private extras = inject(SchoolExtrasService);
  private toast = inject(ToastService);
  private cdr = inject(ChangeDetectorRef);

  @Input({ required: true }) kind: 'students' | 'parents' = 'students';
  @Input({ required: true }) id = 0;
  @Input() version: string | null | undefined = null;
  @Input() name = '';
  @Input() size = 72;
  @Output() changed = new EventEmitter<string | null>();

  busy = false;

  pick(input: HTMLInputElement): void {
    const file = input.files?.[0];
    input.value = '';
    if (!file) return;
    if (file.size > 5 * 1024 * 1024) { this.toast.error('Photo', 'The photo must be 5 MB or smaller.'); return; }
    this.busy = true;
    this.extras.setPhoto(this.kind, this.id, file).subscribe({
      next: r => { this.busy = false; this.version = r.photoUpdatedAt; this.changed.emit(r.photoUpdatedAt); this.cdr.markForCheck(); },
      error: err => { this.busy = false; this.toast.error('Photo', err?.error?.message ?? 'Could not save the photo.'); this.cdr.markForCheck(); }
    });
  }

  remove(): void {
    this.busy = true;
    this.extras.deletePhoto(this.kind, this.id).subscribe({
      next: () => { this.busy = false; this.version = null; this.changed.emit(null); this.cdr.markForCheck(); },
      error: err => { this.busy = false; this.toast.error('Photo', err?.error?.message ?? 'Could not remove the photo.'); this.cdr.markForCheck(); }
    });
  }
}
