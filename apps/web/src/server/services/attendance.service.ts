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

    // 3. Validate student is in class roster
    const lesson = await this.repo.getLesson(lessonId);
    if (!lesson) {
      return { success: false, message: 'Không tìm thấy thông tin buổi học.', statusCode: 404 };
    }

    const roster = await this.repo.getRoster(lesson.classOfferingId);
    const normalizedEmail = studentEmail.trim().toLowerCase();
    const isEnrolled = roster.some((r) => r.email.toLowerCase() === normalizedEmail);

    if (!isEnrolled) {
      return {
        success: false,
        message: 'Email của bạn không nằm trong danh sách sinh viên của lớp học này.',
        statusCode: 403,
      };
    }

    // 4. Check existing attendance result and manual override precedence (FR-14, FR-19)
    const currentResults = await this.repo.getAttendanceResults(lessonId);
    const existing = currentResults.find((r) => r.studentEmail.toLowerCase() === normalizedEmail);

    if (existing?.isManualOverride) {
      return {
        success: false,
        message: 'Kết quả điểm danh đã được giảng viên điều chỉnh trực tiếp, không thể ghi đè.',
        statusCode: 409,
      };
    }

    if (existing?.status === 'P') {
      return {
        success: true,
        message: 'Bạn đã điểm danh thành công trước đó.',
        statusCode: 200,
      };
    }

    // 5. Save Check-in (serialized by repository / data gateway)
    const saved = await this.repo.saveCheckIn(lessonId, normalizedEmail);
    if (!saved) {
      return {
        success: false,
        message: 'Lưu dữ liệu điểm danh thất bại. Vui lòng thử lại.',
        statusCode: 500,
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
