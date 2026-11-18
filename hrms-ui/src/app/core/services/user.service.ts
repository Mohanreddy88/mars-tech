import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';
import { AppUser, UserRequest, UserUpdateRequest, AvailableEmployee } from '../models/user.model';
import { environment } from '../../../environments/environment';

@Injectable({ providedIn: 'root' })
export class UserService {
  private apiUrl = `${environment.apiUrl}/users`;

  constructor(private http: HttpClient) {}

  getAll(): Observable<AppUser[]> {
    return this.http.get<AppUser[]>(this.apiUrl);
  }

  getById(id: number): Observable<AppUser> {
    return this.http.get<AppUser>(`${this.apiUrl}/${id}`);
  }

  create(payload: UserRequest): Observable<AppUser & { welcomeEmailSent: boolean }> {
    return this.http.post<AppUser & { welcomeEmailSent: boolean }>(this.apiUrl, payload);
  }

  /** Active employees that don't have a login yet. */
  availableEmployees(): Observable<AvailableEmployee[]> {
    return this.http.get<AvailableEmployee[]>(`${this.apiUrl}/available-employees`);
  }

  /** New "Set my password" email. */
  sendWelcome(id: number): Observable<{ message: string }> {
    return this.http.post<{ message: string }>(`${this.apiUrl}/${id}/send-welcome`, {});
  }

  update(id: number, payload: UserUpdateRequest): Observable<AppUser> {
    return this.http.put<AppUser>(`${this.apiUrl}/${id}`, payload);
  }

  delete(id: number): Observable<void> {
    return this.http.delete<void>(`${this.apiUrl}/${id}`);
  }
}
