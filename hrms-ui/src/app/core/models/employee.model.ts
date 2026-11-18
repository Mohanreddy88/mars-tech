/** Employee record as returned by the API */
export interface Employee {
  id: number;
  employeeCode: string;           // Unique employee code (e.g., EMP000001)
  name: string;
  email: string;
  phone: string;                  // number without the country code
  phoneCountryCode: string;       // e.g. "+60"
  departmentId: number | null;    // FK to Department
  departmentName?: string;        // Resolved department name (joined in API response)
  designation: string;
  joinDate: string;
  salary: number;
  isActive: boolean;
  idType: IdType;                 // NRIC or Passport
  icPassport: string;             // NRIC (12 digits) or passport number
  idCountry: string;              // Malaysia for NRIC, issuing country for a passport
  dateOfBirth: string | null;     // ISO date
  taxNumber: string;              // Tax Identification Number (TIN)
  bankId: number | null;          // FK to BankMaster
  accountNumber: string;          // Bank account number for salary
  bankName?: string;              // Resolved bank name (joined in API response)
  profilePicture: string;         // Profile picture URL or path
  gender: string;                 // Male / Female / Other
  epfEmployeeRateOverride?: number | null;   // % — null = company rate (Master → Statutory Rates)
  epfEmployerRateOverride?: number | null;
}

/** Payload sent when creating or updating an employee */
export interface EmployeeRequest {
  name: string;
  email: string;
  phone: string;
  phoneCountryCode: string;
  departmentId: number | null;    // Changed from department string to departmentId FK
  designation: string;
  joinDate: string;
  salary: number;
  isActive: boolean;
  idType: IdType;
  icPassport: string;
  idCountry: string;
  dateOfBirth: string | null;
  taxNumber: string;
  bankId: number | null;
  accountNumber: string;
  profilePicture: string;         // Profile picture URL or path
  gender: string;                 // Male / Female / Other
  epfEmployeeRateOverride?: number | null;
  epfEmployerRateOverride?: number | null;
}

/** Identification type: NRIC = 12 digits (country Malaysia), Passport = 8–10 letters/digits. */
export type IdType = 'NRIC' | 'Passport';
