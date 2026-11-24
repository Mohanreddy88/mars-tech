using System.Security.Claims;
using HrmsApi.Data;
using HrmsApi.Models;
using HrmsApi.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace HrmsApi.Controllers;

/// <summary>
/// School → Families (admin). A family is a mother and/or father and the children they share,
/// set on one screen so every child gets the same parents in one save. Nothing new is stored:
/// a family is read from the child ↔ parent links (<see cref="StudentParent"/>).
///
/// Half-siblings are two families that share a parent: Rudvik → Mounika + Mohan, his half-brother
/// → Mounika + Narsi. Mounika is one parent record in both; each child keeps their own father.
/// Guardians stay on the child (Children → edit), not on the family.
/// </summary>
[ApiController]
[Route("api/school/families")]
[Authorize(Roles = UserAccess.Admin)]
[RequiresSchoolFeatures]
public class FamiliesController : ControllerBase
{
    private readonly HrmsDbContext _db;
    private readonly IAuditService _audit;

    public FamiliesController(HrmsDbContext db, IAuditService audit)
    {
        _db = db; _audit = audit;
    }

    /// <summary>
    /// GET /api/school/families — every family (children grouped by their mother + father), plus
    /// children with no mother or father linked (mother and father both null), so the office can
    /// see what is missing. Inactive children are included and flagged.
    /// </summary>
    [HttpGet]
    public async Task<IActionResult> GetAll()
    {
        var children = await _db.Students.AsNoTracking()
            .Select(s => new
            {
                s.Id, s.FullName, s.IsActive, s.NoMotherOnRecord, s.NoFatherOnRecord,
                className = s.Class != null ? s.Class.Name : null,
                parents = s.Parents.Select(sp => new { sp.Parent.Id, sp.Parent.FullName, sp.Parent.Relationship,
                                                       sp.Parent.Phone, hasLogin = sp.Parent.UserId != null }).ToList()
            }).ToListAsync();

        var families = children
            .Select(c => new
            {
                child = c,
                mother = c.parents.FirstOrDefault(p => p.Relationship == "Mother"),
                father = c.parents.FirstOrDefault(p => p.Relationship == "Father")
            })
            // "No father on record" (single mother) is its own family, apart from "father not set yet"
            .GroupBy(x => (motherId: x.mother?.Id, fatherId: x.father?.Id,
                           noMother: x.mother == null && x.child.NoMotherOnRecord, noFather: x.father == null && x.child.NoFatherOnRecord))
            .Select(g => new
            {
                mother = g.First().mother,
                father = g.First().father,
                // Single parent confirmed by the office (not a mistake to fix)
                noMother = g.Key.noMother,
                noFather = g.Key.noFather,
                children = g.OrderBy(x => x.child.FullName).Select(x => new
                {
                    x.child.Id, x.child.FullName, x.child.className, x.child.IsActive,
                    guardians = x.child.parents.Where(p => p.Relationship == Parent.Guardian)
                                               .Select(p => new { p.Id, p.FullName }).ToList()
                }).ToList()
            })
            // Families with both parents first, then one parent, then children with none
            .OrderBy(f => (f.mother == null && !f.noMother ? 1 : 0) + (f.father == null && !f.noFather ? 1 : 0))
            .ThenBy(f => f.mother?.FullName ?? f.father?.FullName ?? "")
            .ToList();

        return Ok(families);
    }

