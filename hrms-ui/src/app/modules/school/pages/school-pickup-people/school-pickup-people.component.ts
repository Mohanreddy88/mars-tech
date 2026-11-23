import { Component, OnInit, ChangeDetectorRef, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { SchoolService, PickupPerson } from '../../../../core/services/school.service';
import { ToastService } from '../../../../core/services/toast.service';
import { formatPhone } from '../../../../shared/phone';

/**
 * School → Pick-up People (admin): people the parents added to collect their children. They can
 * collect only once approved here; a rejection's reason is shown to the parent. Same as the app.
 */
@Component({
  selector: 'app-school-pickup-people',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './school-pickup-people.component.html',
  styleUrls: ['../../school-shared.scss']
})
export class SchoolPickupPeopleComponent implements OnInit {
  private school = inject(SchoolService);
  private toast = inject(ToastService);
  private cdr = inject(ChangeDetectorRef);

  readonly phone = formatPhone;

  tab: 'Pending' | 'all' = 'Pending';
  people: PickupPerson[] = [];
  loading = true;
  busy: number | null = null;
  rejecting: PickupPerson | null = null;
  reason = '';

  ngOnInit(): void { this.load(); }

  load(): void {
    this.loading = true;
    this.school.getPickupPeople(this.tab).subscribe({
      next: p => { this.people = p; this.loading = false; this.cdr.markForCheck(); },
      error: err => {
        this.loading = false;
        this.toast.error('Load Failed', err?.error?.message ?? 'Could not load pick-up people.');
        this.cdr.markForCheck();
      }
    });
  }

  show(tab: 'Pending' | 'all'): void { this.tab = tab; this.load(); }

  approve(p: PickupPerson): void {
    this.busy = p.id;
    this.school.approvePickupPerson(p.id).subscribe({
      next: () => { this.busy = null; this.toast.success('Approved', `${p.fullName} may now collect ${p.childName}.`); this.load(); },
      error: err => { this.busy = null; this.toast.error('Approve', err?.error?.message ?? 'Could not approve.'); this.cdr.markForCheck(); }
    });
  }

  startReject(p: PickupPerson): void { this.rejecting = p; this.reason = ''; }

  confirmReject(): void {
    const p = this.rejecting;
    if (!p) return;
    this.busy = p.id;
    this.school.rejectPickupPerson(p.id, this.reason.trim() || null).subscribe({
      next: () => { this.busy = null; this.rejecting = null; this.toast.success('Not approved', `The parent was told.`); this.load(); },
      error: err => { this.busy = null; this.toast.error('Reject', err?.error?.message ?? 'Could not save.'); this.cdr.markForCheck(); }
    });
  }
}
