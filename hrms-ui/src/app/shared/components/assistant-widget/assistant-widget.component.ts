import { ChangeDetectionStrategy, ChangeDetectorRef, Component, ElementRef, ViewChild, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { AssistantService, BotAction, BotAiNotice, BotAnswer, BotStart, BotTopic, BotTurn } from '../../../core/services/assistant.service';
import { AuthService } from '../../../core/services/auth.service';

/** One line in the chat. */
interface ChatLine {
  from: 'bot' | 'me';
  text: string;
  /** Buttons under a bot line: questions to pick, topics, or a page link. */
  questions?: { id: number; question: string }[];
  topics?: BotTopic[];
  action?: BotAction | null;
  /** "Message the school office" (parents, after an unanswered question). */
  handoff?: string;
  /** Answered by the AI (shown with a small label). */
  ai?: boolean;
  /** A report or document to download (AI answers). */
  download?: { label: string; path: string } | null;
}

/**
 * The help chatbot: a round button at the bottom right of every page that opens a small chat.
 * People pick a topic and a question, or type their own; answers come from the questions and
 * answers the company's admins wrote (Master → Chatbot). With AI answers on, questions about the
 * user's own records are answered by the AI (within what their login may see), with page buttons
 * and report downloads.
 */
@Component({
  selector: 'app-assistant-widget',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './assistant-widget.component.html',
  styleUrls: ['./assistant-widget.component.scss'],
  changeDetection: ChangeDetectionStrategy.OnPush
})
export class AssistantWidgetComponent {
  private bot = inject(AssistantService);
  private auth = inject(AuthService);
  private router = inject(Router);
  private cdr = inject(ChangeDetectorRef);

  @ViewChild('scroller') scroller?: ElementRef<HTMLElement>;
  @ViewChild('input') input?: ElementRef<HTMLInputElement>;

  open = false;
  loading = false;
  asking = false;
  failed = false;
  text = '';
  lines: ChatLine[] = [];
  start: BotStart | null = null;
  /** "Smart answers are paused…" (or, for admins, why AI stopped), shown above the chat. */
  notice: BotAiNotice | null = null;
  /** When the notice was last checked; reopening the chat after a while checks again. */
  private noticeCheckedAt = 0;
  /** Questions and answers so far (text only), sent with each question so the AI can follow up. */
  private history: BotTurn[] = [];
  /** All answers by id, so a picked question shows its answer at once. */
  private answers = new Map<number, BotAnswer>();

  toggle(): void {
    this.open = !this.open;
    if (this.open && !this.start && !this.loading) this.load();
    else if (this.open && this.start && Date.now() - this.noticeCheckedAt > 60_000) this.refreshNotice();
    if (this.open) this.focusInput();
  }

  /** Re-checks whether AI answers are stopped or working again, without resetting the chat. */
  private refreshNotice(): void {
    this.noticeCheckedAt = Date.now();
    this.bot.start().subscribe({
      next: s => {
        this.notice = s.aiNotice ?? null;
        if (this.start) this.start.ai = s.ai;
        this.cdr.markForCheck();
      },
      error: () => { /* keep what we have */ }
    });
  }

  load(): void {
    this.loading = true;
    this.failed = false;
    this.bot.start().subscribe({
      next: s => {
        this.start = s;
        this.notice = s.aiNotice ?? null;
        this.noticeCheckedAt = Date.now();
        this.loading = false;
        this.answers.clear();
        s.topics.forEach(t => t.items.forEach(i => this.answers.set(i.id, i)));
        this.lines = [{ from: 'bot', text: s.greeting, topics: s.topics }];
        if (s.topics.length === 0) {
          this.lines.push({ from: 'bot', text: 'There are no help topics yet, but you can still type a question.' });
        }
        this.cdr.markForCheck();
        this.scrollDown();
      },
      error: () => { this.loading = false; this.failed = true; this.cdr.markForCheck(); }
    });
  }

  /** Shows the questions of a topic. */
  pickTopic(t: BotTopic): void {
    this.lines.push({ from: 'me', text: t.category });
    this.lines.push({ from: 'bot', text: `Here's what I can help with about ${t.category.toLowerCase()}:`, questions: t.items.map(i => ({ id: i.id, question: i.question })) });
    this.scrollDown();
  }

  /** Shows the answer to a listed question. */
  pickQuestion(q: { id: number; question: string }): void {
    const a = this.answers.get(q.id);
    this.lines.push({ from: 'me', text: q.question });
    if (a) {
      this.lines.push({ from: 'bot', text: a.answer, action: a.action });
      this.remember(q.question, a.answer);
    }
    else this.askServer(q.question, false);
    this.scrollDown();
  }

  /** Shows the topics again, unless they are already the last thing in the chat. */
  showMenu(): void {
    if (!this.start) return;
    const last = this.lines[this.lines.length - 1];
    if (!last?.topics?.length) {
      this.lines.push({ from: 'bot', text: 'What would you like help with?', topics: this.start.topics });
    }
    this.scrollDown();
  }

  send(): void {
    const t = this.text.trim();
    if (!t || this.asking) return;
    this.text = '';
    this.askServer(t, true);
  }

  private askServer(t: string, echo: boolean): void {
    if (echo) this.lines.push({ from: 'me', text: t });
    this.asking = true;
    this.scrollDown();
    this.bot.ask(t, this.history.slice(-10)).subscribe({
      next: r => {
        this.asking = false;
        // AI stopped or failed: show why (answer came from the list); an AI answer clears it
        const had = !!this.notice;
        if (r.aiNotice) this.notice = r.aiNotice;
        else if (r.source === 'ai') this.notice = null;
        if (had !== !!this.notice) this.bot.aiChanged.next();
        if (r.answer) {
          this.lines.push({ from: 'bot', text: r.answer.answer, action: r.answer.action, ai: r.source === 'ai', download: r.answer.download });
          this.remember(t, r.answer.answer);
          if (r.related.length) this.lines.push({ from: 'bot', text: 'Related questions:', questions: r.related });
        } else {
          this.lines.push({
            from: 'bot',
            text: r.reply ?? 'Sorry, I don\'t know that one.',
            questions: r.related.length ? r.related : undefined,
            handoff: r.unanswered && this.start?.canMessageSchool ? t : undefined
          });
          if (r.unanswered && r.related.length) this.lines[this.lines.length - 1].text += ' Maybe one of these helps:';
        }
        this.cdr.markForCheck();
        this.scrollDown();
        this.focusInput();
      },
      error: () => {
        this.asking = false;
        this.lines.push({ from: 'bot', text: 'Sorry, I couldn\'t reach the server. Please try again.' });
        this.cdr.markForCheck();
        this.scrollDown();
      }
    });
  }

  private remember(question: string, answer: string): void {
    this.history.push({ fromUser: true, text: question }, { fromUser: false, text: answer });
    if (this.history.length > 20) this.history = this.history.slice(-20);
  }

  /** Opens the page an answer links to. */
  go(a: BotAction): void {
    const url = this.routeFor(a.key);
    if (!url) return;
    this.open = false;
    this.router.navigateByUrl(url);
  }

  /** Parents: start a conversation with the office about what they asked. */
  messageSchool(question: string): void {
    this.open = false;
    this.router.navigate(['/parent/messages'], { queryParams: { new: 1, kind: 'Office', subject: question.slice(0, 150) } });
  }

  canGo(a: BotAction | null | undefined): boolean { return !!a && !!this.routeFor(a.key); }

  private routeFor(key: string): string | null {
    const parent = this.auth.getRole() === 'Parent';
    const map: Record<string, string> = parent
      ? {
          'fees': '/parent/fees', 'messages': '/parent/messages', 'new-message': '/parent/messages?new=1',
          'announcements': '/parent/announcements', 'notifications': '/notifications',
          'change-password': '/self-service/change-password'
        }
      : {
          'apply-leave': '/self-service/my-leave?tab=new', 'my-leave': '/self-service/my-leave',
          'payslips': '/self-service/my-payslips', 'attendance': '/self-service/my-attendance',
          'profile': '/self-service/my-profile', 'notifications': '/notifications',
          'change-password': '/self-service/change-password',
          // Staff and admin pages (the API only offers the ones this login may open)
          'school-attendance': '/school/attendance', 'school-messages': '/school/messages', 'my-class': '/school/my-class',
          'school-fees': '/school/fees', 'school-children': '/school/registrations/children',
          'approvals': '/leave/requests', 'payroll': '/payroll/list', 'employees': '/employees'
        };
    return map[key] ?? null;
  }

  downloading: string | null = null;

  /** Downloads a report the AI offered (with the login token), e.g. unpaid fees as Excel. */
  download(d: { label: string; path: string }): void {
    if (this.downloading) return;
    this.downloading = d.path;
    this.bot.downloadFile(d.path).subscribe({
      next: () => { this.downloading = null; this.cdr.markForCheck(); },
      error: () => {
        this.downloading = null;
        this.lines.push({ from: 'bot', text: `Sorry, "${d.label}" could not be downloaded. Please try again.` });
        this.cdr.markForCheck();
        this.scrollDown();
      }
    });
  }

  onKeydown(e: KeyboardEvent): void {
    if (e.key === 'Escape') { this.open = false; }
  }

  private scrollDown(): void {
    this.cdr.markForCheck();
    setTimeout(() => {
      const el = this.scroller?.nativeElement;
      if (el) el.scrollTop = el.scrollHeight;
    });
  }

  private focusInput(): void {
    setTimeout(() => this.input?.nativeElement.focus(), 50);
  }
}
