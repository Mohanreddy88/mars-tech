import { Component, OnInit, ChangeDetectorRef } from '@angular/core';
import { Router, RouterModule } from '@angular/router';
import { CommonModule } from '@angular/common';
import { HttpClient } from '@angular/common/http';
import { AuthService } from '../../../../core/services/auth.service';
import { environment } from '../../../../../environments/environment';
import { photoUrl } from '../../../../core/utils/photo-url';

/** A birthday on the Home page (day and month only — no year or age). */
interface BirthdayItem {
  id: number;
  name: string;
  employeeCode: string;
  profilePicture: string | null;
  department: string | null;
  birthday: string;        // e.g. "10 Dec"
  daysUntil?: number;      // upcoming: 0 = today
  daysAgo?: number;        // recent
}

@Component({
  selector: 'app-home-component',
  standalone: true,
  imports: [RouterModule, CommonModule],
  templateUrl: './home-component.html',
  styleUrl: './home-component.scss',
})
export class HomeComponent implements OnInit {
  currentYear = new Date().getFullYear();

  /** Birthdays from employees' Date of Birth: next 30 days and last 7 days. */
  upcoming: BirthdayItem[] = [];
  recent: BirthdayItem[] = [];
  employeesWithDob = 0;
  birthdaysLoaded = false;
  readonly photoUrl = photoUrl;

  constructor(
    private authService: AuthService,
    private router: Router,
    private http: HttpClient,
    private cdr: ChangeDetectorRef
  ) {}

  ngOnInit(): void {
    // Redirect employees to their dashboard, only admins see home
    const user = this.authService.getUser();
    if (user?.role !== 'Admin') {
      this.router.navigate(['/self-service/dashboard']);
      return;
    }
    this.http.get<{ upcoming: BirthdayItem[]; recent: BirthdayItem[]; employeesWithDob: number }>(
      `${environment.apiUrl}/dashboard/birthdays`
    ).subscribe({
      next: r => {
        this.upcoming = r.upcoming.slice(0, 5);
        this.recent = r.recent.slice(0, 5);
        this.employeesWithDob = r.employeesWithDob;
        this.birthdaysLoaded = true;
        this.cdr.detectChanges();
      },
      error: () => { this.birthdaysLoaded = true; this.cdr.detectChanges(); }
    });
  }

  upcomingLabel(b: BirthdayItem): string {
    return b.daysUntil === 0 ? 'Today 🎉' : b.daysUntil === 1 ? 'Tomorrow' : `+${b.daysUntil} days`;
  }

  recentLabel(b: BirthdayItem): string {
    return b.daysAgo === 1 ? 'Yesterday' : `${b.daysAgo} days ago`;
  }

  initial(name: string): string { return (name || '?').charAt(0).toUpperCase(); }
}
