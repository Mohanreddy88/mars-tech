using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace HrmsApi.Migrations
{
    /// <inheritdoc />
    public partial class AssistantAiErrorReason : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "Error",
                table: "BotAiUsage",
                type: "character varying(300)",
                maxLength: 300,
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "Error",
                table: "BotAiUsage");
        }
    }
}
