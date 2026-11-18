using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace HrmsApi.Migrations
{
    /// <inheritdoc />
    public partial class TimesheetCommentsToRemarks : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // Timesheet days: Note = leave code only (AL, ML, …), Remarks = the employee's comment.
            // 1. The old timesheet offered "MC" for medical leave; the company leave type code is "ML".
            migrationBuilder.Sql(@"UPDATE ""AttendancePeriodDays"" SET ""Note"" = 'ML' WHERE upper(trim(""Note"")) = 'MC';");
            // 2. Codes typed in lower case / with spaces -> AL
            migrationBuilder.Sql(@"UPDATE ""AttendancePeriodDays"" d SET ""Note"" = t.""Code"" FROM ""LeaveTypes"" t WHERE upper(trim(d.""Note"")) = t.""Code"" AND d.""Note"" <> t.""Code"";");
            // 3. The comment button used to write into Note: move such text to Remarks.
            migrationBuilder.Sql(@"
UPDATE ""AttendancePeriodDays"" d
SET ""Remarks"" = CASE WHEN coalesce(d.""Remarks"", '') = '' THEN d.""Note"" ELSE d.""Remarks"" || ' ' || d.""Note"" END,
    ""Note"" = NULL
WHERE coalesce(d.""Note"", '') <> ''
  AND NOT EXISTS (SELECT 1 FROM ""LeaveTypes"" t WHERE t.""Code"" = d.""Note"");");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {

        }
    }
}
