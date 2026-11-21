import { Component, ElementRef, OnDestroy, OnInit, ViewChild, ChangeDetectorRef, inject } from '@angular/core';
import { CommonModule, Location } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterModule } from '@angular/router';
import { Subscription } from 'rxjs';
import {
  SchoolService, SchoolMe, ConversationSummary, ConversationHeader, ChatMessage, LiveMessage, LiveRead, utc
} from '../../../../core/services/school.service';
import { ToastService } from '../../../../core/services/toast.service';

/**
 * Messages between parents and the school, one thread per child: with the class teacher and
 * with the office. Parents see their children's threads; class teachers their classes';
 * admins every thread (and answer the office ones). New messages arrive live.
 */
@Component({
  selector: 'app-school-messages',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterModule],
  templateUrl: './school-messages.component.html',
  styleUrls: ['./school-messages.component.scss']
})
export class SchoolMessagesComponent implements OnInit, OnDestroy {
  private school = inject(SchoolService);
  private toast = inject(ToastService);
  private route = inject(ActivatedRoute);
  private router = inject(Router);
  private location = inject(Location);
  private cdr = inject(ChangeDetectorRef);
  private subs = new Subscription();

  @ViewChild('scroller') scroller?: ElementRef<HTMLElement>;
  @ViewChild('composer') composer?: ElementRef<HTMLTextAreaElement>;

  readonly utc = utc;

  me: SchoolMe | null = null;
  conversations: ConversationSummary[] = [];
  listLoading = true;
  search = '';
  kindFilter: '' | 'Office' | 'Teacher' = '';

  selectedId: number | null = null;
  header: ConversationHeader | null = null;
  messages: ChatMessage[] = [];
  hasMore = false;
  seenUpTo = 0;
  threadLoading = false;
  loadingOlder = false;

  text = '';
  file: File | null = null;
  sending = false;

  /** Photo previews: message id → object URL (the files need the login token, so they're fetched). */
  previews = new Map<number, string>();

  get filtered(): ConversationSummary[] {
    const q = this.search.trim().toLowerCase();
    return this.conversations.filter(c =>
      (!this.kindFilter || c.kind === this.kindFilter)
      && (!q || c.studentName.toLowerCase().includes(q) || (c.className ?? '').toLowerCase().includes(q)
          || c.parentNames.some(p => p.toLowerCase().includes(q)) || c.title.toLowerCase().includes(q)));
  }

  get isParent(): boolean { return !!this.me?.isParent; }

  ngOnInit(): void {
    this.school.loadMe().subscribe(me => {
      this.me = me;
      const c = this.route.snapshot.queryParamMap.get('c');
      this.loadList(c ? +c : null);
    });
    this.subs.add(this.school.liveMessage$.subscribe(e => this.onLiveMessage(e)));
    this.subs.add(this.school.liveRead$.subscribe(e => this.onLiveRead(e)));
  }

  ngOnDestroy(): void {
    this.subs.unsubscribe();
    this.previews.forEach(url => URL.revokeObjectURL(url));
  }

  // ── Thread list ──

  loadList(select: number | null = null): void {
    this.school.getConversations().subscribe({
      next: list => {
        this.conversations = list;
        this.listLoading = false;
        // Parents with one child (two threads) go straight to the class teacher thread on wide screens
        const target = select ?? this.selectedId
          ?? (this.isParent && window.innerWidth >= 900 ? list.find(c => c.kind === 'Teacher')?.id ?? null : null);
        if (target && target !== this.selectedId) this.select(target);
        this.cdr.markForCheck();
      },
      error: err => {
        this.listLoading = false;
        this.toast.error('Messages', err?.error?.message ?? 'Could not load conversations.');
        this.cdr.markForCheck();
      }
    });
  }

