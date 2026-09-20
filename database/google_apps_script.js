/**
 * Google Apps Script Data Gateway for PRM393 Attendance System
 * Tạo Tab Overview và Tab riêng cho TỪNG LỚP HỌC của Giảng viên
 * Hiển thị 20 Slot điểm danh, tự tính Tỉ lệ vắng & Cảnh báo CẤM THI (>20%)
 * Cập nhật Realtime trực tiếp vào từng ô Slot của sinh viên với LockService chống đua.
 */

var APP_RESET_KEY = 'mot-khoa-bi-mat-rat-dai';
var VIETNAM_TIME_ZONE = 'Asia/Ho_Chi_Minh';

function vietnamTimestamp() {
  return Utilities.formatDate(new Date(), VIETNAM_TIME_ZONE, 'dd/MM/yyyy HH:mm:ss');
}

function canonicalSlotTimes(dailySlot) {
  var times = {
    1: ['07:00', '09:15'],
    2: ['09:30', '11:45'],
    3: ['12:30', '14:45'],
    4: ['15:00', '17:15'],
    5: ['17:45', '19:15']
  };
  return times[Number(dailySlot)] || null;
}

function canonicalLessonTime(value, dailySlot, isStart) {
  var times = canonicalSlotTimes(dailySlot);
  if (times) return times[isStart ? 0 : 1];
  return value instanceof Date
    ? Utilities.formatDate(value, VIETNAM_TIME_ZONE, 'HH:mm')
    : String(value || '').trim();
}

function lessonFromRow(row) {
  var dailySlot = Number(row[4]);
  return {
    lessonId: row[0],
    sequenceNumber: Number(row[2]),
    date: row[3],
    dailySlot: dailySlot,
    startTime: canonicalLessonTime(row[5], dailySlot, true),
    endTime: canonicalLessonTime(row[6], dailySlot, false),
    isAdjusted: row[7] === true,
    status: row[8] || 'scheduled'
  };
}

function doPost(e) {
  try {
    var contents = JSON.parse(e.postData.contents);
    var action = contents.action;
    var payload = contents.payload || {};

    // 1. Acquire Script Lock để tuần tự hóa các yêu cầu điểm danh đồng thời
    var lock = LockService.getScriptLock();
    var hasLock = lock.tryLock(20000); // Chờ tối đa 20 giây

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

function doGet(e) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  return ContentService.createTextOutput(JSON.stringify({
    status: 'ok',
    gateway: 'PRM393 Google Apps Script Data Gateway (Class Markbooks Active)',
    spreadsheetUrl: ss ? ss.getUrl() : null
  })).setMimeType(ContentService.MimeType.JSON);
}

/**
 * Tạo Menu tiện ích trên Google Sheets: Cho phép đổi toàn bộ các tab sang giao diện Notion ngay lập tức
 */
function onOpen() {
  try {
    SpreadsheetApp.getUi()
      .createMenu('✦ iPresent')
      .addItem('Chuyển toàn bộ Sheet sang giao diện Notion', 'reformatAllSheetsToNotion')
      .addToUi();
  } catch (e) {}
}

/**
 * Hàm làm mới / định dạng lại toàn bộ các tab lớp học hiện có sang chuẩn Notion Database
 * Bảo toàn 100% dữ liệu sinh viên và kết quả điểm danh P/A
 */
function reformatAllSheetsToNotion() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheets = ss.getSheets();
  var systemSheets = {
    'Overview': true, 'Classes': true, 'Students': true,
    'Lessons': true, 'Sessions': true, 'Attendances': true, 'App_Empty': true
  };

  var processedCount = 0;
  for (var i = 0; i < sheets.length; i++) {
    var sheet = sheets[i];
    var name = sheet.getName();
    if (systemSheets[name] || name.indexOf('Temp_') === 0 || name.indexOf('[Archived]') === 0) {
      continue;
    }

    var lastRow = sheet.getLastRow();
    var lastCol = sheet.getLastColumn();
    if (lastRow < 2 || lastCol < 6) continue;

    // 1. Reformat Banner (Row 1)
    var bannerCell = sheet.getRange(1, 1);
    var bannerVal = String(bannerCell.getValue() || '');
    bannerVal = bannerVal.replace(/^[📚📊]\s*/, '').replace(/\|/g, '·').trim();
    if (bannerVal.indexOf('✦') !== 0) bannerVal = '✦  ' + bannerVal;
    bannerCell.setValue(bannerVal);
    bannerCell.setBackground('#F1F1EF'); // Notion Callout Gray
    bannerCell.setFontColor('#37352F'); // Notion Primary Text
    bannerCell.setFontWeight('bold');
    bannerCell.setFontSize(11);
    bannerCell.setHorizontalAlignment('left');
    bannerCell.setVerticalAlignment('middle');
    bannerCell.setBorder(true, true, true, true, false, false, '#E9E9E7', SpreadsheetApp.BorderStyle.SOLID);
    sheet.setRowHeight(1, 38);

    // 2. Reformat Headers (Row 2)
    var headerRange = sheet.getRange(2, 1, 1, lastCol);
    var headerVals = headerRange.getValues()[0];
    for (var h = 0; h < headerVals.length; h++) {
      var hText = String(headerVals[h] || '');
      hText = hText.replace(/\((\d{2})-(\d{2})\)/, '$2/$1');
      hText = hText.replace('Tổng vắng (A)', 'Tổng vắng');
      hText = hText.replace('Tỉ lệ vắng (%)', 'Tỉ lệ vắng');
      hText = hText.replace('Kết quả FAP', 'Trạng thái');
      headerVals[h] = hText;
    }
    headerRange.setValues([headerVals]);
    headerRange.setBackground('#F7F6F3'); // Notion Database Header
    headerRange.setFontColor('#787774'); // Notion Muted Label
    headerRange.setFontWeight('bold');
    headerRange.setFontSize(10);
    headerRange.setHorizontalAlignment('center');
    headerRange.setVerticalAlignment('middle');
    headerRange.setWrap(true);
    headerRange.setBorder(true, true, true, true, true, true, '#E9E9E7', SpreadsheetApp.BorderStyle.SOLID);
    sheet.setRowHeight(2, 38);

    // 3. Reformat Data Rows (Row 3..N)
    if (lastRow >= 3) {
      var numRows = lastRow - 2;
      var dataRange = sheet.getRange(3, 1, numRows, lastCol);
      dataRange.setFontColor('#37352F');
      dataRange.setFontSize(10);
      dataRange.setBorder(true, true, true, true, true, true, '#EDEDEB', SpreadsheetApp.BorderStyle.SOLID);

      // Zebra striping Notion
      var bgMatrix = [];
      for (var r = 0; r < numRows; r++) {
        var rowBg = (r % 2 === 0) ? '#FFFFFF' : '#FAFAF9';
        var rBgs = [];
        for (var c = 0; c < lastCol; c++) rBgs.push(rowBg);
        bgMatrix.push(rBgs);
      }
      dataRange.setBackgrounds(bgMatrix);

      sheet.getRange(3, 1, numRows, 1).setHorizontalAlignment('center').setFontColor('#787774');
      sheet.getRange(3, 2, numRows, 1).setHorizontalAlignment('center').setFontColor('#37352F');
      sheet.getRange(3, 3, numRows, 1).setHorizontalAlignment('left').setFontColor('#37352F');
      sheet.getRange(3, 4, numRows, 1).setHorizontalAlignment('left').setFontColor('#787774');
      sheet.getRange(3, 5, numRows, 1).setHorizontalAlignment('center').setFontColor('#787774');
      var slotCount = Math.max(1, lastCol - 8);
      sheet.getRange(3, 6, numRows, slotCount).setHorizontalAlignment('center').setFontWeight('bold');
      sheet.getRange(3, 5 + slotCount + 1, numRows, 3).setHorizontalAlignment('center');
      sheet.setRowHeights(3, numRows, 26);

      // Cập nhật công thức Trạng thái không dùng emoji
      var pctColLetter = DatabaseService.getColumnLetter(5 + slotCount + 2);
      for (var rIdx = 3; rIdx <= lastRow; rIdx++) {
        sheet.getRange(rIdx, lastCol).setFormula(
          '=IF(' + pctColLetter + rIdx + '>0.20, "Cấm thi", IF(' + pctColLetter + rIdx + '>=0.15, "Cảnh báo", "Đủ điều kiện"))'
        );
      }

      // Conditional Formatting: Notion Tag Pills
      var slotRange = sheet.getRange(3, 6, numRows, slotCount);
      var resultRange = sheet.getRange(3, lastCol, numRows, 1);

      var ruleP = SpreadsheetApp.newConditionalFormatRule()
        .whenTextEqualTo('P')
        .setBackground('#DBEDDB') // Notion Green Tag
        .setFontColor('#1C3829')
        .setRanges([slotRange])
        .build();

      var ruleA = SpreadsheetApp.newConditionalFormatRule()
        .whenTextEqualTo('A')
        .setBackground('#FFE2DD') // Notion Red Tag
        .setFontColor('#5D1715')
        .setRanges([slotRange])
        .build();

      var ruleCamThi = SpreadsheetApp.newConditionalFormatRule()
        .whenTextEqualTo('Cấm thi')
        .setBackground('#FFE2DD')
        .setFontColor('#5D1715')
        .setRanges([resultRange])
        .build();

      var ruleCanhBao = SpreadsheetApp.newConditionalFormatRule()
        .whenTextEqualTo('Cảnh báo')
        .setBackground('#FDECC8')
        .setFontColor('#402C1B')
        .setRanges([resultRange])
        .build();

      var ruleDuDieuKien = SpreadsheetApp.newConditionalFormatRule()
        .whenTextEqualTo('Đủ điều kiện')
        .setBackground('#DBEDDB')
        .setFontColor('#1C3829')
        .setRanges([resultRange])
        .build();

      sheet.setConditionalFormatRules([ruleP, ruleA, ruleCamThi, ruleCanhBao, ruleDuDieuKien]);
    }
    processedCount++;
  }

  // Cập nhật Tab Overview nếu có
  var overviewSheet = ss.getSheetByName('Overview');
  if (overviewSheet && overviewSheet.getLastRow() >= 2) {
    var oTitle = overviewSheet.getRange('A1');
    var oTitleVal = String(oTitle.getValue() || '').replace(/^[📊📚]\s*/, '').replace(/\|/g, '·').trim();
    if (oTitleVal.indexOf('✦') !== 0) oTitleVal = '✦  ' + oTitleVal;
    oTitle.setValue(oTitleVal);
    oTitle.setBackground('#F1F1EF');
    oTitle.setFontColor('#37352F');
    oTitle.setFontWeight('bold');
    oTitle.setFontSize(11);
    oTitle.setHorizontalAlignment('left');
    oTitle.setBorder(true, true, true, true, false, false, '#E9E9E7', SpreadsheetApp.BorderStyle.SOLID);
    overviewSheet.setRowHeight(1, 38);

    var oHeader = overviewSheet.getRange(2, 1, 1, overviewSheet.getLastColumn());
    oHeader.setBackground('#F7F6F3');
    oHeader.setFontColor('#787774');
    oHeader.setFontWeight('bold');
    oHeader.setFontSize(10);
    oHeader.setBorder(true, true, true, true, true, true, '#E9E9E7', SpreadsheetApp.BorderStyle.SOLID);
    overviewSheet.setRowHeight(2, 34);

    if (overviewSheet.getLastRow() >= 3) {
      var oNum = overviewSheet.getLastRow() - 2;
      var oData = overviewSheet.getRange(3, 1, oNum, overviewSheet.getLastColumn());
      oData.setFontColor('#37352F');
      oData.setFontSize(10);
      oData.setBorder(true, true, true, true, true, true, '#EDEDEB', SpreadsheetApp.BorderStyle.SOLID);
      overviewSheet.setRowHeights(3, oNum, 28);
    }
  }

  SpreadsheetApp.flush();
  return { success: true, processedCount: processedCount };
}

