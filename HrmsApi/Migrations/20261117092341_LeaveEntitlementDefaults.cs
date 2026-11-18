using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace HrmsApi.Migrations
{
    /// <inheritdoc />
    public partial class LeaveEntitlementDefaults : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // Company minimum for Annual leave is 12 days (was the seed value 14). Medical stays 14, the
            // Employment Act minimum. Employees' balances are recalculated the next time leave is viewed
            // (LeaveEntitlement: 12/16 by service, Medical 14/18/22, joining year pro-rated).
            migrationBuilder.Sql(@"UPDATE ""LeaveTypes"" SET ""DefaultDaysPerYear"" = 12 WHERE ""Code"" = 'AL' AND ""DefaultDaysPerYear"" = 14;");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {

        }
    }
}