  select(id: number): void {
    if (this.selectedId === id && this.header) return;
    this.selectedId = id;
    this.header = null;
    this.messages = [];
    this.text = '';
    this.file = null;
    this.threadLoading = true;
    // Address bar only: a router navigation would rebuild the page (NoReuseStrategy)
    this.location.replaceState(this.router.url.split('?')[0], `c=${id}`);

    this.school.getMessages(id).subscribe({
      next: page => {
        if (this.selectedId !== id) return;
        this.header = page.conversation;
        this.messages = page.messages;
        this.hasMore = page.hasMore;
        this.seenUpTo = page.seenUpTo;
        this.threadLoading = false;
        this.loadPreviews(page.messages);
        this.markRead();
        this.cdr.markForCheck();
        this.scrollToBottom();
        setTimeout(() => this.composer?.nativeElement.focus(), 50);
      },
      error: err => {
        this.threadLoading = false;
        this.toast.error('Messages', err?.error?.message ?? 'Could not open the conversation.');
        this.cdr.markForCheck();
      }
    });
  }

  back(): void {
    this.selectedId = null;
    this.header = null;
    this.location.replaceState(this.router.url.split('?')[0]);
  }

  loadOlder(): void {
    if (!this.selectedId || !this.messages.length) return;
    const id = this.selectedId;
    const el = this.scroller?.nativeElement;
    const fromBottom = el ? el.scrollHeight - el.scrollTop : 0;
    this.loadingOlder = true;
    this.school.getMessages(id, this.messages[0].id).subscribe({
      next: page => {
        this.loadingOlder = false;
        if (this.selectedId !== id) return;
        this.messages = [...page.messages, ...this.messages];
        this.hasMore = page.hasMore;
        this.loadPreviews(page.messages);
        this.cdr.markForCheck();
        // Keep the reader's place
        setTimeout(() => { if (el) el.scrollTop = el.scrollHeight - fromBottom; });
      },
      error: () => { this.loadingOlder = false; this.cdr.markForCheck(); }
    });
  }

  // ── Sending ──

