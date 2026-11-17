using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace HrmsApi.Migrations
{
    /// <inheritdoc />
    public partial class AddEmployeeIdentity : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "IdCountry",
                table: "Employees",
                type: "text",
                nullable: false,
                defaultValue: "Malaysia");

            migrationBuilder.AddColumn<string>(
                name: "IdType",
                table: "Employees",
                type: "text",
                nullable: false,
                defaultValue: "NRIC");

            migrationBuilder.AddColumn<string>(
                name: "PhoneCountryCode",
                table: "Employees",
                type: "text",
                nullable: false,
                defaultValue: "+60");

            // Existing employees (hand-written; keeps their data in the new format):
            // 1. An IC that is 12 digits once dashes/spaces are removed → NRIC, stored as 12 digits.
            migrationBuilder.Sql(@"
UPDATE ""Employees"" SET ""IcPassport"" = regexp_replace(""IcPassport"", '[\s-]', '', 'g')
WHERE regexp_replace(""IcPassport"", '[\s-]', '', 'g') ~ '^\d{12}$';");

            // 2. Anything else that is filled in → Passport; country unknown, so HR picks it at the next edit.
            migrationBuilder.Sql(@"
UPDATE ""Employees"" SET ""IdType"" = 'Passport', ""IdCountry"" = ''
WHERE ""IcPassport"" <> '' AND ""IcPassport"" !~ '^\d{12}$';");

            // 3. Phone saved as ""+60123456789"" → code +60 and number 123456789.
            migrationBuilder.Sql(@"
UPDATE ""Employees"" SET ""Phone"" = substr(regexp_replace(""Phone"", '[\s()-]', '', 'g'), 4)
WHERE regexp_replace(""Phone"", '[\s()-]', '', 'g') ~ '^\+60\d{7,12}$';");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "IdCountry",
                table: "Employees");

            migrationBuilder.DropColumn(
                name: "IdType",
                table: "Employees");

            migrationBuilder.DropColumn(
                name: "PhoneCountryCode",
                table: "Employees");
        }
    }
}
