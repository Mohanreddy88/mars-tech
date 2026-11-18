import { Component, OnInit, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormBuilder, FormGroup, ReactiveFormsModule, Validators, AbstractControl, ValidationErrors } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';

import { EmployeeService, EmployeeCreateResult } from '../../../../core/services/employee.service';
import { DepartmentService, Department } from '../../../../core/services/department.service';
import { BankService } from '../../../../core/services/bank.service';
import { ToastService } from '../../../../core/services/toast.service';
import { Bank } from '../../../../core/models/bank.model';
import { IdType } from '../../../../core/models/employee.model';
import { COUNTRIES_SORTED, DIAL_CODES } from '../../../../core/data/countries';
import { photoUrl } from '../../../../core/utils/photo-url';

/** NRIC: exactly 12 digits. Passport: 8–10 letters or digits. Mobile: 7–12 digits. */
const NRIC_PATTERN     = /^\d{12}$/;
const PASSPORT_PATTERN = /^[A-Za-z0-9]{8,10}$/;
const MOBILE_PATTERN   = /^\d{7,12}$/;
const MIN_AGE          = 15;   // minimum working age in Malaysia (same rule as the API)

/** yyyy-mm-dd of a Date in local time, for <input type="date">. */
function isoDate(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

/** Date of birth: not in the future, at least MIN_AGE years old, not more than 100 years ago. */
function dobValidator(c: AbstractControl): ValidationErrors | null {
  if (!c.value) return null;   // "required" handles an empty value
  const dob = new Date(c.value + 'T00:00:00');
  if (isNaN(dob.getTime())) return { dob: 'Enter a valid date' };
  const today = new Date(); today.setHours(0, 0, 0, 0);
  if (dob > today) return { dob: "Date of birth can't be in the future" };
  const youngest = new Date(today); youngest.setFullYear(today.getFullYear() - MIN_AGE);
  if (dob > youngest) return { dob: `Employee must be at least ${MIN_AGE} years old` };
  const oldest = new Date(today); oldest.setFullYear(today.getFullYear() - 100);
  if (dob < oldest) return { dob: 'Check the date of birth (over 100 years ago)' };
  return null;
}

/** Birth date from a Malaysian NRIC (YYMMDD…), or null if the first 6 digits are not a real date. */
function dobFromNric(nric: string): string | null {
  if (!/^\d{12}$/.test(nric)) return null;
  const yy = +nric.slice(0, 2), mm = +nric.slice(2, 4), dd = +nric.slice(4, 6);
  const nowYY = new Date().getFullYear() % 100;
  const year = yy > nowYY ? 1900 + yy : 2000 + yy;   // e.g. 90 → 1990, 05 → 2005
  const d = new Date(year, mm - 1, dd);
  if (d.getFullYear() !== year || d.getMonth() !== mm - 1 || d.getDate() !== dd) return null;
  return isoDate(d);
}

/**
 * EmployeeFormComponent — handles both Add and Edit employee workflows.
 *
 * - On /employees/add  → creates a new employee
 * - On /employees/edit/:id → loads existing employee and updates it
 *
 * New fields: IcPassport, TaxNumber, BankId (dropdown), AccountNumber
 */
@Component({
  selector: 'app-employee-form-component',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule],
  templateUrl: './employee-form-component.html',
  styleUrls: ['./employee-form-component.scss']
})
export class EmployeeFormComponent implements OnInit {

  form!: FormGroup;
  isEdit    = false;
  employeeId: number | null = null;
  loading   = false;   // true while loading employee data for edit
  saving    = false;   // true while the save API call is in flight
  departments: Department[] = [];  // populated from Department master for the dropdown
  banks: Bank[] = [];  // populated from BankMaster for the dropdown
  uploading = false;   // true while uploading profile picture
  profilePictureUrl: string | null = null;  // Preview URL for uploaded image
  readonly countries = COUNTRIES_SORTED;   // passport country dropdown
  readonly dialCodes = DIAL_CODES;         // mobile country code dropdown

  constructor(
    private fb: FormBuilder,
    private route: ActivatedRoute,
    private router: Router,
    private employeeService: EmployeeService,
    private departmentService: DepartmentService,
    private bankService: BankService,
    private toast: ToastService,
    private cdr: ChangeDetectorRef
  ) {}

