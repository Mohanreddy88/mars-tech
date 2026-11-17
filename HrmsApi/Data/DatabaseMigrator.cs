using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HrmsApi.Data;

/// <summary>
/// One-time bridge from the old "EnsureCreated" databases to EF Core migrations.
/// </summary>
public static class DatabaseMigrator
{
    /// <summary>
    /// Databases created before migrations existed (by EnsureCreated or the SQL script)
    /// already have every table but no "__EFMigrationsHistory". Running the InitialCreate
    /// migration on them would fail with "table already exists", so record InitialCreate
    /// as applied instead. Later migrations then run normally. Does nothing on a new,
    /// empty database or on one that already uses migrations.
    /// </summary>
    public static async Task BaselineLegacyDatabaseAsync(HrmsDbContext context, ILogger logger)
    {
        var historyTable = context.GetService<IHistoryRepository>();
        if (await historyTable.ExistsAsync())
            return;

        if (!await TableExistsAsync(context, "Users"))
            return; // empty database: InitialCreate will create everything

        var initial = context.Database.GetMigrations().First();
        var version = typeof(DbContext).Assembly.GetName().Version!;

        logger.LogWarning("Existing database without migration history — marking {Migration} as applied", initial);
        await context.Database.ExecuteSqlRawAsync(historyTable.GetCreateIfNotExistsScript());
        await context.Database.ExecuteSqlRawAsync(
            "INSERT INTO \"__EFMigrationsHistory\" (\"MigrationId\", \"ProductVersion\") VALUES ({0}, {1})",
            initial, $"{version.Major}.{version.Minor}.{version.Build}");
    }

    private static async Task<bool> TableExistsAsync(HrmsDbContext context, string table)
    {
        var count = await context.Database
            .SqlQueryRaw<int>(
                "SELECT COUNT(*)::int AS \"Value\" FROM information_schema.tables WHERE table_schema = current_schema() AND table_name = {0}",
                table)
            .SingleAsync();
        return count > 0;
    }
}
