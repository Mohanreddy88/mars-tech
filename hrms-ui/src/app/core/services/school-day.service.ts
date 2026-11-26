import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable } from 'rxjs';
import { environment } from '../../../environments/environment';

// ── School phase 3: the child's day (attendance, parents' notes, daily report) ──

export interface AttendanceInfo {
  status: 'Present' | 'Absent';
  checkIn: string | null;       // "08:05" school time
  checkInBy: string | null;
  checkOut: string | null;
  checkOutBy: string | null;
  pickedUpBy: string | null;
  absenceReason: string | null;
  /** Checked in after the "late after" time. */
  isLate?: boolean;
  /** Marked absent automatically (not in by the "absent after" time). */
  autoAbsent?: boolean;
  /** Checked out automatically in the evening (the teacher didn't). */
  autoCheckOut?: boolean;
}

export interface ParentNoteInfo {
  id: number;
  studentId: number;
  kind: 'Absence' | 'Pickup';
  fromDate: string;
  toDate: string;
  pickupName: string | null;
  pickupPhone: string | null;
  pickupTime: string | null;
  message: string | null;
  createdByName: string;
  createdAt: string;
  seenAt: string | null;
  seenByName: string | null;
  cancelled: boolean;
}

export interface AttendanceRow {
  studentId: number;
  fullName: string;
  classId: number | null;
  className: string | null;
  sessionType: string;
  medicalNotes: string | null;
  parents: { fullName: string; relationship: string; phone: string | null }[];
  attendance: AttendanceInfo | null;
  notes: ParentNoteInfo[];
  report: { published: boolean; photos: number; mood: string | null } | null;
  /** Teachers can't check this child in / out: absent (staff-marked, or parent-reported and approved). */
  locked?: boolean;
}

export interface AttendanceDay {
  date: string;
  today: string;
  /** Teachers change only today's attendance; admins any day. */
  canEdit?: boolean;
  rows: AttendanceRow[];
  summary: { total: number; present: number; checkedOut: number; absent: number; notMarked: number; reportsPublished: number; late?: number };
  /** School timings ("HH:mm"): check-out suggests the session's end. */
  times?: SchoolTimes;
}

export interface SchoolTimes {
  start: string; lateAfter: string; absentAfter: string;
  halfDayEnd: string; fullDayEnd: string; daycareEnd: string;
  autoCheckOutAt: string; auto: boolean;
}

export interface DailyReportInfo {
  id: number;
  date: string;
  breakfast: string | null;
  lunch: string | null;
  snack: string | null;
  napFrom: string | null;
  napTo: string | null;
  toilet: string | null;
  mood: string | null;
  activities: string | null;
  teacherNote: string | null;
  publishedAt: string | null;
  updatedByName: string;
  updatedAt: string;
  photos: { id: number; fileName: string }[];
}

export type DailyReportSave = Omit<DailyReportInfo, 'id' | 'date' | 'publishedAt' | 'updatedByName' | 'updatedAt' | 'photos'> & { publish?: boolean };

export interface ChildDay {
  child: { id: number; fullName: string; classId: number | null; className: string | null; teacher: string | null };
  date: string;
  today: string;
  attendance: AttendanceInfo | null;
  report: DailyReportInfo | null;
  notes: ParentNoteInfo[];
}

export interface NoteSave {
  studentId: number;
  kind: 'Absence' | 'Pickup';
  fromDate: string;
  toDate?: string | null;
  pickupName?: string | null;
  pickupPhone?: string | null;
  pickupTime?: string | null;
  message?: string | null;
}

export const MEAL_AMOUNTS = ['All', 'Most', 'Some', 'None'];
export const MOODS: { value: string; icon: string }[] = [
  { value: 'Happy',  icon: '😄' },
  { value: 'Calm',   icon: '🙂' },
  { value: 'Tired',  icon: '🥱' },
  { value: 'Upset',  icon: '😢' },
  { value: 'Unwell', icon: '🤒' },
];
export const moodIcon = (m: string | null | undefined) => MOODS.find(x => x.value === m)?.icon ?? '';

/** yyyy-mm-dd in Malaysia (the school's calendar), whatever the browser's time zone. */
export function schoolToday(): string {
  return new Date(Date.now() + 8 * 3600_000).toISOString().substring(0, 10);
}

