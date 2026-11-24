import { ChangeDetectorRef, Component, DestroyRef, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Observable, interval } from 'rxjs';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import {
  AssistantService, BotAudience, BotFaq, BotFaqSave, BotUnanswered, BotAdminList, BotAiStatus
} from '../../../../core/services/assistant.service';
import { ToastService } from '../../../../core/services/toast.service';
import { ConfirmModalComponent } from '../../../../shared/components/confirm-modal/confirm-modal.component';

/**
 * Master → Chatbot: the questions and answers the help chatbot gives, and the questions people
 * asked that it couldn't answer (turn those into new answers).
 */
@Component({
  selector: 'app-chatbot',
  standalone: true,
  imports: [CommonModule, FormsModule, ConfirmModalComponent],
  templateUrl: './chatbot-component.html',
  styleUrls: ['../../../school/school-shared.scss', './chatbot-component.scss']
})
export class ChatbotComponent implements OnInit {
  private bot = inject(AssistantService);
  private toast = inject(ToastService);
  private cdr = inject(ChangeDetectorRef);

  tab: 'faqs' | 'unanswered' = 'faqs';
  loading = true;
  data: BotAdminList | null = null;
  search = '';
  audienceFilter: '' | BotAudience = '';

  unanswered: BotUnanswered[] = [];
  unansweredLoading = false;

  // Form
  showForm = false;
  editing: BotFaq | null = null;
  form: BotFaqSave = this.empty();
  formError = '';
  saving = false;
  /** Unanswered question being turned into an answer (removed from the list once saved). */
  fromUnanswered: BotUnanswered | null = null;

  ai: BotAiStatus | null = null;
  aiSaving = false;

  // Connect AI (the company's own Anthropic API key)
  showConnect = false;
  apiKey = '';
  connecting = false;
  connectError = '';
  confirmDisconnect = false;

  confirmDelete: BotFaq | null = null;
  confirmClear = false;
  addingStarter = false;

  readonly audienceLabels: Record<BotAudience, string> = { All: 'Everyone', Parent: 'Parents', Employee: 'Staff' };

  private destroyRef = inject(DestroyRef);

  ngOnInit(): void {
    this.load();
    this.loadAi();
    // Keep the AI card current (e.g. "AI isn't working" appears while people are chatting)
    this.bot.aiChanged.pipe(takeUntilDestroyed(this.destroyRef)).subscribe(() => this.loadAi());
    interval(60_000).pipe(takeUntilDestroyed(this.destroyRef)).subscribe(() => {
      if (document.visibilityState === 'visible') this.loadAi();
    });
  }

  loadAi(): void {
    this.bot.aiStatus().subscribe({ next: a => { this.ai = a; this.cdr.markForCheck(); }, error: () => {} });
  }

  toggleAi(): void {
    if (!this.ai || this.aiSaving) return;
    this.aiSaving = true;
    this.bot.setAi(!this.ai.enabled).subscribe({
      next: r => {
        this.aiSaving = false;
        if (this.ai) this.ai = { ...this.ai, enabled: r.enabled };
        this.toast.success('AI answers', r.enabled
          ? "Switched on. Personal questions are now answered from each person's own records."
          : 'Switched off. The chatbot answers from this list only.');
        this.cdr.markForCheck();
      },
      error: err => {
        this.aiSaving = false;
        this.toast.error('AI answers', err?.error?.message ?? 'Could not change the setting.');
        this.cdr.markForCheck();
      }
    });
  }

  openConnect(): void {
    this.apiKey = '';
    this.connectError = '';
    this.showConnect = true;
  }

  /** Sends the key to the server, which tests it with Anthropic and stores it encrypted. */
  connect(): void {
    const key = this.apiKey.trim();
    if (!key.startsWith('sk-ant-')) { this.connectError = 'Paste the whole API key; it starts with sk-ant-.'; return; }
    this.connecting = true;
    this.connectError = '';
    this.bot.connectKey(key).subscribe({
      next: r => {
        this.connecting = false;
        this.showConnect = false;
        this.apiKey = '';
        this.toast.success('AI connected', `Your Anthropic key (${r.keyHint}) works. AI answers are on for everyone in the company.`);
        this.loadAi();
      },
      error: err => {
        this.connecting = false;
        this.connectError = err?.error?.message ?? 'Could not connect. Please try again.';
        this.cdr.markForCheck();
      }
    });
  }

  disconnect(): void {
    this.confirmDisconnect = false;
    this.bot.disconnectKey().subscribe({
      next: r => {
        this.toast.success('AI disconnected', r.enabled
          ? "Your key was removed. AI answers now use the server's key."
          : 'Your key was removed and AI answers are off. The chatbot answers from this list.');
        this.loadAi();
      },
      error: err => this.toast.error('AI answers', err?.error?.message ?? 'Could not remove the key.')
    });
  }

  /** "12.3k" style token counts. */
  tokens(n: number): string {
    return n >= 1_000_000 ? (n / 1_000_000).toFixed(1) + 'M' : n >= 1000 ? (n / 1000).toFixed(1) + 'k' : String(n);
  }

  load(): void {
    this.bot.adminList().subscribe({
      next: d => { this.data = d; this.loading = false; this.cdr.markForCheck(); },
      error: err => {
        this.loading = false;
        this.toast.error('Chatbot', err?.error?.message ?? 'Could not load the questions.');
        this.cdr.markForCheck();
      }
    });
  }

