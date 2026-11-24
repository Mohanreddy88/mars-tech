using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace HrmsApi.Migrations
{
    /// <inheritdoc />
    public partial class StudentSingleParentFlags : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<bool>(
                name: "NoFatherOnRecord",
                table: "Students",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<bool>(
                name: "NoMotherOnRecord",
                table: "Students",
                type: "boolean",
                nullable: false,
                defaultValue: false);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "NoFatherOnRecord",
                table: "Students");

            migrationBuilder.DropColumn(
                name: "NoMotherOnRecord",
                table: "Students");
        }
    }
}
