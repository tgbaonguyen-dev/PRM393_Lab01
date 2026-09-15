/**
 * PRM393 - M1 Schedule Gateway (standalone Apps Script project)
 *
 * Paste this ENTIRE file into a brand-new Apps Script project's Code.gs.
 * This code owns only Classes, Students and Lessons. It intentionally does
 * not call or replace the team's legacy attendance gateway actions.
 */

var SPREADSHEET_ID = '1102ggK2ZECoywxAh6HgNB-Rln3iFsqnjCEeF7hNjQyw';

var CLASS_HEADERS = [
  'classId', 'classCode', 'subjectCode', 'semester', 'scheduleCode',
  'sourceSheetName', 'lessonCount', 'updatedAt'
];
var STUDENT_HEADERS = [
  'recordKey', 'classId', 'classCode', 'rollNumber', 'fullName',
  'email', 'memberCode', 'active'
];
var LESSON_HEADERS = [
  'lessonId', 'classId', 'sequenceNumber', 'date', 'dailySlot',
  'startTime', 'endTime', 'isAdjusted', 'status'
];

function doGet() {
  var spreadsheet = getSpreadsheet();
  return jsonResponse({
    status: 'ok',
    gateway: 'PRM393 M1 Schedule Gateway',
    spreadsheetUrl: spreadsheet.getUrl()
  });
}

function doPost(e) {
  var lock = LockService.getScriptLock();
  try {
    if (!lock.tryLock(20000)) {
      throw new Error('Gateway đang bận. Vui lòng thử lại sau ít phút.');
    }
    if (!e || !e.postData || !e.postData.contents) {
      throw new Error('Thiếu JSON request body.');
    }
    var request = JSON.parse(e.postData.contents);
    var result = dispatchAction(request.action, request.payload || {});
    return jsonResponse({success: true, data: result});
  } catch (error) {
    return jsonResponse({success: false, error: String(error)});
  } finally {
    if (lock.hasLock()) lock.releaseLock();
  }
}

function dispatchAction(action, payload) {
  switch (action) {
    case 'saveClassOffering':
      return saveClassOffering(payload.offering, payload.roster, payload.lessons);
    case 'listSchedules':
      return listSchedules();
    case 'getSchedule':
      return getSchedule(payload.classId);
    case 'ping':
      return {message: 'M1 gateway is ready'};
    default:
      throw new Error('Unknown action: ' + action);
  }
}

function getSpreadsheet() {
  return SpreadsheetApp.openById(SPREADSHEET_ID);
}

function jsonResponse(value) {
  return ContentService
    .createTextOutput(JSON.stringify(value))
    .setMimeType(ContentService.MimeType.JSON);
}

function ensureSheet(name, headers) {
  var spreadsheet = getSpreadsheet();
  var sheet = spreadsheet.getSheetByName(name);
  if (!sheet) sheet = spreadsheet.insertSheet(name);
  if (sheet.getLastRow() === 0) sheet.getRange(1, 1, 1, headers.length).setValues([headers]);
  return sheet;
}

function readRows(sheet) {
  if (sheet.getLastRow() <= 1) return [];
  return sheet.getRange(2, 1, sheet.getLastRow() - 1, sheet.getLastColumn()).getValues();
}

function writeRows(sheet, headers, rows) {
  sheet.clearContents();
  sheet.getRange(1, 1, 1, headers.length).setValues([headers]);
  if (rows.length > 0) sheet.getRange(2, 1, rows.length, headers.length).setValues(rows);
  sheet.setFrozenRows(1);
}

function asText(value) {
  return value === null || value === undefined ? '' : String(value).trim();
}

function requireText(value, label) {
  var text = asText(value);
  if (!text) throw new Error('Thiếu ' + label + '.');
  return text;
}

function sameId(left, right) {
  return asText(left) === asText(right);
}

