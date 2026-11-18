import { Component } from '@angular/core';
import { RouterLink } from '@angular/router';

/** Public page (no login): how MarsHRMS handles personal data. Linked from the app footer. */
@Component({
  selector: 'app-privacy-policy',
  standalone: true,
  imports: [RouterLink],
  styleUrl: './legal-page.scss',
  template: `
<div class="legal">
  <div class="legal-top">
    <a class="brand" routerLink="/">Mars<span>HRMS</span></a>
    <a class="other" routerLink="/terms">Terms of Use</a>
  </div>

  <article class="card">
    <h1>Privacy Policy</h1>
    <p class="updated">Last updated: 18 November 2026</p>

    <p>
      MarsHRMS is an HR and payroll system used by employers. This policy explains what personal data
      the system holds, why, and how it is protected. Your employer decides what data is entered and is
      responsible for it under Malaysia's Personal Data Protection Act 2010 (PDPA); MarsHRMS processes
      that data on your employer's behalf.
    </p>

    <h2>1. Data we hold</h2>
    <ul>
      <li>Identity: name, NRIC or passport number, date of birth, gender, profile photo</li>
      <li>Contact: email address and mobile number</li>
      <li>Employment: employee code, department, designation, join date, salary</li>
      <li>Payment and tax: bank and account number, tax identification number (TIN)</li>
      <li>Work records: timesheets, attendance, leave requests and balances</li>
      <li>Payroll: payslips, allowances, deductions, EPF, SOCSO, EIS and PCB amounts, EA forms</li>
      <li>Account: username, role, and a record of actions taken in the system</li>
    </ul>

    <h2>2. Why we use it</h2>
    <p>
      Only to run HR and payroll for your employer: recording attendance and leave, calculating salaries
      and statutory contributions, producing payslips and EA forms, paying salaries, and sending account
      emails such as password resets.
    </p>

    <h2>3. How it is protected</h2>
    <ul>
      <li>Each company's data is kept in its own separate database.</li>
      <li>All connections use encrypted HTTPS.</li>
      <li>Passwords are stored only in hashed form and cannot be read by anyone.</li>
      <li>Access depends on role: employees see only their own records; HR administrators manage their company.</li>
      <li>Important actions are recorded in an audit log.</li>
      <li>Sessions sign out automatically after a period of inactivity.</li>
    </ul>

    <h2>4. Sharing</h2>
    <p>
      Personal data is not sold. It is shared only with your employer, with service providers needed to
      run the system (for example, to deliver email), and where the law requires it.
    </p>

    <h2>5. Keeping and backing up data</h2>
    <p>
      Data is kept while your employer uses MarsHRMS, and for as long as employment and tax laws require.
      Backups are made every night and kept for 14 days so data can be restored after a problem.
    </p>

    <h2>6. Your rights</h2>
    <p>
      You may ask to see or correct your personal data. You can update your contact details under
      <strong>My Profile</strong>, or contact your employer's HR department. For other requests or questions,
      email <a href="mailto:support@marstech.tech">support&#64;marstech.tech</a>.
    </p>

    <h2>7. Changes to this policy</h2>
    <p>If this policy changes, the new version will be published on this page with a new date.</p>
  </article>
</div>
`
})
export class PrivacyPolicyComponent {}
