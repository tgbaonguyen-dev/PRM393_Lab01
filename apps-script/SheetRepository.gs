/**
 * SheetRepository: Direct read/write interactions with Google Sheets tabs
 * Conforms to SRS v4.0 with dynamic slot count support
 */
var SheetRepository = {
  getSpreadsheet: function () {
    return SpreadsheetApp.getActiveSpreadsheet();
  },

  /**
   * Automatically initializes necessary sheets and column headers
   */
  setupDatabase: function () {
    var ss = this.getSpreadsheet();

    var schemas = {
      ClassOfferings: ['Id', 'ClassCode', 'SubjectCode', 'Semester', 'ScheduleCode', 'SlotCount', 'OwnerEmail'],
      Rosters: ['ClassOfferingId', 'RollNumber', 'FullName', 'Email', 'MemberCode'],
      Lessons: ['Id', 'ClassOfferingId', 'SequenceNumber', 'Date', 'DailySlot', 'StartTime', 'EndTime', 'Status'],
      Windows: ['Id', 'LessonId', 'OpenedAt', 'ClosedAt', 'IsOpen'],
      AttendanceResults: ['LessonId', 'StudentEmail', 'Status', 'IsManualOverride', 'CheckedInAt']
    };

    for (var sheetName in schemas) {
      var sheet = ss.getSheetByName(sheetName);
      if (!sheet) {
        sheet = ss.insertSheet(sheetName);
        sheet.appendRow(schemas[sheetName]);
        sheet.getRange(1, 1, 1, schemas[sheetName].length).setFontWeight('bold');
        sheet.setFrozenRows(1);
      }
    }

    return { success: true, message: 'Database sheets initialized successfully.' };
  },

  /**
   * Saves or updates a Class Offering, its Roster, and generated Lessons
   */
  saveClassOffering: function (offering, roster, lessons) {
    var ss = this.getSpreadsheet();
    this.setupDatabase();

    // 1. Save ClassOffering
    var offeringSheet = ss.getSheetByName('ClassOfferings');
    var offeringData = offeringSheet.getDataRange().getValues();
    var existingRow = -1;
    for (var i = 1; i < offeringData.length; i++) {
      if (offeringData[i][0] === offering.id) {
        existingRow = i + 1;
        break;
      }
    }

    var offeringRow = [
      offering.id,
      offering.classCode,
      offering.subjectCode,
      offering.semester,
      offering.scheduleCode,
      offering.slotCount || lessons.length,
      offering.ownerEmail || ''
    ];

    if (existingRow > 0) {
      offeringSheet.getRange(existingRow, 1, 1, offeringRow.length).setValues([offeringRow]);
    } else {
      offeringSheet.appendRow(offeringRow);
    }

    // 2. Save Roster
    var rosterSheet = ss.getSheetByName('Rosters');
    for (var r = 0; r < roster.length; r++) {
      var student = roster[r];
      var normalizedEmail = String(student.email).trim().toLowerCase();
      rosterSheet.appendRow([
        offering.id,
        student.rollNumber,
        student.fullName,
        normalizedEmail,
        student.memberCode || ''
      ]);
    }

    // 3. Save Lessons
    var lessonSheet = ss.getSheetByName('Lessons');
    for (var l = 0; l < lessons.length; l++) {
      var les = lessons[l];
      lessonSheet.appendRow([
        les.id,
        offering.id,
        les.sequenceNumber,
        les.date,
        les.dailySlot,
        les.startTime,
        les.endTime,
        les.status || 'scheduled'
      ]);
    }

    SpreadsheetApp.flush();
    return { success: true, offeringId: offering.id };
  },

  /**
   * Opens attendance window (FR-09, FR-13)
   * On first open: initializes absent 'A' for all enrolled students
   */
  openWindow: function (lessonId) {
    var ss = this.getSpreadsheet();
    this.setupDatabase();

    var windowSheet = ss.getSheetByName('Windows');
    var windowId = 'win_' + Utilities.getUuid();
    var openedAt = new Date().toISOString();

    // Append new window record
    windowSheet.appendRow([windowId, lessonId, openedAt, '', true]);

    // Check if this lesson has existing attendance results
    var resultsSheet = ss.getSheetByName('AttendanceResults');
    var existingResults = this.getResults(lessonId);

    if (existingResults.length === 0) {
      // First open: find class offering and roster to initialize all to 'A'
      var lesson = this.getLesson(lessonId);
      if (lesson) {
        var roster = this.getRoster(lesson.classOfferingId);
        for (var i = 0; i < roster.length; i++) {
          resultsSheet.appendRow([lessonId, roster[i].email.toLowerCase(), 'A', false, '']);
        }
      }
    }

    SpreadsheetApp.flush();
    return {
      id: windowId,
      lessonId: lessonId,
      openedAt: openedAt,
      isOpen: true
    };
  },

  /**
   * Closes active window (FR-12)
   */
  closeWindow: function (windowId) {
    var ss = this.getSpreadsheet();
    var sheet = ss.getSheetByName('Windows');
    if (!sheet) return false;

    var data = sheet.getDataRange().getValues();
    for (var i = 1; i < data.length; i++) {
      if (data[i][0] === windowId) {
        sheet.getRange(i + 1, 4).setValue(new Date().toISOString()); // closedAt
        sheet.getRange(i + 1, 5).setValue(false); // isOpen = false
        SpreadsheetApp.flush();
        return true;
      }
    }
    return false;
  },

  /**
   * Records student check-in (FR-19, FR-20)
   */
  recordCheckIn: function (lessonId, studentEmail) {
    var ss = this.getSpreadsheet();
    var sheet = ss.getSheetByName('AttendanceResults');
    if (!sheet) return false;

    var data = sheet.getDataRange().getValues();
    var normalizedEmail = studentEmail.toLowerCase();

    for (var i = 1; i < data.length; i++) {
      if (data[i][0] === lessonId && String(data[i][1]).toLowerCase() === normalizedEmail) {
        // If already manually overridden by lecturer, DO NOT overwrite (FR-14)
        var isManualOverride = data[i][3];
        if (isManualOverride === true || isManualOverride === 'true') {
          return false;
        }
        sheet.getRange(i + 1, 3).setValue('P');
        sheet.getRange(i + 1, 5).setValue(new Date().toISOString());
        SpreadsheetApp.flush();
        return true;
      }
    }

    // If not found in results, append row
    sheet.appendRow([lessonId, normalizedEmail, 'P', false, new Date().toISOString()]);
    SpreadsheetApp.flush();
    return true;
  },

  /**
   * Records manual override by lecturer (FR-14)
   */
  recordOverride: function (lessonId, studentEmail, status) {
    var ss = this.getSpreadsheet();
    var sheet = ss.getSheetByName('AttendanceResults');
    if (!sheet) return false;

    var data = sheet.getDataRange().getValues();
    var normalizedEmail = studentEmail.toLowerCase();

    for (var i = 1; i < data.length; i++) {
      if (data[i][0] === lessonId && String(data[i][1]).toLowerCase() === normalizedEmail) {
        sheet.getRange(i + 1, 3).setValue(status);
        sheet.getRange(i + 1, 4).setValue(true); // isManualOverride = true
        sheet.getRange(i + 1, 5).setValue(new Date().toISOString());
        SpreadsheetApp.flush();
        return true;
      }
    }

    sheet.appendRow([lessonId, normalizedEmail, status, true, new Date().toISOString()]);
    SpreadsheetApp.flush();
    return true;
  },

  /**
   * Retrieves attendance results for a lesson
   */
  getResults: function (lessonId) {
    var ss = this.getSpreadsheet();
    var sheet = ss.getSheetByName('AttendanceResults');
    if (!sheet) return [];

    var data = sheet.getDataRange().getValues();
    var results = [];
    for (var i = 1; i < data.length; i++) {
      if (data[i][0] === lessonId) {
        results.push({
          lessonId: data[i][0],
          studentEmail: data[i][1],
          status: data[i][2],
          isManualOverride: Boolean(data[i][3]),
          checkedInAt: data[i][4]
        });
      }
    }
    return results;
  },

  /**
   * Retrieves active window for a lesson
   */
  getActiveWindow: function (lessonId) {
    var ss = this.getSpreadsheet();
    var sheet = ss.getSheetByName('Windows');
    if (!sheet) return null;

    var data = sheet.getDataRange().getValues();
    for (var i = data.length - 1; i >= 1; i--) {
      if (data[i][1] === lessonId && (data[i][4] === true || data[i][4] === 'true')) {
        return {
          id: data[i][0],
          lessonId: data[i][1],
          openedAt: data[i][2],
          closedAt: data[i][3],
          isOpen: true
        };
      }
    }
    return null;
  },

  /**
   * Retrieves a lesson by ID
   */
  getLesson: function (lessonId) {
    var ss = this.getSpreadsheet();
    var sheet = ss.getSheetByName('Lessons');
    if (!sheet) return null;

    var data = sheet.getDataRange().getValues();
    for (var i = 1; i < data.length; i++) {
      if (data[i][0] === lessonId) {
        return {
          id: data[i][0],
          classOfferingId: data[i][1],
          sequenceNumber: Number(data[i][2]),
          date: data[i][3],
          dailySlot: Number(data[i][4]),
          startTime: data[i][5],
          endTime: data[i][6],
          status: data[i][7]
        };
      }
    }
    return null;
  },

  /**
   * Retrieves roster for a class offering
   */
  getRoster: function (classOfferingId) {
    var ss = this.getSpreadsheet();
    var sheet = ss.getSheetByName('Rosters');
    if (!sheet) return [];

    var data = sheet.getDataRange().getValues();
    var roster = [];
    for (var i = 1; i < data.length; i++) {
      if (data[i][0] === classOfferingId) {
        roster.push({
          classOfferingId: data[i][0],
          rollNumber: data[i][1],
          fullName: data[i][2],
          email: data[i][3],
          memberCode: data[i][4]
        });
      }
    }
    return roster;
  }
};
