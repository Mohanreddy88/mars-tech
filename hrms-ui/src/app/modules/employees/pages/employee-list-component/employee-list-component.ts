import { Component, OnInit, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router, RouterLink } from '@angular/router';
import { EmployeeService } from '../../../../core/services/employee.service';
import { AuthService } from '../../../../core/services/auth.service';
import { ToastService } from '../../../../core/services/toast.service';
import { Employee } from '../../../../core/models/employee.model';
import { ConfirmModalComponent } from '../../../../shared/components/confirm-modal/confirm-modal.component';
import { photoUrl } from '../../../../core/utils/photo-url';

@Component({
  selector: 'app-employee-list',
  standalone: true,
  imports: [CommonModule, ConfirmModalComponent, RouterLink],
  templateUrl: './employee-list-component.html',
  styleUrl: './employee-list-component.scss'
})
export class EmployeeListComponent implements OnInit {
  employees: Employee[] = [];
  loading = false;
  isAdmin = false;

  // Confirmation modal state
  showConfirmModal = false;
  confirmModalTitle = '';
  confirmModalMessage = '';
  confirmModalVariant: 'danger' | 'warning' | 'info' = 'danger';
  pendingDeleteId: number | null = null;
  pendingDeleteName = '';
  sendingId: number | null = null;   // employee whose login email is being sent
  readonly photoUrl = photoUrl;   // uploaded photo → browser address

  constructor(
    private employeeService: EmployeeService,
    private authService: AuthService,
    private router: Router,
    private toast: ToastService,
    private cdr: ChangeDetectorRef
  ) {}

  ngOnInit(): void {
    this.isAdmin = this.authService.isAdmin();
    this.loadEmployees();
  }

  loadEmployees(): void {
    this.loading = true;
    // Admin sees all records (active + inactive), User sees only their own
    this.employeeService.getAll(this.isAdmin).subscribe({
      next: (data) => {
        this.employees = data;
        this.loading = false;
        this.cdr.detectChanges();
      },
      error: (err) => {
        // Only show error toast for actual server errors
        // 404 = Not Found (empty data) - don't show error
        // 200 with empty array = Success with no data - don't show error
        if (err.status && err.status !== 404 && err.status !== 204) {
          const errorMsg = err?.error?.message || err?.message || 'Could not load employees.';
          this.toast.error('Load Failed', errorMsg);
        }
        // Always set loading to false and show empty state
        this.employees = [];
        this.loading = false;
        this.cdr.detectChanges();
      }
    });
  }

  addEmployee(): void { this.router.navigate(['/employees/add']); }
  editEmployee(id: number): void { this.router.navigate(['/employees/edit', id]); }

  /** Email the employee a "Set my password" link (new login if they have none). */
  sendLoginEmail(emp: Employee): void {
    if (!emp.email) { this.toast.warning('No email', `${emp.name} has no email address.`); return; }
    this.sendingId = emp.id;
    this.employeeService.sendWelcome(emp.id).subscribe({
      next: res => {
        this.sendingId = null;
        this.toast.success('Login email sent', `Username ${res.username}. A "Set my password" link was emailed to ${res.email}.`);
        this.cdr.detectChanges();
      },
      error: err => {
        this.sendingId = null;
        this.toast.error('Login email not sent', err?.error?.message ?? 'Please try again.');
        this.cdr.detectChanges();
      }
    });
  }

  deleteEmployee(id: number, name: string): void {
    this.pendingDeleteId = id;
    this.pendingDeleteName = name;
    this.confirmModalTitle = 'Delete Employee';
    this.confirmModalMessage = `Are you sure you want to delete "${name}"? This action cannot be undone.`;
    this.confirmModalVariant = 'danger';
    this.showConfirmModal = true;
  }

  onConfirmDelete(): void {
    if (!this.pendingDeleteId) return;
    this.employeeService.delete(this.pendingDeleteId).subscribe({
      next: () => {
        this.toast.success('Employee Deleted', `${this.pendingDeleteName} has been removed.`);
        this.pendingDeleteId = null;
        this.pendingDeleteName = '';
        this.loadEmployees();
      },
      error: (err: any) => {
        this.toast.error('Delete Failed', err?.error?.message ?? 'Failed to delete.');
        this.pendingDeleteId = null;
        this.pendingDeleteName = '';
      }
    });
  }

  onCancelDelete(): void {
    this.pendingDeleteId = null;
    this.pendingDeleteName = '';
  }
}