  ngOnInit(): void {
    // Build the reactive form with all fields including new ones
    this.form = this.fb.group({
      name:           ['', [Validators.required]],
      email:          ['', [Validators.required, Validators.email]],
      phoneCountryCode: ['+60', [Validators.required]],
      phone:          ['', [Validators.required, Validators.pattern(MOBILE_PATTERN)]],
      departmentId:   [null, [Validators.required]],  // Changed to departmentId FK
      designation:    ['', [Validators.required]],
      joinDate:       ['', [Validators.required]],
      salary:         [0,  [Validators.required, Validators.min(0)]],
      isActive:       [true],
      idType:         ['NRIC' as IdType, [Validators.required]],
      icPassport:     [''],    // NRIC or passport number — rules set by applyIdType()
      idCountry:      [{ value: 'Malaysia', disabled: true }],
      dateOfBirth:    ['', [Validators.required, dobValidator]],
      taxNumber:      [''],    // Tax Identification Number
      bankId:         [null],  // FK to BankMaster
      accountNumber:  [''],    // Bank account number
      profilePicture: [''],    // Profile picture URL/path
      gender:         ['']     // Male / Female / Other
    });

    // NRIC ↔ Passport: switch the number rules and the country field
    this.applyIdType('NRIC');
    this.form.get('idType')!.valueChanges.subscribe((type: IdType) => {
      this.form.patchValue({ icPassport: '' }, { emitEvent: false });   // formats differ — start again
      this.applyIdType(type, true);
    });

    // Load active departments and banks for the dropdowns regardless of add/edit mode
    this.loadDepartments();
    this.loadBanks();

    // Determine if this is an edit operation by checking route params
    const id = this.route.snapshot.paramMap.get('id');
    if (id) {
      this.isEdit    = true;
      this.employeeId = Number(id);
      this.loadEmployee(this.employeeId);
    }
  }

  /** Convenience getter for easy template access to form controls */
  get f() { return this.form.controls; }

  /**
   * Loads the active department list from the API.
   * Used to populate the Department dropdown in the form.
   */
  loadDepartments(): void {
    this.departmentService.getActive().subscribe({
      next:  (data) => { this.departments = data; this.cdr.detectChanges(); },
      error: ()     => { this.toast.warning('Departments', 'Could not load department list.'); }
    });
  }

  /**
   * Loads the active bank list from the API.
   * Used to populate the Bank dropdown in the form.
   */
  loadBanks(): void {
    this.bankService.getActive().subscribe({
      next:  (data) => { this.banks = data; this.cdr.detectChanges(); },
      error: ()     => { this.toast.warning('Banks', 'Could not load bank list.'); }
    });
  }

  /**
   * Loads an existing employee by ID and patches the form values.
   * Only called in edit mode.
   */
  loadEmployee(id: number): void {
    this.loading = true;
    this.employeeService.getById(id).subscribe({
      next: (emp) => {
        // Patch all form fields from the API response
        this.form.patchValue({
          ...emp,
          // API returns ISO datetime — strip time part for the date input
          joinDate:       emp.joinDate ? emp.joinDate.split('T')[0] : '',
          dateOfBirth:    emp.dateOfBirth ? emp.dateOfBirth.split('T')[0] : '',
          // Ensure null FKs are handled correctly
          departmentId:   emp.departmentId ?? null,
          bankId:         emp.bankId ?? null,
          profilePicture: emp.profilePicture ?? '',
          gender:         emp.gender ?? '',
          idType:         emp.idType || 'NRIC',
          phoneCountryCode: emp.phoneCountryCode || '+60'
        }, { emitEvent: false });
        this.applyIdType(emp.idType || 'NRIC');
        if (emp.idType === 'Passport') this.form.get('idCountry')!.setValue(emp.idCountry ?? '');
        // Set preview URL for existing profile picture
        this.profilePictureUrl = photoUrl(emp.profilePicture);
        this.loading = false;
        this.cdr.detectChanges(); // force view to re-render with loaded data
      },
      error: () => {
        this.toast.error('Load Failed', 'Could not load employee data.');
        this.loading = false;
        this.cdr.detectChanges();
      }
    });
  }