function saveClassOffering(offering, roster, lessons) {
  if (!offering || typeof offering !== 'object') throw new Error('offering không hợp lệ.');
  if (!Array.isArray(roster)) throw new Error('roster không hợp lệ.');
  if (!Array.isArray(lessons)) throw new Error('lessons không hợp lệ.');

  var classId = requireText(offering.classId, 'classId');
  var classes = ensureSheet('Classes', CLASS_HEADERS);
  var students = ensureSheet('Students', STUDENT_HEADERS);
  var lessonsSheet = ensureSheet('Lessons', LESSON_HEADERS);

  // Upsert only this class. Other imported classes are preserved.
  var classRows = readRows(classes).filter(function(row) { return !sameId(row[0], classId); });
  classRows.push([
    classId,
    asText(offering.classCode).toUpperCase(),
    asText(offering.subjectCode).toUpperCase(),
    asText(offering.semester).toUpperCase(),
    asText(offering.scheduleCode),
    asText(offering.sourceSheetName),
    Number(offering.lessonCount) || 20,
    new Date().toISOString()
  ]);
  writeRows(classes, CLASS_HEADERS, classRows);

  // A re-save replaces this class's roster/lessons only. This removes stale
  // records after the lecturer corrects an import, but preserves other classes.
  var studentRows = readRows(students).filter(function(row) { return !sameId(row[1], classId); });
  roster.forEach(function(student) {
    var rollNumber = asText(student.rollNumber).toUpperCase();
    studentRows.push([
      classId + '|' + rollNumber,
      classId,
      asText(student.classCode || offering.classCode).toUpperCase(),
      rollNumber,
      asText(student.fullName),
      asText(student.email).toLowerCase(),
      asText(student.memberCode),
      true
    ]);
  });
  writeRows(students, STUDENT_HEADERS, studentRows);

  var lessonRows = readRows(lessonsSheet).filter(function(row) { return !sameId(row[1], classId); });
  lessons.forEach(function(lesson) {
    lessonRows.push([
      requireText(lesson.lessonId, 'lessonId'),
      classId,
      Number(lesson.sequenceNumber),
      asText(lesson.date),
      Number(lesson.dailySlot),
      asText(lesson.startTime),
      asText(lesson.endTime),
      lesson.isAdjusted === true,
      asText(lesson.status) || 'scheduled'
    ]);
  });
  writeRows(lessonsSheet, LESSON_HEADERS, lessonRows);
  SpreadsheetApp.flush();
  return {classId: classId, saved: true};
}

function listSchedules() {
  var sheet = getSpreadsheet().getSheetByName('Classes');
  return readRows(sheet || ensureSheet('Classes', CLASS_HEADERS))
    .filter(function(row) { return asText(row[0]); })
    .map(function(row) {
      return {
        classId: asText(row[0]), classCode: asText(row[1]),
        subjectCode: asText(row[2]), semester: asText(row[3]),
        scheduleCode: asText(row[4]), sourceSheetName: asText(row[5]),
        lessonCount: Number(row[6])
      };
    });
}

function getSchedule(classId) {
  classId = requireText(classId, 'classId');
  var offering = listSchedules().filter(function(item) { return item.classId === classId; })[0];
  if (!offering) return null;

  var spreadsheet = getSpreadsheet();
  var studentSheet = spreadsheet.getSheetByName('Students');
  var lessonSheet = spreadsheet.getSheetByName('Lessons');
  var students = readRows(studentSheet || ensureSheet('Students', STUDENT_HEADERS))
    .filter(function(row) { return sameId(row[1], classId); })
    .map(function(row) {
      return {classCode: asText(row[2]), rollNumber: asText(row[3]), fullName: asText(row[4]), email: asText(row[5]), memberCode: asText(row[6])};
    });
  var lessons = readRows(lessonSheet || ensureSheet('Lessons', LESSON_HEADERS))
    .filter(function(row) { return sameId(row[1], classId); })
    .map(function(row) {
      return {
        lessonId: asText(row[0]), sequenceNumber: Number(row[2]), date: asText(row[3]),
        dailySlot: Number(row[4]), startTime: asText(row[5]), endTime: asText(row[6]),
        isAdjusted: row[7] === true, status: asText(row[8]) || 'scheduled'
      };
    })
    .sort(function(a, b) { return a.sequenceNumber - b.sequenceNumber; });
  return {classOffering: offering, students: students, lessons: lessons};
}
