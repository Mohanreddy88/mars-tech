import { Component } from '@angular/core';
import { RouterLink } from '@angular/router';

/** Public page (no login): terms for using MarsHRMS. Linked from the app footer. */
@Component({
  selector: 'app-terms-of-use',
  standalone: true,
  imports: [RouterLink],
  styleUrl: './legal-page.scss',
  template: `
<div class="legal">
  <div class="legal-top">
    <a class="brand" routerLink="/">Mars<span>HRMS</span></a>
    <a class="other" routerLink="/privacy">Privacy Policy</a>
  </div>

  <article class="card">
    <h1>Terms of Use</h1>
    <p class="updated">Last updated: 18 November 2026</p>

    <p>
      These terms apply to everyone who signs in to MarsHRMS, the HR and payroll system provided to your
      employer. By using it, you agree to them.
    </p>

    <h2>1. Your account</h2>
    <ul>
      <li>Use only the account given to you, and keep your password private.</li>
      <li>Do not share your login with anyone, including colleagues.</li>
      <li>Tell your HR department straight away if you think someone else has used your account.</li>
    </ul>

    <h2>2. Acceptable use</h2>
    <ul>
      <li>Use MarsHRMS only for your work and your employer's HR and payroll purposes.</li>
      <li>Do not try to access data you are not allowed to see, or to get around security controls.</li>
      <li>Do not upload unlawful, harmful or misleading content.</li>
    </ul>

    <h2>3. Accuracy of information</h2>
    <p>
      Enter correct information in timesheets, leave requests and your profile. Your employer is
      responsible for the data it enters, for the statutory rates it sets (EPF, SOCSO, EIS and PCB), and for
      checking payroll results before salaries are paid or statutory returns are filed.
    </p>

    <h2>4. Availability</h2>
    <p>
      We aim to keep MarsHRMS available at all times. It may occasionally be unavailable for maintenance
      or updates. Data is backed up every night.
    </p>

    <h2>5. Responsibility</h2>
    <p>
      MarsHRMS supports your employer's HR and payroll work. Employment decisions, salary payments and
      statutory submissions remain the responsibility of your employer.
    </p>

    <h2>6. Privacy</h2>
    <p>How personal data is handled is explained in the <a routerLink="/privacy">Privacy Policy</a>.</p>

    <h2>7. Changes and contact</h2>
    <p>
      If these terms change, the new version will be published on this page with a new date. Questions:
      <a href="mailto:support@marstech.tech">support&#64;marstech.tech</a>.
    </p>
  </article>
</div>
`
})
export class TermsOfUseComponent {}
