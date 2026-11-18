import { Directive, ElementRef, HostListener, forwardRef, Input } from '@angular/core';
import { ControlValueAccessor, NG_VALUE_ACCESSOR } from '@angular/forms';

/**
 * Banking-style amount input (RM, 2 decimals), like online banking transfer screens:
 *   - digits fill from the right:  1 → 0.01, 12 → 0.12, 1234 → 12.34, 123456 → 1,234.56
 *   - Backspace removes the last digit (1,234.56 → 123.45); the caret always stays at the end,
 *     so digits can't be typed or deleted in the middle
 *   - select all + Backspace/Delete clears to 0.00; pasting "RM 1,234.50" gives 1,234.50
 *
 * Usage (works with formControlName and ngModel; the model value is a number, e.g. 1234.56):
 *   <input moneyInput formControlName="salary" />
 *   <input moneyInput [(ngModel)]="form.amount" />
 */
@Directive({
  selector: 'input[moneyInput]',
  standalone: true,
  providers: [{ provide: NG_VALUE_ACCESSOR, useExisting: forwardRef(() => MoneyInputDirective), multi: true }],
  host: {
    type: 'text',
    inputmode: 'numeric',
    autocomplete: 'off',
    '[style.text-align]': '"right"',
    '[style.font-variant-numeric]': '"tabular-nums"'
  }
})
export class MoneyInputDirective implements ControlValueAccessor {
  /** Largest amount in cents (default RM 9,999,999,999.99). */
  @Input() maxCents = 999_999_999_999;

  private cents = 0;
  private onChange: (v: number) => void = () => {};
  private onTouched: () => void = () => {};

  constructor(private el: ElementRef<HTMLInputElement>) {}

  // ── ControlValueAccessor ───────────────────────────────────────────
  writeValue(value: number | string | null): void {
    const n = typeof value === 'string' ? parseFloat(value) : value;
    this.cents = n == null || isNaN(n) ? 0 : Math.round(Math.abs(n) * 100);
    this.render();
  }
  registerOnChange(fn: (v: number) => void): void { this.onChange = fn; }
  registerOnTouched(fn: () => void): void { this.onTouched = fn; }
  setDisabledState(disabled: boolean): void { this.el.nativeElement.disabled = disabled; }

  // ── Typing (beforeinput covers keyboards, phone keypads and paste) ───
  @HostListener('beforeinput', ['$event'])
  onBeforeInput(e: InputEvent): void {
    e.preventDefault();                                   // we decide what the field shows
    const input = this.el.nativeElement;
    const allSelected = input.selectionStart === 0 && input.selectionEnd === input.value.length && input.value.length > 0;

    switch (e.inputType) {
      case 'insertText': {
        const digits = (e.data ?? '').replace(/\D/g, '');
        if (!digits) return;
        let c = allSelected ? 0 : this.cents;
        for (const d of digits) {
          const next = c * 10 + +d;
          if (next > this.maxCents) break;
          c = next;
        }
        this.set(c);
        return;
      }
      case 'deleteContentBackward':                        // Backspace
      case 'deleteContentForward':                         // Delete
        this.set(allSelected ? 0 : Math.floor(this.cents / 10));
        return;
      case 'insertFromPaste':
      case 'insertFromDrop':
      case 'insertReplacementText': {
        const text = e.data ?? e.dataTransfer?.getData('text') ?? '';
        const amount = parseFloat(text.replace(/[^\d.]/g, ''));
        if (!isNaN(amount)) this.set(Math.min(Math.round(amount * 100), this.maxCents));
        return;
      }
      default:
        if (e.inputType.startsWith('delete')) this.set(0);  // cut, Ctrl+Backspace … clear the amount
        return;                                            // ignore anything else (e.g. line breaks)
    }
  }

  /** Older browsers without beforeinput paste support. */
  @HostListener('paste', ['$event'])
  onPaste(e: ClipboardEvent): void {
    e.preventDefault();
    const amount = parseFloat((e.clipboardData?.getData('text') ?? '').replace(/[^\d.]/g, ''));
    if (!isNaN(amount)) this.set(Math.min(Math.round(amount * 100), this.maxCents));
  }

  /** Keep the caret at the end: no editing in the middle of the amount. */
  @HostListener('click') @HostListener('focus') @HostListener('keyup', ['$event'])
  keepCaretAtEnd(e?: KeyboardEvent): void {
    if (e && (e.ctrlKey || e.metaKey || e.shiftKey)) return;   // allow Ctrl+A / Shift+arrows to select
    const input = this.el.nativeElement;
    const end = input.value.length;
    requestAnimationFrame(() => {
      if (document.activeElement === input && input.selectionStart === input.selectionEnd) input.setSelectionRange(end, end);
    });
  }

  @HostListener('keydown', ['$event'])
  onKeydown(e: KeyboardEvent): void {
    // Arrow/Home keys would move the caret into the middle — keep it at the end
    if (['ArrowLeft', 'ArrowRight', 'Home', 'End', 'ArrowUp', 'ArrowDown'].includes(e.key) && !e.shiftKey) e.preventDefault();
  }

  @HostListener('blur')
  onBlur(): void { this.onTouched(); }

  // ── helpers ────────────────────────────────────────────────────────
  private set(cents: number): void {
    this.cents = cents;
    this.render();
    this.onChange(cents / 100);
  }

  private render(): void {
    const input = this.el.nativeElement;
    input.value = (this.cents / 100).toLocaleString('en-MY', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    const end = input.value.length;
    if (document.activeElement === input) input.setSelectionRange(end, end);
  }
}
