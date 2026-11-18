import { Component, OnInit, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router } from '@angular/router';
import { FormsModule } from '@angular/forms';
import { UserService } from '../../../../core/services/user.service';
import { ToastService } from '../../../../core/services/toast.service';
import { AppUser, AvailableEmployee } from '../../../../core/models/user.model';
import { ConfirmModalComponent } from '../../../../shared/components/confirm-modal/confirm-modal.component';

/**
 * Master → Users. A login belongs to an employee when both have the same email.
 *   Employee role → pick an employee who has no login yet (same as the automatic login from Employees)
 *   Admin / User  → username + email (HR, office staff)
 * New logins get a "Set my password" email; nobody types a password for someone else.
 */
@Component({
  selector: 'app-user-list',
  standalone: true,
  imports: [CommonModule, FormsModule, ConfirmModalComponent],
  templateUrl: './user-list-component.html',
  styleUrl: './user-list-component.scss'
})
export class UserListComponent implements OnInit {
  users: AppUser[] = [];
  loading = false;
  saving  = false;
  roleOptions = ['Admin', 'Employee', 'User'];
  showModal = false;
  isEdit    = false;
  editId: number | null = null;
  editingLinked: AppUser['employee'] = null;   // employee the edited login belongs to
  modalError = '';
  sendingId: number | null = null;

  availableEmployees: AvailableEmployee[] = [];
  loadingEmployees = false;

  // Confirmation modal state
  showConfirmModal = false;
  confirmModalTitle = '';
  confirmModalMessage = '';
  confirmModalVariant: 'danger' | 'warning' | 'info' = 'danger';
  pendingDeleteUser: AppUser | null = null;

  form = { username: '', email: '', password: '', role: 'Admin', isActive: true, employeeId: null as number | null };

  constructor(
    private userService: UserService,
    private toast: ToastService,
    private cdr: ChangeDetectorRef,
    private router: Router
  ) {}

  ngOnInit(): void { this.loadUsers(); }

  get warningCount(): number { return this.users.filter(u => u.warning).length; }

  get selectedEmployee(): AvailableEmployee | undefined {
    return this.availableEmployees.find(e => e.id === this.form.employeeId);
  }

  loadUsers(): void {
    this.loading = true;
    this.userService.getAll().subscribe({
      next: (data) => { this.users = data; this.loading = false; this.cdr.detectChanges(); },
      error: (err) => {
        if (err.status !== 404) this.toast.error('Load Failed', 'Could not load users.');
        this.loading = false;
        this.cdr.detectChanges();
      }
    });
  }

  openCreate(): void {
    this.isEdit = false; this.editId = null; this.editingLinked = null;
    this.form = { username: '', email: '', password: '', role: 'Admin', isActive: true, employeeId: null };
    this.showModal = true; this.modalError = '';
    this.loadingEmployees = true;
    this.userService.availableEmployees().subscribe({
      next: list => { this.availableEmployees = list; this.loadingEmployees = false; this.cdr.detectChanges(); },
      error: () => { this.availableEmployees = []; this.loadingEmployees = false; this.cdr.detectChanges(); }
    });
  }

  openEdit(u: AppUser): void {
    this.isEdit = true; this.editId = u.id; this.editingLinked = u.employee;
    this.form = { username: u.username, email: u.email, password: '', role: u.role, isActive: u.isActive, employeeId: null };
    this.showModal = true; this.modalError = '';
  }

  closeModal(): void { this.showModal = false; this.modalError = ''; }

  get canSave(): boolean {
    if (this.saving) return false;
    if (!this.isEdit && this.form.role === 'Employee') return this.form.employeeId != null;
    return this.form.username.trim().length >= 3 && this.form.email.includes('@');
  }

  save(): void {
    this.modalError = '';
    this.saving = true;

    if (this.isEdit && this.editId !== null) {
      this.userService.update(this.editId, {
        username: this.form.username.trim(), email: this.form.email.trim(), role: this.form.role,
        isActive: this.form.isActive, password: this.form.password || undefined
      }).subscribe({
        next: () => {
          this.saving = false;
          this.toast.success('User Updated', `${this.form.username} updated.`);
          this.closeModal(); this.loadUsers();
        },
        error: (err: any) => { this.saving = false; this.modalError = err?.error?.message ?? 'Failed to update.'; this.cdr.detectChanges(); }
      });
      return;
    }

    const payload = this.form.role === 'Employee'
      ? { role: 'Employee', employeeId: this.form.employeeId }
      : { role: this.form.role, username: this.form.username.trim(), email: this.form.email.trim() };
    this.userService.create(payload).subscribe({
      next: (res) => {
        this.saving = false;
        if (res.welcomeEmailSent) {
          this.toast.success('Login created', `${res.username}: a "Set my password" link was emailed to ${res.email}.`);
        } else {
          this.toast.warning('Login created, email not sent', `Use the envelope button to send ${res.username} the link again.`);
        }
        this.closeModal(); this.loadUsers();
      },
      error: (err: any) => { this.saving = false; this.modalError = err?.error?.message ?? 'Failed to create.'; this.cdr.detectChanges(); }
    });
  }

  sendLoginEmail(u: AppUser): void {
    this.sendingId = u.id;
    this.userService.sendWelcome(u.id).subscribe({
      next: res => { this.sendingId = null; this.toast.success('Email sent', res.message); this.cdr.detectChanges(); },
      error: err => { this.sendingId = null; this.toast.error('Email not sent', err?.error?.message ?? 'Please try again.'); this.cdr.detectChanges(); }
    });
  }

  deleteUser(u: AppUser): void {
    this.pendingDeleteUser = u;
    this.confirmModalTitle = 'Delete User';
    this.confirmModalMessage = u.employee
      ? `Delete the login "${u.username}"? ${u.employee.name} will no longer be able to sign in. The employee record is kept.`
      : `Are you sure you want to delete user "${u.username}"? This action cannot be undone.`;
    this.confirmModalVariant = 'danger';
    this.showConfirmModal = true;
  }

  onConfirmDelete(): void {
    if (!this.pendingDeleteUser) return;
    this.userService.delete(this.pendingDeleteUser.id).subscribe({
      next: () => {
        this.toast.success('Deleted', `${this.pendingDeleteUser!.username} removed.`);
        this.pendingDeleteUser = null;
        this.loadUsers();
      },
      error: (err: any) => {
        this.toast.error('Delete Failed', err?.error?.message ?? 'Failed.');
        this.pendingDeleteUser = null;
      }
    });
  }

  onCancelDelete(): void { this.pendingDeleteUser = null; }

  getRoleClass(role: string): string {
    if (role === 'Admin') return 'role-admin';
    if (role === 'Employee') return 'role-employee';
    return 'role-user';
  }

  backToHome(): void { this.router.navigate(['/home']); }
}