    /// <summary>
    /// PUT /api/school/families — set the mother and/or father of the chosen children.
    /// For each child in <c>studentIds</c>: the mother becomes <c>motherId</c> (any other mother is
    /// unlinked) and the father becomes <c>fatherId</c>; a null id leaves that side as it is.
    /// Children in <c>removeStudentIds</c> are unlinked from this mother and father (taken out of the family).
    /// New parents and children are added first with the usual Parents / Children forms.
    /// </summary>
    [HttpPut]
    public async Task<IActionResult> Save([FromBody] FamilyRequest req)
    {
        var add = req.StudentIds?.Distinct().ToList() ?? new();
        var remove = (req.RemoveStudentIds ?? new()).Distinct().Where(id => !add.Contains(id)).ToList();
        if (req.MotherId == null && req.FatherId == null)
            return BadRequest(new { message = "Choose the mother, the father or both.", field = "motherId" });
        // Apps that send NoMother/NoFather: both parents are required unless "no … on record" is ticked
        if (req.NoMother == false && req.MotherId == null && add.Count > 0)
            return BadRequest(new { message = "Choose the mother, or tick \"No mother on record\".", field = "motherId" });
        if (req.NoFather == false && req.FatherId == null && add.Count > 0)
            return BadRequest(new { message = "Choose the father, or tick \"No father on record\".", field = "fatherId" });
        if (add.Count == 0 && remove.Count == 0)
            return BadRequest(new { message = "Add at least one child to the family.", field = "studentIds" });

        var parentIds = new[] { req.MotherId, req.FatherId }.Where(i => i != null).Select(i => i!.Value).ToList();
        var parents = await _db.Parents.Where(p => parentIds.Contains(p.Id)).ToDictionaryAsync(p => p.Id);
        Parent? mother = null, father = null;
        if (req.MotherId != null)
        {
            if (!parents.TryGetValue(req.MotherId.Value, out mother))
                return BadRequest(new { message = "The chosen mother no longer exists. Reload the page.", field = "motherId" });
            if (mother.Relationship != "Mother")
                return BadRequest(new { message = $"{mother.FullName} is saved as {mother.Relationship.ToLower()}, not mother. Change it under Parents first.", field = "motherId" });
        }
        if (req.FatherId != null)
        {
            if (!parents.TryGetValue(req.FatherId.Value, out father))
                return BadRequest(new { message = "The chosen father no longer exists. Reload the page.", field = "fatherId" });
            if (father.Relationship != "Father")
                return BadRequest(new { message = $"{father.FullName} is saved as {father.Relationship.ToLower()}, not father. Change it under Parents first.", field = "fatherId" });
        }

        var allIds = add.Concat(remove).ToList();
        var kids = await _db.Students.Where(s => allIds.Contains(s.Id)).ToListAsync();
        var students = kids.Select(s => new { s.Id, s.FullName }).ToList();
        if (students.Count != allIds.Count)
            return BadRequest(new { message = "One of the chosen children no longer exists. Reload the page.", field = "studentIds" });

        var links = await _db.StudentParents.Include(sp => sp.Parent)
            .Where(sp => allIds.Contains(sp.StudentId)).ToListAsync();
        var changes = new List<string>();
        string Name(int id) => students.First(s => s.Id == id).FullName;

        foreach (var sid in add)
        {
            foreach (var (chosen, relationship) in new[] { (mother, "Mother"), (father, "Father") })
            {
                if (chosen == null) continue;
                var old = links.Where(l => l.StudentId == sid && l.Parent.Relationship == relationship && l.ParentId != chosen.Id).ToList();
                foreach (var l in old) changes.Add($"{Name(sid)}: {relationship.ToLower()} {l.Parent.FullName} → {chosen.FullName}");
                _db.StudentParents.RemoveRange(old);
                if (!links.Any(l => l.StudentId == sid && l.ParentId == chosen.Id))
                {
                    _db.StudentParents.Add(new StudentParent { StudentId = sid, ParentId = chosen.Id });
                    if (old.Count == 0) changes.Add($"{Name(sid)}: {relationship.ToLower()} {chosen.FullName}");
                }
            }

            // Single parent: no mother / father on record — any linked one is taken off, and it's recorded
            var kid = kids.First(k => k.Id == sid);
            foreach (var (none, relationship) in new[] { (req.NoMother == true && mother == null, "Mother"), (req.NoFather == true && father == null, "Father") })
            {
                if (!none) continue;
                var old = links.Where(l => l.StudentId == sid && l.Parent.Relationship == relationship).ToList();
                foreach (var l in old) changes.Add($"{Name(sid)}: removed {relationship.ToLower()} {l.Parent.FullName}");
                _db.StudentParents.RemoveRange(old);
                if (relationship == "Mother" && !kid.NoMotherOnRecord) { kid.NoMotherOnRecord = true; changes.Add($"{Name(sid)}: no mother on record"); }
                if (relationship == "Father" && !kid.NoFatherOnRecord) { kid.NoFatherOnRecord = true; changes.Add($"{Name(sid)}: no father on record"); }
            }
            if (mother != null) kid.NoMotherOnRecord = false;
            if (father != null) kid.NoFatherOnRecord = false;
        }
        foreach (var sid in remove)
        {
            var gone = links.Where(l => l.StudentId == sid && parentIds.Contains(l.ParentId)).ToList();
            foreach (var l in gone) changes.Add($"{Name(sid)}: removed {l.Parent.Relationship.ToLower()} {l.Parent.FullName}");
            _db.StudentParents.RemoveRange(gone);
        }

        await _db.SaveChangesAsync();
        if (changes.Count > 0)
            await _audit.LogAsync("Updated", "Family", (req.MotherId ?? req.FatherId)!.Value.ToString(),
                "Family of " + string.Join(" and ", new[] { mother?.FullName, father?.FullName }.Where(n => n != null)) + ": " + string.Join("; ", changes),
                User.Identity?.Name ?? "unknown",
                int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var uid) ? uid : null,
                null, null, HttpContext.Connection.RemoteIpAddress?.ToString());
        return Ok(new { changed = changes.Count });
    }
}

public class FamilyRequest
{
    public int? MotherId { get; set; }
    public int? FatherId { get; set; }
    /// <summary>Children of this mother and father.</summary>
    public List<int>? StudentIds { get; set; }
    /// <summary>Children taken out of the family (unlinked from this mother and father).</summary>
    public List<int>? RemoveStudentIds { get; set; }
    /// <summary>
    /// Single parent: true = no mother / father on record for these children (any linked one is
    /// taken off). Apps that send false require MotherId / FatherId. Null = old client, no check.
    /// </summary>
    public bool? NoMother { get; set; }
    public bool? NoFather { get; set; }
}