  onKeydown(e: KeyboardEvent): void {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      this.send();
    }
  }

  onFile(event: Event): void {
    const input = event.target as HTMLInputElement;
    const f = input.files?.[0] ?? null;
    input.value = '';
    if (!f) return;
    if (f.size > 5 * 1024 * 1024) { this.toast.error('Attachment', 'The file must be 5 MB or smaller.'); return; }
    if (!['image/jpeg', 'image/png', 'application/pdf'].includes(f.type)) { this.toast.error('Attachment', 'Attach a photo (JPG, PNG) or a PDF.'); return; }
    this.file = f;
  }

  send(): void {
    const body = this.text.trim();
    if (!this.selectedId || this.sending || (!body && !this.file)) return;
    const id = this.selectedId;
    this.sending = true;
    this.school.sendMessage(id, body, this.file).subscribe({
      next: msg => {
        this.sending = false;
        this.text = '';
        this.file = null;
        this.addMessage(msg);
        this.cdr.markForCheck();
        setTimeout(() => this.composer?.nativeElement.focus());
      },
      error: err => {
        this.sending = false;
        this.toast.error('Not sent', err?.error?.message ?? 'The message could not be sent. Please try again.');
        this.cdr.markForCheck();
      }
    });
  }

  // ── Live updates ──

  private onLiveMessage(e: LiveMessage): void {
    const summary = this.conversations.find(c => c.id === e.conversationId);
    if (!summary) { this.loadList(); return; }   // e.g. a parent's first message reaches the teacher

    const mine = e.message.senderUserId === this.me?.userId;
    summary.lastMessage = { text: e.message.body || '📎 Attachment', senderName: e.message.senderName, mine };
    summary.lastMessageAt = e.message.sentAt;
    this.conversations = [summary, ...this.conversations.filter(c => c.id !== summary.id)];

    if (e.conversationId === this.selectedId) {
      this.addMessage(e.message);
      if (!mine) this.markRead();
    } else if (!mine) {
      summary.unread++;
    }
    this.cdr.markForCheck();
  }

  private onLiveRead(e: LiveRead): void {
    if (e.userId === this.me?.userId) {
      const c = this.conversations.find(x => x.id === e.conversationId);
      if (c) c.unread = 0;
    } else if (e.conversationId === this.selectedId && e.byParent !== this.isParent) {
      this.seenUpTo = Math.max(this.seenUpTo, e.lastReadMessageId);
    }
    this.cdr.markForCheck();
  }

  private addMessage(msg: ChatMessage): void {
    if (msg.conversationId !== this.selectedId || this.messages.some(m => m.id === msg.id)) return;
    const el = this.scroller?.nativeElement;
    const atBottom = !el || el.scrollHeight - el.scrollTop - el.clientHeight < 120;
    this.messages = [...this.messages, msg];
    this.loadPreviews([msg]);
    const summary = this.conversations.find(c => c.id === msg.conversationId);
    if (summary) {
      summary.lastMessage = { text: msg.body || '📎 Attachment', senderName: msg.senderName, mine: msg.senderUserId === this.me?.userId };
      summary.lastMessageAt = msg.sentAt;
    }
    if (atBottom || msg.senderUserId === this.me?.userId) this.scrollToBottom();
  }

  private markRead(): void {
    const last = this.messages[this.messages.length - 1];
    if (!this.selectedId || !last) return;
    const c = this.conversations.find(x => x.id === this.selectedId);
    if (c) c.unread = 0;
    this.school.markRead(this.selectedId, last.id).subscribe({ error: () => {} });
  }

  // ── Display helpers ──

  isMine(m: ChatMessage): boolean { return m.senderUserId === this.me?.userId; }

  /** "Seen" on my messages the other side has read. */
  isSeen(m: ChatMessage): boolean { return this.isMine(m) && m.id <= this.seenUpTo; }

  roleLabel(m: ChatMessage): string {
    return m.senderRole === 'Office' ? 'Office' : m.senderRole === 'Teacher' ? 'Teacher' : 'Parent';
  }

  /** Show a date line before the first message of each day. */
  showDay(i: number): boolean {
    if (i === 0) return true;
    const a = utc(this.messages[i - 1].sentAt), b = utc(this.messages[i].sentAt);
    return !!a && !!b && a.toDateString() !== b.toDateString();
  }

  dayLabel(s: string): string {
    const d = utc(s)!;
    const today = new Date();
    const yesterday = new Date(); yesterday.setDate(today.getDate() - 1);
    if (d.toDateString() === today.toDateString()) return 'Today';
    if (d.toDateString() === yesterday.toDateString()) return 'Yesterday';
    return d.toLocaleDateString(undefined, { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' });
  }

  /** Thread name in the list: parents see who they talk to, staff see the child. */
  threadTitle(c: ConversationSummary): string {
    return this.isParent ? c.title : c.studentName;
  }

  threadSubtitle(c: ConversationSummary): string {
    if (this.isParent) return c.studentName + (c.className ? ` · ${c.className}` : '');
    const who = c.kind === 'Office' ? 'Office' : 'Class teacher';
    return [c.className, who].filter(Boolean).join(' · ');
  }

  openAttachment(m: ChatMessage): void {
    this.school.openBlob(this.school.attachment(m.id));
  }

  private loadPreviews(list: ChatMessage[]): void {
    for (const m of list) {
      if (!m.attachment || m.attachment.contentType === 'application/pdf' || this.previews.has(m.id)) continue;
      this.previews.set(m.id, '');
      this.school.attachment(m.id).subscribe({
        next: blob => { this.previews.set(m.id, URL.createObjectURL(blob)); this.cdr.markForCheck(); },
        error: () => this.previews.delete(m.id)
      });
    }
  }

  private scrollToBottom(): void {
    setTimeout(() => {
      const el = this.scroller?.nativeElement;
      if (el) el.scrollTop = el.scrollHeight;
    });
  }

  fileSize(bytes: number): string {
    return bytes < 1024 * 1024 ? `${Math.max(1, Math.round(bytes / 1024))} KB` : `${(bytes / 1024 / 1024).toFixed(1)} MB`;
  }
}
