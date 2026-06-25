using ReverseProxy.Backend.Shared;
using SampleC.Components;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddRazorComponents()
    .AddInteractiveServerComponents();

// Behaves correctly behind the portal reverse proxy (forwarded headers).
builder.Services.AddBackendReverseProxy();

var app = builder.Build();

// Apply forwarded headers + the configured PathBase ("/c"). Must run first.
app.UseBackendReverseProxy();

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error", createScopeForErrors: true);
}

app.UseAntiforgery();

app.MapStaticAssets();
app.MapRazorComponents<App>()
    .AddInteractiveServerRenderMode();

app.Run();
