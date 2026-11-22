import { Component, ElementRef, OnDestroy, OnInit, ViewChild, ChangeDetectorRef, inject } from '@angular/core';
import { CommonModule, Location } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterModule } from '@angular/router';
import { Subscription } from 'rxjs';
import {
  SchoolService, SchoolMe, ConversationSummary, ConversationHeader, ChatMessage, LiveMessage, LiveRead,
  LiveConversation, utc
} from '../../../../core/services/school.service';
import { ToastService } from '../../../../core/services/toast.service';

/** A child the user can start a conversation about. */
interface ChildOption { id: number; fullName: string; className: string | null; classId: number | null; }

/**
 * Messages between parents and the school. Each conversation is about one child, goes to the
 * class teacher or the office, and has a subject; parents (and staff) start a new one per topic.
 * Staff close a conversation when done; a reply reopens it. Parents see their children's
 * conversations; class teachers their classes'; admins all (and answer the office ones).
 * New messages arrive live.
 *
 * Query parameters: c=<id> opens a conversation; new=1 opens "New conversation"
 * (optional child=<id>, kind=Teacher|Office, subject=… prefill it, e.g. from the help chatbot).
 */
@Component({
  selector: 'app-school-messages',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterModule],
  templateUrl: './school-messages.component.html',
  styleUrls: ['../../school-shared.scss', './school-messages.component.scss']
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
  /** Staff work through open conversations; parents see all of theirs. */
  statusFilter: '' | 'Open' | 'Closed' = '';
  statusBusy = false;

  // New conversation
  showNew = false;
  newChildren: ChildOption[] = [];
  newChildrenLoading = false;
  newForm = { studentId: null as number | null, kind: 'Teacher' as 'Teacher' | 'Office', subject: '', body: '' };
  newFile: File | null = null;
  newError = '';
  starting = false;

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
      && (!this.statusFilter || c.status === this.statusFilter)
      && (!q || c.studentName.toLowerCase().includes(q) || (c.className ?? '').toLowerCase().includes(q)
          || c.parentNames.some(p => p.toLowerCase().includes(q)) || c.title.toLowerCase().includes(q)
          || c.subject.toLowerCase().includes(q)));
  }

  get isParent(): boolean { return !!this.me?.isParent; }
  get isStaff(): boolean { return !!this.me && (this.me.isAdmin || this.me.isTeacher); }
  get openCount(): number { return this.conversations.filter(c => c.status === 'Open').length; }

  ngOnInit(): void {
    this.school.loadMe().subscribe(me => {
      this.me = me;
      if (!me?.isParent) this.statusFilter = 'Open';
      const params = this.route.snapshot.queryParamMap;
      const c = params.get('c');
      this.loadList(c ? +c : null);
      if (params.get('new')) {
        const kind = params.get('kind');
        this.openNew({
          studentId: params.get('child') ? +params.get('child')! : null,
          kind: kind === 'Office' || kind === 'Teacher' ? kind : null,
          subject: params.get('subject') ?? ''
        });
        this.location.replaceState(this.router.url.split('?')[0]);
      }
    });
    this.subs.add(this.school.liveMessage$.subscribe(e => this.onLiveMessage(e)));
    this.subs.add(this.school.liveRead$.subscribe(e => this.onLiveRead(e)));
    this.subs.add(this.school.liveConversation$.subscribe(e => this.onLiveConversation(e)));
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
        // Parents on wide screens go straight to their latest conversation
        const target = select ?? this.selectedId
          ?? (this.isParent && window.innerWidth >= 900 ? list[0]?.id ?? null : null);
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

  // ── New conversation ──

  /** Opens the "New conversation" form, optionally prefilled. */
  openNew(prefill: { studentId?: number | null; kind?: 'Teacher' | 'Office' | null; subject?: string } = {}): void {
    this.newError = '';
    this.newFile = null;
    this.newForm = {
      studentId: prefill.studentId ?? null,
      kind: prefill.kind ?? (this.me?.isAdmin && !this.isParent ? 'Office' : 'Teacher'),
      subject: (prefill.subject ?? '').slice(0, 150),
      body: ''
    };
    this.showNew = true;

    if (this.isParent) {
      this.newChildren = (this.me?.children ?? []).map(c => ({ id: c.id, fullName: c.fullName, className: c.className, classId: c.classId }));
      this.pickDefaultChild();
    } else {
      // Staff: the children they may message (the API limits teachers to their classes)
      this.newChildrenLoading = true;
      this.school.getStudents().subscribe({
        next: list => {
          this.newChildren = list.filter(s => s.isActive)
            .map(s => ({ id: s.id, fullName: s.fullName, className: s.className, classId: s.classId }));
          this.newChildrenLoading = false;
          this.pickDefaultChild();
          this.cdr.markForCheck();
        },
        error: () => { this.newChildrenLoading = false; this.newError = 'Could not load the children.'; this.cdr.markForCheck(); }
      });
    }
  }

  private pickDefaultChild(): void {
    if (this.newForm.studentId && !this.newChildren.some(c => c.id === this.newForm.studentId)) this.newForm.studentId = null;
    if (!this.newForm.studentId && this.newChildren.length === 1) this.newForm.studentId = this.newChildren[0].id;
  }

  /** Who the conversation can go to: parents and admins choose; a class teacher writes as the teacher. */
  get canChooseKind(): boolean { return this.isParent || !!this.me?.isAdmin; }

  /** Name of the class teacher of the chosen child (parents only know it from their children list). */
  get newTeacherName(): string | null {
    const child = this.me?.children?.find(c => c.id === this.newForm.studentId);
    return child?.classTeacherName ?? null;
  }

  onNewFile(event: Event): void {
    const input = event.target as HTMLInputElement;
    const f = input.files?.[0] ?? null;
    if (!f) { this.newFile = null; return; }
    if (f.size > 5 * 1024 * 1024) { this.newError = 'The file must be 5 MB or smaller.'; input.value = ''; return; }
    if (!['image/jpeg', 'image/png', 'application/pdf'].includes(f.type)) { this.newError = 'Attach a photo (JPG, PNG) or a PDF.'; input.value = ''; return; }
    this.newError = '';
    this.newFile = f;
  }

  startConversation(): void {
    const f = this.newForm;
    if (!f.studentId) { this.newError = 'Choose the child.'; return; }
    if (!f.subject.trim()) { this.newError = 'Enter a subject.'; return; }
    if (!f.body.trim() && !this.newFile) { this.newError = 'Write a message.'; return; }
    const kind = this.canChooseKind ? f.kind : 'Teacher';
    this.starting = true;
    this.newError = '';
    this.school.startConversation(f.studentId, kind, f.subject.trim(), f.body.trim(), this.newFile).subscribe({
      next: r => {
        this.starting = false;
        this.showNew = false;
        if (this.statusFilter === 'Closed') this.statusFilter = '';
        this.selectedId = null;
        this.loadList(r.id);
        this.toast.success('Sent', 'Your conversation has started.');
      },
      error: err => {
        this.starting = false;
        this.newError = err?.error?.message ?? 'Could not start the conversation. Please try again.';
        this.cdr.markForCheck();
      }
    });
  }

  // ── Close / reopen ──

  toggleStatus(): void {
    if (!this.selectedId || !this.header || this.statusBusy) return;
    const id = this.selectedId;
    const close = this.header.status === 'Open';
    this.statusBusy = true;
    this.school.setConversationStatus(id, close).subscribe({
      next: r => {
        this.statusBusy = false;
        this.applyStatus({ conversationId: id, status: r.status, closedByName: r.closedByName });
        this.toast.success(close ? 'Closed' : 'Reopened', close ? 'The conversation is marked as done.' : 'The conversation is open again.');
      },
      error: err => {
        this.statusBusy = false;
        this.toast.error('Messages', err?.error?.message ?? 'Could not change the conversation.');
        this.cdr.markForCheck();
      }
    });
  }

  private applyStatus(e: LiveConversation): void {
    const summary = this.conversations.find(c => c.id === e.conversationId);
    if (summary) summary.status = e.status;
    if (this.header && this.header.id === e.conversationId) {
      this.header = { ...this.header, status: e.status, closedByName: e.closedByName, closedAt: e.status === 'Closed' ? new Date().toISOString() : null };
    }
    this.conversations = [...this.conversations];
    this.cdr.markForCheck();
  }

  // ── Live updates ──

  private onLiveConversation(e: LiveConversation): void { this.applyStatus(e); }

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

  /** Conversation name in the list: its subject. */
  threadTitle(c: ConversationSummary): string { return c.subject; }

  /** Parents see who they talk to and about which child; staff see the child and class. */
  threadSubtitle(c: ConversationSummary): string {
    if (this.isParent) return `${c.title} · ${c.studentName}`;
    const who = c.kind === 'Office' ? 'Office' : 'Class teacher';
    return [c.studentName, c.className, who].filter(Boolean).join(' · ');
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
