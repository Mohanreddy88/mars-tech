using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace HrmsApi.Migrations
{
    /// <inheritdoc />
    public partial class CompanyAiKey : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "AssistantAiKeyEncrypted",
                table: "CompanySettings",
                type: "character varying(1000)",
                maxLength: 1000,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "AssistantAiKeyHint",
                table: "CompanySettings",
                type: "character varying(20)",
                maxLength: 20,
                nullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "AssistantAiKeySetAt",
                table: "CompanySettings",
                type: "timestamp without time zone",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "AssistantAiKeyEncrypted",
                table: "CompanySettings");

            migrationBuilder.DropColumn(
                name: "AssistantAiKeyHint",
                table: "CompanySettings");

            migrationBuilder.DropColumn(
                name: "AssistantAiKeySetAt",
                table: "CompanySettings");
        }
    }
}
