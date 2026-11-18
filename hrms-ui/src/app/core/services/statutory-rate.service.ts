import { Injectable } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable } from 'rxjs';
import { environment } from '../../../environments/environment';

/** SOCSO amounts (RM) for monthly wages up to `upTo` (null = and above). */
export interface SocsoBand { upTo: number | null; employee: number; employer: number; }

/** Tax rate (%) for annual chargeable income up to `upTo` (null = and above). */
export interface TaxBand { upTo: number | null; rate: number; }

export interface StatutoryRateSetRequest {
  name: string;
  effectiveFrom: string;               // yyyy-MM-dd
  notes?: string | null;
  epfEmployeeRate: number;             // %
  epfEmployerRate: number;             // % (wages up to threshold)
  epfEmployerRateAboveThreshold: number;
  epfEmployerThreshold: number;        // RM
  socsoBands: SocsoBand[];
  eisEmployeeRate: number;             // %
  eisEmployerRate: number;             // %
  eisWageCeiling: number;              // RM
  taxPersonalRelief: number;           // RM per year
  taxBands: TaxBand[];
}

export interface StatutoryRateSet extends StatutoryRateSetRequest {
  id: number;
  createdAt: string;
  updatedAt?: string | null;
  payrollsUsing: number;
  isCurrent: boolean;
}

export interface StatutoryPreview {
  wage: number;
  epfEmployeeRate: number; epfEmployerRate: number;
  epfEmployee: number; epfEmployer: number;
  socsoEmployee: number; socsoEmployer: number;
  eisEmployee: number; eisEmployer: number;
  pcb: number;
  totalEmployeeDeductions: number;
  netPay: number;
  totalEmployerCost: number;
}

@Injectable({ providedIn: 'root' })
export class StatutoryRateService {
  private apiUrl = `${environment.apiUrl}/statutoryrates`;

  constructor(private http: HttpClient) {}

  getAll(): Observable<StatutoryRateSet[]> {
    return this.http.get<StatutoryRateSet[]>(this.apiUrl);
  }

  forMonth(month: number, year: number): Observable<StatutoryRateSet> {
    const params = new HttpParams().set('month', month).set('year', year);
    return this.http.get<StatutoryRateSet>(`${this.apiUrl}/for-month`, { params });
  }

  create(req: StatutoryRateSetRequest): Observable<StatutoryRateSet> {
    return this.http.post<StatutoryRateSet>(this.apiUrl, req);
  }

  update(id: number, req: StatutoryRateSetRequest): Observable<StatutoryRateSet> {
    return this.http.put<StatutoryRateSet>(`${this.apiUrl}/${id}`, req);
  }

  delete(id: number): Observable<{ message: string }> {
    return this.http.delete<{ message: string }>(`${this.apiUrl}/${id}`);
  }

  preview(rates: StatutoryRateSetRequest, wage: number): Observable<StatutoryPreview> {
    return this.http.post<StatutoryPreview>(`${this.apiUrl}/preview`, { rates, wage });
  }
}
