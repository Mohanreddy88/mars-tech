import { Injectable, PLATFORM_ID, inject } from '@angular/core';
import { isPlatformBrowser } from '@angular/common';
import { HttpClient } from '@angular/common/http';
import { BehaviorSubject, Observable, Subject, of, catchError, map, tap } from 'rxjs';
import type { HubConnection } from '@microsoft/signalr';
import { environment } from '../../../environments/environment';
import { AuthService } from './auth.service';

// ── Models ────────────────────────────────────────────────────────────────

/** The signed-in user's place in the school features (from GET /school/me). */
export interface SchoolMe {
  enabled: boolean;
  userId: number;
  name: string;
  isAdmin: boolean;
  isTeacher: boolean;
  isParent: boolean;
  classes: { id: number; name: string }[];
  children: ChildSummary[] | null;
}

export interface ChildSummary {
  id: number;
  fullName: string;
  dateOfBirth: string | null;
  sessionType: string;
  classId: number | null;
  className: string | null;
  classTeacherName: string | null;
}

export interface SchoolClass {
  id: number;
  name: string;
  description: string | null;
  sortOrder: number;
  isActive: boolean;
  classTeacherId: number | null;
  classTeacherName: string | null;
  studentCount: number;
}

export interface StudentParentInfo {
  id: number;
  fullName: string;
  relationship: string;
  phone: string | null;
  email: string | null;
  hasLogin: boolean;
  isActive: boolean;
}

export interface Student {
  id: number;
  fullName: string;
  admissionNo: string | null;
  dateOfBirth: string | null;
  gender: string | null;
  classId: number | null;
  className: string | null;
  classTeacherName: string | null;
  sessionType: string;
  joinedOn: string | null;
  medicalNotes: string | null;
  emergencyContactName: string | null;
  emergencyContactPhone: string | null;
  notes: string | null;
  isActive: boolean;
  parents: StudentParentInfo[];
}

export type StudentSave = Omit<Student, 'id' | 'className' | 'classTeacherName' | 'parents'> & {
  /** Parents to link; null/undefined leaves the links unchanged. */
  parentIds?: number[] | null;
  /** Save even if a child with the same name and date of birth exists. */
  allowDuplicate?: boolean;
};

export interface ParentRecord {
  id: number;
  fullName: string;
  email: string | null;
  phone: string | null;
  relationship: string;
  isActive: boolean;
  createdAt: string;
  hasLogin: boolean;
  username: string | null;
  loginActive: boolean;
  loginPending: boolean;
  children: { id: number; fullName: string; isActive: boolean; className: string | null }[];
}

export interface ParentSave {
  fullName: string;
  email: string | null;
  phone: string | null;
  relationship: string;
  isActive: boolean;
  studentIds: number[];
  createLogin: boolean;
  /** Optional new password for an existing login (changed by the parent at next sign-in). */
  password?: string | null;
}

export interface Announcement {
  id: number;
  title: string;
  body: string;
  classId: number | null;
  className: string | null;
  createdByName: string;
  createdAt: string;
  attachment: { name: string; contentType: string; size: number } | null;
  isRead: boolean;
  canDelete: boolean;
  readCount: number | null;
  audienceCount: number | null;
}

export interface ConversationSummary {
  id: number;
  kind: 'Teacher' | 'Office';
  studentId: number;
  studentName: string;
  className: string | null;
  lastMessageAt: string | null;
  subject: string;
  status: ConversationStatus;
  startedByMe: boolean;
  title: string;
  teacherName: string | null;
  parentNames: string[];
  lastMessage: { text: string; senderName: string; mine: boolean } | null;
  unread: number;
}

export interface ChatMessage {
  id: number;
  conversationId: number;
  senderUserId: number;
  senderName: string;
  senderRole: 'Parent' | 'Teacher' | 'Office';
  body: string;
  sentAt: string;
  attachment: { name: string; contentType: string; size: number } | null;
}

export type ConversationStatus = 'Open' | 'Closed';

export interface ConversationHeader {
  id: number;
  kind: 'Teacher' | 'Office';
  studentId: number;
  subject: string;
  status: ConversationStatus;
  closedAt: string | null;
  closedByName: string | null;
  studentName: string;
  className: string | null;
  teacherName: string | null;
  title: string;
  parents: { fullName: string; relationship: string; hasLogin: boolean }[];
}

export interface MessagePage {
  conversation: ConversationHeader;
  messages: ChatMessage[];
  hasMore: boolean;
  seenUpTo: number;
}