  /**
   * Submits the form — creates or updates depending on isEdit flag.
   * Shows a toast on success or failure.
   */
  onSubmit(): void {
    if (this.form.invalid) {
      // Mark all fields touched so validation messages appear
      this.form.markAllAsTouched();
      this.toast.warning('Validation Error', 'Please fill all required fields correctly.');
      return;
    }

    this.saving = true;

    const raw = this.form.getRawValue();   // includes the disabled country field

    // Build strongly-typed payload matching EmployeeRequest on the API
    const payload = {
      name:           raw.name,
      email:          raw.email,
      phone:          raw.phone,
      phoneCountryCode: raw.phoneCountryCode ?? '+60',
      idType:         raw.idType,
      idCountry:      raw.idCountry ?? '',
      dateOfBirth:    raw.dateOfBirth || null,
      departmentId:   raw.departmentId   ?? null,  // Changed to departmentId
      designation:    raw.designation,
      joinDate:       raw.joinDate,
      salary:         +raw.salary,
      isActive:       raw.isActive,
      icPassport:     raw.icPassport     ?? '',
      taxNumber:      raw.taxNumber      ?? '',
      bankId:         raw.bankId         ?? null,
      accountNumber:  raw.accountNumber  ?? '',
      profilePicture: raw.profilePicture ?? '',
      gender:         raw.gender         ?? ''
    };

    // Shared success/error handlers
    const onSuccess = (res?: EmployeeCreateResult | void) => {
      this.saving = false;
      const action = this.isEdit ? 'Updated' : 'Created';
      this.toast.success(`Employee ${action}`, `${raw.name} has been ${action.toLowerCase()} successfully.`);
      if (res && res.userCreated) {
        if (res.welcomeEmailSent) {
          this.toast.success('Login email sent', `Username ${res.username}. A "Set my password" link was emailed to ${res.email}.`);
        } else {
          this.toast.warning('Login email not sent', `Username ${res.username}. Use the envelope button in the employee list to send it again.`);
        }
      } else if (res && res.userAlreadyExists) {
        this.toast.info('Existing login', `${res.email} already has a login, so no new account was created.`);
      }
      this.router.navigate(['/employees']);
    };
    const onError = (err: any) => {
      this.saving = false;
      // Show the server's field message under that field too
      const field = err?.error?.field as string | undefined;
      if (field && this.form.get(field)) {
        this.form.get(field)!.setErrors({ server: err.error.message });
        this.form.get(field)!.markAsTouched();
        this.cdr.detectChanges();
      }
      this.toast.error('Save Failed', err?.error?.message ?? 'Failed to save employee.');
    };

    // Use if/else instead of ternary to avoid Observable union type mismatch
    if (this.isEdit && this.employeeId) {
      this.employeeService.update(this.employeeId, payload)
        .subscribe({ next: onSuccess, error: onError });
    } else {
      this.employeeService.create(payload)
        .subscribe({ next: onSuccess, error: onError });
    }
  }

  // ── Identification (NRIC / Passport) and mobile ─────────────────

  get isPassport(): boolean { return this.form.get('idType')!.value === 'Passport'; }

  /**
   * NRIC     → 12 digits, country fixed to Malaysia (field disabled)
   * Passport → 8–10 letters/digits, country dropdown enabled and required
   */
  applyIdType(type: IdType, userChanged = false): void {
    const id      = this.form.get('icPassport')!;
    const country = this.form.get('idCountry')!;
    if (type === 'Passport') {
      id.setValidators([Validators.required, Validators.pattern(PASSPORT_PATTERN)]);
      country.setValidators([Validators.required]);
      if (userChanged || country.value === 'Malaysia') country.setValue('');
      country.enable({ emitEvent: false });
    } else {
      id.setValidators([Validators.required, Validators.pattern(NRIC_PATTERN)]);
      country.clearValidators();
      country.setValue('Malaysia');
      country.disable({ emitEvent: false });
    }
    id.updateValueAndValidity({ emitEvent: false });
    country.updateValueAndValidity({ emitEvent: false });
  }

  /** Typing filter: NRIC keeps digits only (max 12); passport keeps letters/digits in capitals (max 10). */
  onIdInput(): void {
    const ctrl = this.form.get('icPassport')!;
    const v = String(ctrl.value ?? '');
    const clean = this.isPassport
      ? v.replace(/[^A-Za-z0-9]/g, '').toUpperCase().slice(0, 10)
      : v.replace(/\D/g, '').slice(0, 12);
    if (clean !== v) ctrl.setValue(clean);

    // NRIC starts with the birth date (YYMMDD): fill Date of Birth when it is empty or was filled from the NRIC before
    if (!this.isPassport) {
      const dob = dobFromNric(clean);
      const dobCtrl = this.form.get('dateOfBirth')!;
      if (dob && (!dobCtrl.value || dobCtrl.value === this.dobFilledFromNric)) {
        dobCtrl.setValue(dob);
        dobCtrl.markAsTouched();
        this.dobFilledFromNric = dob;
      }
    }
  }

