using Microsoft.AspNetCore.Components.Web;
using Microsoft.AspNetCore.Components.WebAssembly.Hosting;
using Assemulator.Services;
using MudBlazor.Services;
using System.Net.Http.Json;

var builder = WebAssemblyHostBuilder.CreateDefault(args);
builder.RootComponents.Add<Assemulator.App>("#app");
builder.RootComponents.Add<HeadOutlet>("head::after");

// Runtime overrides let each environment set Nextcloud endpoints/tokens
// without rebuilding the Blazor app.
var bootstrapHttp = new HttpClient
{
    BaseAddress = new Uri(builder.HostEnvironment.BaseAddress)
};

try
{
    var runtimeConfig = await bootstrapHttp.GetFromJsonAsync<RuntimeConfig>("runtime-config.json");
    if (runtimeConfig?.Nextcloud is not null)
    {
        var runtimeOverrides = new Dictionary<string, string?>
        {
            ["Nextcloud:BaseUrl"] = runtimeConfig.Nextcloud.BaseUrl,
            ["Nextcloud:ShareToken"] = runtimeConfig.Nextcloud.ShareToken,
            ["Nextcloud:MetadataPath"] = runtimeConfig.Nextcloud.MetadataPath,
        };
        builder.Configuration.AddInMemoryCollection(runtimeOverrides);
    }
}
catch
{
    // Optional file. Fallback to appsettings values.
}

builder.Services.AddScoped(sp => new HttpClient
{
    BaseAddress = new Uri(builder.HostEnvironment.BaseAddress)
});

builder.Services.AddScoped<IRomRepository, RomRepository>();
builder.Services.AddScoped<INextcloudService, NextcloudService>();
builder.Services.AddMudServices();

await builder.Build().RunAsync();

public sealed class RuntimeConfig
{
    public RuntimeNextcloudConfig? Nextcloud { get; set; }
}

public sealed class RuntimeNextcloudConfig
{
    public string? BaseUrl { get; set; }
    public string? ShareToken { get; set; }
    public string? MetadataPath { get; set; }
}
