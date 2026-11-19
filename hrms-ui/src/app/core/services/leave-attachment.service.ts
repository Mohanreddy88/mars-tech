import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';
import { environment } from '../../../environments/environment';

export const LEAVE_DOC_MAX_BYTES = 5 * 1024 * 1024;
export const LEAVE_DOC_ACCEPT = '.pdf,.jpg,.jpeg,.png,application/pdf,image/jpeg,image/png';

/** MC letter / supporting document for a leave request (owner or Admin only). */
@Injectable({ providedIn: 'root' })
export class LeaveAttachmentService {
  private apiUrl = `${environment.apiUrl}/leave-attachments`;

  constructor(private http: HttpClient) {}

  upload(leaveRequestId: number, file: File): Observable<{ fileName: string }> {
    const form = new FormData();
    form.append('file', file, file.name);
    return this.http.post<{ fileName: string }>(`${this.apiUrl}/${leaveRequestId}`, form);
  }

  remove(leaveRequestId: number): Observable<{ message: string }> {
    return this.http.delete<{ message: string }>(`${this.apiUrl}/${leaveRequestId}`);
  }

  /**
   * Opens the document in a new tab. The file needs the login token, so it is fetched
   * first and shown from memory; the tab is opened straight away so pop-up blockers allow it.
   */
  open(leaveRequestId: number, onError: (message: string) => void): void {
    const tab = window.open('', '_blank');
    this.http.get(`${this.apiUrl}/${leaveRequestId}`, { responseType: 'blob' }).subscribe({
      next: (blob) => {
        const url = URL.createObjectURL(blob);
        if (tab) tab.location.href = url; else window.location.href = url;
        setTimeout(() => URL.revokeObjectURL(url), 60_000);
      },
      error: (err) => {
        tab?.close();
        onError(err?.status === 404 ? 'No document has been uploaded for this leave.' : 'Could not open the document.');
      }
    });
  }

  /** Checks type and size before uploading; returns an error message or null. */
  static validate(file: File): string | null {
    const okType = /\.(pdf|jpe?g|png)$/i.test(file.name);
    if (!okType) return 'Choose a PDF, JPG or PNG file.';
    if (file.size > LEAVE_DOC_MAX_BYTES) return 'The file must be 5 MB or smaller.';
    return null;
  }
}
