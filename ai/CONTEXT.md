# Attendance Domain

Vocabulary for the lecturer attendance project. Current requirements, scope, decisions, and implementation status are recorded in [SRS v4.0](../docs/SRS.md). The previous web/Supabase direction is superseded by that specification.

## Language

**Class offering**:
A class taught for a specific subject and semester. A class code alone does not uniquely identify an offering.

**Daily slot**:
One of four teaching time ranges in a day, numbered 1–4.
_Avoid_: Using this term for a lesson's sequence number.

**Schedule code**:
A two-digit markbook worksheet prefix. The first digit selects Monday/Thursday, Tuesday/Friday, or Wednesday/Saturday; the second selects the daily slot.

**Lesson**:
A dated teaching occurrence within an offering, numbered 1–20 in the current scope. The export labels Slot 01–20 refer to these lessons.

**Enrollment**:
A student's membership in a class offering, with the email used to match their authenticated identity.

**Attendance window**:
An explicitly opened period accepting check-ins for one lesson. Reopening the lesson creates a new window while retaining results.
_Avoid_: Using session to mean both lesson and attendance window.

**Attendance result**:
A student's result for a lesson: blank before first opening, then A (absent) or P (present).

**Manual override**:
A lecturer's explicit correction of an attendance result, which a later student check-in must not replace.

**Markbook**:
The imported multi-worksheet XLSX or ODS file supplying rosters and weekly schedule metadata. Grade and examination columns are not attendance results.
