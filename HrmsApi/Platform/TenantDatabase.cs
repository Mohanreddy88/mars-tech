using System.Text.RegularExpressions;
using HrmsApi.Data;
using HrmsApi.Models;
using Microsoft.EntityFrameworkCore;
using Npgsql;

namespace HrmsApi.Platform;

/// <summary>Creating and upgrading company databases (PostgreSQL).</summary>
public static class TenantDatabase
{
    private static readonly Regex SafeName = new("^[a-z][a-z0-9_]{0,62}$", RegexOptions.Compiled);

    public static async Task<bool> ExistsAsync(string baseConnectionString, string database)
    {
        await using var conn = await OpenMaintenanceAsync(baseConnectionString);
        await using var cmd = new NpgsqlCommand("SELECT 1 FROM pg_database WHERE datname = @n", conn);
        cmd.Parameters.AddWithValue("n", database);
        return await cmd.ExecuteScalarAsync() != null;
    }

    /// <summary>CREATE DATABASE when missing. Returns true if it was created now.</summary>
    public static async Task<bool> CreateIfMissingAsync(string baseConnectionString, string database)
    {
        if (!SafeName.IsMatch(database))
            throw new ArgumentException($"Invalid database name '{database}'.");
        if (await ExistsAsync(baseConnectionString, database)) return false;

        await using var conn = await OpenMaintenanceAsync(baseConnectionString);
        // Identifiers can't be parameters; the name is checked against SafeName above.
        await using var cmd = new NpgsqlCommand($"CREATE DATABASE \"{database}\"", conn);
        await cmd.ExecuteNonQueryAsync();
        return true;
    }

    /// <summary>Only used to undo a company creation that failed half-way.</summary>
    public static async Task DropAsync(string baseConnectionString, string database)
    {
        if (!SafeName.IsMatch(database))
            throw new ArgumentException($"Invalid database name '{database}'.");
        NpgsqlConnection.ClearAllPools();
        await using var conn = await OpenMaintenanceAsync(baseConnectionString);
        await using var cmd = new NpgsqlCommand($"DROP DATABASE IF EXISTS \"{database}\" WITH (FORCE)", conn);
        await cmd.ExecuteNonQueryAsync();
    }

    public static HrmsDbContext OpenCompany(string connectionString) =>
        new(new DbContextOptionsBuilder<HrmsDbContext>().UseNpgsql(connectionString).Options);

    /// <summary>Bring a company database up to date: migrations, then default data.</summary>
    public static async Task MigrateAndSeedAsync(HrmsDbContext context, ILogger logger, string label, bool seedDefaultAdmin)
    {
        await DatabaseMigrator.BaselineLegacyDatabaseAsync(context, logger);
        var pending = (await context.Database.GetPendingMigrationsAsync()).ToList();
        logger.LogInformation(pending.Count == 0
            ? "✅ [{Label}] database schema up to date"
            : "🔄 [{Label}] applying {Count} migration(s): {List}", label, pending.Count, string.Join(", ", pending));
        await context.Database.MigrateAsync();
        await DataSeeder.SeedAsync(context, logger, seedDefaultAdmin);
    }

    private static async Task<NpgsqlConnection> OpenMaintenanceAsync(string baseConnectionString)
    {
        var cs = new NpgsqlConnectionStringBuilder(baseConnectionString) { Database = "postgres", Pooling = false };
        var conn = new NpgsqlConnection(cs.ConnectionString);
        await conn.OpenAsync();
        return conn;
    }
}

/// <summary>Default data every company database starts with.</summary>
public static class DataSeeder
{
    /// <param name="seedDefaultAdmin">
    /// Create admin / Admin@123 when there are no users. Only for single-company mode: companies
    /// created in the portal get their own admin account with a one-time password instead.
    /// </param>
    public static async Task SeedAsync(HrmsDbContext context, ILogger logger, bool seedDefaultAdmin)
    {
        if (!await context.LeaveTypes.AnyAsync())
        {
            logger.LogInformation("🌱 Seeding leave types...");
            var now = DateTime.UtcNow;
            LeaveType L(string name, string code, int days, bool paid = true) => new()
            {
                Name = name, Code = code, DefaultDaysPerYear = days, IsActive = true,
                RequiresApproval = true, IsPaid = paid, CreatedAt = now
            };
            context.LeaveTypes.AddRange(
                L("Annual Leave", "AL", 14), L("Medical Leave", "ML", 14), L("Emergency Leave", "EL", 2),
                L("Casual Leave", "CL", 3), L("Maternity Leave", "MTL", 98), L("Paternity Leave", "PTL", 7),
                L("Unpaid Leave", "UL", 0, paid: false), L("Study Leave", "SL", 5),
                L("Hajj Leave", "HL", 0, paid: false), L("Replacement Leave", "RL", 0));
            await context.SaveChangesAsync();
            logger.LogInformation("✅ Leave types seeded (10 types)");
        }

        if (seedDefaultAdmin && !await context.Users.AnyAsync())
        {
            logger.LogInformation("🌱 Seeding default admin user...");
            context.Users.Add(new User
            {
                Username     = "admin",
                Email        = "admin@hrms.local",
                PasswordHash = BCrypt.Net.BCrypt.HashPassword("Admin@123"),
                Role         = "Admin",
                IsActive     = true,
                CreatedAt    = DateTime.UtcNow
            });
            await context.SaveChangesAsync();
            logger.LogInformation("✅ Default admin user created (Username: admin)");
        }
    }
}
