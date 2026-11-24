using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace HrmsApi.Migrations
{
    /// <inheritdoc />
    public partial class FeePriceListsAndDeposits : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "FeePriceLists",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    Name = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                    EffectiveFrom = table.Column<DateTime>(type: "date", nullable: false),
                    TwiceAYearMonths = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    Terms = table.Column<string>(type: "character varying(2000)", maxLength: 2000, nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_FeePriceLists", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "StudentDeposits",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    StudentId = table.Column<int>(type: "integer", nullable: false),
                    Description = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    Amount = table.Column<decimal>(type: "numeric(12,2)", precision: 12, scale: 2, nullable: false),
                    InvoiceId = table.Column<int>(type: "integer", nullable: true),
                    Status = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    SettledAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    SettledByName = table.Column<string>(type: "character varying(150)", maxLength: 150, nullable: true),
                    Note = table.Column<string>(type: "character varying(300)", maxLength: 300, nullable: true),
                    DeductedInvoiceId = table.Column<int>(type: "integer", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_StudentDeposits", x => x.Id);
                    table.ForeignKey(
                        name: "FK_StudentDeposits_Students_StudentId",
                        column: x => x.StudentId,
                        principalTable: "Students",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "FeePriceCharges",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    PriceListId = table.Column<int>(type: "integer", nullable: false),
                    Name = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    Kind = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    Amount = table.Column<decimal>(type: "numeric(12,2)", precision: 12, scale: 2, nullable: false),
                    SessionType = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: true),
                    SortOrder = table.Column<int>(type: "integer", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_FeePriceCharges", x => x.Id);
                    table.ForeignKey(
                        name: "FK_FeePriceCharges_FeePriceLists_PriceListId",
                        column: x => x.PriceListId,
                        principalTable: "FeePriceLists",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "FeePriceSessions",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    PriceListId = table.Column<int>(type: "integer", nullable: false),
                    SessionType = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    Offered = table.Column<bool>(type: "boolean", nullable: false),
                    Start = table.Column<string>(type: "character varying(5)", maxLength: 5, nullable: false),
                    End = table.Column<string>(type: "character varying(5)", maxLength: 5, nullable: false),
                    MealsIncluded = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    MonthlyFee = table.Column<decimal>(type: "numeric(12,2)", precision: 12, scale: 2, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_FeePriceSessions", x => x.Id);
                    table.ForeignKey(
                        name: "FK_FeePriceSessions_FeePriceLists_PriceListId",
                        column: x => x.PriceListId,
                        principalTable: "FeePriceLists",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_FeePriceCharges_PriceListId",
                table: "FeePriceCharges",
                column: "PriceListId");

            migrationBuilder.CreateIndex(
                name: "IX_FeePriceLists_EffectiveFrom",
                table: "FeePriceLists",
                column: "EffectiveFrom",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_FeePriceSessions_PriceListId_SessionType",
                table: "FeePriceSessions",
                columns: new[] { "PriceListId", "SessionType" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_StudentDeposits_StudentId_Status",
                table: "StudentDeposits",
                columns: new[] { "StudentId", "Status" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "FeePriceCharges");

            migrationBuilder.DropTable(
                name: "FeePriceSessions");

            migrationBuilder.DropTable(
                name: "StudentDeposits");

            migrationBuilder.DropTable(
                name: "FeePriceLists");
        }
    }
}
