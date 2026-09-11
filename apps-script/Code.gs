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
    case 'syncAllClasses':
      return SheetRepository.syncAllClassesFromDesktop(payload.classes, payload.startDate);
    case 'clearAllDatabase':
      return SheetRepository.clearAllDatabase();
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
    default:
      throw new Error('Unknown action: ' + action);
  }
}

function doGet(e) {
  var ss = SheetRepository.getSpreadsheet();
  return ContentService.createTextOutput(JSON.stringify({
    status: 'ok',
    gateway: 'PRM393 Google Apps Script Data Gateway',
    spreadsheetUrl: ss.getUrl()
  })).setMimeType(ContentService.MimeType.JSON);
}

/**
 * Hàm xoá toàn bộ dữ liệu và sheet cũ trên Google Sheet
 * Giảng viên có thể chọn hàm này và bấm Run trên Apps Script để dọn sạch ngay
 */
function clearEntireSpreadsheet() {
  var ss = SheetRepository.getSpreadsheet();
  SheetRepository.clearAllDatabase();
  Logger.log('========================================================');
  Logger.log('🧹 ĐÃ XOÁ TOÀN BỘ CÁC BẢNG CŨ TRÊN GOOGLE SHEET!');
  Logger.log('👉 Sẵn sàng nhận dữ liệu đồng bộ từ Desktop app.');
  Logger.log('👉 Link file: ' + ss.getUrl());
  Logger.log('========================================================');
  return ss.getUrl();
}

/**
 * Custom Menu trên Google Sheet
 */
function onOpen() {
  SpreadsheetApp.getUi()
    .createMenu('PRM393')
    .addItem('🧹 Dọn sạch dữ liệu cũ', 'clearEntireSpreadsheet')
    .addToUi();
}