/** Live events from /api/hubs/chat. */
export interface LiveMessage { conversationId: number; message: ChatMessage; }
export interface LiveConversation { conversationId: number; status: ConversationStatus; closedByName: string | null; }
export interface LiveRead { conversationId: number; userId: number; lastReadMessageId: number; byParent: boolean; }

export const SESSION_TYPES = ['Half day', 'Full day', 'Daycare'];
export const RELATIONSHIPS = ['Mother', 'Father', 'Guardian'];

/**
 * School features: classes, children, parents, announcements and parent messages.
 * Also keeps the live connection (SignalR) and the unread counts for the menu badges.
 */
@Injectable({ providedIn: 'root' })
export class SchoolService {
  private api = `${environment.apiUrl}/school`;
  private http = inject(HttpClient);
  private auth = inject(AuthService);
  private isBrowser = isPlatformBrowser(inject(PLATFORM_ID));

  private meSubject = new BehaviorSubject<SchoolMe | null>(null);
  /** Null until loaded (or when school features don't apply to this login). */
  readonly me$ = this.meSubject.asObservable();
  private meFor: string | null = null;

  private unreadMessagesSubject = new BehaviorSubject<number>(0);
  readonly unreadMessages$ = this.unreadMessagesSubject.asObservable();
  private unreadAnnouncementsSubject = new BehaviorSubject<number>(0);
  readonly unreadAnnouncements$ = this.unreadAnnouncementsSubject.asObservable();

  /** New message in any thread this user sees. */
  readonly liveMessage$ = new Subject<LiveMessage>();
  /** Someone read a thread up to a message ("Seen" ticks). */
  readonly liveRead$ = new Subject<LiveRead>();
  /** A conversation was closed or reopened. */
  readonly liveConversation$ = new Subject<LiveConversation>();
  /** A new announcement for this parent. */
  readonly liveAnnouncement$ = new Subject<{ id: number; title: string; className: string | null }>();
  /** A child's day changed: check-in / check-out, daily report published (parents). */
  readonly liveDay$ = new Subject<{ studentId: number; date: string }>();
  /** A parent's absence / pickup note was sent or seen. */
  readonly liveNote$ = new Subject<{ id: number; studentId: number }>();
  /** An invoice was sent, paid or a reminder came (parents). */
  readonly liveFees$ = new Subject<{ studentId: number }>();

  private hub: HubConnection | null = null;

  constructor() {
    // Signing out stops the live connection and forgets this user's school details.
    this.auth.isLoggedIn().subscribe(loggedIn => {
      if (!loggedIn) this.reset();
    });
  }

  // ── Me, badges, live connection ──

  /** Loads /school/me once per login (force = reload) and starts live updates when it applies. */
  loadMe(force = false): Observable<SchoolMe | null> {
    const token = this.auth.getToken();
    if (!token) return of(null);
    if (!force && this.meFor === token && this.meSubject.value) return of(this.meSubject.value);
    return this.http.get<SchoolMe>(`${this.api}/me`).pipe(
      tap(me => {
        this.meFor = token;
        this.meSubject.next(me);
        if (me.enabled && (me.isAdmin || me.isTeacher || me.isParent)) {
          this.refreshUnread();
          this.connect();
        } else {
          this.disconnect();
        }
      }),
      catchError(() => of(null))
    );
  }

  get me(): SchoolMe | null { return this.meSubject.value; }

  refreshUnread(): void {
    const me = this.meSubject.value;
    if (!me?.enabled) return;
    this.http.get<{ count: number }>(`${this.api}/messages/unread-count`)
      .subscribe({ next: r => this.unreadMessagesSubject.next(r.count), error: () => {} });
    if (me.isParent)
      this.http.get<{ count: number }>(`${this.api}/announcements/unread-count`)
        .subscribe({ next: r => this.unreadAnnouncementsSubject.next(r.count), error: () => {} });
  }

  private connecting = false;