  loadUnanswered(): void {
    this.unansweredLoading = true;
    this.bot.unanswered().subscribe({
      next: u => { this.unanswered = u; this.unansweredLoading = false; this.cdr.markForCheck(); },
      error: () => { this.unansweredLoading = false; this.cdr.markForCheck(); }
    });
  }

  setTab(t: 'faqs' | 'unanswered'): void {
    this.tab = t;
    if (t === 'unanswered') this.loadUnanswered();
  }

  get filtered(): BotFaq[] {
    const q = this.search.trim().toLowerCase();
    return (this.data?.faqs ?? []).filter(f =>
      (!this.audienceFilter || f.audience === this.audienceFilter)
      && (!q || f.question.toLowerCase().includes(q) || f.answer.toLowerCase().includes(q)
          || f.category.toLowerCase().includes(q) || (f.keywords ?? '').toLowerCase().includes(q)));
  }

  /** Existing topic names, for the topic field's suggestions. */
  get categories(): string[] {
    return [...new Set((this.data?.faqs ?? []).map(f => f.category))].sort();
  }

  /** Page links that fit the chosen audience. */
  get actionChoices(): { key: string; label: string }[] {
    const a = this.form.audience;
    return (this.data?.actions ?? []).filter(x => a === 'All' ? x.audience === 'All' : x.audience === a || x.audience === 'All');
  }

  actionLabel(key: string | null): string | null {
    return key ? this.data?.actions.find(a => a.key === key)?.label ?? key : null;
  }

  // ── Add / edit ──

  private empty(): BotFaqSave {
    return { category: '', question: '', answer: '', keywords: '', audience: 'All', action: null, sortOrder: null, isActive: true };
  }

  openCreate(prefill?: BotUnanswered): void {
    this.editing = null;
    this.fromUnanswered = prefill ?? null;
    this.form = this.empty();
    if (prefill) {
      this.form.question = prefill.text.slice(0, 300);
      this.form.audience = prefill.audience;
    }
    this.formError = '';
    this.showForm = true;
  }

  openEdit(f: BotFaq): void {
    this.editing = f;
    this.fromUnanswered = null;
    this.form = {
      category: f.category, question: f.question, answer: f.answer, keywords: f.keywords ?? '',
      audience: f.audience, action: f.action, sortOrder: f.sortOrder, isActive: f.isActive
    };
    this.formError = '';
    this.showForm = true;
  }

  onAudienceChange(): void {
    if (this.form.action && !this.actionChoices.some(a => a.key === this.form.action)) this.form.action = null;
  }

  save(): void {
    if (!this.form.question.trim()) { this.formError = 'Enter the question.'; return; }
    if (!this.form.answer.trim()) { this.formError = 'Enter the answer.'; return; }
    this.saving = true;
    this.formError = '';
    const req: Observable<unknown> = this.editing ? this.bot.update(this.editing.id, this.form) : this.bot.create(this.form);
    req.subscribe({
      next: () => {
        this.saving = false;
        this.showForm = false;
        this.toast.success('Saved', this.editing ? 'The answer was updated.' : 'The chatbot knows this one now.');
        const from = this.fromUnanswered;
        if (from) {
          this.bot.deleteUnanswered(from.id).subscribe({ next: () => this.loadUnanswered(), error: () => {} });
        }
        this.load();
      },
      error: err => {
        this.saving = false;
        this.formError = err?.error?.message ?? 'Could not save.';
        this.cdr.markForCheck();
      }
    });
  }

  toggleActive(f: BotFaq): void {
    const save: BotFaqSave = { ...f, keywords: f.keywords ?? '', isActive: !f.isActive };
    this.bot.update(f.id, save).subscribe({
      next: () => { f.isActive = !f.isActive; this.cdr.markForCheck(); },
      error: err => this.toast.error('Chatbot', err?.error?.message ?? 'Could not change it.')
    });
  }

  remove(): void {
    const f = this.confirmDelete;
    this.confirmDelete = null;
    if (!f) return;
    this.bot.delete(f.id).subscribe({
      next: () => { this.toast.success('Deleted', 'The question was removed.'); this.load(); },
      error: err => this.toast.error('Delete failed', err?.error?.message ?? 'Could not delete.')
    });
  }

  addStarter(): void {
    this.addingStarter = true;
    this.bot.addStarter().subscribe({
      next: r => {
        this.addingStarter = false;
        this.toast.success('Starter questions', r.added ? `${r.added} questions added. Review the answers and edit them for your company.` : 'All starter questions are already there.');
        this.load();
      },
      error: err => {
        this.addingStarter = false;
        this.toast.error('Chatbot', err?.error?.message ?? 'Could not add them.');
        this.cdr.markForCheck();
      }
    });
  }

  // ── Unanswered ──

  dismiss(u: BotUnanswered): void {
    this.bot.deleteUnanswered(u.id).subscribe({
      next: () => {
        this.unanswered = this.unanswered.filter(x => x.id !== u.id);
        if (this.data) this.data.unansweredCount = Math.max(0, this.data.unansweredCount - 1);
        this.cdr.markForCheck();
      },
      error: () => this.toast.error('Chatbot', 'Could not remove it.')
    });
  }

  clearAll(): void {
    this.confirmClear = false;
    this.bot.clearUnanswered().subscribe({
      next: () => { this.unanswered = []; if (this.data) this.data.unansweredCount = 0; this.cdr.markForCheck(); },
      error: () => this.toast.error('Chatbot', 'Could not clear the list.')
    });
  }

  utc(s: string): Date { return new Date(s.endsWith('Z') ? s : s + 'Z'); }
}
