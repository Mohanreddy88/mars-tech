using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace HrmsApi.Migrations
{
    /// <summary>
    /// Starting master data for every company database (runs once per database, also for companies
    /// created later): Malaysian banks used for salary payment, and common departments.
    /// Only adds names that don't exist yet; companies can deactivate what they don't need.
    /// </summary>
    public partial class SeedMalaysianBanksAndDepartments : Migration
    {
        /// <summary>Licensed commercial and Islamic banks (Bank Negara Malaysia) + development banks common for salaries.</summary>
        private static readonly string[] Banks =
        {
            // Commercial banks
            "Affin Bank Berhad",
            "Alliance Bank Malaysia Berhad",
            "AmBank (M) Berhad",
            "Bangkok Bank Berhad",
            "Bank of America Malaysia Berhad",
            "Bank of China (Malaysia) Berhad",
            "BNP Paribas Malaysia Berhad",
            "China Construction Bank (Malaysia) Berhad",
            "CIMB Bank Berhad",
            "Citibank Berhad",
            "Deutsche Bank (Malaysia) Berhad",
            "Hong Leong Bank Berhad",
            "HSBC Bank Malaysia Berhad",
            "India International Bank (Malaysia) Berhad",
            "Industrial and Commercial Bank of China (Malaysia) Berhad",
            "J.P. Morgan Chase Bank Berhad",
            "Malayan Banking Berhad (Maybank)",
            "Mizuho Bank (Malaysia) Berhad",
            "MUFG Bank (Malaysia) Berhad",
            "OCBC Bank (Malaysia) Berhad",
            "Public Bank Berhad",
            "RHB Bank Berhad",
            "Standard Chartered Bank Malaysia Berhad",
            "Sumitomo Mitsui Banking Corporation Malaysia Berhad",
            "United Overseas Bank (Malaysia) Berhad",
            // Islamic banks
            "Affin Islamic Bank Berhad",
            "Al Rajhi Banking & Investment Corporation (Malaysia) Berhad",
            "Alliance Islamic Bank Berhad",
            "AmBank Islamic Berhad",
            "Bank Islam Malaysia Berhad",
            "Bank Muamalat Malaysia Berhad",
            "CIMB Islamic Bank Berhad",
            "Hong Leong Islamic Bank Berhad",
            "HSBC Amanah Malaysia Berhad",
            "Kuwait Finance House (Malaysia) Berhad",
            "Maybank Islamic Berhad",
            "MBSB Bank Berhad",
            "OCBC Al-Amin Bank Berhad",
            "Public Islamic Bank Berhad",
            "RHB Islamic Bank Berhad",
            "Standard Chartered Saadiq Berhad",
            // Development financial institutions often used for salaries
            "Bank Kerjasama Rakyat Malaysia Berhad (Bank Rakyat)",
            "Bank Simpanan Nasional (BSN)",
            "Agrobank (Bank Pertanian Malaysia Berhad)",
        };

        private static readonly (string Name, string Description)[] Departments =
        {
            ("Administration",         "Office administration and general management"),
            ("Human Resources",        "Recruitment, payroll and employee relations"),
            ("Finance & Accounts",     "Accounting, budgeting and payments"),
            ("Information Technology", "IT systems, software and support"),
            ("Operations",             "Day-to-day operations and service delivery"),
            ("Sales & Marketing",      "Sales, marketing and business development"),
            ("Customer Service",       "Customer and parent enquiries and support"),
        };

        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            foreach (var bank in Banks)
            {
                var n = bank.Replace("'", "''");
                migrationBuilder.Sql($@"
INSERT INTO ""BankMaster"" (""Name"", ""IsActive"", ""CreatedDate"", ""CreatedBy"")
SELECT '{n}', true, now(), 'system'
WHERE NOT EXISTS (SELECT 1 FROM ""BankMaster"" WHERE lower(""Name"") = lower('{n}'));");
            }

            foreach (var (name, description) in Departments)
            {
                var n = name.Replace("'", "''");
                var d = description.Replace("'", "''");
                // "Information Technology" is skipped where the company already has "IT"
                var alsoSkip = name == "Information Technology" ? " OR lower(\"Name\") = 'it'" : "";
                migrationBuilder.Sql($@"
INSERT INTO ""Departments"" (""Name"", ""Description"", ""IsActive"", ""CreatedAt"")
SELECT '{n}', '{d}', true, now()
WHERE NOT EXISTS (SELECT 1 FROM ""Departments"" WHERE lower(""Name"") = lower('{n}'){alsoSkip});");
            }
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            // Master data may already be used by employees; nothing is removed on rollback.
        }
    }
}
