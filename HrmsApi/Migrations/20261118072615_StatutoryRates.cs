using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace HrmsApi.Migrations
{
    /// <inheritdoc />
    public partial class StatutoryRates : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<decimal>(
                name: "EisAmount",
                table: "Payrolls",
                type: "numeric(18,2)",
                precision: 18,
                scale: 2,
                nullable: false,
                defaultValue: 0m);

            migrationBuilder.AddColumn<decimal>(
                name: "EisEmployerAmount",
                table: "Payrolls",
                type: "numeric(18,2)",
                precision: 18,
                scale: 2,
                nullable: false,
                defaultValue: 0m);

            migrationBuilder.AddColumn<decimal>(
                name: "EpfEmployeeRate",
                table: "Payrolls",
                type: "numeric(6,3)",
                precision: 6,
                scale: 3,
                nullable: true);

            migrationBuilder.AddColumn<decimal>(
                name: "EpfEmployerAmount",
                table: "Payrolls",
                type: "numeric(18,2)",
                precision: 18,
                scale: 2,
                nullable: false,
                defaultValue: 0m);

            migrationBuilder.AddColumn<decimal>(
                name: "EpfEmployerRate",
                table: "Payrolls",
                type: "numeric(6,3)",
                precision: 6,
                scale: 3,
                nullable: true);

            migrationBuilder.AddColumn<decimal>(
                name: "SocsoEmployerAmount",
                table: "Payrolls",
                type: "numeric(18,2)",
                precision: 18,
                scale: 2,
                nullable: false,
                defaultValue: 0m);

            migrationBuilder.AddColumn<int>(
                name: "StatutoryRateSetId",
                table: "Payrolls",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "StatutoryRateSetName",
                table: "Payrolls",
                type: "character varying(100)",
                maxLength: 100,
                nullable: true);

            migrationBuilder.AddColumn<decimal>(
                name: "EpfEmployeeRateOverride",
                table: "Employees",
                type: "numeric(6,3)",
                precision: 6,
                scale: 3,
                nullable: true);

            migrationBuilder.AddColumn<decimal>(
                name: "EpfEmployerRateOverride",
                table: "Employees",
                type: "numeric(6,3)",
                precision: 6,
                scale: 3,
                nullable: true);

            migrationBuilder.CreateTable(
                name: "StatutoryRateSets",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    Name = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    EffectiveFrom = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    Notes = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    EpfEmployeeRate = table.Column<decimal>(type: "numeric(6,3)", precision: 6, scale: 3, nullable: false),
                    EpfEmployerRate = table.Column<decimal>(type: "numeric(6,3)", precision: 6, scale: 3, nullable: false),
                    EpfEmployerRateAboveThreshold = table.Column<decimal>(type: "numeric(6,3)", precision: 6, scale: 3, nullable: false),
                    EpfEmployerThreshold = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    SocsoBandsJson = table.Column<string>(type: "text", nullable: false),
                    EisEmployeeRate = table.Column<decimal>(type: "numeric(6,3)", precision: 6, scale: 3, nullable: false),
                    EisEmployerRate = table.Column<decimal>(type: "numeric(6,3)", precision: 6, scale: 3, nullable: false),
                    EisWageCeiling = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    TaxPersonalRelief = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    TaxBandsJson = table.Column<string>(type: "text", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_StatutoryRateSets", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_StatutoryRateSets_EffectiveFrom",
                table: "StatutoryRateSets",
                column: "EffectiveFrom",
                unique: true);

            // Starting rate set for every company database: exactly the rates that were hard-coded
            // before (EPF 2% / employer 13%, the previous SOCSO table, PCB bands, RM9,000 relief),
            // so payroll results do not change on deploy. EIS starts at 0% (it was not deducted).
            // HR reviews these and adds new sets under Master → Statutory Rates.
            // Values are frozen here on purpose (not read from code) — see StatutoryRateDefaults.
            migrationBuilder.Sql($@"
INSERT INTO ""StatutoryRateSets""
    (""Name"", ""EffectiveFrom"", ""Notes"",
     ""EpfEmployeeRate"", ""EpfEmployerRate"", ""EpfEmployerRateAboveThreshold"", ""EpfEmployerThreshold"",
     ""SocsoBandsJson"", ""EisEmployeeRate"", ""EisEmployerRate"", ""EisWageCeiling"",
     ""TaxPersonalRelief"", ""TaxBandsJson"", ""CreatedAt"")
SELECT 'Initial rates', TIMESTAMP '2000-01-01 00:00:00',
       'Rates the system used before Statutory Rates could be edited. Review and add a new rate set for current official rates.',
       2, 13, 13, 5000,
       '{SocsoBandsJson}', 0, 0, 6000,
       9000, '{TaxBandsJson}', NOW() AT TIME ZONE 'UTC'
WHERE NOT EXISTS (SELECT 1 FROM ""StatutoryRateSets"");");
        }

        private const string SocsoBandsJson =
            "[{\"upTo\":30,\"employee\":0.1,\"employer\":0.53},{\"upTo\":50,\"employee\":0.2,\"employer\":0.88},{\"upTo\":70,\"employee\":0.25,\"employer\":1.23},{\"upTo\":100,\"employee\":0.35,\"employer\":1.75},{\"upTo\":150,\"employee\":0.5,\"employer\":2.63},{\"upTo\":200,\"employee\":0.65,\"employer\":3.5},{\"upTo\":300,\"employee\":1,\"employer\":5.25},{\"upTo\":400,\"employee\":1.35,\"employer\":7},{\"upTo\":500,\"employee\":1.7,\"employer\":8.75},{\"upTo\":600,\"employee\":2.05,\"employer\":10.5},{\"upTo\":700,\"employee\":2.4,\"employer\":12.25},{\"upTo\":800,\"employee\":2.75,\"employer\":14},{\"upTo\":900,\"employee\":3.1,\"employer\":15.75},{\"upTo\":1000,\"employee\":3.45,\"employer\":17.5},{\"upTo\":1100,\"employee\":3.8,\"employer\":19.25},{\"upTo\":1200,\"employee\":4.15,\"employer\":21},{\"upTo\":1300,\"employee\":4.5,\"employer\":22.75},{\"upTo\":1400,\"employee\":4.85,\"employer\":24.5},{\"upTo\":1500,\"employee\":5.2,\"employer\":26.25},{\"upTo\":1600,\"employee\":5.55,\"employer\":28},{\"upTo\":1700,\"employee\":5.9,\"employer\":29.75},{\"upTo\":1800,\"employee\":6.25,\"employer\":31.5},{\"upTo\":1900,\"employee\":6.6,\"employer\":33.25},{\"upTo\":2000,\"employee\":6.95,\"employer\":35},{\"upTo\":2100,\"employee\":7.3,\"employer\":36.75},{\"upTo\":2200,\"employee\":7.65,\"employer\":38.5},{\"upTo\":2300,\"employee\":8,\"employer\":40.25},{\"upTo\":2400,\"employee\":8.35,\"employer\":42},{\"upTo\":2500,\"employee\":8.7,\"employer\":43.75},{\"upTo\":2600,\"employee\":9.05,\"employer\":45.5},{\"upTo\":2700,\"employee\":9.4,\"employer\":47.25},{\"upTo\":2800,\"employee\":9.75,\"employer\":49},{\"upTo\":2900,\"employee\":10.1,\"employer\":50.75},{\"upTo\":3000,\"employee\":10.45,\"employer\":52.5},{\"upTo\":3100,\"employee\":10.8,\"employer\":54.25},{\"upTo\":3200,\"employee\":11.15,\"employer\":56},{\"upTo\":3300,\"employee\":11.5,\"employer\":57.75},{\"upTo\":3400,\"employee\":11.85,\"employer\":59.5},{\"upTo\":3500,\"employee\":12.2,\"employer\":61.25},{\"upTo\":3600,\"employee\":12.55,\"employer\":63},{\"upTo\":3700,\"employee\":12.9,\"employer\":64.75},{\"upTo\":3800,\"employee\":13.25,\"employer\":66.5},{\"upTo\":3900,\"employee\":13.6,\"employer\":68.25},{\"upTo\":4000,\"employee\":13.95,\"employer\":70},{\"upTo\":4500,\"employee\":14.75,\"employer\":78.75},{\"upTo\":5000,\"employee\":16.6,\"employer\":87.5},{\"upTo\":null,\"employee\":19.75,\"employer\":87.5}]";

        private const string TaxBandsJson =
            "[{\"upTo\":5000,\"rate\":0},{\"upTo\":20000,\"rate\":1},{\"upTo\":35000,\"rate\":3},{\"upTo\":50000,\"rate\":8},{\"upTo\":70000,\"rate\":13},{\"upTo\":100000,\"rate\":21},{\"upTo\":400000,\"rate\":24},{\"upTo\":600000,\"rate\":24.5},{\"upTo\":2000000,\"rate\":25},{\"upTo\":null,\"rate\":26}]";

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "StatutoryRateSets");

            migrationBuilder.DropColumn(
                name: "EisAmount",
                table: "Payrolls");

            migrationBuilder.DropColumn(
                name: "EisEmployerAmount",
                table: "Payrolls");

            migrationBuilder.DropColumn(
                name: "EpfEmployeeRate",
                table: "Payrolls");

            migrationBuilder.DropColumn(
                name: "EpfEmployerAmount",
                table: "Payrolls");

            migrationBuilder.DropColumn(
                name: "EpfEmployerRate",
                table: "Payrolls");

            migrationBuilder.DropColumn(
                name: "SocsoEmployerAmount",
                table: "Payrolls");

            migrationBuilder.DropColumn(
                name: "StatutoryRateSetId",
                table: "Payrolls");

            migrationBuilder.DropColumn(
                name: "StatutoryRateSetName",
                table: "Payrolls");

            migrationBuilder.DropColumn(
                name: "EpfEmployeeRateOverride",
                table: "Employees");

            migrationBuilder.DropColumn(
                name: "EpfEmployerRateOverride",
                table: "Employees");
        }
    }
}
