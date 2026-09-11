import { AttendanceResult, AttendanceWindow } from '@/types/domain';
import { IDataGatewayRepository, dataGatewayRepository } from '../repositories/data-gateway.repository';
import { QRService, qrService } from './qr.service';

export interface CheckInResult {
  success: boolean;
  message: string;
  statusCode: number;
}

export class AttendanceService {
  constructor(
    private readonly repo: IDataGatewayRepository = dataGatewayRepository,
    private readonly qr: QRService = qrService
  ) {}

  /**
   * Opens an attendance window for a lesson (FR-09)
   */
  async openWindow(lessonId: string): Promise<AttendanceWindow> {
    return this.repo.openAttendanceWindow(lessonId);
  }

  /**
   * Explicitly closes an attendance window (FR-12)
   */
  async closeWindow(windowId: string): Promise<boolean> {
    return this.repo.closeAttendanceWindow(windowId);
  }

  /**
   * Processes a student check-in (FR-17, FR-18, FR-19, FR-20, FR-21)
   */
  async processCheckIn(qrToken: string, studentEmail: string): Promise<CheckInResult> {
    // 1. Validate QR Token
    const qrValidation = this.qr.validateToken(qrToken);
    if (!qrValidation.isValid || !qrValidation.payload) {
      return {
        success: false,
        message: qrValidation.error || 'Mã QR không hợp lệ hoặc đã hết hạn.',
        statusCode: 400,
      };
    }

    const { lessonId, windowId } = qrValidation.payload;

    // 2. Validate Window State
    const activeWindow = await this.repo.getActiveWindow(lessonId);
    if (!activeWindow || !activeWindow.isOpen || activeWindow.id !== windowId) {
      return {
        success: false,
        message: 'Ca điểm danh đã kết thúc hoặc không còn mở.',
        statusCode: 403,
      };
    }

    const normalizedEmail = studentEmail.trim().toLowerCase();

    // 3. Check existing attendance result
    const currentResults = await this.repo.getAttendanceResults(lessonId);
    const existing = currentResults.find((r) => r.studentEmail.toLowerCase() === normalizedEmail);

    if (existing?.status === 'P') {
      return {
        success: true,
        message: 'Bạn đã điểm danh thành công trước đó.',
        statusCode: 200,
      };
    }

    // 4. Save Check-in directly to the class sheet
    const saved = await this.repo.saveCheckIn(lessonId, normalizedEmail);
    if (!saved) {
      return {
        success: false,
        message: 'Điểm danh không thành công. Email của bạn không nằm trong danh sách sinh viên của lớp học này.',
        statusCode: 403,
      };
    }

    return {
      success: true,
      message: 'Điểm danh thành công!',
      statusCode: 200,
    };
  }

  /**
   * Retrieves live attendance results for 5s desktop polling
   */
  async getPollResults(lessonId: string): Promise<AttendanceResult[]> {
    return this.repo.getAttendanceResults(lessonId);
  }

  /**
   * Applies manual override by lecturer (FR-14)
   */
  async applyManualOverride(lessonId: string, studentEmail: string, status: 'A' | 'P'): Promise<boolean> {
    return this.repo.saveManualOverride(lessonId, studentEmail.trim().toLowerCase(), status);
  }
}

export const attendanceService = new AttendanceService();
