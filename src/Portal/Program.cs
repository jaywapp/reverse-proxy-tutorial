var builder = WebApplication.CreateBuilder(args);

// YARP reverse proxy: routes & clusters are loaded from appsettings.json.
builder.Services.AddReverseProxy()
    .LoadFromConfig(builder.Configuration.GetSection("ReverseProxy"));

var app = builder.Build();

// WebSocket support is required so Blazor Server circuits (SignalR) can be
// proxied to the backend apps. YARP forwards WebSocket upgrades automatically.
app.UseWebSockets();

// Landing page and any static assets live in wwwroot.
app.UseDefaultFiles();
app.UseStaticFiles();

// A backend served under "/a" expects its <base href> to end with a slash, so a
// request to the bare prefix "/a" must redirect to "/a/". We derive the set of
// prefixes ("/a", "/b", ...) from the configured route paths so there is nothing
// hard-coded here -- add a route in appsettings.json and it just works.
var prefixes = PathPrefixes.FromReverseProxyConfig(builder.Configuration);
app.Use(async (ctx, next) =>
{
    // EXACT match only: "/a" redirects, but "/a/" does not (that would loop).
    var path = ctx.Request.Path.Value ?? string.Empty;
    if (prefixes.Contains(path))
    {
        ctx.Response.Redirect($"{ctx.Request.PathBase}{path}/", permanent: false);
        return;
    }
    await next();
});

// Forward everything matched by the configured routes to the backend apps.
app.MapReverseProxy();

app.Run();

/// <summary>
/// Extracts the leading static path segment of every configured YARP route
/// (e.g. route path "/a/{**catch-all}" -> "/a"). Used to redirect bare prefixes
/// to their trailing-slash form.
/// </summary>
static class PathPrefixes
{
    public static HashSet<string> FromReverseProxyConfig(IConfiguration configuration)
    {
        var set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var route in configuration.GetSection("ReverseProxy:Routes").GetChildren())
        {
            var matchPath = route["Match:Path"];
            if (string.IsNullOrWhiteSpace(matchPath)) continue;

            var firstSegment = matchPath.TrimStart('/').Split('/', 2)[0];
            // Skip catch-all/parameter segments like "{**catch-all}".
            if (firstSegment.Length == 0 || firstSegment.Contains('{')) continue;

            set.Add("/" + firstSegment);
        }
        return set;
    }
}
