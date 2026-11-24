using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace HrmsApi.Migrations
{
    /// <inheritdoc />
    public partial class ParentBanners : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "SchoolBanners",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    Title = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: false),
                    Text = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    ButtonText = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: true),
                    Link = table.Column<string>(type: "character varying(300)", maxLength: 300, nullable: true),
                    Theme = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    ClassId = table.Column<int>(type: "integer", nullable: true),
                    StartsOn = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    EndsOn = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    IsActive = table.Column<bool>(type: "boolean", nullable: false),
                    SortOrder = table.Column<int>(type: "integer", nullable: false),
                    ImageContentType = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    ImageData = table.Column<byte[]>(type: "bytea", nullable: true),
                    ImageVersion = table.Column<int>(type: "integer", nullable: false),
                    CreatedByName = table.Column<string>(type: "character varying(150)", maxLength: 150, nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_SchoolBanners", x => x.Id);
                    table.ForeignKey(
                        name: "FK_SchoolBanners_SchoolClasses_ClassId",
                        column: x => x.ClassId,
                        principalTable: "SchoolClasses",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_SchoolBanners_ClassId",
                table: "SchoolBanners",
                column: "ClassId");

            migrationBuilder.CreateIndex(
                name: "IX_SchoolBanners_IsActive_SortOrder",
                table: "SchoolBanners",
                columns: new[] { "IsActive", "SortOrder" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "SchoolBanners");
        }
    }
}
