using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace HrmsApi.Migrations
{
    /// <inheritdoc />
    public partial class AssistantAiAnswers : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<bool>(
                name: "AssistantAiEnabled",
                table: "CompanySettings",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.CreateTable(
                name: "BotAiUsage",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    UserId = table.Column<int>(type: "integer", nullable: false),
                    AskedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    Model = table.Column<string>(type: "character varying(60)", maxLength: 60, nullable: false),
                    InputTokens = table.Column<int>(type: "integer", nullable: false),
                    OutputTokens = table.Column<int>(type: "integer", nullable: false),
                    ToolCalls = table.Column<int>(type: "integer", nullable: false),
                    Succeeded = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_BotAiUsage", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_BotAiUsage_AskedAt",
                table: "BotAiUsage",
                column: "AskedAt");

            migrationBuilder.CreateIndex(
                name: "IX_BotAiUsage_UserId_AskedAt",
                table: "BotAiUsage",
                columns: new[] { "UserId", "AskedAt" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "BotAiUsage");

            migrationBuilder.DropColumn(
                name: "AssistantAiEnabled",
                table: "CompanySettings");
        }
    }
}
