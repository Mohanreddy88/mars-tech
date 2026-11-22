using FluentAssertions;
using HrmsApi.Services;

namespace HrmsApi.Tests;

/// <summary>Phone numbers: Malaysian by default, stored as +60…, foreign numbers with their + code.</summary>
public class PhoneNumbersTests
{
    [Theory]
    [InlineData("012-345 6789",      "+60123456789")]   // mobile
    [InlineData("0123456789",        "+60123456789")]
    [InlineData("+60 12-345 6789",   "+60123456789")]
    [InlineData("+60 012-345 6789",  "+60123456789")]   // trunk 0 written after the country code
    [InlineData("60123456789",       "+60123456789")]   // + forgotten
    [InlineData("0060123456789",     "+60123456789")]
    [InlineData("011-2345 6789",     "+601123456789")]  // 011: one digit longer
    [InlineData("03-1234 5678",      "+60312345678")]   // KL landline
    [InlineData("04-123 4567",       "+6041234567")]    // Penang landline
    [InlineData("088-123 456",       "+6088123456")]    // Sabah landline
    [InlineData("+65 8123 4567",     "+6581234567")]    // Singapore
    [InlineData("+91 98765 43210",   "+919876543210")]  // India
    public void Valid_numbers_are_stored_in_one_form(string typed, string stored)
    {
        var (value, error) = PhoneNumbers.Normalize(typed);
        error.Should().BeNull();
        value.Should().Be(stored);
    }

    [Theory]
    [InlineData("012-345 678")]      // a digit short
    [InlineData("012-345 67890")]    // a digit too many (only 011 / 015 numbers are this long)
    [InlineData("03-123 4567")]      // KL landline needs 8 digits
    [InlineData("12345")]
    [InlineData("+65 123")]
    [InlineData("call me")]
    public void Wrong_numbers_are_refused(string typed)
    {
        var (value, error) = PhoneNumbers.Normalize(typed);
        value.Should().BeNull();
        error.Should().NotBeNull();
    }

    [Fact]
    public void Empty_is_allowed()
    {
        PhoneNumbers.Normalize("  ").Should().Be(((string?)null, (string?)null));
    }

    // Employees keep code and number apart: "+60" + "123456789"
    [Theory]
    [InlineData("+60", "012-345 6789",    "+60",  "123456789")]
    [InlineData("+60", "123456789",       "+60",  "123456789")]     // stored the old way
    [InlineData(null,  "03-1234 5678",    "+60",  "312345678")]
    [InlineData("+60", "+60 12-345 6789", "+60",  "123456789")]     // typed in full
    [InlineData("+60", "+977 9812345678", "+977", "9812345678")]    // typed in full with another code
    [InlineData("+977", "9812345678",     "+977", "9812345678")]    // Nepal
    [InlineData("+880", "01712-345678",   "+880", "01712345678")]   // Bangladesh: only the length is checked
    public void Employee_numbers_split_into_code_and_number(string? code, string typed, string wantCode, string wantNumber)
    {
        var (c, n, error) = PhoneNumbers.Split(code, typed);
        error.Should().BeNull();
        c.Should().Be(wantCode);
        n.Should().Be(wantNumber);
    }

    [Theory]
    [InlineData("+60", "")]
    [InlineData("+60", "12345")]
    [InlineData("60x", "0123456789")]
    public void Employee_numbers_that_are_wrong_are_refused(string code, string typed)
    {
        PhoneNumbers.Split(code, typed).Error.Should().NotBeNull();
    }

    [Fact]
    public void Old_free_text_values_compare_by_their_standard_form()
    {
        PhoneNumbers.Key("012 345 6789").Should().Be(PhoneNumbers.Key("+60123456789"));
    }
}