function dispatchAction(action, payload) {
  switch (action) {
    case 'reformatAllSheetsToNotion':
      return reformatAllSheetsToNotion();
    case 'resetApplicationData':
      return DatabaseService.resetApplicationData(payload);
    case 'syncAllClasses':
      return DatabaseService.syncAllClassesFromDesktop(payload.classes, payload.startDate, payload.clearPrevious);
    case 'saveClassOffering':
      return DatabaseService.saveClassOffering(payload.offering, payload.roster, payload.lessons);
    case 'saveClassOfferings':
      return DatabaseService.saveClassOfferings(payload.items);
    case 'syncActiveClassIds':
      return DatabaseService.syncActiveClassIds(payload.activeClassIds);
    case 'listSchedules':
      return DatabaseService.listSchedules();
    case 'getSchedule':
      return DatabaseService.getSchedule(payload.classId);
    case 'getAllSchedules':
      return DatabaseService.getAllSchedules();
    case 'repairLessonTimes':
      return DatabaseService.repairLessonTimes();
    case 'setupDatabase':
      return DatabaseService.setupDatabase();
    case 'openAttendanceWindow':
      return DatabaseService.openAttendanceWindow(payload.lessonId || payload.sessionId);
    case 'closeAttendanceWindow':
      return DatabaseService.closeAttendanceWindow(payload.windowId);
    case 'saveCheckIn':
      return DatabaseService.recordCheckIn(payload.lessonId || payload.sessionId, payload.studentEmail);
    case 'saveManualOverride':
      return DatabaseService.recordOverride(payload.lessonId || payload.sessionId, payload.studentEmail, payload.status);
    case 'getAttendanceResults':
      return DatabaseService.getAttendanceResults(payload.lessonId || payload.sessionId);
    case 'getAllAttendance':
      return DatabaseService.getAllAttendance();
    case 'getActiveWindow':
      return DatabaseService.getActiveWindow(payload.lessonId || payload.sessionId);
    case 'isStudentInClass':
      return DatabaseService.isStudentInClass(payload.classId, payload.studentEmail);
    case 'resetSlotAttendance':
      return DatabaseService.resetSlotAttendance(payload.lessonId || payload.sessionId, payload.status || 'A');
    case 'clearAllDatabase':
      return DatabaseService.clearAllDatabase();
    default:
      throw new Error('Unknown action: ' + action);
  }
}

/**
 * Service Quản lý dữ liệu và Giao diện Bảng điểm Markbook trên Google Sheets
 */
