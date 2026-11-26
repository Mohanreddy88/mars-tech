import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpEvent, HttpParams } from '@angular/common/http';
import { Observable, of, shareReplay, map, catchError } from 'rxjs';
import { environment } from '../../../environments/environment';

// ── Timetable ──

export interface TimetableLogInfo { note: string; updatedByName: string; updatedAt: string; }

export interface TimetableSlot {
  id: number;
  classId: number;
  className: string;
  /** 1 = Monday … 7 = Sunday. */
  dayOfWeek: number;
  startTime: string;   // "HH:mm"
  endTime: string;
  subject: string;
  notes: string | null;
  teacherEmployeeId: number | null;
  /** The period's teacher, or the class teacher when none is named. */
  teacherName: string | null;
  /** "What we covered" on the requested date (that weekday's periods only). */
  log: TimetableLogInfo | null;
  canWriteLog: boolean;
}

export interface TimetableWeek {
  date: string;
  dayOfWeek: number;
  slots: TimetableSlot[];
  classId?: number | null;
  className?: string | null;
}

export interface TimetableSlotSave {
  classId: number;
  dayOfWeek: number;
  startTime: string;
  endTime: string;
  subject: string;
  teacherEmployeeId: number | null;
  notes: string | null;
}

/** Daily record (admins): what was on the timetable each date, with the teachers' notes. */
export interface TimetableRecordPeriod {
  slotId: number;
  classId: number;
  className: string;
  startTime: string;
  endTime: string;
  subject: string;
  teacherName: string | null;
  note: string | null;
  noteBy: string | null;
  noteAt: string | null;
}

export interface TimetableRecord {
  from: string;
  to: string;
  today: string;
  days: { date: string; dayOfWeek: number; periods: TimetableRecordPeriod[] }[];
  summary: { periods: number; written: number };
}

export const WEEK_DAYS = [
  { n: 1, short: 'Mon', long: 'Monday' }, { n: 2, short: 'Tue', long: 'Tuesday' }, { n: 3, short: 'Wed', long: 'Wednesday' },
  { n: 4, short: 'Thu', long: 'Thursday' }, { n: 5, short: 'Fri', long: 'Friday' }, { n: 6, short: 'Sat', long: 'Saturday' },
  { n: 7, short: 'Sun', long: 'Sunday' }
];

// ── Stories ──

export interface StoryMedia {
  id: number;
  kind: 'Photo' | 'Video';
  fileName: string;
  contentType: string;
  sizeBytes: number;
  /** Signed link relative to the API root (valid ~12 h). */
  url: string;
  downloadUrl: string;
}

export interface Story {
  id: number;
  classId: number | null;
  className: string | null;
  caption: string | null;
  createdByName: string;
  createdAt: string;
  publishedAt: string | null;
  canEdit: boolean;
  media: StoryMedia[];
}

@Injectable({ providedIn: 'root' })
export class SchoolExtrasService {
  private http = inject(HttpClient);
  private api = `${environment.apiUrl}/school`;
  /** Object URLs of profile photos, by "<kind>/<id>?v=<version>". */
  private photos = new Map<string, Observable<string | null>>();

  /** Full URL for a path the API returns relative to its root (story media links). */
  mediaUrl(relative: string): string { return `${environment.apiUrl.replace(/\/$/, '')}/${relative}`; }

  // ── Timetable ──
  /** The daily record from..to (at most 31 days); classId null = every class. */
  timetableRecord(classId: number | null, from: string, to: string): Observable<TimetableRecord> {
    let params = new HttpParams().set('from', from).set('to', to);
    if (classId) params = params.set('classId', classId);
    return this.http.get<TimetableRecord>(`${this.api}/timetable/record`, { params });
  }

