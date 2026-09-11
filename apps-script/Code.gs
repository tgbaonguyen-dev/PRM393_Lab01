/**
 * Google Apps Script Data Gateway for PRM393 Attendance
 * Exposes Web App endpoints with LockService concurrency serialization
 */

function doPost(e) {
  try {
    var contents = JSON.parse(e.postData.contents);
    var action = contents.action;
    var payload = contents.payload || {};

    // Acquire Script Lock to serialize concurrent check-ins
    var lock = LockService.getScriptLock();
    // Wait up to 20 seconds for other concurrent executions to finish
    var hasLock = lock.tryLock(20000);

    if (!hasLock) {
      return ContentService.createTextOutput(JSON.stringify({
        success: false,
        error: 'Hệ thống đang bận xử lý lượt điểm danh khác. Vui lòng thử lại sau giây lát.'
      })).setMimeType(ContentService.MimeType.JSON);
    }

    var result;
    try {
      result = dispatchAction(action, payload);
    } finally {
      lock.releaseLock();
    }

    return ContentService.createTextOutput(JSON.stringify({
      success: true,
      data: result
    })).setMimeType(ContentService.MimeType.JSON);

  } catch (err) {
    return ContentService.createTextOutput(JSON.stringify({
      success: false,
      error: err.toString()
    })).setMimeType(ContentService.MimeType.JSON);
  }
}

function dispatchAction(action, payload) {
  switch (action) {
    case 'setupDatabase':
      return SheetRepository.setupDatabase();
    case 'saveClassOffering':
      return SheetRepository.saveClassOffering(payload.offering, payload.roster, payload.lessons);
    case 'openAttendanceWindow':
      return SheetRepository.openWindow(payload.lessonId);
    case 'closeAttendanceWindow':
      return SheetRepository.closeWindow(payload.windowId);
    case 'saveCheckIn':
      return SheetRepository.recordCheckIn(payload.lessonId, payload.studentEmail);
    case 'saveManualOverride':
      return SheetRepository.recordOverride(payload.lessonId, payload.studentEmail, payload.status);
    case 'getAttendanceResults':
      return SheetRepository.getResults(payload.lessonId);
    case 'getActiveWindow':
      return SheetRepository.getActiveWindow(payload.lessonId);
    case 'getLesson':
      return SheetRepository.getLesson(payload.lessonId);
    case 'getRoster':
      return SheetRepository.getRoster(payload.classOfferingId);
    default:
      throw new Error('Unknown action: ' + action);
  }
}

function doGet(e) {
  return ContentService.createTextOutput(JSON.stringify({
    status: 'ok',
    gateway: 'PRM393 Google Apps Script Data Gateway'
  })).setMimeType(ContentService.MimeType.JSON);
}
