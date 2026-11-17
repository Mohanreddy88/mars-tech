import { Component, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { AuthService } from '../../../core/services/auth.service';

/** Login for the Super Admin portal (admin.marshrms.com). Company users log in on their own address. */
@Component({
  selector: 'app-platform-login',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './platform-login.component.html',
  styleUrl: './platform-login.component.scss'
})
export class PlatformLoginComponent {
  username = '';
  password = '';
  loading = false;
  error = '';

  constructor(private auth: AuthService, private router: Router, private cdr: ChangeDetectorRef) {
    if (auth.isAuthenticated() && auth.getRole() === 'SuperAdmin') this.router.navigate(['/']);
  }

  submit(): void {
    if (!this.username.trim() || !this.password) { this.error = 'Enter your username and password.'; return; }
    this.loading = true;
    this.error = '';
    this.auth.loginPlatform({ username: this.username.trim(), password: this.password }).subscribe({
      next: () => { this.loading = false; this.router.navigate(['/']); },
      error: err => {
        this.loading = false;
        this.error = err?.status === 429
          ? 'Too many attempts. Wait a minute and try again.'
          : err?.error?.message ?? 'Could not log in. Please try again.';
        this.cdr.detectChanges();
      }
    });
  }
}