  classTimetable(classId: number, date?: string): Observable<TimetableWeek> {
    let params = new HttpParams().set('classId', classId);
    if (date) params = params.set('date', date);
    return this.http.get<TimetableWeek>(`${this.api}/timetable`, { params });
  }
  childTimetable(studentId: number, date?: string): Observable<TimetableWeek> {
    return this.http.get<TimetableWeek>(`${this.api}/timetable/child/${studentId}`, { params: date ? { date } : {} });
  }
  myTimetable(date?: string): Observable<TimetableWeek> {
    return this.http.get<TimetableWeek>(`${this.api}/timetable/mine`, { params: date ? { date } : {} });
  }
  timetableTeachers(): Observable<{ id: number; name: string }[]> { return this.http.get<{ id: number; name: string }[]>(`${this.api}/timetable/teachers`); }
  createSlot(s: TimetableSlotSave): Observable<{ id: number }> { return this.http.post<{ id: number }>(`${this.api}/timetable/slots`, s); }
  updateSlot(id: number, s: TimetableSlotSave): Observable<{ id: number }> { return this.http.put<{ id: number }>(`${this.api}/timetable/slots/${id}`, s); }
  deleteSlot(id: number): Observable<void> { return this.http.delete<void>(`${this.api}/timetable/slots/${id}`); }
  copyDay(classId: number, fromDay: number, toDays: number[]): Observable<{ copied: number }> {
    return this.http.post<{ copied: number }>(`${this.api}/timetable/copy`, { classId, fromDay, toDays });
  }
  saveLog(slotId: number, date: string, note: string): Observable<TimetableLogInfo | null> {
    return this.http.put<TimetableLogInfo | null>(`${this.api}/timetable/slots/${slotId}/log`, { date, note });
  }

  // ── Profile photos (children / parents) ──

  /** Object URL of the photo (cached per version), or null when there is none or it can't be loaded. */
  photo(kind: 'students' | 'parents', id: number, version: string | null | undefined): Observable<string | null> {
    if (!version) return of(null);
    const key = `${kind}/${id}?v=${version}`;
    let cached = this.photos.get(key);
    if (!cached) {
      cached = this.http.get(`${this.api}/${kind}/${id}/photo`, { params: { v: version }, responseType: 'blob' }).pipe(
        map(b => URL.createObjectURL(b)),
        catchError(() => of(null)),
        shareReplay(1));
      this.photos.set(key, cached);
    }
    return cached;
  }
  setPhoto(kind: 'students' | 'parents', id: number, file: File): Observable<{ photoUpdatedAt: string }> {
    const fd = new FormData();
    fd.append('file', file);
    return this.http.put<{ photoUpdatedAt: string }>(`${this.api}/${kind}/${id}/photo`, fd);
  }
  deletePhoto(kind: 'students' | 'parents', id: number): Observable<void> { return this.http.delete<void>(`${this.api}/${kind}/${id}/photo`); }

  // ── Stories ──
  stories(skip = 0, take = 20, classId?: number | null): Observable<Story[]> {
    let params = new HttpParams().set('skip', skip).set('take', take);
    if (classId) params = params.set('classId', classId);
    return this.http.get<Story[]>(`${this.api}/stories`, { params });
  }
  story(id: number): Observable<Story> { return this.http.get<Story>(`${this.api}/stories/${id}`); }
  storyClasses(): Observable<{ wholeSchool: boolean; classes: { id: number; name: string }[] }> {
    return this.http.get<{ wholeSchool: boolean; classes: { id: number; name: string }[] }>(`${this.api}/stories/classes`);
  }
  createStory(classId: number | null, caption: string | null): Observable<{ id: number }> {
    return this.http.post<{ id: number }>(`${this.api}/stories`, { classId, caption });
  }
  updateStory(id: number, classId: number | null, caption: string | null): Observable<{ id: number }> {
    return this.http.put<{ id: number }>(`${this.api}/stories/${id}`, { classId, caption });
  }
  /** Upload one file with progress events. */
  addStoryMedia(id: number, file: File): Observable<HttpEvent<StoryMedia>> {
    const fd = new FormData();
    fd.append('file', file);
    return this.http.post<StoryMedia>(`${this.api}/stories/${id}/media`, fd, { reportProgress: true, observe: 'events' });
  }
  deleteStoryMedia(mediaId: number): Observable<void> { return this.http.delete<void>(`${this.api}/stories/media/${mediaId}`); }
  publishStory(id: number): Observable<{ id: number; sentTo: number }> { return this.http.post<{ id: number; sentTo: number }>(`${this.api}/stories/${id}/publish`, {}); }
  deleteStory(id: number): Observable<void> { return this.http.delete<void>(`${this.api}/stories/${id}`); }
}
