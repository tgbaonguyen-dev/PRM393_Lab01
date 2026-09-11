/**
 * Google Apps Script SheetRepository for PRM393
 * Quản lý trực tiếp cấu trúc Google Sheet chuẩn Giảng viên:
 * - 1 Sheet 'Overview': Tổng quan các lớp học trong học kỳ, môn học, ca dạy, ngày bắt đầu - kết thúc, sĩ số.
 * - Các Sheet riêng cho từng lớp (ví dụ: '12_PRM393_SE1920'): Chứa danh sách sinh viên thực tế và 20 cột Slot học.
 * - Công thức FAP tự động: Nghỉ <= 20% tổng slot là Đủ điều kiện, quá 20% là Cấm thi.
 * - Cập nhật trực tiếp P/A vào ô của từng sinh viên theo thời gian thực.
 */

var SheetRepository = {
  // Điền ID của Google Sheet nếu muốn cố định, hoặc để trống để tự động nhận diện
  SPREADSHEET_ID: '',

  /**
   * Lấy hoặc tạo bảng tính Google Sheet
   */
  getSpreadsheet: function () {
    var ss = SpreadsheetApp.getActiveSpreadsheet();
    if (ss) return ss;

    if (this.SPREADSHEET_ID && this.SPREADSHEET_ID.trim() !== '') {
      return SpreadsheetApp.openById(this.SPREADSHEET_ID.trim());
    }

    var props = PropertiesService.getScriptProperties();
    var savedId = props.getProperty('SPREADSHEET_ID');
    if (savedId) {
      try {
        return SpreadsheetApp.openById(savedId);
      } catch (e) {}
    }

    var newSs = SpreadsheetApp.create('PRM393 Sổ Điểm Danh Học Kỳ');
    props.setProperty('SPREADSHEET_ID', newSs.getId());
    return newSs;
  },

  /**
   * Xóa sạch toàn bộ các sheet cũ hiện có để làm mới hoàn toàn
   */
  clearAllDatabase: function () {
    var ss = this.getSpreadsheet();
    var tempSheet = ss.insertSheet('Temp_' + new Date().getTime());
    var sheets = ss.getSheets();
    for (var i = 0; i < sheets.length; i++) {
      if (sheets[i].getName() !== tempSheet.getName()) {
        try {
          ss.deleteSheet(sheets[i]);
        } catch (e) {}
      }
    }
    return tempSheet;
  },

  /**
   * Đồng bộ toàn bộ các lớp học từ Desktop App lên Google Sheet
   * Nhận mảng classes và ngày bắt đầu do Giảng viên chọn trên Desktop
   */
  syncAllClassesFromDesktop: function (classes, startDateStr) {
    var ss = this.getSpreadsheet();
    var tempSheet = this.clearAllDatabase();

    // 1. Tạo Sheet OVERVIEW
    var overviewSheet = ss.insertSheet('Overview', 0);
    this.setupOverviewSheet(overviewSheet, classes, startDateStr);

    // 2. Tạo Sheet cho TỪNG LỚP HỌC
    for (var i = 0; i < classes.length; i++) {
      try {
        var cls = classes[i];
        var cName = cls.className || ('Lop_' + (i + 1));
        var sheetName = (cls.scheduleCode || '12') + '_' + (cls.subjectCode || 'PRM393') + '_' + cName;
        var existing = ss.getSheetByName(sheetName);
        if (existing) {
          try { ss.deleteSheet(existing); } catch (e) {}
        }
        var classSheet = ss.insertSheet(sheetName);
        this.setupClassMarkbookSheet(classSheet, cls, startDateStr);
      } catch (classErr) {
        Logger.log('Lỗi tạo sheet lớp ' + i + ': ' + classErr);
      }
    }

    // 3. Xoá sheet tạm
    try {
      if (tempSheet && ss.getSheets().length > 1) {
        ss.deleteSheet(tempSheet);
      }
    } catch (e) {}

    // Lưu danh sách lớp vào Script Properties để phục vụ tra cứu điểm danh nhanh
    var props = PropertiesService.getScriptProperties();
    props.setProperty('CLASSES_CACHE', JSON.stringify(classes));

    SpreadsheetApp.flush();
    return {
      success: true,
      classCount: classes.length,
      spreadsheetUrl: ss.getUrl()
    };
  },

  /**
   * Thiết lập Sheet Overview
   */
  setupOverviewSheet: function (sheet, classes, startDateStr) {
    sheet.clear();

    // Banner tiêu đề
    sheet.getRange('A1:I1').merge();
    var titleCell = sheet.getRange('A1');
    titleCell.setValue('📊 TỔNG QUAN LỊCH GIẢNG DẠY HỌC KỲ (Bắt đầu từ: ' + (startDateStr || 'Theo lịch') + ')');
    titleCell.setBackground('#1E3A8A');
    titleCell.setFontColor('#FFFFFF');
    titleCell.setFontWeight('bold');
    titleCell.setFontSize(14);
    titleCell.setHorizontalAlignment('center');
    titleCell.setVerticalAlignment('middle');
    sheet.setRowHeight(1, 45);

    // Dòng Header
    var headers = ['STT', 'Mã Môn', 'Lớp Học', 'Mã Lịch', 'Thứ & Ca Dạy', 'Khung Giờ', 'Ngày Bắt Đầu', 'Ngày Kết Thúc', 'Sĩ Số SV'];
    sheet.getRange(2, 1, 1, headers.length).setValues([headers]);
    var headerRange = sheet.getRange(2, 1, 1, headers.length);
    headerRange.setBackground('#F1F5F9');
    headerRange.setFontColor('#1E293B');
    headerRange.setFontWeight('bold');
    headerRange.setHorizontalAlignment('center');
    headerRange.setVerticalAlignment('middle');
    sheet.setRowHeight(2, 35);

    var rows = [];
    for (var i = 0; i < classes.length; i++) {
      var c = classes[i];
      var scheduleInfo = this.getScheduleDescription(c.scheduleCode);
      var lessons = c.lessons || [];
      var firstDate = lessons.length > 0 ? lessons[0].date : (startDateStr || '');
      var lastDate = lessons.length > 0 ? lessons[lessons.length - 1].date : '';
      var timeRange = lessons.length > 0 ? (lessons[0].startTime + ' - ' + lessons[0].endTime) : '09:50 - 12:10';

      rows.push([
        i + 1,
        c.subjectCode || 'PRM393',
        c.className,
        c.scheduleCode,
        scheduleInfo,
        timeRange,
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
      dataRange.setBorder(true, true, true, true, true, true, '#CBD5E1', SpreadsheetApp.BorderStyle.SOLID);
    }

    sheet.setFrozenRows(2);
    var colWidths = [45, 90, 110, 80, 160, 125, 110, 110, 80];
    for (var c = 0; c < colWidths.length; c++) {
      sheet.setColumnWidth(c + 1, colWidths[c]);
    }
  },

  /**
   * Thiết lập Sheet Markbook cho 1 Lớp cụ thể
   */
  setupClassMarkbookSheet: function (sheet, cls, startDateStr) {
    sheet.clear();
    var lessons = cls.lessons || [];
    var slotCount = lessons.length > 0 ? lessons.length : (cls.slotCount || 20);
    var scheduleInfo = this.getScheduleDescription(cls.scheduleCode);

    // Dòng 1: Banner lớp học
    var totalCols = 5 + slotCount + 3; // 5 cột info + N slot + 3 cột thống kê
    sheet.getRange(1, 1, 1, totalCols).merge();
    var bannerCell = sheet.getRange(1, 1);
    bannerCell.setValue('📚 Môn: ' + (cls.subjectCode || 'PRM393') + '  |  Lớp: ' + cls.className + '  |  Lịch: ' + cls.scheduleCode + ' (' + scheduleInfo + ')  |  Sĩ số: ' + (cls.roster ? cls.roster.length : 0) + ' SV');
    bannerCell.setBackground('#1E3A8A'); // Navy Blue
    bannerCell.setFontColor('#FFFFFF');
    bannerCell.setFontWeight('bold');
    bannerCell.setFontSize(12);
    bannerCell.setHorizontalAlignment('left');
    bannerCell.setVerticalAlignment('middle');
    sheet.setRowHeight(1, 38);

    // Dòng 2: Tiêu đề cột
    var headers = ['STT', 'MSSV', 'Họ và tên', 'Email FPT', 'Mã FAP'];
    for (var s = 1; s <= slotCount; s++) {
      var les = lessons[s - 1];
      var slotTitle = 'Slot ' + (s < 10 ? '0' + s : s);
      if (les && les.date) {
        slotTitle += '\n(' + String(les.date).substring(5) + ')'; // Ví dụ: Slot 01\n(09-07)
      }
      headers.push(slotTitle);
    }
    headers.push('Tổng vắng (A)');
    headers.push('Tỉ lệ vắng (%)');
    headers.push('Kết quả FAP');

    sheet.getRange(2, 1, 1, headers.length).setValues([headers]);
    var headerRange = sheet.getRange(2, 1, 1, headers.length);
    headerRange.setBackground('#2563EB'); // Royal Blue
    headerRange.setFontColor('#FFFFFF');
    headerRange.setFontWeight('bold');
    headerRange.setHorizontalAlignment('center');
    headerRange.setVerticalAlignment('middle');
    headerRange.setWrap(true);
    sheet.setRowHeight(2, 42);

    // Dòng 3..N: Dữ liệu Sinh viên
    var roster = cls.roster || [];
    var rows = [];

    for (var r = 0; r < roster.length; r++) {
      var st = roster[r];
      var rowNum = r + 3; // Bắt đầu từ dòng 3
      var email = String(st.email).trim().toLowerCase();
      var row = [
        r + 1,
        st.rollNumber,
        st.fullName,
        email,
        st.memberCode || ''
      ];

      // Điền thông tin điểm danh đã có trước đó (đồng bộ từ Desktop App)
      var studentAttendance = st.attendance || {};
      for (var s = 1; s <= slotCount; s++) {
        var status = studentAttendance[s] || studentAttendance[String(s)] || '';
        row.push(status);
      }

      // Các cột thống kê FAP:
      // Cột slot bắt đầu từ F (cột 6) đến cột (5 + slotCount)
      var startColLetter = 'F';
      var endColLetter = this.getColumnLetter(5 + slotCount);
      var absentColLetter = this.getColumnLetter(5 + slotCount + 1);
      var pctColLetter = this.getColumnLetter(5 + slotCount + 2);

      // Công thức tính Tổng Vắng (số buổi 'A')
      var absentFormula = '=COUNTIF(' + startColLetter + rowNum + ':' + endColLetter + rowNum + ', "A")';

      // Công thức tính Tỉ lệ Vắng (%)
      var pctFormula = '=IF(' + slotCount + '>0, ' + absentColLetter + rowNum + '/' + slotCount + ', 0)';

      // Công thức Kết Quả: Nghỉ <= 20% là Đủ điều kiện, quá 20% là CẤM THI
      var resultFormula = '=IF(' + pctColLetter + rowNum + '>0.20, "🚫 CẤM THI", IF(' + pctColLetter + rowNum + '>=0.15, "⚠️ NGUY CƠ", "✅ ĐỦ ĐIỀU KIỆN"))';

      row.push(absentFormula);
      row.push(pctFormula);
      row.push(resultFormula);

      rows.push(row);
    }

    if (rows.length > 0) {
      var dataRange = sheet.getRange(3, 1, rows.length, headers.length);
      dataRange.setValues(rows);
      dataRange.setVerticalAlignment('middle');
      dataRange.setBorder(true, true, true, true, true, true, '#CBD5E1', SpreadsheetApp.BorderStyle.SOLID);

      // Căn giữa STT, MSSV, Mã FAP, và các cột Slot
      sheet.getRange(3, 1, rows.length, 2).setHorizontalAlignment('center'); // STT & MSSV
      sheet.getRange(3, 5, rows.length, slotCount + 3).setHorizontalAlignment('center'); // Mã FAP, Slot, Thống kê
      sheet.getRange(3, 6, rows.length, slotCount + 3).setFontWeight('bold');

      // Định dạng % cho cột Tỉ lệ vắng
      var pctColIndex = 5 + slotCount + 2;
      sheet.getRange(3, pctColIndex, rows.length, 1).setNumberFormat('0.0%');

      // Conditional Formatting: P = Xanh lá, A = Đỏ
      var slotRange = sheet.getRange(3, 6, rows.length, slotCount);
      var ruleP = SpreadsheetApp.newConditionalFormatRule()
        .whenTextEqualTo('P')
        .setBackground('#DCFCE7')
        .setFontColor('#15803D')
        .setRanges([slotRange])
        .build();

      var ruleA = SpreadsheetApp.newConditionalFormatRule()
        .whenTextEqualTo('A')
        .setBackground('#FEE2E2')
        .setFontColor('#B91C1C')
        .setRanges([slotRange])
        .build();

      sheet.setConditionalFormatRules([ruleP, ruleA]);
    }

    // Cố định dòng 2 (Header) và cố định 3 cột đầu (STT, MSSV, Tên)
    sheet.setFrozenRows(2);
    sheet.setFrozenColumns(3);

    // Căn chỉnh độ rộng cực nhanh bằng setColumnWidths (giảm từ 28 calls xuống 7 calls)
    sheet.setColumnWidth(1, 45);  // STT
    sheet.setColumnWidth(2, 95);  // MSSV
    sheet.setColumnWidth(3, 180); // Họ và tên
    sheet.setColumnWidth(4, 220); // Email
    sheet.setColumnWidth(5, 85);  // MemberCode
    sheet.setColumnWidths(6, slotCount, 68); // Tất cả các cột Slot trong 1 lệnh duy nhất!
    sheet.setColumnWidth(5 + slotCount + 1, 105);
    sheet.setColumnWidth(5 + slotCount + 2, 105);
    sheet.setColumnWidth(5 + slotCount + 3, 130);
  },

  /**
   * Ghi nhận điểm danh sinh viên (P - Có mặt)
   * Cập nhật trực tiếp vào ô của sinh viên đó trong sheet của lớp
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
   * Cập nhật giá trị ô Slot của sinh viên trong sheet lớp
   */
  /**
   * Cập nhật giá trị ô Slot của sinh viên trong đúng sheet lớp tương ứng
   * Tuyệt đối không tạo lại sheet, chỉ cập nhật 1 ô duy nhất!
   */
  setAttendanceStatus: function (lessonId, studentEmail, status) {
    var ss = this.getSpreadsheet();
    var parts = this.parseLessonId(lessonId);
    if (!parts) return false;

    var targetSheet = this.findClassSheet(ss, parts);
    if (!targetSheet) return false;

    var data = targetSheet.getDataRange().getValues();
    if (data.length <= 2) return false;

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

    if (targetRow === -1) return false;

    // Cột slot tương ứng: Slot 1 là cột F (cột 6), Slot N là (5 + sequenceNumber)
    var targetCol = 5 + parts.sequenceNumber;
    targetSheet.getRange(targetRow, targetCol).setValue(status);
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
   * Lấy kết quả điểm danh của 1 buổi học để phục vụ polling
   */
  getResults: function (lessonId) {
    var ss = this.getSpreadsheet();
    var parts = this.parseLessonId(lessonId);
    if (!parts) return [];

    var targetSheet = this.findClassSheet(ss, parts);
    if (!targetSheet) return [];

    var data = targetSheet.getDataRange().getValues();
    if (data.length <= 2) return [];

    var colIndex = 5 + parts.sequenceNumber - 1; // 0-indexed
    var results = [];

    for (var r = 2; r < data.length; r++) {
      var email = String(data[r][3]).trim().toLowerCase();
      var val = String(data[r][colIndex] || '').trim();
      if (email && val) {
        results.push({
          studentEmail: email,
          status: val,
          isManualOverride: false
        });
      }
    }

    return results;
  },

  /**
   * Quản lý ca điểm danh mở (Lưu trong ScriptProperties để không làm rác bảng tính)
   */
  openWindow: function (lessonId) {
    var props = PropertiesService.getScriptProperties();
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

  closeWindow: function (windowId) {
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

  /**
   * Tìm sheet của lớp bằng cách khớp cả className và subjectCode
   */
  findClassSheet: function (ss, parts) {
    var sheets = ss.getSheets();
    for (var i = 0; i < sheets.length; i++) {
      var sName = sheets[i].getName();
      if (sName === 'Overview' || sName.indexOf('Temp_') === 0) continue;
      var matchClass = sName.toLowerCase().indexOf(parts.className.toLowerCase()) !== -1;
      var matchSubject = !parts.subjectCode || sName.toLowerCase().indexOf(parts.subjectCode.toLowerCase()) !== -1;
      if (matchClass && matchSubject) {
        return sheets[i];
      }
    }
    return null;
  },

  /**
   * Phân tích lessonId dạng 'PRM393_SE1920_Lesson_1' thành subjectCode, className và sequenceNumber
   */
  parseLessonId: function (lessonId) {
    if (!lessonId) return null;
    var match = lessonId.match(/^([A-Za-z0-9]+)_([A-Za-z0-9]+)_Lesson_(\d+)/i);
    if (match) {
      return {
        subjectCode: match[1],
        className: match[2],
        sequenceNumber: parseInt(match[3], 10)
      };
    }
    var fallback = lessonId.match(/_([A-Za-z0-9]+)_Lesson_(\d+)/i);
    if (fallback) {
      return {
        subjectCode: '',
        className: fallback[1],
        sequenceNumber: parseInt(fallback[2], 10)
      };
    }
    return null;
  },

  /**
   * Mô tả mã lịch học FAP
   */
  getScheduleDescription: function (code) {
    var map = {
      '12': 'Thứ 2 & Thứ 5, Ca 2 (09:50 - 12:10)',
      '14': 'Thứ 2 & Thứ 5, Ca 4 (15:20 - 17:40)',
      '21': 'Thứ 3 & Thứ 6, Ca 1 (07:30 - 09:50)',
      '22': 'Thứ 3 & Thứ 6, Ca 2 (09:50 - 12:10)',
      '23': 'Thứ 3 & Thứ 6, Ca 3 (12:50 - 15:10)',
      '24': 'Thứ 3 & Thứ 6, Ca 4 (15:20 - 17:40)',
      '31': 'Thứ 4 & Thứ 7, Ca 1 (07:30 - 09:50)',
      '32': 'Thứ 4 & Thứ 7, Ca 2 (09:50 - 12:10)'
    };
    return map[String(code)] || ('Mã lịch ' + code);
  },

  /**
   * Chuyển chỉ số cột thành chữ cái (1 -> A, 6 -> F, 27 -> AA)
   */
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
