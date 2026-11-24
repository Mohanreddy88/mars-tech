using FluentAssertions;
using HrmsApi.Controllers;
using HrmsApi.Platform;
using HrmsApi.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;

namespace HrmsApi.Tests;

/// <summary>Public website (marshrms.com): contact form, and company addresses now on sub-domains.</summary>
public class PublicSiteTests
{
    private sealed class FakeQueue : IEmailQueue
    {
        public List<EmailJob> Jobs { get; } = new();
        public void Enqueue(EmailJob job) => Jobs.Add(job);
    }

    private static (PublicController ctl, FakeQueue queue) Controller()
    {
        var queue = new FakeQueue();
        var config = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["Contact:Email"] = "support@marstech.tech"
        }).Build();
        return (new PublicController(config, NullLogger<PublicController>.Instance, new TenantCatalog(null!),
            Options.Create(new TenancyOptions { Enabled = false }), queue), queue);
    }

    [Fact]
    public async Task Company_list_is_empty_when_companies_are_switched_off()
    {
        var (ctl, _) = Controller();
        var ok = (await ctl.Companies()).Should().BeOfType<OkObjectResult>().Subject;
        ((System.Collections.IEnumerable)ok.Value!).Cast<object>().Should().BeEmpty();
    }

    [Fact]
    public void Contact_SendsEscapedEmailToSupport()
    {
        var (ctl, queue) = Controller();
        var r = ctl.Contact(new ContactRequest
        {
            Name = "Mohan", Organisation = "Golden <b>Kids</b>", Kind = "School", Email = "mohan@example.com",
            Message = "<script>alert(1)</script> Please call me"
        });
        r.Should().BeOfType<OkObjectResult>();
        var job = queue.Jobs.Should().ContainSingle().Subject;
        job.ToEmail.Should().Be("support@marstech.tech");
        job.Subject.Should().Contain("Mohan");
        job.Body.Should().NotContain("<script>").And.Contain("&lt;script&gt;").And.Contain("Golden &lt;b&gt;Kids");
    }

    [Fact]
    public void Contact_Validates_AndIgnoresBots()
    {
        var (ctl, queue) = Controller();
        ctl.Contact(new ContactRequest { Name = "", Email = "a@b.co" }).Should().BeOfType<BadRequestObjectResult>();
        ctl.Contact(new ContactRequest { Name = "Ali" }).Should().BeOfType<BadRequestObjectResult>("email or phone needed");
        ctl.Contact(new ContactRequest { Name = "Ali", Email = "not-an-email" }).Should().BeOfType<BadRequestObjectResult>();
        // Honeypot filled: looks fine to the bot, nothing is sent
        ctl.Contact(new ContactRequest { Name = "Bot", Email = "bot@spam.com", Website = "http://spam" }).Should().BeOfType<OkObjectResult>();
        queue.Jobs.Should().BeEmpty();
        // Phone only is enough
        ctl.Contact(new ContactRequest { Name = "Ali", Phone = "+60123456789" }).Should().BeOfType<OkObjectResult>();
        queue.Jobs.Should().HaveCount(1);
    }

    [Fact]
    public void CompanyAddresses_AreSubDomains_TheBareDomainIsTheWebsite()
    {
        var prod = new TenancyOptions { Enabled = true, BaseDomains = "marshrms.com,marstech.tech", RootTenant = "demo" };
        prod.UrlFor("demo").Should().Be("https://demo.marshrms.com");
        prod.UrlFor("montessori").Should().Be("https://montessori.marshrms.com");
        // demo.marshrms.com is the demo company; the bare domain still maps to it for the API
        prod.Match("demo.marshrms.com").Should().Be(new HostMatch(HostKind.Tenant, "demo"));
        prod.Match("marshrms.com").Should().Be(new HostMatch(HostKind.Root, "demo"));

        var uat = new TenancyOptions { Enabled = true, BaseDomains = "uat.marshrms.com,uat.marstech.tech" };
        uat.UrlFor("demo").Should().Be("https://demo.uat.marshrms.com");

        var local = new TenancyOptions();
        local.UrlFor("demo").Should().Be("http://localhost:4200");
    }
}
