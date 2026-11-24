using HrmsApi.Data;
using Microsoft.EntityFrameworkCore;

namespace HrmsApi.Services;

/// <summary>
/// Keeps <c>Student.NoMotherOnRecord / NoFatherOnRecord</c> true to the links: a child who now has
/// a mother (father) linked is no longer "no mother (father) on record".
/// </summary>
public static class SchoolParentFlags
{
    public static async Task SyncAsync(HrmsDbContext db, IReadOnlyCollection<int> studentIds)
    {
        if (studentIds.Count == 0) return;
        var kids = await db.Students.Where(s => studentIds.Contains(s.Id) && (s.NoMotherOnRecord || s.NoFatherOnRecord))
            .Select(s => new
            {
                Student = s,
                hasMother = s.Parents.Any(p => p.Parent.Relationship == "Mother"),
                hasFather = s.Parents.Any(p => p.Parent.Relationship == "Father")
            }).ToListAsync();
        foreach (var k in kids)
        {
            if (k.hasMother) k.Student.NoMotherOnRecord = false;
            if (k.hasFather) k.Student.NoFatherOnRecord = false;
        }
        if (kids.Count > 0) await db.SaveChangesAsync();
    }
}
