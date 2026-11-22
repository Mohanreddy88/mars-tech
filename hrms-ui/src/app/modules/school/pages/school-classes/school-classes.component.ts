import { Component, OnInit, ChangeDetectorRef, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterModule } from '@angular/router';
import { SchoolService, SchoolClass } from '../../../../core/services/school.service';
import { EmployeeService } from '../../../../core/services/employee.service';
import { ToastService } from '../../../../core/services/toast.service';
import { ConfirmModalComponent } from '../../../../shared/components/confirm-modal/confirm-modal.component';

/** School → Classes (admin): PG, N1, N2, K1, K2 … and each class's teacher. */
@Component({
  selector: 'app-school-classes',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterModule, ConfirmModalComponent],
  templateUrl: './school-classes.component.html',
  styleUrls: ['../../school-shared.scss']
})
export class SchoolClassesComponent implements OnInit {
  private school = inject(SchoolService);
  private employees = inject(EmployeeService);
  private toast = inject(ToastService);
  private cdr = inject(ChangeDetectorRef);

  classes: SchoolClass[] = [];
  teachers: { id: number; name: string }[] = [];
  loading = true;

  showModal = false;
  editId: number | null = null;
  saving = false;
  modalError = '';
  form = this.blank();

  confirmDelete: SchoolClass | null = null;

  ngOnInit(): void {
    this.load();
    this.employees.getAll().subscribe({
      next: (list: any) => {
        const items: any[] = Array.isArray(list) ? list : (list?.items ?? list?.data ?? []);
        this.teachers = items.filter(e => e.isActive !== false)
          .map(e => ({ id: e.id, name: e.name }))
          .sort((a, b) => a.name.localeCompare(b.name));
        this.cdr.markForCheck();
      },
      error: () => {}
    });
  }

  load(): void {
    this.loading = true;
    this.school.getClasses().subscribe({
      next: c => { this.classes = c; this.loading = false; this.cdr.markForCheck(); },
      error: err => {
        this.loading = false;
        this.toast.error('Load Failed', err?.error?.message ?? 'Could not load classes.');
        this.cdr.markForCheck();
      }
    });
  }

  blank() { return { name: '', description: '', classTeacherId: null as number | null, sortOrder: 0, isActive: true }; }

  openCreate(): void {
    this.editId = null;
    this.form = this.blank();
    this.form.sortOrder = (this.classes.reduce((m, c) => Math.max(m, c.sortOrder), 0) || 0) + 1;
    this.modalError = '';
    this.showModal = true;
  }

  openEdit(c: SchoolClass): void {
    this.editId = c.id;
    this.form = { name: c.name, description: c.description ?? '', classTeacherId: c.classTeacherId, sortOrder: c.sortOrder, isActive: c.isActive };
    this.modalError = '';
    this.showModal = true;
  }

  save(): void {
    if (!this.form.name.trim()) { this.modalError = 'Enter the class name.'; return; }
    this.saving = true;
    const body = { ...this.form, name: this.form.name.trim(), classTeacherId: this.form.classTeacherId || null };
    const req = this.editId ? this.school.updateClass(this.editId, body) : this.school.createClass(body);
    req.subscribe({
      next: () => {
        this.saving = false;
        this.showModal = false;
        this.toast.success(this.editId ? 'Class Updated' : 'Class Added', body.name);
        this.load();
        this.school.loadMe(true).subscribe();   // the class teacher's menu may change
      },
      error: err => {
        this.saving = false;
        this.modalError = err?.error?.message ?? 'Could not save the class.';
        this.cdr.markForCheck();
      }
    });
  }

  remove(): void {
    const c = this.confirmDelete;
    this.confirmDelete = null;
    if (!c) return;
    this.school.deleteClass(c.id).subscribe({
      next: () => { this.toast.success('Deleted', `${c.name} was removed.`); this.load(); },
      error: err => this.toast.error('Delete Failed', err?.error?.message ?? 'Could not delete the class.')
    });
  }
}