  /** Last date of birth taken from the NRIC (so a later NRIC correction updates it, but a typed date is kept). */
  private dobFilledFromNric = '';

  /** Latest allowed date of birth (MIN_AGE years ago) for the date picker. */
  get maxDob(): string {
    const d = new Date(); d.setFullYear(d.getFullYear() - MIN_AGE);
    return isoDate(d);
  }

  /** Inline message under Date of Birth, or '' when it is valid. */
  get dobError(): string {
    const c = this.form.get('dateOfBirth')!;
    if (!c.errors) return '';
    if (c.errors['server']) return c.errors['server'];
    if (c.errors['required']) return 'Date of birth is required';
    return c.errors['dob'] ?? 'Enter a valid date';
  }

  /** Typing filter: mobile number keeps digits only (max 12); a pasted "+60 12-345 6789" loses its "+60". */
  onPhoneInput(): void {
    const ctrl = this.form.get('phone')!;
    const v = String(ctrl.value ?? '');
    const code = String(this.form.get('phoneCountryCode')!.value ?? '');
    const withoutCode = code && v.trim().startsWith(code) ? v.trim().slice(code.length) : v;
    const clean = withoutCode.replace(/\D/g, '').slice(0, 12);
    if (clean !== v) ctrl.setValue(clean);
  }

  /** Inline message under the ID number, or '' when it is valid. */
  get idError(): string {
    const c = this.form.get('icPassport')!;
    if (!c.errors) return '';
    if (c.errors['server']) return c.errors['server'];
    if (c.errors['required']) return this.isPassport ? 'Passport number is required' : 'NRIC number is required';
    const len = String(c.value ?? '').length;
    return this.isPassport
      ? `Passport number must be 8–10 letters or numbers (${len} entered)`
      : `NRIC must be exactly 12 digits (${len} entered)`;
  }

  /** Inline message under the mobile number, or '' when it is valid. */
  get phoneError(): string {
    const c = this.form.get('phone')!;
    if (!c.errors) return '';
    if (c.errors['server']) return c.errors['server'];
    if (c.errors['required']) return 'Mobile number is required';
    return 'Mobile number must be 7–12 digits (numbers only)';
  }

  /** Navigates back to the employee list without saving */
  cancel(): void {
    this.router.navigate(['/employees']);
  }

  /**
   * Handles profile picture file selection and upload
   */
  onFileSelected(event: any): void {
    const file = event.target.files?.[0];
    if (!file) return;

    // Validate file type
    const allowedTypes = ['image/jpeg', 'image/jpg', 'image/png', 'image/gif'];
    if (!allowedTypes.includes(file.type)) {
      this.toast.warning('Invalid File', 'Only JPG, PNG, and GIF images are allowed.');
      return;
    }

    // Validate file size (max 5MB)
    if (file.size > 5 * 1024 * 1024) {
      this.toast.warning('File Too Large', 'File size must not exceed 5MB.');
      return;
    }

    this.uploadFile(file);
  }

  /**
   * Uploads the selected file to the API
   */
  private uploadFile(file: File): void {
    this.uploading = true;
    const formData = new FormData();
    formData.append('file', file);

    this.employeeService.uploadProfilePicture(formData).subscribe({
      next: (response: any) => {
        this.profilePictureUrl = photoUrl(response.filePath);
        this.form.patchValue({ profilePicture: response.filePath });
        this.toast.success('Upload Success', 'Profile picture uploaded successfully.');
        this.uploading = false;
        this.cdr.detectChanges();
      },
      error: (err) => {
        this.toast.error('Upload Failed', err?.error?.message ?? 'Failed to upload profile picture.');
        this.uploading = false;
        this.cdr.detectChanges();
      }
    });
  }

  /**
   * Removes the uploaded profile picture
   */
  removeProfilePicture(): void {
    this.profilePictureUrl = null;
    this.form.patchValue({ profilePicture: '' });
    this.toast.info('Removed', 'Profile picture removed.');
  }

  backToHome(): void {
    this.router.navigate(['/home']);
  }
}