  private async connect(): Promise<void> {
    if (!this.isBrowser || this.hub || this.connecting) return;
    this.connecting = true;
    // The SignalR client is only downloaded by logins that use the school features
    const { HubConnectionBuilder, LogLevel } = await import('@microsoft/signalr').finally(() => this.connecting = false);
    if (this.hub || !this.auth.getToken() || !this.meSubject.value?.enabled) return;   // signed out meanwhile
    const hubUrl = environment.apiUrl.replace(/\/$/, '') + '/hubs/chat';
    this.hub = new HubConnectionBuilder()
      .withUrl(hubUrl, { accessTokenFactory: () => this.auth.getToken() ?? '', withCredentials: false })
      .withAutomaticReconnect()
      .configureLogging(LogLevel.Warning)
      .build();

    this.hub.on('message', (e: LiveMessage) => {
      this.liveMessage$.next(e);
      if (e.message.senderUserId !== this.meSubject.value?.userId) this.refreshUnread();
    });
    this.hub.on('read', (e: LiveRead) => {
      this.liveRead$.next(e);
      if (e.userId === this.meSubject.value?.userId) this.refreshUnread();
    });
    this.hub.on('conversation', (e: LiveConversation) => this.liveConversation$.next(e));
    this.hub.on('announcement',(e: { id: number; title: string; className: string | null }) => {
      this.liveAnnouncement$.next(e);
      this.refreshUnread();
    });
    this.hub.on('day', (e: { studentId: number; date: string }) => this.liveDay$.next(e));
    this.hub.on('note', (e: { id: number; studentId: number }) => this.liveNote$.next(e));
    this.hub.on('fees', (e: { studentId: number }) => this.liveFees$.next(e));
    // After a dropped connection, catch up on anything missed
    this.hub.onreconnected(() => this.refreshUnread());

    this.hub.start().catch(err => console.warn('Live updates unavailable; messages still load on refresh.', err));
  }

  private disconnect(): void {
    const hub = this.hub;
    this.hub = null;
    if (hub && hub.state !== 'Disconnected') hub.stop().catch(() => {});
  }

  private reset(): void {
    this.disconnect();
    this.meFor = null;
    this.meSubject.next(null);
    this.unreadMessagesSubject.next(0);
    this.unreadAnnouncementsSubject.next(0);
  }

  // ── Settings ──

  setEnabled(enabled: boolean): Observable<{ enabled: boolean }> {
    return this.http.put<{ enabled: boolean }>(`${this.api}/settings`, { enabled })
      .pipe(tap(() => this.loadMe(true).subscribe()));
  }

  // ── Classes ──

  getClasses(): Observable<SchoolClass[]> { return this.http.get<SchoolClass[]>(`${this.api}/classes`); }
  createClass(c: Partial<SchoolClass>): Observable<{ id: number }> { return this.http.post<{ id: number }>(`${this.api}/classes`, c); }
  updateClass(id: number, c: Partial<SchoolClass>): Observable<{ id: number }> { return this.http.put<{ id: number }>(`${this.api}/classes/${id}`, c); }
  deleteClass(id: number): Observable<void> { return this.http.delete<void>(`${this.api}/classes/${id}`); }

  // ── Children ──

  getStudents(classId?: number | null, includeInactive = false): Observable<Student[]> {
    const params: Record<string, string> = {};
    if (classId) params['classId'] = String(classId);
    if (includeInactive) params['includeInactive'] = 'true';
    return this.http.get<Student[]>(`${this.api}/students`, { params });
  }
  createStudent(s: StudentSave): Observable<{ id: number }> { return this.http.post<{ id: number }>(`${this.api}/students`, s); }
  updateStudent(id: number, s: StudentSave): Observable<{ id: number }> { return this.http.put<{ id: number }>(`${this.api}/students/${id}`, s); }
  deleteStudent(id: number): Observable<void> { return this.http.delete<void>(`${this.api}/students/${id}`); }

  // ── Parents ──

  getParents(): Observable<ParentRecord[]> { return this.http.get<ParentRecord[]>(`${this.api}/parents`); }
  createParent(p: ParentSave): Observable<{ id: number; message: string | null }> { return this.http.post<{ id: number; message: string | null }>(`${this.api}/parents`, p); }
  updateParent(id: number, p: ParentSave): Observable<{ id: number; message: string | null }> { return this.http.put<{ id: number; message: string | null }>(`${this.api}/parents/${id}`, p); }
  inviteParent(id: number): Observable<{ message: string }> { return this.http.post<{ message: string }>(`${this.api}/parents/${id}/invite`, {}); }
  deleteParent(id: number): Observable<void> { return this.http.delete<void>(`${this.api}/parents/${id}`); }

  // ── Announcements ──

