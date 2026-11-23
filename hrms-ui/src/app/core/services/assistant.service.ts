import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpResponse } from '@angular/common/http';
import { Observable, Subject, map } from 'rxjs';
import { environment } from '../../../environments/environment';

// ── Models ────────────────────────────────────────────────────────────────

export interface BotAction { key: string; label: string; }

export interface BotAnswer {
  id: number;
  question: string;
  answer: string;
  action: BotAction | null;
  /** AI answers: a report or document to download (API path relative to /api). */
  download?: { label: string; path: string } | null;
}

export interface BotTopic { category: string; items: BotAnswer[]; }

export interface BotStart {
  greeting: string;
  topics: BotTopic[];
  actions: BotAction[];
  canMessageSchool: boolean;
  /** AI answers are on for this company. */
  ai: boolean;
  /** Shown at the top of the chat while AI answers are stopped (e.g. no Anthropic credit). */
  aiNotice?: BotAiNotice | null;
}

/**
 * A note about AI answers for the top of the chat. Admins get "error" (stopped, with the fix and
 * a link) or "warning"; everyone else "info" ("smart answers are paused…", no billing details).
 */
export interface BotAiNotice {
  level: 'error' | 'warning' | 'info';
  message: string;
  link: string | null;
  linkLabel: string | null;
}

export interface BotAskResult {
  /** Small talk or "no answer" text; null when an answer was found. */
  reply: string | null;
  answer: BotAnswer | null;
  related: { id: number; question: string }[];
  unanswered: boolean;
  /** Who answered: the FAQ list, the AI, or nobody. */
  source: 'faq' | 'ai' | 'none';
  /** Set when the AI is stopped or just failed; this answer came from the list. */
  aiNotice?: BotAiNotice | null;
}

/** An earlier turn of the chat, sent back so the AI can follow up. */
export interface BotTurn { fromUser: boolean; text: string; }

export interface BotAiUsage { questions: number; answered: number; inputTokens: number; outputTokens: number; }
export interface BotAiStatus {
  /** A key is available (the company's own or the server's). */
  configured: boolean;
  /** Whose key answers: the company's (Connect AI), the server's, or none. */
  keySource: 'company' | 'server' | null;
  /** Last characters of the company's key, e.g. "…a1b2". */
  keyHint: string | null;
  keySetAt: string | null;
  /** A key is saved but can't be read any more: connect it again. */
  keyUnreadable: boolean;
  serverKeyAvailable: boolean;
  enabled: boolean;
  model: string;
  dailyLimitPerUser: number;
  today: BotAiUsage;
  last30Days: BotAiUsage;
  /** The latest AI failure (e.g. no Anthropic credit), until an AI answer works again. */
  problem: BotAiProblem | null;
}

export interface BotAiProblem {
  /** What went wrong and how to fix it, e.g. "Your Anthropic credit has run out…". */
  message: string;
  /** When it last failed (UTC). */
  at: string;
  /** Questions in a row that failed. */
  failures: number;
}

export type BotAudience = 'All' | 'Parent' | 'Employee';

export interface BotFaq {
  id: number;
  category: string;
  question: string;
  answer: string;
  keywords: string | null;
  audience: BotAudience;
  action: string | null;
  sortOrder: number;
  isActive: boolean;
  updatedAt: string;
}

export type BotFaqSave = Omit<BotFaq, 'id' | 'updatedAt' | 'sortOrder'> & { sortOrder: number | null };

export interface BotAdminList {
  faqs: BotFaq[];
  audiences: BotAudience[];
  actions: { key: string; label: string; audience: BotAudience }[];
  schoolFeatures: boolean;
  unansweredCount: number;
}

export interface BotUnanswered { id: number; text: string; audience: 'Parent' | 'Employee'; askedAt: string; }

/** The help chatbot (/api/assistant): answers from the company's own questions and answers. */
@Injectable({ providedIn: 'root' })
export class AssistantService {
  private http = inject(HttpClient);
  private api = `${environment.apiUrl}/assistant`;

  /** The chat saw AI answers stop or start working again (the Chatbot page refreshes its AI card). */
  readonly aiChanged = new Subject<void>();

  start(): Observable<BotStart> { return this.http.get<BotStart>(`${this.api}/start`); }
  ask(text: string, history: BotTurn[] = []): Observable<BotAskResult> {
    return this.http.post<BotAskResult>(`${this.api}/ask`, { text, history });
  }

  /**
   * Downloads a file the assistant offered and saves it under the server's file name.
   * The path comes from our own API's answer (relative to /api), and the login token is sent with it.
   */
  downloadFile(path: string): Observable<void> {
    const url = `${environment.apiUrl.replace(/\/$/, '')}/${path.replace(/^\//, '')}`;
    return this.http.get(url, { responseType: 'blob', observe: 'response' }).pipe(map((res: HttpResponse<Blob>) => {
      const cd = res.headers.get('content-disposition') ?? '';
      const name = /filename\*=UTF-8''([^;]+)/i.exec(cd)?.[1] ?? /filename="?([^";]+)"?/i.exec(cd)?.[1] ?? 'download';
      const link = document.createElement('a');
      link.href = URL.createObjectURL(res.body!);
      link.download = decodeURIComponent(name);
      link.click();
      setTimeout(() => URL.revokeObjectURL(link.href), 10_000);
    }));
  }

  // Admin: AI answers
  aiStatus(): Observable<BotAiStatus> { return this.http.get<BotAiStatus>(`${this.api}/admin/ai`); }
  /** Connects the company's own Anthropic API key (tested by the server, stored encrypted). */
  connectKey(apiKey: string): Observable<{ connected: boolean; keyHint: string; enabled: boolean }> {
    return this.http.put<{ connected: boolean; keyHint: string; enabled: boolean }>(`${this.api}/admin/ai/key`, { apiKey });
  }
  disconnectKey(): Observable<{ enabled: boolean }> { return this.http.delete<{ enabled: boolean }>(`${this.api}/admin/ai/key`); }
  setAi(enabled: boolean): Observable<{ enabled: boolean }> {
    return this.http.put<{ enabled: boolean }>(`${this.api}/admin/ai`, { enabled });
  }

  // Admin
  adminList(): Observable<BotAdminList> { return this.http.get<BotAdminList>(`${this.api}/admin/faqs`); }
  create(faq: BotFaqSave): Observable<{ id: number }> { return this.http.post<{ id: number }>(`${this.api}/admin/faqs`, faq); }
  update(id: number, faq: BotFaqSave): Observable<void> { return this.http.put<void>(`${this.api}/admin/faqs/${id}`, faq); }
  delete(id: number): Observable<void> { return this.http.delete<void>(`${this.api}/admin/faqs/${id}`); }
  addStarter(): Observable<{ added: number }> { return this.http.post<{ added: number }>(`${this.api}/admin/faqs/starter`, {}); }
  unanswered(): Observable<BotUnanswered[]> { return this.http.get<BotUnanswered[]>(`${this.api}/admin/unanswered`); }
  deleteUnanswered(id: number): Observable<void> { return this.http.delete<void>(`${this.api}/admin/unanswered/${id}`); }
  clearUnanswered(): Observable<void> { return this.http.delete<void>(`${this.api}/admin/unanswered`); }
}
