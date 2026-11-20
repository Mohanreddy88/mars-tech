using Microsoft.AspNetCore.Authorization;
using HrmsApi.Platform;
using Microsoft.AspNetCore.Mvc;

namespace HrmsApi.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize(Roles = "Admin")]   // company data and admin actions: not for employee logins
public class FileUploadController : ControllerBase
{
    private readonly IWebHostEnvironment _env;
    private readonly ILogger<FileUploadController> _logger;
    private readonly ITenantContext _tenant;

    public FileUploadController(IWebHostEnvironment env, ILogger<FileUploadController> logger, ITenantContext tenant)
    {
        _tenant = tenant;
        _env = env;
        _logger = logger;
    }

    /// <summary>uploads/profiles, or uploads/{company}/profiles when several companies share the app.</summary>
    private string UploadsSubPath => _tenant.MultiTenant && _tenant.Tenant != null
        ? Path.Combine("uploads", _tenant.Tenant.Slug, "profiles")
        : Path.Combine("uploads", "profiles");

    /// <summary>
    /// POST /api/fileupload/profile
    /// Upload employee profile picture
    /// </summary>
    [HttpPost("profile")]
    public async Task<IActionResult> UploadProfile(IFormFile file)
    {
        if (file == null || file.Length == 0)
            return BadRequest(new { message = "No file uploaded" });

        // Validate file type
        var allowedExtensions = new[] { ".jpg", ".jpeg", ".png", ".gif" };
        var extension = Path.GetExtension(file.FileName).ToLowerInvariant();
        
        if (!allowedExtensions.Contains(extension))
            return BadRequest(new { message = "Only image files (jpg, jpeg, png, gif) are allowed" });

        // Validate file size (max 5MB)
        if (file.Length > 5 * 1024 * 1024)
            return BadRequest(new { message = "File size must not exceed 5MB" });

        try
        {
            // Generate unique filename
            var fileName = $"{Guid.NewGuid()}{extension}";
            var uploadsFolder = Path.Combine(_env.WebRootPath, UploadsSubPath);

            // Ensure directory exists
            if (!Directory.Exists(uploadsFolder))
                Directory.CreateDirectory(uploadsFolder);

            var filePath = Path.Combine(uploadsFolder, fileName);

            // Save file
            using (var stream = new FileStream(filePath, FileMode.Create))
            {
                await file.CopyToAsync(stream);
            }

            // Return relative URL path
            var fileUrl = $"/{UploadsSubPath.Replace(Path.DirectorySeparatorChar, '/')}/{fileName}";
            
            _logger.LogInformation("Profile picture uploaded: {FileName}", fileName);
            
            return Ok(new { filePath = fileUrl, fileName });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error uploading profile picture");
            return StatusCode(500, new { message = "Error uploading file" });
        }
    }

    /// <summary>
    /// DELETE /api/fileupload/profile/{fileName}
    /// Delete profile picture
    /// </summary>
    [HttpDelete("profile/{fileName}")]
    public IActionResult DeleteProfile(string fileName)
    {
        try
        {
            fileName = Path.GetFileName(fileName);   // no "../" tricks
            var uploadsFolder = Path.Combine(_env.WebRootPath, UploadsSubPath);
            var filePath = Path.Combine(uploadsFolder, fileName);

            if (System.IO.File.Exists(filePath))
            {
                System.IO.File.Delete(filePath);
                _logger.LogInformation("Profile picture deleted: {FileName}", fileName);
                return Ok(new { message = "File deleted successfully" });
            }

            return NotFound(new { message = "File not found" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting profile picture");
            return StatusCode(500, new { message = "Error deleting file" });
        }
    }
}
