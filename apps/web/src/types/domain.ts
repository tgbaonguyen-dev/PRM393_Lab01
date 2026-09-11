/**
 * Domain types according to SRS v4.0 Section 8 (Logical Data Model)
 */

export interface ClassOffering {
  id: string;
  classCode: string;   // e.g. "SE1917"
  subjectCode: string; // e.g. "PRM393"
  semester: string;    // e.g. "FA26"
  scheduleCode: string;// e.g. "12"
  slotCount?: number;  // Dynamic slot count (e.g. 15, 20, 30)
  ownerEmail: string;
}

export interface Enrollment {
  id: string;
  classOfferingId: string;
  rollNumber: string;
  fullName: string;
  email: string;       // Used for sign-in matching
  memberCode?: string;
}

export interface Lesson {
  id: string;
  classOfferingId: string;
  sequenceNumber: number; // 1 to 20
  date: string;           // YYYY-MM-DD
  dailySlot: number;      // 1 to 4
  startTime: string;      // HH:mm
  endTime: string;        // HH:mm
  status: 'scheduled' | 'active' | 'closed';
}

export interface AttendanceWindow {
  id: string;
  lessonId: string;
  openedAt: string;
  closedAt?: string;
  isOpen: boolean;
}

export type AttendanceStatus = 'A' | 'P';

export interface AttendanceResult {
  lessonId: string;
  studentEmail: string;
  status: AttendanceStatus;
  isManualOverride: boolean;
  checkedInAt?: string;
}

export interface QRTokenPayload {
  windowId: string;
  lessonId: string;
  timestamp: number; // UNIX epoch ms
  expiresAt: number; // timestamp + 15000ms
  nonce: string;
}
