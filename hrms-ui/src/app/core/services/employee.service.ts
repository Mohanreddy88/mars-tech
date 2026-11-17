import { Injectable } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable } from 'rxjs';
import { Employee, EmployeeRequest } from '../models/employee.model';
import { environment } from '../../../environments/environment';

@Injectable({ providedIn: 'root' })
export class EmployeeService {
  private apiUrl = `${environment.apiUrl}/employees`;

  constructor(private http: HttpClient) {}

  /**
   * Get all employees.
   * - Admin: retrieves ALL records (active + inactive)
   * - User: retrieves only their own record(s) filtered by username
   */
  getAll(includeInactive = false): Observable<Employee[]> {
    let params = new HttpParams();
    if (includeInactive) {
      params = params.set('includeInactive', 'true');
    }
    return this.http.get<Employee[]>(this.apiUrl, { params });
  }

  /**
   * Get active employees only (for dropdowns, etc.)
   */
  getActive(): Observable<Employee[]> {
    return this.http.get<Employee[]>(`${this.apiUrl}/active`);
  }

  getById(id: number): Observable<Employee> {
    return this.http.get<Employee>(`${this.apiUrl}/${id}`);
  }

  create(payload: EmployeeRequest): Observable<EmployeeCreateResult> {
    return this.http.post<EmployeeCreateResult>(this.apiUrl, payload);
  }

  /** Email the employee a new "Set my password" link (creates their login if missing). */
  sendWelcome(id: number): Observable<{ message: string; username: string; email: string; userCreated: boolean }> {
    return this.http.post<{ message: string; username: string; email: string; userCreated: boolean }>(`${this.apiUrl}/${id}/send-welcome`, {});
  }

  update(id: number, payload: EmployeeRequest): Observable<void> {
    return this.http.put<void>(`${this.apiUrl}/${id}`, payload);
  }

  delete(id: number): Observable<void> {
    return this.http.delete<void>(`${this.apiUrl}/${id}`);
  }

  /**
   * Upload profile picture for an employee
   */
  uploadProfilePicture(formData: FormData): Observable<any> {
    return this.http.post(`${environment.apiUrl}/fileupload/profile`, formData);
  }

  /**
   * Delete profile picture
   */
  deleteProfilePicture(fileName: string): Observable<any> {
    return this.http.delete(`${environment.apiUrl}/fileupload/profile/${fileName}`);
  }
}

/** Response of POST /api/employees. */
export interface EmployeeCreateResult {
  message: string;
  employeeCode: string;
  id: number;
  userCreated: boolean;
  userAlreadyExists: boolean;
  username: string | null;
  welcomeEmailSent: boolean;
  email: string;
}
