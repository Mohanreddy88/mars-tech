using HrmsApi.Data;
using HrmsApi.Models;
using HrmsApi.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace HrmsApi.Controllers;

/// <summary>
/// Profile photos of children and parents (JPG / PNG, 5 MB). Stored in the company's database and
/// served only to people who may see that child or parent — never from the public uploads folder.
/// Children: the office or the child's parents change it. Parents: the office or the parent.
/// Staff photos stay on the employee record (Employees → profile picture).
/// </summary>
[ApiController]
[Route("api/school")]
[Authorize]
[RequiresSchoolFeatures]
public class ProfilePhotosController : ControllerBase
{
    private readonly HrmsDbContext _db;

    public ProfilePhotosController(HrmsDbContext db) { _db = db; }

    // ── Children ──

    [HttpGet("students/{id:int}/photo")]
    public async Task<IActionResult> GetChild(int id)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        var classId = await _db.Students.Where(s => s.Id == id).Select(s => new { s.ClassId }).FirstOrDefaultAsync()
                      ?? throw new KeyNotFoundException("Child not found.");
        if (me == null || !me.CanSeeStudent(id, classId.ClassId)) return Forbid();
        return await ServeAsync(_db.ProfilePhotos.Where(p => p.StudentId == id));
    }

    [HttpPut("students/{id:int}/photo")]
    [RequestSizeLimit(ProfilePhoto.MaxBytes + 512 * 1024)]
    public async Task<IActionResult> SetChild(int id, IFormFile file)
    {
        var s = await _db.Students.FindAsync(id) ?? throw new KeyNotFoundException("Child not found.");
        if (!await CanEditChildAsync(id)) return Forbid();
        var (photo, error) = await ReadAsync(file);
        if (error != null) return BadRequest(new { message = error });

        var row = await _db.ProfilePhotos.FirstOrDefaultAsync(p => p.StudentId == id);
        if (row == null) { row = new ProfilePhoto { StudentId = id }; _db.ProfilePhotos.Add(row); }
        (row.ContentType, row.Data, row.UpdatedAt) = (photo!.Value.type, photo.Value.data, DateTime.UtcNow);
        s.PhotoUpdatedAt = row.UpdatedAt;
        await _db.SaveChangesAsync();
        return Ok(new { photoUpdatedAt = s.PhotoUpdatedAt });
    }

    [HttpDelete("students/{id:int}/photo")]
    public async Task<IActionResult> DeleteChild(int id)
    {
        var s = await _db.Students.FindAsync(id) ?? throw new KeyNotFoundException("Child not found.");
        if (!await CanEditChildAsync(id)) return Forbid();
        _db.ProfilePhotos.RemoveRange(await _db.ProfilePhotos.Where(p => p.StudentId == id).ToListAsync());
        s.PhotoUpdatedAt = null;
        await _db.SaveChangesAsync();
        return NoContent();
    }

    // ── Parents ──

    [HttpGet("parents/{id:int}/photo")]
    public async Task<IActionResult> GetParent(int id)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me == null || !await CanSeeParentAsync(me, id)) return Forbid();
        return await ServeAsync(_db.ProfilePhotos.Where(p => p.ParentId == id));
    }

    [HttpPut("parents/{id:int}/photo")]
    [RequestSizeLimit(ProfilePhoto.MaxBytes + 512 * 1024)]
    public async Task<IActionResult> SetParent(int id, IFormFile file)
    {
        var parent = await _db.Parents.FindAsync(id) ?? throw new KeyNotFoundException("Parent not found.");
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me == null || !(me.IsAdmin || me.ParentId == id)) return Forbid();
        var (photo, error) = await ReadAsync(file);
        if (error != null) return BadRequest(new { message = error });

        var row = await _db.ProfilePhotos.FirstOrDefaultAsync(p => p.ParentId == id);
        if (row == null) { row = new ProfilePhoto { ParentId = id }; _db.ProfilePhotos.Add(row); }
        (row.ContentType, row.Data, row.UpdatedAt) = (photo!.Value.type, photo.Value.data, DateTime.UtcNow);
        parent.PhotoUpdatedAt = row.UpdatedAt;
        await _db.SaveChangesAsync();
        return Ok(new { photoUpdatedAt = parent.PhotoUpdatedAt });
    }

    [HttpDelete("parents/{id:int}/photo")]
    public async Task<IActionResult> DeleteParent(int id)
    {
        var parent = await _db.Parents.FindAsync(id) ?? throw new KeyNotFoundException("Parent not found.");
        var me = await SchoolViewer.LoadAsync(_db, User);
        if (me == null || !(me.IsAdmin || me.ParentId == id)) return Forbid();
        _db.ProfilePhotos.RemoveRange(await _db.ProfilePhotos.Where(p => p.ParentId == id).ToListAsync());
        parent.PhotoUpdatedAt = null;
        await _db.SaveChangesAsync();
        return NoContent();
    }

    // ── helpers ──

    /// <summary>The office, or a parent of the child.</summary>
    private async Task<bool> CanEditChildAsync(int studentId)
    {
        var me = await SchoolViewer.LoadAsync(_db, User);
        return me != null && (me.IsAdmin || (me.IsParent && me.ChildIds.Contains(studentId)));
    }

    /// <summary>The office, the parent, a co-parent of one of their children, or a teacher of one of their children's classes.</summary>
    private async Task<bool> CanSeeParentAsync(SchoolViewer me, int parentId)
    {
        if (me.IsAdmin || me.ParentId == parentId) return true;
        var children = _db.StudentParents.Where(sp => sp.ParentId == parentId && sp.Student.IsActive);
        if (me.IsParent) return await children.AnyAsync(sp => me.ChildIds.Contains(sp.StudentId));
        return me.TeacherClassIds.Count > 0
            && await children.AnyAsync(sp => sp.Student.ClassId != null && me.TeacherClassIds.Contains(sp.Student.ClassId.Value));
    }

    private async Task<IActionResult> ServeAsync(IQueryable<ProfilePhoto> q)
    {
        var p = await q.AsNoTracking().Select(x => new { x.ContentType, x.Data }).FirstOrDefaultAsync()
                ?? throw new KeyNotFoundException("No photo.");
        // Private, but the URL carries ?v=<updated> so the browser / app may keep it for a while
        Response.Headers["Cache-Control"] = "private, max-age=86400";
        Response.Headers["X-Content-Type-Options"] = "nosniff";
        return File(p.Data, p.ContentType);
    }

    private static async Task<((string type, byte[] data)? photo, string? error)> ReadAsync(IFormFile? file)
    {
        if (file == null || file.Length == 0) return (null, "Choose a photo.");
        if (file.Length > ProfilePhoto.MaxBytes) return (null, "The photo must be 5 MB or smaller.");
        using var ms = new MemoryStream();
        await file.CopyToAsync(ms);
        var bytes = ms.ToArray();
        var type = LeaveAttachment.DetectType(bytes);
        if (type is not ("image/jpeg" or "image/png")) return (null, "Choose a JPG or PNG photo.");
        return ((type, bytes), null);
    }
}