var DatabaseService = {
  // Explicit full reset, independent of legacy presentation-only clearAllDatabase.
  // doPost already holds the same lock used for every attendance write.
  resetApplicationData: function (payload) {
    var props = PropertiesService.getScriptProperties();
    var expected = props.getProperty('APP_RESET_KEY') || (typeof APP_RESET_KEY !== 'undefined' ? APP_RESET_KEY : null);
    if (!expected || payload.resetKey !== expected || payload.confirmation !== 'DELETE_ALL_APP_DATA') {
      throw new Error('Reset authorization failed.');
    }
    var ss = this.getSpreadsheet();
    var canonical = {Overview: true, Classes: true, Students: true,
      Lessons: true, Sessions: true, Attendances: true};
    // Invalidate all QR windows first, including when a later delete fails.
    props.deleteProperty('ACTIVE_WINDOW');
    var placeholder = ss.getSheetByName('App_Empty') || ss.insertSheet('App_Empty');
    placeholder.showSheet();
    ss.getSheets().forEach(function (sheet) {
      var name = sheet.getName();
      var owned = canonical[name] || /^[123][1-5]_/.test(name) ||
        /^(?:\[Archived\]|_Archived_) [123][1-5]_/.test(name) || /^Temp_\d+$/.test(name);
      if (owned) ss.deleteSheet(sheet);
    });
    placeholder.clear();
    placeholder.getRange(1, 1).setValue('iPresent — Chưa có dữ liệu');
    SpreadsheetApp.flush();
    return {reset: true};
  },

  getSpreadsheet: function () {
    return SpreadsheetApp.getActiveSpreadsheet();
  },

  // Canonical M1 storage. These tabs are append/upsert based; unlike the old
  // syncAllClasses demo action, they never clear another class or attendance.
  ensureDataSheet: function (name, headers) {
    var ss = this.getSpreadsheet();
    var sheet = ss.getSheetByName(name);
    if (!sheet) sheet = ss.insertSheet(name);
    if (sheet.getLastRow() === 0) sheet.appendRow(headers);
    if (name === 'Classes' && sheet.getLastColumn() < headers.length) {
      var values = sheet.getDataRange().getValues();
      values[0] = headers.slice();
      for (var rowIndex = 1; rowIndex < values.length; rowIndex++) {
        while (values[rowIndex].length < headers.length) values[rowIndex].push(true);
      }
      sheet.clearContents();
      sheet.getRange(1, 1, values.length, headers.length).setValues(values);
    }
    return sheet;
  },

  upsertRow: function (sheet, key, row) {
    var values = sheet.getDataRange().getValues();
    for (var index = 1; index < values.length; index++) {
      if (String(values[index][0]) === String(key)) {
        sheet.getRange(index + 1, 1, 1, row.length).setValues([row]);
        return;
      }
    }
    sheet.appendRow(row);
  },

  upsertRowsBatch: function (sheet, keyColIndex, newRows) {
    if (!newRows || newRows.length === 0) return;
    var values = sheet.getDataRange().getValues();
    if (values.length <= 1) {
      sheet.getRange(2, 1, newRows.length, newRows[0].length).setValues(newRows);
      return;
    }
    var keyMap = {};
    for (var i = 1; i < values.length; i++) {
      var key = String(values[i][keyColIndex] || '');
      if (key) keyMap[key] = i;
    }
    for (var j = 0; j < newRows.length; j++) {
      var row = newRows[j];
      var rowKey = String(row[keyColIndex] || '');
      if (rowKey && keyMap[rowKey] !== undefined) {
        values[keyMap[rowKey]] = row;
      } else {
        values.push(row);
        keyMap[rowKey] = values.length - 1;
      }
    }
    sheet.getRange(1, 1, values.length, values[0].length).setValues(values);
  },

  saveClassOffering: function (offering, roster, lessons) {
    return this.saveClassOfferings([{ offering: offering, roster: roster, lessons: lessons }]);
  },

  saveClassOfferings: function (items) {
    if (!Array.isArray(items) || items.length === 0) {
      throw new Error('items phải là danh sách lớp không rỗng.');
    }
    var classes = this.ensureDataSheet('Classes', [
      'classId', 'classCode', 'subjectCode', 'semester', 'scheduleCode',
      'sourceSheetName', 'lessonCount', 'updatedAt', 'active'
    ]);
    var students = this.ensureDataSheet('Students', [
      'recordKey', 'classId', 'classCode', 'rollNumber', 'fullName',
      'email', 'memberCode', 'active'
    ]);
    var lessonRows = this.ensureDataSheet('Lessons', [
      'lessonId', 'classId', 'sequenceNumber', 'date', 'dailySlot',
      'startTime', 'endTime', 'isAdjusted', 'status'
    ]);

    var classDataRows = [];
    var studentDataRows = [];
    var lessonDataRows = [];
    var savedClassIds = [];
    var now = vietnamTimestamp();

    for (var i = 0; i < items.length; i++) {
      var item = items[i] || {};
      var offering = item.offering;
      if (!offering || !offering.classId) continue;
      savedClassIds.push(offering.classId);

      classDataRows.push([
        offering.classId, String(offering.classCode || ''), String(offering.subjectCode || ''),
        String(offering.semester || ''), String(offering.scheduleCode || ''), String(offering.sourceSheetName || ''),
        offering.lessonCount || 20, now, true
      ]);

      (item.roster || []).forEach(function (student) {
        var recordKey = offering.classId + '|' + String(student.rollNumber || '').toUpperCase();
        studentDataRows.push([
          recordKey, offering.classId, String(student.classCode || offering.classCode || ''),
          String(student.rollNumber || ''), String(student.fullName || ''), String(student.email || '').toLowerCase(),
          String(student.memberCode || ''), true
        ]);
      });

      (item.lessons || []).forEach(function (lesson) {
        var dailySlot = Number(lesson.dailySlot);
        lessonDataRows.push([
          String(lesson.lessonId || ''), offering.classId, Number(lesson.sequenceNumber), String(lesson.date || ''),
          dailySlot,
          canonicalLessonTime(lesson.startTime, dailySlot, true),
          canonicalLessonTime(lesson.endTime, dailySlot, false),
          lesson.isAdjusted === true, String(lesson.status || 'scheduled')
        ]);
      });
    }

    if (classDataRows.length > 0) this.upsertRowsBatch(classes, 0, classDataRows);
    if (studentDataRows.length > 0) this.upsertRowsBatch(students, 0, studentDataRows);
    if (lessonDataRows.length > 0) this.upsertRowsBatch(lessonRows, 0, lessonDataRows);

    SpreadsheetApp.flush();
    return { savedClassIds: savedClassIds, classCount: savedClassIds.length };
  },

  syncActiveClassIds: function (activeClassIds) {
    if (!Array.isArray(activeClassIds) || activeClassIds.length === 0) {
      throw new Error('activeClassIds phải là danh sách không rỗng.');
    }
    var active = {};
    activeClassIds.forEach(function (classId) {
      var normalized = String(classId || '').trim();
      if (normalized) active[normalized] = true;
    });
    var sheet = this.getSpreadsheet().getSheetByName('Classes');
    if (!sheet || sheet.getLastRow() <= 1) return { activeCount: 0, inactiveCount: 0 };
    var values = sheet.getDataRange().getValues();
    while (values[0].length < 9) values[0].push('');
    for (var rowIndex = 1; rowIndex < values.length; rowIndex++) {
      while (values[rowIndex].length < 9) values[rowIndex].push(true);
    }
    var header = values[0];
    if (String(header[8] || '').trim() !== 'active') {
      header[8] = 'active';
      sheet.clearContents();
      sheet.getRange(1, 1, values.length, values[0].length).setValues(values);
    }
    var activeCount = 0;
    var inactiveCount = 0;
    for (var i = 1; i < values.length; i++) {
      var classId = String(values[i][0] || '').trim();
      if (!classId) continue;
      values[i][8] = active[classId] === true;
      if (values[i][8]) activeCount++; else inactiveCount++;
    }
    sheet.getRange(1, 1, values.length, values[0].length).setValues(values);
    SpreadsheetApp.flush();
    return { activeClassIds: Object.keys(active), activeCount: activeCount, inactiveCount: inactiveCount };
  },

  listSchedules: function () {
    var sheet = this.getSpreadsheet().getSheetByName('Classes');
    if (!sheet || sheet.getLastRow() <= 1) return [];
    var rows = sheet.getDataRange().getValues();
    return rows.slice(1).filter(function (row) {
      return row[0] && (row[8] === undefined || row[8] === '' || row[8] === true || String(row[8]).toLowerCase() === 'true');
    }).map(function (row) {
      return {
        classId: String(row[0] || ''), classCode: String(row[1] || ''), subjectCode: String(row[2] || ''), semester: String(row[3] || ''),
        scheduleCode: String(row[4] || ''), sourceSheetName: String(row[5] || ''), lessonCount: Number(row[6]), active: true
      };
    });
  },

  getSchedule: function (classId) {
    var offerings = this.listSchedules().filter(function (item) { return item.classId === classId; });
    if (offerings.length === 0) return null;
    var ss = this.getSpreadsheet();
    var studentsSheet = ss.getSheetByName('Students');
    var lessonsSheet = ss.getSheetByName('Lessons');
    var students = studentsSheet && studentsSheet.getLastRow() > 1
      ? studentsSheet.getDataRange().getValues().slice(1).filter(function (row) { return row[1] === classId; }).map(function (row) {
          return { classCode: row[2], rollNumber: row[3], fullName: row[4], email: row[5], memberCode: row[6] };
        }) : [];
    var lessons = lessonsSheet && lessonsSheet.getLastRow() > 1
      ? lessonsSheet.getDataRange().getValues().slice(1).filter(function (row) { return row[1] === classId; }).map(function (row) {
          return lessonFromRow(row);
        }).sort(function (left, right) { return left.sequenceNumber - right.sequenceNumber; }) : [];
    return { classOffering: offerings[0], students: students, lessons: lessons };
  },

  getAllSchedules: function () {
    var schedules = [];
    var offerings = this.listSchedules();
    for (var i = 0; i < offerings.length; i++) {
      var schedule = this.getSchedule(offerings[i].classId);
      if (schedule) schedules.push(schedule);
    }
    return schedules;
  },

  repairLessonTimes: function () {
    var sheet = this.getSpreadsheet().getSheetByName('Lessons');
    if (!sheet || sheet.getLastRow() <= 1) return { updatedRows: 0 };

    var values = sheet.getRange(2, 1, sheet.getLastRow() - 1, sheet.getLastColumn()).getValues();
    var updatedRows = 0;
    values.forEach(function (row) {
      var dailySlot = Number(row[4]);
      var times = canonicalSlotTimes(dailySlot);
      if (!times) return;
      if (String(row[5] || '').trim() !== times[0] || String(row[6] || '').trim() !== times[1]) {
        row[5] = times[0];
        row[6] = times[1];
        updatedRows++;
      }
    });
    if (updatedRows > 0) {
      sheet.getRange(2, 1, values.length, values[0].length).setValues(values);
      SpreadsheetApp.flush();
    }
    return { updatedRows: updatedRows };
  },

  /**
   * Xóa sạch toàn bộ các sheet cũ để làm mới hoàn toàn
   */
  clearAllDatabase: function () {
    var ss = this.getSpreadsheet();
    var tempSheet = ss.insertSheet('Temp_' + new Date().getTime());
    // M1 stores canonical schedules here. The legacy presentation reset must
    // never delete them, otherwise a later demo sync would erase history.
    var protectedSheets = {
      'Classes': true, 'Students': true, 'Lessons': true,
      'Sessions': true, 'Attendances': true
    };
    var sheets = ss.getSheets();
    for (var i = 0; i < sheets.length; i++) {
      if (sheets[i].getName() !== tempSheet.getName() && !protectedSheets[sheets[i].getName()]) {
        try {
          ss.deleteSheet(sheets[i]);
        } catch (e) {}
      }
    }
    return tempSheet;
  },

  /**
   * Chuẩn hóa tên Sheet tuân thủ quy tắc nghiêm ngặt của Google Sheets:
   * - Tối đa 80 ký tự (Google cho phép 100)
   * - Không chứa các ký tự cấm: [ ] * ? : / \
   * - Không bắt đầu/kết thúc bằng dấu nháy đơn '
   */
  sanitizeSheetName: function (rawName) {
    if (!rawName) return 'Sheet';
    var clean = String(rawName)
      .replace(/[\[\]\*?\:\/\\']/g, '_')
      .trim();
    if (clean.length > 80) {
      clean = clean.substring(0, 80);
    }
    return clean || 'Sheet';
  },

  /**
   * Kiểm tra xem một sheet lớp đã có bất kỳ kết quả điểm danh thực tế (P hoặc A) nào chưa
   */
  hasAttendanceData: function (sheet) {
    if (!sheet) return false;
    var lastRow = sheet.getLastRow();
    var lastCol = sheet.getLastColumn();
    if (lastRow < 3 || lastCol < 6) return false;

    try {
      // Đọc vùng slot điểm danh từ dòng 3 trở đi, từ cột F (cột 6)
      var slotData = sheet.getRange(3, 6, lastRow - 2, Math.min(25, lastCol - 5)).getValues();
      for (var r = 0; r < slotData.length; r++) {
        for (var c = 0; c < slotData[r].length; c++) {
          var val = String(slotData[r][c] || '').trim().toUpperCase();
          if (val === 'P' || val === 'A') {
            return true;
          }
        }
      }
    } catch (e) {
      Logger.log('Lỗi kiểm tra hasAttendanceData: ' + e);
    }
    return false;
  },

  /**
   * Đồng bộ toàn bộ các lớp học từ Desktop App lên Google Sheet
   * Cơ chế Upsert thông minh với các ràng buộc an toàn:
   * 1. Ghim Overview cố định ở vị trí đầu tiên
   * 2. Sanitize tên sheet chống ký tự cấm
   * 3. Bảo vệ dữ liệu điểm danh: Lớp bị loại khỏi import nếu đã có điểm danh thì chuyển sang [Archived], không xoá
   * 4. Sheet trắng chưa điểm danh thì xoá an toàn
   */
  syncAllClassesFromDesktop: function (classes, startDateStr, clearPrevious) {
    var ss = this.getSpreadsheet();

    // 1. Quản lý Sheet OVERVIEW (Nếu đã có thì cập nhật, chưa có thì tạo mới)
    var overviewSheet = ss.getSheetByName('Overview');
    if (!overviewSheet) {
      overviewSheet = ss.insertSheet('Overview', 0);
    }
    this.setupOverviewSheet(overviewSheet, classes, startDateStr);

    // RÀNG BUỘC: Luôn ghim tab Overview ở vị trí số 1 bên trái
    try {
      ss.setActiveSheet(overviewSheet);
      ss.moveActiveSheet(1);
    } catch (orderErr) {}

    // Nếu người dùng yêu cầu xóa thông tin của các sheet trước đó khi upload markbook mới
    if (clearPrevious === true) {
      var allExistingSheets = ss.getSheets();
      for (var sIdx = allExistingSheets.length - 1; sIdx >= 0; sIdx--) {
        var sToDel = allExistingSheets[sIdx];
        var sToDelName = sToDel.getName();
        if (sToDelName !== 'Overview' && sToDelName.indexOf('Temp_') !== 0) {
          try {
            ss.deleteSheet(sToDel);
            Logger.log('Đã xóa sheet cũ trước đó: ' + sToDelName);
          } catch (e) {
            Logger.log('Không thể xóa sheet cũ: ' + sToDelName + ': ' + e);
          }
        }
      }
    }

    // 2. Đồng bộ từng lớp học và thu thập danh sách tên sheet active
    var expectedSheetNames = {};
    for (var i = 0; i < classes.length; i++) {
      try {
        var cls = classes[i];
        var cName = cls.className || ('Lop_' + (i + 1));
        var rawSheetName = (cls.scheduleCode || '12') + '_' + (cls.subjectCode || 'PRM393') + '_' + cName;
        // RÀNG BUỘC: Sanitize tên sheet chống ký tự cấm của Google Sheets
        var sheetName = this.sanitizeSheetName(rawSheetName);
        expectedSheetNames[sheetName] = true;

        var classSheet = ss.getSheetByName(sheetName);
        if (!classSheet) {
          // Thêm sheet mới vào vị trí cuối cùng bên phải (không chèn đằng trước)
          classSheet = ss.insertSheet(sheetName, ss.getSheets().length);
        }

        // RÀNG BUỘC THỨ TỰ:
        // Đặt vị trí sheet theo đúng thứ tự danh sách lớp (sau Overview, lớp thêm sau vào sau)
        try {
          ss.setActiveSheet(classSheet);
          ss.moveActiveSheet(i + 2);
        } catch (moveErr) {}

        this.setupClassMarkbookSheet(classSheet, cls, startDateStr, clearPrevious);
      } catch (classErr) {
        Logger.log('Lỗi đồng bộ sheet lớp ' + i + ': ' + classErr);
      }
    }

    // 3. Xử lý các sheet thừa (lớp không còn trong danh sách file import mới)
    // RÀNG BUỘC BẢO VỆ DỮ LIỆU:
    // - Nếu sheet ĐÃ CÓ dữ liệu điểm danh (P hoặc A): KHÔNG xoá, đổi tên thành [Archived] và ẩn tab
    // - Nếu sheet là sheet trắng (chưa từng điểm danh): Cho phép xoá an toàn
    var protectedSystemSheets = {
      'Overview': true,
      'Classes': true,
      'Students': true,
      'Lessons': true,
      'Sessions': true,
      'Attendances': true
    };
    var allSheets = ss.getSheets();
    for (var s = allSheets.length - 1; s >= 0; s--) {
      var sheet = allSheets[s];
      var sName = sheet.getName();
      if (!protectedSystemSheets[sName] && !expectedSheetNames[sName] && sName.indexOf('Temp_') !== 0) {
        try {
          if (this.hasAttendanceData(sheet)) {
            // Bảo toàn lịch sử: đánh dấu Archived và ẩn sheet
            if (sName.indexOf('[Archived] ') !== 0) {
              var archivedName = this.sanitizeSheetName('[Archived] ' + sName);
              if (ss.getSheetByName(archivedName)) {
                archivedName = this.sanitizeSheetName(archivedName + '_' + new Date().getTime());
              }
              sheet.setName(archivedName);
              try {
                sheet.setTabColor('#94A3B8');
                sheet.hideSheet();
              } catch (e) {}
              Logger.log('Đã lưu trữ an toàn sheet có điểm danh: ' + archivedName);
            }
          } else {
            // Sheet trắng chưa điểm danh: xoá an toàn
            ss.deleteSheet(sheet);
            Logger.log('Đã dọn dẹp sheet trắng không dùng: ' + sName);
          }
        } catch (delErr) {
          Logger.log('Lỗi xử lý sheet thừa ' + sName + ': ' + delErr);
        }
      }
    }

    // Kích hoạt lại tab Overview để khi mở file luôn thấy Overview đầu tiên
    try {
      ss.setActiveSheet(overviewSheet);
    } catch (e) {}

    SpreadsheetApp.flush();
    return {
      success: true,
      classCount: classes.length,
      spreadsheetUrl: ss.getUrl()
    };
  },

  /**
   * Thiết lập Sheet Overview tổng quan theo chuẩn Notion Database
   */
  setupOverviewSheet: function (sheet, classes, startDateStr) {
    sheet.clear();
    sheet.clearFormats();

    // Banner tiêu đề (Callout box đặc trưng của Notion)
    sheet.getRange('A1:H1').merge();
    var titleCell = sheet.getRange('A1');
    var startText = startDateStr ? '  ·  Ngày bắt đầu: ' + startDateStr : '';
    titleCell.setValue('✦  TỔNG QUAN LỊCH GIẢNG DẠY HỌC KỲ' + startText);
    titleCell.setBackground('#F1F1EF'); // Notion Callout Gray
    titleCell.setFontColor('#37352F'); // Notion Primary Charcoal
    titleCell.setFontWeight('bold');
    titleCell.setFontSize(11);
    titleCell.setHorizontalAlignment('left');
    titleCell.setVerticalAlignment('middle');
    titleCell.setBorder(true, true, true, true, false, false, '#E9E9E7', SpreadsheetApp.BorderStyle.SOLID);
    sheet.setRowHeight(1, 38);

    // Header bảng (Property headers chuẩn Notion: nền ấm #F7F6F3, chữ xám #787774)
    var headers = ['STT', 'Mã môn', 'Tên lớp', 'Mã lịch', 'Lịch học chi tiết', 'Khai giảng', 'Kết thúc', 'Sĩ số'];
    sheet.getRange(2, 1, 1, headers.length).setValues([headers]);
    var hRange = sheet.getRange(2, 1, 1, headers.length);
    hRange.setBackground('#F7F6F3'); // Notion Database Header
    hRange.setFontColor('#787774'); // Notion Muted Property Label
    hRange.setFontWeight('bold');
    hRange.setFontSize(10);
    hRange.setHorizontalAlignment('center');
    hRange.setVerticalAlignment('middle');
    hRange.setBorder(true, true, true, true, true, true, '#E9E9E7', SpreadsheetApp.BorderStyle.SOLID);
    sheet.setRowHeight(2, 34);

    // Dữ liệu từng lớp
    var rows = [];
    for (var i = 0; i < classes.length; i++) {
      var c = classes[i];
      var lessons = c.lessons || [];
      var firstDate = (lessons.length > 0 && lessons[0].date) ? lessons[0].date : (startDateStr || '-');
      var lastDate = (lessons.length > 0 && lessons[lessons.length - 1].date) ? lessons[lessons.length - 1].date : '-';
      var schedDesc = this.getScheduleDescription(c.scheduleCode);

      rows.push([
        i + 1,
        c.subjectCode || 'PRM393',
        c.className,
        c.scheduleCode || '',
        schedDesc,
        firstDate,
        lastDate,
        c.roster ? c.roster.length : 0
      ]);
    }

    if (rows.length > 0) {
      var dataRange = sheet.getRange(3, 1, rows.length, headers.length);
      dataRange.setValues(rows);
      dataRange.setHorizontalAlignment('center');
      dataRange.setVerticalAlignment('middle');
      dataRange.setFontColor('#37352F');
      dataRange.setFontSize(10);
      dataRange.setBorder(true, true, true, true, true, true, '#EDEDEB', SpreadsheetApp.BorderStyle.SOLID);

      // Zebra striping nhẹ nhàng kiểu Notion (#FFFFFF và #FAFAF9)
      var bgList = [];
      for (var r = 0; r < rows.length; r++) {
        var rowBg = (r % 2 === 0) ? '#FFFFFF' : '#FAFAF9';
        var rBgs = [];
        for (var col = 0; col < headers.length; col++) rBgs.push(rowBg);
        bgList.push(rBgs);
      }
      dataRange.setBackgrounds(bgList);

      sheet.getRange(3, 8, rows.length, 1).setNumberFormat('0');
      sheet.getRange(3, 6, rows.length, 2).setNumberFormat('@');
      sheet.setRowHeights(3, rows.length, 28);
    }

    sheet.setFrozenRows(2);
    var colWidths = [45, 90, 115, 85, 230, 140, 140, 80];
    for (var c = 0; c < colWidths.length; c++) {
      sheet.setColumnWidth(c + 1, colWidths[c]);
    }
  },

  /**
   * Thiết lập Sheet Markbook cho 1 Lớp cụ thể chuẩn Notion Database
   * Tông màu ấm, typography sắc nét, tag pill pastel và viền tối giản
   * Tự động bảo toàn các dấu điểm danh (P / A) đã ghi nhận trước đó
   */
  setupClassMarkbookSheet: function (sheet, cls, startDateStr, clearPrevious) {
    var lessons = cls.lessons || [];
    var slotCount = lessons.length > 0 ? lessons.length : (cls.slotCount || 20);
    var scheduleInfo = this.getScheduleDescription(cls.scheduleCode);

    // 0. Nếu không yêu cầu clearPrevious và sheet đã có dữ liệu trước đó, bảo toàn toàn bộ kết quả điểm danh (P / A)
    var existingAttendance = {};
    if (!clearPrevious) {
      try {
        if (sheet.getLastRow() >= 3 && sheet.getLastColumn() >= 6) {
          var existingData = sheet.getDataRange().getValues();
          for (var er = 2; er < existingData.length; er++) {
            var eRoll = String(existingData[er][1] || '').trim().toLowerCase();
            var eEmail = String(existingData[er][3] || '').trim().toLowerCase();
            if (!eEmail && !eRoll) continue;

            var attMap = {};
            for (var es = 1; es <= slotCount; es++) {
              var colIdx = 5 + es - 1; // 0-indexed: Cột F là index 5 (Slot 1)
              if (colIdx < existingData[er].length) {
                var mark = String(existingData[er][colIdx] || '').trim();
                if (mark === 'P' || mark === 'A') {
                  attMap[es] = mark;
                }
              }
            }
            if (eEmail) existingAttendance[eEmail] = attMap;
            if (eRoll) existingAttendance[eRoll] = attMap;
          }
        }
      } catch (readErr) {
        Logger.log('Không thể đọc dữ liệu điểm danh cũ: ' + readErr);
      }
    }

    sheet.clear();

    // Dòng 1: Banner lớp học (Notion Callout Box: nền #F1F1EF, chữ than #37352F, viền #E9E9E7)
    var totalCols = 5 + slotCount + 3; // 5 cột info + N slot + 3 cột thống kê
    sheet.getRange(1, 1, 1, totalCols).merge();
    var bannerCell = sheet.getRange(1, 1);
    bannerCell.setValue('✦  Môn: ' + (cls.subjectCode || 'PRM393') + '  ·  Lớp: ' + cls.className + '  ·  Lịch: ' + cls.scheduleCode + ' (' + scheduleInfo + ')  ·  ' + (cls.roster ? cls.roster.length : 0) + ' sinh viên');
    bannerCell.setBackground('#F1F1EF'); // Notion Callout Gray
    bannerCell.setFontColor('#37352F'); // Notion Primary Text
    bannerCell.setFontWeight('bold');
    bannerCell.setFontSize(11);
    bannerCell.setHorizontalAlignment('left');
    bannerCell.setVerticalAlignment('middle');
    bannerCell.setBorder(true, true, true, true, false, false, '#E9E9E7', SpreadsheetApp.BorderStyle.SOLID);
    sheet.setRowHeight(1, 38);

    // Dòng 2: Tiêu đề cột (Notion Database Header: nền #F7F6F3, chữ xám #787774)
    var headers = ['STT', 'MSSV', 'Họ và tên', 'Email', 'Mã FAP'];
    for (var s = 1; s <= slotCount; s++) {
      var les = lessons[s - 1];
      var slotTitle = 'Slot ' + (s < 10 ? '0' + s : s);
      if (les && les.date) {
        var dateParts = String(les.date).split('-');
        if (dateParts.length === 3) {
          slotTitle += '\n' + dateParts[2] + '/' + dateParts[1]; // 07/09 định dạng chuẩn
        } else {
          slotTitle += '\n' + String(les.date).substring(5);
        }
      }
      headers.push(slotTitle);
    }
    headers.push('Tổng vắng');
    headers.push('Tỉ lệ vắng');
    headers.push('Trạng thái');

    sheet.getRange(2, 1, 1, headers.length).setValues([headers]);
    var headerRange = sheet.getRange(2, 1, 1, headers.length);
    headerRange.setBackground('#F7F6F3'); // Notion Database Header
    headerRange.setFontColor('#787774'); // Notion Secondary Gray
    headerRange.setFontWeight('bold');
    headerRange.setFontSize(10);
    headerRange.setHorizontalAlignment('center');
    headerRange.setVerticalAlignment('middle');
    headerRange.setWrap(true);
    headerRange.setBorder(true, true, true, true, true, true, '#E9E9E7', SpreadsheetApp.BorderStyle.SOLID);
    sheet.setRowHeight(2, 38);

    // Dòng 3..N: Dữ liệu Sinh viên
    var roster = cls.roster || [];
    var rows = [];

    for (var r = 0; r < roster.length; r++) {
      var st = roster[r];
      var rowNum = r + 3;
      var email = String(st.email || '').trim().toLowerCase();
      var roll = String(st.rollNumber || '').trim().toLowerCase();
      var row = [
        r + 1,
        st.rollNumber || '',
        st.fullName || '',
        email,
        st.memberCode || ''
      ];

      // Điền trạng thái điểm danh hiện tại nếu có (ưu tiên điểm danh đã có trên sheet)
      var studentAttendance = existingAttendance[email] ||
                              existingAttendance[roll] ||
                              st.attendance || {};
      for (var s = 1; s <= slotCount; s++) {
        var status = studentAttendance[s] || studentAttendance[String(s)] || '';
        row.push(status);
      }

      // Công thức tính Tổng Vắng (số buổi 'A')
      var startColLetter = 'F';
      var endColLetter = this.getColumnLetter(5 + slotCount);
      var absentColLetter = this.getColumnLetter(5 + slotCount + 1);
      var pctColLetter = this.getColumnLetter(5 + slotCount + 2);

      var absentFormula = '=COUNTIF(' + startColLetter + rowNum + ':' + endColLetter + rowNum + ', "A")';
      var pctFormula = '=IF(' + slotCount + '>0, ' + absentColLetter + rowNum + '/' + slotCount + ', 0)';
      var resultFormula = '=IF(' + pctColLetter + rowNum + '>0.20, "Cấm thi", IF(' + pctColLetter + rowNum + '>=0.15, "Cảnh báo", "Đủ điều kiện"))';

      row.push(absentFormula);
      row.push(pctFormula);
      row.push(resultFormula);

      rows.push(row);
    }

    if (rows.length > 0) {
      var dataRange = sheet.getRange(3, 1, rows.length, headers.length);
      dataRange.setValues(rows);
      dataRange.setVerticalAlignment('middle');
      dataRange.setFontColor('#37352F');
      dataRange.setFontSize(10);
      dataRange.setBorder(true, true, true, true, true, true, '#EDEDEB', SpreadsheetApp.BorderStyle.SOLID);

      // Zebra striping nhẹ nhàng kiểu Notion (#FFFFFF và #FAFAF9)
      var bgMatrix = [];
      for (var r = 0; r < rows.length; r++) {
        var rowBg = (r % 2 === 0) ? '#FFFFFF' : '#FAFAF9';
        var rBgs = [];
        for (var col = 0; col < headers.length; col++) {
          rBgs.push(rowBg);
        }
        bgMatrix.push(rBgs);
      }
      dataRange.setBackgrounds(bgMatrix);

      // Căn chỉnh vị trí chuẩn Notion Table
      sheet.getRange(3, 1, rows.length, 1).setHorizontalAlignment('center').setFontColor('#787774'); // STT mờ
      sheet.getRange(3, 2, rows.length, 1).setHorizontalAlignment('center').setFontColor('#37352F'); // MSSV
      sheet.getRange(3, 3, rows.length, 1).setHorizontalAlignment('left').setFontColor('#37352F');   // Họ và tên
      sheet.getRange(3, 4, rows.length, 1).setHorizontalAlignment('left').setFontColor('#787774');   // Email (gray)
      sheet.getRange(3, 5, rows.length, 1).setHorizontalAlignment('center').setFontColor('#787774'); // Mã FAP
      sheet.getRange(3, 6, rows.length, slotCount).setHorizontalAlignment('center').setFontWeight('bold');
      sheet.getRange(3, 5 + slotCount + 1, rows.length, 3).setHorizontalAlignment('center');

      // Chiều cao từng hàng dữ liệu thoáng đãng
      sheet.setRowHeights(3, rows.length, 26);

      // Định dạng % cho cột Tỉ lệ vắng
      var pctColIndex = 5 + slotCount + 2;
      sheet.getRange(3, pctColIndex, rows.length, 1).setNumberFormat('0.0%').setFontColor('#787774');

      // Conditional Formatting: Tone màu Notion Tags / Pills chính hãng
      var slotRange = sheet.getRange(3, 6, rows.length, slotCount);
      var ruleP = SpreadsheetApp.newConditionalFormatRule()
        .whenTextEqualTo('P')
        .setBackground('#DBEDDB') // Notion Green tag
        .setFontColor('#1C3829') // Notion Green text
        .setRanges([slotRange])
        .build();

      var ruleA = SpreadsheetApp.newConditionalFormatRule()
        .whenTextEqualTo('A')
        .setBackground('#FFE2DD') // Notion Red tag
        .setFontColor('#5D1715') // Notion Red text
        .setRanges([slotRange])
        .build();

      // Conditional Formatting cho cột Trạng thái (Notion tag pills)
      var resultColIndex = 5 + slotCount + 3;
      var resultRange = sheet.getRange(3, resultColIndex, rows.length, 1);

      var ruleCamThi = SpreadsheetApp.newConditionalFormatRule()
        .whenTextEqualTo('Cấm thi')
        .setBackground('#FFE2DD') // Notion Red tag
        .setFontColor('#5D1715')
        .setRanges([resultRange])
        .build();

      var ruleCanhBao = SpreadsheetApp.newConditionalFormatRule()
        .whenTextEqualTo('Cảnh báo')
        .setBackground('#FDECC8') // Notion Yellow/Orange tag
        .setFontColor('#402C1B')
        .setRanges([resultRange])
        .build();

      var ruleDuDieuKien = SpreadsheetApp.newConditionalFormatRule()
        .whenTextEqualTo('Đủ điều kiện')
        .setBackground('#DBEDDB') // Notion Green tag
        .setFontColor('#1C3829')
        .setRanges([resultRange])
        .build();

      sheet.setConditionalFormatRules([ruleP, ruleA, ruleCamThi, ruleCanhBao, ruleDuDieuKien]);
    }

    // Cố định dòng 2 (Header) và 3 cột đầu (STT, MSSV, Tên)
    sheet.setFrozenRows(2);
    sheet.setFrozenColumns(3);

    // Độ rộng các cột chuẩn form Notion
    sheet.setColumnWidth(1, 45);  // STT
    sheet.setColumnWidth(2, 95);  // MSSV
    sheet.setColumnWidth(3, 190); // Họ và tên
    sheet.setColumnWidth(4, 220); // Email
    sheet.setColumnWidth(5, 85);  // Mã FAP
    sheet.setColumnWidths(6, slotCount, 64); // Các cột Slot
    sheet.setColumnWidth(5 + slotCount + 1, 95);  // Tổng vắng
    sheet.setColumnWidth(5 + slotCount + 2, 95);  // Tỉ lệ vắng
    sheet.setColumnWidth(5 + slotCount + 3, 115); // Trạng thái
  },

  /**
   * Ghi nhận điểm danh sinh viên (P - Có mặt)
   * Cập nhật trực tiếp vào ô tương ứng trong sheet của lớp
   */
  recordCheckIn: function (lessonId, studentEmail) {
    return this.setAttendanceStatus(lessonId, studentEmail, 'P');
  },

  /**
   * Giảng viên đổi điểm danh thủ công (P hoặc A)
   */
  recordOverride: function (lessonId, studentEmail, status) {
    return this.setAttendanceStatus(lessonId, studentEmail, status);
  },

  /**
   * Cập nhật giá trị ô Slot của sinh viên trong đúng sheet lớp tương ứng
   * Tuyệt đối không tạo lại sheet, chỉ cập nhật 1 ô duy nhất trong 1 giây!
   */
  setAttendanceStatus: function (lessonId, studentEmail, status) {
    var ss = this.getSpreadsheet();
    var parts = this.parseLessonId(lessonId);
    if (!parts) return { success: false, error: 'Sai định dạng lessonId: ' + lessonId };

    var targetSheet = this.findClassSheet(ss, parts);
    if (!targetSheet) return { success: false, error: 'Không tìm thấy sheet của lớp ' + parts.className };

    var data = targetSheet.getDataRange().getValues();
    if (data.length <= 2) return { success: false, error: 'Sheet lớp chưa có sinh viên' };

    var normalizedEmail = String(studentEmail).trim().toLowerCase();
    var targetRow = -1;

    // Tìm dòng của sinh viên (cột D là Email, index 3; hoặc cột B là MSSV, index 1)
    for (var r = 2; r < data.length; r++) {
      var emailInCell = String(data[r][3]).trim().toLowerCase();
      var rollInCell = String(data[r][1]).trim().toLowerCase();
      if (emailInCell === normalizedEmail || rollInCell === normalizedEmail) {
        targetRow = r + 1; // 1-indexed
        break;
      }
    }

    if (targetRow === -1) {
      return { success: false, error: 'Không tìm thấy sinh viên ' + studentEmail + ' trong lớp ' + parts.className };
    }

    // Cột slot tương ứng: Slot 1 là cột F (cột 6), Slot N là (5 + sequenceNumber)
    var targetCol = 5 + parts.sequenceNumber;
    var currentCell = targetSheet.getRange(targetRow, targetCol);
    var currentVal = String(currentCell.getValue() || '').trim().toUpperCase();

    // Nếu sinh viên đã có trạng thái P từ trước, báo đã điểm danh rồi
    if (currentVal === 'P' && status === 'P') {
      return {
        success: true,
        alreadyRecorded: true,
        status: 'ALREADY_CHECKED_IN',
        className: parts.className,
        sequenceNumber: parts.sequenceNumber,
        studentEmail: studentEmail
      };
    }

    currentCell.setValue(status);
    SpreadsheetApp.flush();

    return {
      success: true,
      className: parts.className,
      sequenceNumber: parts.sequenceNumber,
      studentEmail: studentEmail,
      status: status
    };
  },

  /**
   * Lấy kết quả điểm danh của 1 buổi học để phục vụ polling 5s
   */
  getAttendanceResults: function (lessonId) {
    var ss = this.getSpreadsheet();
    var parts = this.parseLessonId(lessonId);
    if (!parts) return [];

    var targetSheet = this.findClassSheet(ss, parts);
    if (!targetSheet) return [];

    var data = targetSheet.getDataRange().getValues();
    if (data.length <= 2) return [];

    var targetCol = 5 + parts.sequenceNumber;
    var numRows = data.length - 2;
    var range = targetSheet.getRange(3, targetCol, numRows, 1);
    var colValues = range.getValues();
    var results = [];
    var hasBlankChanges = false;

    for (var r = 0; r < colValues.length; r++) {
      var email = String(data[r + 2][3] || '').trim().toLowerCase();
      var rollNumber = String(data[r + 2][1] || '').trim();
      var fullName = String(data[r + 2][2] || '').trim();
      var val = String(colValues[r][0] || '').trim().toUpperCase();

      if (email) {
        // Tự động khởi tạo 'A' cho sinh viên chưa điểm danh để không bị ô trống trên Google Sheet
        if (val === '') {
          colValues[r][0] = 'A';
          val = 'A';
          hasBlankChanges = true;
        }
        results.push({
          studentEmail: email,
          rollNumber: rollNumber,
          fullName: fullName,
          status: val,
          isManualOverride: false
        });
      }
    }

    if (hasBlankChanges) {
      range.setValues(colValues);
      SpreadsheetApp.flush();
    }

    return results;
  },

  /**
   * Đọc toàn bộ ma trận điểm danh của tất cả các lớp học từ Google Sheets
   * Phục vụ đồng bộ 2 chiều (Google Sheets -> App)
   */
  getAllAttendance: function () {
    var ss = this.getSpreadsheet();
    var sheets = ss.getSheets();
    var store = {};

    for (var i = 0; i < sheets.length; i++) {
      var sheet = sheets[i];
      var sheetName = sheet.getName();
      var lowerName = sheetName.toLowerCase();

      // Bỏ qua các sheet hệ thống và sheet đã lưu trữ (Archived)
      if (lowerName === 'overview' || lowerName.indexOf('temp_') === 0 ||
          lowerName.indexOf('archived') !== -1 || lowerName === 'classes' ||
          lowerName === 'students' || lowerName === 'lessons') {
        continue;
      }

      var data = sheet.getDataRange().getValues();
      if (data.length <= 2) continue; // Cần có ít nhất 1 dòng sinh viên (từ dòng 3)

      // Đọc Banner dòng 1 để xác định subjectCode và className nếu có
      var banner = String(data[0][0] || '');
      var subjectCode = '';
      var className = '';

      var subMatch = banner.match(/Môn:\s*([A-Za-z0-9]+)/i);
      if (subMatch) subjectCode = subMatch[1];
      var classMatch = banner.match(/Lớp:\s*([A-Za-z0-9_-]+)/i);
      if (classMatch) className = classMatch[1];

      // Nếu không parse được từ banner thì parse từ tên sheet (ví dụ 12_PRM393_SE1920)
      if (!className) {
        var parts = sheetName.split('_');
        if (parts.length >= 3) {
          subjectCode = subjectCode || parts[1];
          className = parts[2];
        } else {
          className = sheetName;
        }
      }

      var slotCount = 20;
      var slotMap = {};
      for (var s = 1; s <= slotCount; s++) {
        slotMap[s] = {};
      }

      for (var r = 2; r < data.length; r++) {
        var email = String(data[r][3] || '').trim().toLowerCase();
        if (!email) continue;

        for (var s = 1; s <= slotCount; s++) {
          var colIndex = 5 + s - 1; // 0-indexed: Slot 1 là cột F (index 5)
          if (colIndex < data[r].length) {
            var val = String(data[r][colIndex] || '').trim().toUpperCase();
            if (val === 'P' || val === 'A') {
              slotMap[s][email] = val;
            }
          }
        }
      }

      // Lưu trữ theo các định dạng key để đảm bảo Desktop App tra cứu đều tìm thấy
      if (subjectCode && className) {
        var compositeKey = subjectCode + ' - ' + className;
        store[compositeKey] = slotMap;
      }
      store[sheetName] = slotMap;
      if (className) {
        store[className] = slotMap;
      }
    }

    return store;
  },

  /**
   * Quản lý ca điểm danh mở (Lưu trong ScriptProperties để phản hồi tức thì)
   */
  openAttendanceWindow: function (lessonId) {
    var parts = this.parseLessonId(lessonId);
    if (parts) {
      // Khi mở ca lần đầu: chuyển toàn bộ ô trống của slot đó thành 'A'
      var ss = this.getSpreadsheet();
      var targetSheet = this.findClassSheet(ss, parts);
      if (targetSheet) {
        var numRows = targetSheet.getLastRow() - 2;
        if (numRows > 0) {
          var targetCol = 5 + parts.sequenceNumber;
          var range = targetSheet.getRange(3, targetCol, numRows, 1);
          var vals = range.getValues();
          var hasChanges = false;
          for (var r = 0; r < vals.length; r++) {
            var currentVal = String(vals[r][0] || '').trim().toUpperCase();
            if (currentVal === '') {
              vals[r][0] = 'A';
              hasChanges = true;
            }
          }
          if (hasChanges) {
            range.setValues(vals);
            SpreadsheetApp.flush();
          }
        }
      }
    }

    var props = PropertiesService.getScriptProperties();
    // Nếu ca này đã đang mở và trùng lessonId thì giữ nguyên windowId hiện tại
    var windowStr = props.getProperty('ACTIVE_WINDOW');
    if (windowStr) {
      try {
        var existingWin = JSON.parse(windowStr);
        if (existingWin.isOpen && (!lessonId || existingWin.lessonId === lessonId) && existingWin.id) {
          return existingWin;
        }
      } catch (e) {}
    }

    var windowId = 'win_' + new Date().getTime();
    var windowData = {
      id: windowId,
      lessonId: lessonId,
      openedAt: new Date().toISOString(),
      isOpen: true
    };
    props.setProperty('ACTIVE_WINDOW', JSON.stringify(windowData));
    return windowData;
  },

  closeAttendanceWindow: function (windowId) {
    var props = PropertiesService.getScriptProperties();
    var windowStr = props.getProperty('ACTIVE_WINDOW');
    if (windowStr) {
      var win = JSON.parse(windowStr);
      win.isOpen = false;
      win.closedAt = new Date().toISOString();
      props.setProperty('ACTIVE_WINDOW', JSON.stringify(win));
    }
    return true;
  },

  getActiveWindow: function (lessonId) {
    var props = PropertiesService.getScriptProperties();
    var windowStr = props.getProperty('ACTIVE_WINDOW');
    if (!windowStr) return null;
    var win = JSON.parse(windowStr);
    if (win.isOpen && (!lessonId || win.lessonId === lessonId)) {
      return win;
    }
    return null;
  },

  isStudentInClass: function (classId, studentEmail) {
    var normalizedClassId = String(classId || '').trim().toLowerCase();
    var normalizedEmail = String(studentEmail || '').trim().toLowerCase();
    if (!normalizedClassId || !normalizedEmail) return false;

    var ss = this.getSpreadsheet();
    var sheets = ss.getSheets();
    for (var i = 0; i < sheets.length; i++) {
      var sheet = sheets[i];
      var sheetName = sheet.getName().toLowerCase();
      if (sheetName === 'overview' || sheetName.indexOf('temp_') === 0 ||
          sheetName.indexOf('archived') !== -1 ||
          sheetName === 'classes' || sheetName === 'students' || sheetName === 'lessons') continue;

      // Khớp theo classId (ví dụ 11_PRN232_SE1917 hoặc PRN232_SE1917_FA26)
      var parts = normalizedClassId.split('_');
      var match = true;
      for (var p = 0; p < parts.length; p++) {
        if (parts[p].length > 1 && sheetName.indexOf(parts[p]) === -1) {
          match = false;
          break;
        }
      }
      if (!match && sheetName.indexOf(normalizedClassId) === -1) continue;

      var data = sheet.getDataRange().getValues();
      for (var row = 2; row < data.length; row++) {
        var emailInCell = String(data[row][3] || '').trim().toLowerCase();
        var rollInCell = String(data[row][1] || '').trim().toLowerCase();
        if (emailInCell === normalizedEmail || rollInCell === normalizedEmail) {
          return true;
        }
      }
    }
    return false;
  },

  /**
   * Reset toàn bộ trạng thái điểm danh của 1 slot về 'A' (hoặc giá trị chỉ định)
   * Giúp khởi tạo buổi học mới hoặc sửa lại toàn bộ ô bị lỗi
   */
  resetSlotAttendance: function (lessonId, defaultStatus) {
    var ss = this.getSpreadsheet();
    var parts = this.parseLessonId(lessonId);
    if (!parts) return { success: false, error: 'Sai định dạng lessonId: ' + lessonId };

    var targetSheet = this.findClassSheet(ss, parts);
    if (!targetSheet) return { success: false, error: 'Không tìm thấy sheet của lớp' };

    var numRows = targetSheet.getLastRow() - 2;
    if (numRows <= 0) return { success: false, error: 'Sheet không có dữ liệu sinh viên' };

    var targetCol = 5 + parts.sequenceNumber;
    var range = targetSheet.getRange(3, targetCol, numRows, 1);
    var st = defaultStatus || 'A';
    var vals = [];
    for (var r = 0; r < numRows; r++) {
      vals.push([st]);
    }
    range.setValues(vals);
    SpreadsheetApp.flush();

    return {
      success: true,
      className: parts.className,
      sequenceNumber: parts.sequenceNumber,
      count: numRows,
      status: st
    };
  },

  /**
   * Khởi tạo bảng mẫu mặc định nếu chạy lần đầu
   */
  setupDatabase: function () {
    var ss = this.getSpreadsheet();
    var sampleClass = {
      className: 'SE1917',
      subjectCode: 'PRM393',
      scheduleCode: '12',
      slotCount: 20,
      lessons: [],
      roster: [
        { rollNumber: 'SE182346', fullName: 'Trần Gia Bảo', email: 'baotgse182346@fpt.edu.vn', memberCode: 'BaoTG' },
        { rollNumber: 'SE193416', fullName: 'Nguyễn Ngọc Bảo Cường', email: 'cuongnnbse193416@fpt.edu.vn', memberCode: 'CuongNNB' },
        { rollNumber: 'SE190507', fullName: 'Ngô Chí Nam', email: 'namncse190507@fpt.edu.vn', memberCode: 'NamNC' },
        { rollNumber: 'SE193445', fullName: 'Ngô Tấn Thành', email: 'thanhntse193445@fpt.edu.vn', memberCode: 'ThanhNT' },
        { rollNumber: 'SE172145', fullName: 'Nguyễn Mai Hào Thiên', email: 'thiennmhse172145@fpt.edu.vn', memberCode: 'ThienNMH' }
      ]
    };
    for (var s = 1; s <= 20; s++) {
      sampleClass.lessons.push({ sequenceNumber: s, date: '2026-09-' + (10 + s) });
    }
    return this.syncAllClassesFromDesktop([sampleClass], '2026-09-07');
  },

  /**
   * Tìm sheet của lớp bằng cách khớp cả className và subjectCode, loại bỏ triệt để các sheet Archived
   */
  findClassSheet: function (ss, parts) {
    var sheets = ss.getSheets();
    var nonArchivedSheets = [];

    for (var i = 0; i < sheets.length; i++) {
      var sName = sheets[i].getName();
      var lower = sName.toLowerCase();
      if (lower === 'overview' || lower.indexOf('temp_') === 0 || lower.indexOf('archived') !== -1 ||
          lower === 'classes' || lower === 'students' || lower === 'lessons') {
        continue;
      }
      nonArchivedSheets.push(sheets[i]);
    }

    var targetClassName = parts.className ? parts.className.toLowerCase() : '';
    var targetSubject = parts.subjectCode ? parts.subjectCode.toLowerCase() : '';
    var targetSchedule = parts.scheduleCode ? String(parts.scheduleCode) : '';

    // Pass 1: Khớp chính xác scheduleCode + subjectCode + className (ví dụ 14_PRM393_SE1920)
    if (targetSchedule && targetSubject && targetClassName) {
      for (var i = 0; i < nonArchivedSheets.length; i++) {
        var lower = nonArchivedSheets[i].getName().toLowerCase();
        if (lower.indexOf(targetSchedule) !== -1 && lower.indexOf(targetSubject) !== -1 && lower.indexOf(targetClassName) !== -1) {
          return nonArchivedSheets[i];
        }
      }
    }

    // Pass 2: Khớp cả className và subjectCode (tránh nhầm môn giữa SE1917 của PRN232 và PRM393)
    if (targetSubject && targetClassName) {
      for (var i = 0; i < nonArchivedSheets.length; i++) {
        var lower = nonArchivedSheets[i].getName().toLowerCase();
        if (lower.indexOf(targetSubject) !== -1 && lower.indexOf(targetClassName) !== -1) {
          return nonArchivedSheets[i];
        }
      }
    }

    // Pass 3: Khớp tên lớp className
    if (targetClassName) {
      for (var i = 0; i < nonArchivedSheets.length; i++) {
        var lower = nonArchivedSheets[i].getName().toLowerCase();
        if (lower.indexOf(targetClassName) !== -1) {
          return nonArchivedSheets[i];
        }
      }
    }

    return null;
  },

  /**
   * Phân tích lessonId dạng '11_PRN232_SE1917-L03' hoặc 'PRM393_SE1917-L01' thành scheduleCode, subjectCode, className và sequenceNumber
   */
  parseLessonId: function (lessonId) {
    if (!lessonId) return null;
    var str = String(lessonId).trim();

    // Pattern 1: [optional scheduleCode_] subjectCode _ classCode [optional _semester] -L sequenceNumber
    // E.g. 11_PRN232_SE1917-L03, PRM393_SE1917-L01, 11_PRN232_SE1917_FA26-L03, 14_PRM393_SE1920-L01
    var m1 = str.match(/^(?:(\d+)_)?([A-Za-z0-9]+)_([A-Za-z0-9]+)(?:_[A-Za-z0-9]+)?-L(\d+)$/i);
    if (m1) {
      return {
        scheduleCode: m1[1] || '',
        subjectCode: m1[2],
        className: m1[3],
        sequenceNumber: parseInt(m1[4], 10)
      };
    }

    // Pattern 2: [optional scheduleCode_] subjectCode _ classCode _Lesson_ sequenceNumber
    var m2 = str.match(/^(?:(\d+)_)?([A-Za-z0-9]+)_([A-Za-z0-9]+)_Lesson_(\d+)$/i);
    if (m2) {
      return {
        scheduleCode: m2[1] || '',
        subjectCode: m2[2],
        className: m2[3],
        sequenceNumber: parseInt(m2[4], 10)
      };
    }

    // Pattern 3: Explicit slot suffix like -slot-1 or _slot1
    var m3 = str.match(/(?:-|_)(?:slot|lesson|l)(\d+)$/i);
    if (m3) {
      return {
        scheduleCode: '',
        subjectCode: '',
        className: str.replace(m3[0], ''),
        sequenceNumber: parseInt(m3[1], 10)
      };
    }

    // Pattern 4: Fallback - Do NOT treat 4-digit class years (like 1920) as slot sequence!
    var seqMatch = str.match(/-(?:L)?(\d{1,2})$/i);
    return {
      scheduleCode: '',
      subjectCode: '',
      className: str,
      sequenceNumber: seqMatch ? parseInt(seqMatch[1], 10) : 1
    };
  },

  getScheduleDescription: function (code) {
    var normalized = String(code || '');
    var weekdayMap = {
      '1': 'Thứ 2 & Thứ 5',
      '2': 'Thứ 3 & Thứ 6',
      '3': 'Thứ 4 & Thứ 7'
    };
    var timeMap = {
      '1': '07:00 - 09:15',
      '2': '09:30 - 11:45',
      '3': '12:30 - 14:45',
      '4': '15:00 - 17:15',
      '5': '17:45 - 19:15'
    };
    if (!weekdayMap[normalized.charAt(0)] || !timeMap[normalized.charAt(1)]) {
      return 'Mã lịch ' + normalized;
    }
    return weekdayMap[normalized.charAt(0)] + ', Ca ' + normalized.charAt(1) + ' (' + timeMap[normalized.charAt(1)] + ')';
  },

  getColumnLetter: function (colIndex) {
    var temp, letter = '';
    while (colIndex > 0) {
      temp = (colIndex - 1) % 26;
      letter = String.fromCharCode(temp + 65) + letter;
      colIndex = Math.floor((colIndex - temp - 1) / 26);
    }
    return letter;
  }
};
