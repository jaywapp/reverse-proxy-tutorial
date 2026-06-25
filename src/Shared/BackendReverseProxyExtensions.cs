using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace ReverseProxy.Backend.Shared;

/// <summary>
/// Drop-in helpers that make an ASP.NET Core / Blazor Server app behave correctly
/// when it is served under a path prefix (e.g. "/a") behind a reverse proxy.
///
/// Two things every backend app needs:
///   1. Honour the proxy's forwarded headers (original scheme/host/client IP).
///   2. Run under the path base configured in "PathBase" so links, static assets
///      and the SignalR endpoint resolve under "/a" instead of "/".
/// </summary>
public static class BackendReverseProxyExtensions
{
    /// <summary>
    /// Reads the configured path base ("PathBase", e.g. "/a") and returns it as a
    /// browser &lt;base href&gt; value with a trailing slash ("/a/"). Returns "/" when
    /// no path base is configured (app served at the root).
    /// </summary>
    public static string GetBaseHref(this IConfiguration configuration)
    {
        var pathBase = configuration["PathBase"];
        return string.IsNullOrWhiteSpace(pathBase) ? "/" : "/" + pathBase.Trim('/') + "/";
    }

    /// <summary>
    /// Registers the forwarded-headers options needed to sit behind a reverse proxy.
    /// Call this on the service collection during startup.
    /// </summary>
    public static IServiceCollection AddBackendReverseProxy(this IServiceCollection services)
    {
        services.Configure<ForwardedHeadersOptions>(options =>
        {
            options.ForwardedHeaders =
                ForwardedHeaders.XForwardedFor |
                ForwardedHeaders.XForwardedProto |
                ForwardedHeaders.XForwardedHost;
            // The proxy is trusted but its address is not known in advance
            // (containers, IIS, dynamic hosts), so we clear the allow-lists.
            // Lock these down to your proxy's address in hardened deployments.
            options.KnownNetworks.Clear();
            options.KnownProxies.Clear();
        });
        return services;
    }

    /// <summary>
    /// Applies forwarded headers and the configured path base. Must run very early
    /// in the pipeline, before routing/static files. Call this right after Build().
    /// </summary>
    public static WebApplication UseBackendReverseProxy(this WebApplication app)
    {
        app.UseForwardedHeaders();

        var pathBase = app.Configuration["PathBase"];
        if (!string.IsNullOrWhiteSpace(pathBase))
        {
            app.UsePathBase(pathBase);
        }
        return app;
    }
}