  getAnnouncements(): Observable<Announcement[]> { return this.http.get<Announcement[]>(`${this.api}/announcements`); }
  createAnnouncement(title: string, body: string, classId: number | null, file: File | null): Observable<{ id: number; sentTo: number }> {
    const form = new FormData();
    form.append('title', title);
    form.append('body', body);
    if (classId) form.append('classId', String(classId));
    if (file) form.append('file', file);
    return this.http.post<{ id: number; sentTo: number }>(`${this.api}/announcements`, form);
  }
  markAnnouncementRead(id: number): Observable<void> {
    return this.http.post<void>(`${this.api}/announcements/${id}/read`, {}).pipe(tap(() => this.refreshUnread()));
  }
  deleteAnnouncement(id: number): Observable<void> { return this.http.delete<void>(`${this.api}/announcements/${id}`); }
  announcementAttachment(id: number): Observable<Blob> {
    return this.http.get(`${this.api}/announcements/${id}/attachment`, { responseType: 'blob' });
  }

  // ── Messages ──

  getConversations(): Observable<ConversationSummary[]> { return this.http.get<ConversationSummary[]>(`${this.api}/conversations`); }
  openConversation(studentId: number, kind: 'Teacher' | 'Office'): Observable<{ id: number }> {
    return this.http.post<{ id: number }>(`${this.api}/conversations/open`, { studentId, kind });
  }
  /** Starts a new conversation about a child, with a subject and the first message. */
  startConversation(studentId: number, kind: 'Teacher' | 'Office', subject: string, body: string, file: File | null)
    : Observable<{ id: number; message: ChatMessage }> {
    const form = new FormData();
    form.append('studentId', String(studentId));
    form.append('kind', kind);
    form.append('subject', subject);
    form.append('body', body);
    if (file) form.append('file', file);
    return this.http.post<{ id: number; message: ChatMessage }>(`${this.api}/conversations`, form);
  }
  setConversationStatus(conversationId: number, close: boolean): Observable<{ status: ConversationStatus; closedByName: string | null }> {
    return this.http.post<{ status: ConversationStatus; closedByName: string | null }>(
      `${this.api}/conversations/${conversationId}/${close ? 'close' : 'reopen'}`, {});
  }
  getMessages(conversationId: number, before?: number): Observable<MessagePage> {
    const params: Record<string, string> = before ? { before: String(before) } : {};
    return this.http.get<MessagePage>(`${this.api}/conversations/${conversationId}/messages`, { params });
  }
  sendMessage(conversationId: number, body: string, file: File | null): Observable<ChatMessage> {
    const form = new FormData();
    form.append('body', body);
    if (file) form.append('file', file);
    return this.http.post<ChatMessage>(`${this.api}/conversations/${conversationId}/messages`, form);
  }
  markRead(conversationId: number, lastMessageId: number): Observable<void> {
    return this.http.post<void>(`${this.api}/conversations/${conversationId}/read`, { lastMessageId })
      .pipe(tap(() => this.refreshUnread()));
  }
  attachment(messageId: number): Observable<Blob> {
    return this.http.get(`${this.api}/attachments/${messageId}`, { responseType: 'blob' });
  }

  /** Opens a protected file (needs the login token) in a new tab. */
  openBlob(blob$: Observable<Blob>): void {
    // Open the tab now (popup blockers allow it during the click), fill it when the file arrives
    const tab = window.open('', '_blank');
    blob$.pipe(map(b => URL.createObjectURL(b))).subscribe({
      next: url => {
        if (tab) tab.location.href = url; else window.open(url, '_blank');
        setTimeout(() => URL.revokeObjectURL(url), 60_000);
      },
      error: () => tab?.close()
    });
  }
}

/** "3 years 2 months" from a date of birth (children's ages on the class lists). */
export function ageText(dob: string | null): string {
  if (!dob) return '';
  const d = new Date(dob);
  const now = new Date();
  let months = (now.getFullYear() - d.getFullYear()) * 12 + (now.getMonth() - d.getMonth());
  if (now.getDate() < d.getDate()) months--;
  if (months < 0) return '';
  const y = Math.floor(months / 12), m = months % 12;
  if (y === 0) return `${m} month${m === 1 ? '' : 's'}`;
  return m === 0 ? `${y} year${y === 1 ? '' : 's'}` : `${y}y ${m}m`;
}

/** API times are UTC; some arrive without a zone marker. Returns a Date for the date pipe. */
export function utc(value: string | null | undefined): Date | null {
  if (!value) return null;
  return new Date(/[zZ]|[+-]\d\d:?\d\d$/.test(value) ? value : value + 'Z');
}
