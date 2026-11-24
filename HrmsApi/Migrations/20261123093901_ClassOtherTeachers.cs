using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace HrmsApi.Migrations
{
    /// <inheritdoc />
    public partial class ClassOtherTeachers : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "SchoolClassTeachers",
                columns: table => new
                {
                    ClassId = table.Column<int>(type: "integer", nullable: false),
                    EmployeeId = table.Column<int>(type: "integer", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_SchoolClassTeachers", x => new { x.ClassId, x.EmployeeId });
                    table.ForeignKey(
                        name: "FK_SchoolClassTeachers_Employees_EmployeeId",
                        column: x => x.EmployeeId,
                        principalTable: "Employees",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_SchoolClassTeachers_SchoolClasses_ClassId",
                        column: x => x.ClassId,
                        principalTable: "SchoolClasses",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_SchoolClassTeachers_EmployeeId",
                table: "SchoolClassTeachers",
                column: "EmployeeId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "SchoolClassTeachers");
        }
    }
}
