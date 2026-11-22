using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace HrmsApi.Migrations
{
    /// <inheritdoc />
    public partial class ConversationSubjectsAndChatbot : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_Conversations_StudentId_Kind",
                table: "Conversations");

            migrationBuilder.AddColumn<DateTime>(
                name: "ClosedAt",
                table: "Conversations",
                type: "timestamp without time zone",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "ClosedByName",
                table: "Conversations",
                type: "character varying(150)",
                maxLength: 150,
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "CreatedByUserId",
                table: "Conversations",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "Status",
                table: "Conversations",
                type: "character varying(10)",
                maxLength: 10,
                nullable: false,
                defaultValue: "Open");

            migrationBuilder.AddColumn<string>(
                name: "Subject",
                table: "Conversations",
                type: "character varying(150)",
                maxLength: 150,
                nullable: false,
                defaultValue: "General");

            migrationBuilder.CreateTable(
                name: "BotFaqs",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    Category = table.Column<string>(type: "character varying(60)", maxLength: 60, nullable: false),
                    Question = table.Column<string>(type: "character varying(300)", maxLength: 300, nullable: false),
                    Answer = table.Column<string>(type: "character varying(4000)", maxLength: 4000, nullable: false),
                    Keywords = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    Audience = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    Action = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: true),
                    SortOrder = table.Column<int>(type: "integer", nullable: false),
                    IsActive = table.Column<bool>(type: "boolean", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_BotFaqs", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "BotUnanswered",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    Text = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: false),
                    Audience = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    UserId = table.Column<int>(type: "integer", nullable: false),
                    AskedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_BotUnanswered", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_Conversations_LastMessageAt",
                table: "Conversations",
                column: "LastMessageAt");

            migrationBuilder.CreateIndex(
                name: "IX_Conversations_StudentId_Kind",
                table: "Conversations",
                columns: new[] { "StudentId", "Kind" });

            migrationBuilder.CreateIndex(
                name: "IX_BotUnanswered_AskedAt",
                table: "BotUnanswered",
                column: "AskedAt");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "BotFaqs");

            migrationBuilder.DropTable(
                name: "BotUnanswered");

            migrationBuilder.DropIndex(
                name: "IX_Conversations_LastMessageAt",
                table: "Conversations");

            migrationBuilder.DropIndex(
                name: "IX_Conversations_StudentId_Kind",
                table: "Conversations");

            migrationBuilder.DropColumn(
                name: "ClosedAt",
                table: "Conversations");

            migrationBuilder.DropColumn(
                name: "ClosedByName",
                table: "Conversations");

            migrationBuilder.DropColumn(
                name: "CreatedByUserId",
                table: "Conversations");

            migrationBuilder.DropColumn(
                name: "Status",
                table: "Conversations");

            migrationBuilder.DropColumn(
                name: "Subject",
                table: "Conversations");

            migrationBuilder.CreateIndex(
                name: "IX_Conversations_StudentId_Kind",
                table: "Conversations",
                columns: new[] { "StudentId", "Kind" },
                unique: true);
        }
    }
}