/** "2026-11-21" ± days. */
export function addDays(date: string, days: number): string {
  const d = new Date(date + 'T00:00:00Z');
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().substring(0, 10);
}

/** "Sat 21 Nov" */
export function dayLabel(date: string): string {
  return new Date(date + 'T00:00:00Z').toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short', timeZone: 'UTC' });
}

@Injectable({ providedIn: 'root' })
export class SchoolDayService {
  private api = `${environment.apiUrl}/school`;
  private http = inject(HttpClient);

  // Attendance (staff)
  getAttendance(classId: number | null, date: string): Observable<AttendanceDay> {
    let p = new HttpParams().set('date', date);
    if (classId) p = p.set('classId', classId);
    return this.http.get<AttendanceDay>(`${this.api}/attendance`, { params: p });
  }
  checkIn(studentId: number, date: string, time?: string | null): Observable<AttendanceInfo> {
    return this.http.post<AttendanceInfo>(`${this.api}/attendance/${studentId}/check-in`, { date, time: time || null });
  }
  checkOut(studentId: number, date: string, pickedUpBy: string, time?: string | null): Observable<AttendanceInfo> {
    return this.http.post<AttendanceInfo>(`${this.api}/attendance/${studentId}/check-out`, { date, pickedUpBy, time: time || null });
  }
  markAbsent(studentId: number, date: string, reason: string | null): Observable<AttendanceInfo> {
    return this.http.post<AttendanceInfo>(`${this.api}/attendance/${studentId}/absent`, { date, reason });
  }
  clearAttendance(studentId: number, date: string): Observable<void> {
    return this.http.delete<void>(`${this.api}/attendance/${studentId}`, { params: { date } });
  }

  // Parents' notes
  getNotes(studentId?: number | null): Observable<ParentNoteInfo[]> {
    let p = new HttpParams();
    if (studentId) p = p.set('studentId', studentId);
    return this.http.get<ParentNoteInfo[]>(`${this.api}/notes`, { params: p });
  }
  createNote(n: NoteSave): Observable<ParentNoteInfo> { return this.http.post<ParentNoteInfo>(`${this.api}/notes`, n); }
  cancelNote(id: number): Observable<ParentNoteInfo> { return this.http.post<ParentNoteInfo>(`${this.api}/notes/${id}/cancel`, {}); }
  markNoteSeen(id: number): Observable<ParentNoteInfo> { return this.http.post<ParentNoteInfo>(`${this.api}/notes/${id}/seen`, {}); }

  // Day view and daily report
  getDay(studentId: number, date: string): Observable<ChildDay> {
    return this.http.get<ChildDay>(`${this.api}/children/${studentId}/day`, { params: { date } });
  }
  /** Days with attendance or a sent report; default the last 30 days (at most 62 days). */
  getDays(studentId: number, from?: string, to?: string): Observable<{ date: string; status: string | null; report: boolean }[]> {
    let p = new HttpParams();
    if (from) p = p.set('from', from);
    if (to) p = p.set('to', to);
    return this.http.get<{ date: string; status: string | null; report: boolean }[]>(`${this.api}/children/${studentId}/days`, { params: p });
  }


  saveReport(studentId: number, date: string, r: DailyReportSave): Observable<DailyReportInfo> {
    return this.http.put<DailyReportInfo>(`${this.api}/reports/${studentId}`, r, { params: { date } });
  }
  addPhoto(studentId: number, date: string, file: File): Observable<{ id: number; count: number }> {
    const fd = new FormData();
    fd.append('file', file);
    return this.http.post<{ id: number; count: number }>(`${this.api}/reports/${studentId}/photos`, fd, { params: { date } });
  }
  deletePhoto(photoId: number): Observable<void> { return this.http.delete<void>(`${this.api}/reports/photos/${photoId}`); }
  photo(photoId: number): Observable<Blob> { return this.http.get(`${this.api}/reports/photos/${photoId}`, { responseType: 'blob' }); }
  publish(date: string, studentIds: number[]): Observable<{ published: number }> {
    return this.http.post<{ published: number }>(`${this.api}/reports/publish`, { date, studentIds });
  }
}
