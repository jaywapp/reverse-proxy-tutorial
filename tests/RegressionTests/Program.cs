using Microsoft.Extensions.Configuration;
using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using Microsoft.AspNetCore.HttpOverrides;
using ReverseProxy.Backend.Shared;
foreach (var (value, expected) in new (string?, string)[] { (null, "/"), ("", "/"), (" ", "/"), ("/a", "/a/"), ("a", "/a/"), ("/a/", "/a/"), ("/a/b", "/a/b/"), ("/", "//") }) {
    var config = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string,string?> { ["PathBase"] = value }).Build();
    Check.That(config.GetBaseHref() == expected, "Existing base href: " + value);
}
var services = new ServiceCollection();
Check.That(ReferenceEquals(services, services.AddBackendReverseProxy()), "Fluent registration");
using var provider = services.BuildServiceProvider();
var options = provider.GetRequiredService<IOptions<ForwardedHeadersOptions>>().Value;
Check.That(options.ForwardedHeaders.HasFlag(ForwardedHeaders.XForwardedProto), "Forward scheme");
Check.That(options.ForwardedHeaders.HasFlag(ForwardedHeaders.XForwardedHost), "Forward host");
Console.WriteLine($"PASS {Check.Count} proxy regression checks");
