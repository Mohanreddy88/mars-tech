using FluentAssertions;
using HrmsApi.Models;

namespace HrmsApi.Tests;

/// <summary>MC letters are accepted only as real PDF, JPEG or PNG files (checked by content, not file name).</summary>
public class LeaveAttachmentTests
{
    [Fact]
    public void DetectType_RecognisesPdfJpegPng()
    {
        LeaveAttachment.DetectType("%PDF-1.7 rest"u8.ToArray()).Should().Be("application/pdf");
        LeaveAttachment.DetectType(new byte[] { 0xFF, 0xD8, 0xFF, 0xE0, 0x00 }).Should().Be("image/jpeg");
        LeaveAttachment.DetectType(new byte[] { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A }).Should().Be("image/png");
    }

    [Fact]
    public void DetectType_RejectsOtherFiles_EvenWithAPdfName()
    {
        LeaveAttachment.DetectType("<html><script>alert(1)</script>"u8.ToArray()).Should().BeNull();
        LeaveAttachment.DetectType("MZ\u0090\u0000"u8.ToArray()).Should().BeNull();   // Windows executable
        LeaveAttachment.DetectType(Array.Empty<byte>()).Should().BeNull();
    }
}
