using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace HrmsApi.Migrations
{
    /// <inheritdoc />
    public partial class SchoolTimesAndAutoAttendance : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<bool>(
                name: "AutoAbsent",
                table: "StudentAttendance",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<bool>(
                name: "AutoCheckOut",
                table: "StudentAttendance",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<bool>(
                name: "IsLate",
                table: "StudentAttendance",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<string>(
                name: "SchoolAbsentAfter",
                table: "CompanySettings",
                type: "character varying(5)",
                maxLength: 5,
                nullable: false,
                defaultValue: "09:30");

            migrationBuilder.AddColumn<DateTime>(
                name: "SchoolAutoAbsentOn",
                table: "CompanySettings",
                type: "timestamp without time zone",
                nullable: true);

            migrationBuilder.AddColumn<bool>(
                name: "SchoolAutoAttendance",
                table: "CompanySettings",
                type: "boolean",
                nullable: false,
                defaultValue: true);

            migrationBuilder.AddColumn<string>(
                name: "SchoolAutoCheckOutAt",
                table: "CompanySettings",
                type: "character varying(5)",
                maxLength: 5,
                nullable: false,
                defaultValue: "19:00");

            migrationBuilder.AddColumn<DateTime>(
                name: "SchoolAutoCheckOutOn",
                table: "CompanySettings",
                type: "timestamp without time zone",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "SchoolDaycareEnd",
                table: "CompanySettings",
                type: "character varying(5)",
                maxLength: 5,
                nullable: false,
                defaultValue: "18:30");

            migrationBuilder.AddColumn<string>(
                name: "SchoolFullDayEnd",
                table: "CompanySettings",
                type: "character varying(5)",
                maxLength: 5,
                nullable: false,
                defaultValue: "16:30");

            migrationBuilder.AddColumn<string>(
                name: "SchoolHalfDayEnd",
                table: "CompanySettings",
                type: "character varying(5)",
                maxLength: 5,
                nullable: false,
                defaultValue: "12:30");

            migrationBuilder.AddColumn<string>(
                name: "SchoolLateAfter",
                table: "CompanySettings",
                type: "character varying(5)",
                maxLength: 5,
                nullable: false,
                defaultValue: "09:00");

            migrationBuilder.AddColumn<DateTime>(
                name: "SchoolRemindedOn",
                table: "CompanySettings",
                type: "timestamp without time zone",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "SchoolStart",
                table: "CompanySettings",
                type: "character varying(5)",
                maxLength: 5,
                nullable: false,
                defaultValue: "08:30");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "AutoAbsent",
                table: "StudentAttendance");

            migrationBuilder.DropColumn(
                name: "AutoCheckOut",
                table: "StudentAttendance");

            migrationBuilder.DropColumn(
                name: "IsLate",
                table: "StudentAttendance");

            migrationBuilder.DropColumn(
                name: "SchoolAbsentAfter",
                table: "CompanySettings");

            migrationBuilder.DropColumn(
                name: "SchoolAutoAbsentOn",
                table: "CompanySettings");

            migrationBuilder.DropColumn(
                name: "SchoolAutoAttendance",
                table: "CompanySettings");

            migrationBuilder.DropColumn(
                name: "SchoolAutoCheckOutAt",
                table: "CompanySettings");

            migrationBuilder.DropColumn(
                name: "SchoolAutoCheckOutOn",
                table: "CompanySettings");

            migrationBuilder.DropColumn(
                name: "SchoolDaycareEnd",
                table: "CompanySettings");

            migrationBuilder.DropColumn(
                name: "SchoolFullDayEnd",
                table: "CompanySettings");

            migrationBuilder.DropColumn(
                name: "SchoolHalfDayEnd",
                table: "CompanySettings");

            migrationBuilder.DropColumn(
                name: "SchoolLateAfter",
                table: "CompanySettings");

            migrationBuilder.DropColumn(
                name: "SchoolRemindedOn",
                table: "CompanySettings");

            migrationBuilder.DropColumn(
                name: "SchoolStart",
                table: "CompanySettings");
        }
    }
}
