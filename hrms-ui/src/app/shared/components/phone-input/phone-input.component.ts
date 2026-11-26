import { Component, Input, forwardRef, ChangeDetectorRef, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ControlValueAccessor, NG_VALUE_ACCESSOR } from '@angular/forms';
import { PHONE_COUNTRIES, phoneCountryName, MALAYSIA, splitPhone, formatNational, phoneProblem } from '../../phone';

/** The number as shown in the box next to the country code: no leading 0 (+60 already says Malaysia). */
const inBox = (country: string, national: string) => {
  const s = formatNational(country, national);
  return country === MALAYSIA && s.startsWith('0') ? s.substring(1) : s;
};

/**
 * Phone box with a country picker (Malaysia by default). Shows the number after the code without
 * its leading 0 (+60 | 12-345 6789) and gives the form the stored form (+60123456789).
 * Use with [(ngModel)]; the API checks the number again.
 */
@Component({
  selector: 'app-phone-input',
  standalone: true,
  imports: [CommonModule],
  providers: [{ provide: NG_VALUE_ACCESSOR, useExisting: forwardRef(() => PhoneInputComponent), multi: true }],
  template: `
    <div class="phone-box" [class.invalid]="showProblem && problem" [class.disabled]="disabled">
      <select [value]="country" (change)="setCountry($any($event.target).value)" [disabled]="disabled"
              aria-label="Country code" [title]="countryName">
        @for (c of countries; track c.code) { <option [value]="c.code">{{ c.label }}</option> }
      </select>
      <input type="tel" [id]="inputId" [value]="display" (input)="onType($any($event.target))" (blur)="onBlur()"
             [placeholder]="country === malaysia ? '12-345 6789' : 'Phone number'" [disabled]="disabled"
             inputmode="tel" autocomplete="tel-national" maxlength="20" />
    </div>
    @if (showHint && showProblem && problem) { <div class="phone-problem">{{ problem }}</div> }
  `,
  styles: [`
    :host { display: block; }
    .phone-box {
      display: flex; align-items: stretch; width: 100%;
      border: 1.5px solid #d1d5db; border-radius: 8px; background: white; overflow: hidden;
      transition: border-color .2s;
      &:focus-within { border-color: #2563eb; }
      &.invalid { border-color: #dc2626; }
      &.disabled { background: #f3f4f6; }
    }
    select {
      border: none; border-right: 1.5px solid #e5e7eb; background: #f9fafb; padding: 0 8px 0 10px;
      font-size: 14px; outline: none; cursor: pointer; flex: 0 0 auto; max-width: 110px;
    }
    input {
      flex: 1 1 auto; min-width: 0; border: none; outline: none; padding: 10px 14px;
      font-size: 14px; font-family: inherit; background: transparent;
    }
    .phone-problem { font-size: 12px; color: #dc2626; margin-top: 4px; }
  `]
})
export class PhoneInputComponent implements ControlValueAccessor {
  private cdr = inject(ChangeDetectorRef);

  /** id for the <input>, so a <label for> can point at it. */
  @Input() inputId?: string;
  /** false when the form shows its own message under the box. */
  @Input() showHint = true;

  readonly countries = PHONE_COUNTRIES;
  readonly malaysia = MALAYSIA;

  country = MALAYSIA;
  national = '';
  display = '';
  disabled = false;
  showProblem = false;

  private onChange: (v: string | null) => void = () => {};
  private onTouched: () => void = () => {};

  get countryName(): string { return phoneCountryName(this.country); }

  get problem(): string | null { return phoneProblem(this.country, this.national); }

  writeValue(value: string | null): void {
    const { country, national } = splitPhone(value);
    this.country = country || MALAYSIA;
    this.national = national;
    this.display = inBox(this.country, national);
    this.showProblem = !!national;          // an old, badly typed number is pointed out straight away
    this.cdr.markForCheck();
  }

  registerOnChange(fn: (v: string | null) => void): void { this.onChange = fn; }
  registerOnTouched(fn: () => void): void { this.onTouched = fn; }
  setDisabledState(d: boolean): void { this.disabled = d; this.cdr.markForCheck(); }

  setCountry(code: string): void {
    this.country = code;
    this.display = inBox(code, this.national);
    this.emit();
  }

  onType(el: HTMLInputElement): void {
    let digits = el.value.replace(/\D/g, '');
    // A full number pasted with its country code: +60 12-345 6789 / +65 8123 4567
    if (el.value.trim().startsWith('+')) {
      const { country, national } = splitPhone(el.value);
      if (country) { this.country = country; digits = national; }
    }
    // Malaysia: the leading 0 of 012… is not stored (+60 12…)
    this.national = this.country === MALAYSIA && digits.startsWith('0') ? digits.substring(1) : digits;
    // A typed or pasted 0 (012…) is dropped: the +60 box already stands for it
    this.display = inBox(this.country, this.national);
    el.value = this.display;              // keep the caret at the end while formatting
    this.emit();
  }

  onBlur(): void {
    this.showProblem = true;
    this.onTouched();
  }

  private emit(): void {
    this.onChange(this.national ? `+${this.country}${this.national}` : null);
  }
}
