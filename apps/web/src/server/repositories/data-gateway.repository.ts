import { AttendanceResult, AttendanceWindow, ClassOffering, Enrollment, Lesson } from '@/types/domain';

/**
 * Repository Layer: Communicates with Google Apps Script data gateway
 */
export interface IDataGatewayRepository {
  getClassOffering(id: string): Promise<ClassOffering | null>;
  saveClassOffering(offering: ClassOffering, roster: Enrollment[], lessons: Lesson[]): Promise<boolean>;
  syncAllClasses(classes: unknown[], startDate: string): Promise<{ success: boolean; spreadsheetUrl?: string }>;
  getRoster(classOfferingId: string): Promise<Enrollment[]>;
  getLesson(id: string): Promise<Lesson | null>;
  getActiveWindow(lessonId: string): Promise<AttendanceWindow | null>;
  openAttendanceWindow(lessonId: string): Promise<AttendanceWindow>;
  closeAttendanceWindow(windowId: string): Promise<boolean>;
  getAttendanceResults(lessonId: string): Promise<AttendanceResult[]>;
  saveCheckIn(lessonId: string, studentEmail: string): Promise<boolean>;
  saveManualOverride(lessonId: string, studentEmail: string, status: 'A' | 'P'): Promise<boolean>;
}

export class GoogleAppsScriptRepository implements IDataGatewayRepository {
  private readonly gatewayUrl: string;

  constructor(gatewayUrl?: string) {
    this.gatewayUrl = gatewayUrl || process.env.APPS_SCRIPT_GATEWAY_URL || '';
  }

  private async postToGateway(action: string, payload: Record<string, unknown>) {
    if (!this.gatewayUrl) {
      // Return stub/fallback when gateway URL is not yet configured
      return { success: true, data: null };
    }

    const response = await fetch(this.gatewayUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action, payload }),
    });

    if (!response.ok) {
      throw new Error(`Data Gateway returned HTTP ${response.status}`);
    }

    return response.json();
  }

  async getClassOffering(id: string): Promise<ClassOffering | null> {
    const res = await this.postToGateway('getClassOffering', { id });
    return res.data;
  }

  async saveClassOffering(offering: ClassOffering, roster: Enrollment[], lessons: Lesson[]): Promise<boolean> {
    const res = await this.postToGateway('saveClassOffering', { offering, roster, lessons });
    return res.success;
  }

  async syncAllClasses(classes: unknown[], startDate: string): Promise<{ success: boolean; spreadsheetUrl?: string }> {
    const res = await this.postToGateway('syncAllClasses', { classes, startDate });
    return {
      success: res.success,
      spreadsheetUrl: res.data?.spreadsheetUrl,
    };
  }

  async getRoster(classOfferingId: string): Promise<Enrollment[]> {
    const res = await this.postToGateway('getRoster', { classOfferingId });
    return res.data || [];
  }

  async getLesson(id: string): Promise<Lesson | null> {
    const res = await this.postToGateway('getLesson', { id });
    return res.data;
  }

  async getActiveWindow(lessonId: string): Promise<AttendanceWindow | null> {
    const res = await this.postToGateway('getActiveWindow', { lessonId });
    return res.data;
  }

  async openAttendanceWindow(lessonId: string): Promise<AttendanceWindow> {
    const res = await this.postToGateway('openAttendanceWindow', { lessonId });
    return res.data;
  }

  async closeAttendanceWindow(windowId: string): Promise<boolean> {
    const res = await this.postToGateway('closeAttendanceWindow', { windowId });
    return res.success;
  }

  async getAttendanceResults(lessonId: string): Promise<AttendanceResult[]> {
    const res = await this.postToGateway('getAttendanceResults', { lessonId });
    return res.data || [];
  }

  async saveCheckIn(lessonId: string, studentEmail: string): Promise<boolean> {
    const res = await this.postToGateway('saveCheckIn', { lessonId, studentEmail });
    return res.success;
  }

  async saveManualOverride(lessonId: string, studentEmail: string, status: 'A' | 'P'): Promise<boolean> {
    const res = await this.postToGateway('saveManualOverride', { lessonId, studentEmail, status });
    return res.success;
  }
}

// Export singleton instance
export const dataGatewayRepository = new GoogleAppsScriptRepository();
