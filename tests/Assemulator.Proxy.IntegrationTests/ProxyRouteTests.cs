using System.Text.Json;
using System.Xml.Linq;
using Xunit;

namespace Assemulator.Proxy.IntegrationTests;

public class ProxyRouteTests
{
    private static readonly Uri BaseUri = new(Environment.GetEnvironmentVariable("ASSEMULATOR_BASE_URL") ?? "http://127.0.0.1:8088/");
    private static readonly string[] RomExtensions = [".zip", ".nes", ".sfc", ".smc", ".n64", ".z64", ".v64", ".gba", ".md", ".gen", ".bin", ".a26"];

    [Fact]
    public async Task RuntimeConfig_UsesNcApiBaseUrl()
    {
        using var http = CreateHttpClient();
        using var response = await http.GetAsync("runtime-config.json");

        Assert.True(response.IsSuccessStatusCode, $"Expected runtime-config.json to load from {BaseUri}, got {(int)response.StatusCode}.");

        var json = await response.Content.ReadAsStringAsync();
        using var doc = JsonDocument.Parse(json);

        var nextcloud = doc.RootElement.GetProperty("Nextcloud");
        var baseUrl = nextcloud.GetProperty("BaseUrl").GetString();

        Assert.Equal("nc-api", baseUrl);
    }

    [Fact]
    public async Task NcApiProxy_CanFetch_ConsolesJson_FromNextcloud()
    {
        using var http = CreateHttpClient();
        var runtime = await ReadRuntimeConfigAsync(http);

        var proxyBase = BuildProxyBase(runtime.BaseUrl);
        var metadataPath = runtime.MetadataPath.Trim('/');
        var proxiedPath = $"{proxyBase}/public.php/dav/files/{runtime.ShareToken}/{metadataPath}/consoles.json";

        using var response = await http.GetAsync(proxiedPath);
        var body = await response.Content.ReadAsStringAsync();

        Assert.True(response.IsSuccessStatusCode, $"Expected 2xx from proxy path '{proxiedPath}', got {(int)response.StatusCode}. Body: {TrimForMessage(body)}");

        using var doc = JsonDocument.Parse(body);
        Assert.Equal(JsonValueKind.Array, doc.RootElement.ValueKind);
        Assert.True(doc.RootElement.GetArrayLength() > 0, "Expected at least one console entry from proxied metadata.");
    }

    [Fact]
    public async Task NcApiProxy_CanList_ShareRoot_UsingPropfind()
    {
        using var http = CreateHttpClient();
        var runtime = await ReadRuntimeConfigAsync(http);

        var proxyBase = BuildProxyBase(runtime.BaseUrl);
        var rootPath = $"{proxyBase}/public.php/dav/files/{runtime.ShareToken}/";

        using var response = await SendPropfindAsync(http, rootPath);
        var body = await response.Content.ReadAsStringAsync();

        Assert.True((int)response.StatusCode is 200 or 207, $"Expected 200/207 from PROPFIND '{rootPath}', got {(int)response.StatusCode}. Body: {TrimForMessage(body)}");

        var names = ExtractDisplayNames(body);
        Assert.Contains("MetaData", names, StringComparer.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task NcApiProxy_CanList_MetaData_UsingPropfind()
    {
        using var http = CreateHttpClient();
        var runtime = await ReadRuntimeConfigAsync(http);

        var proxyBase = BuildProxyBase(runtime.BaseUrl);
        var metadataPath = runtime.MetadataPath.Trim('/');
        var listPath = $"{proxyBase}/public.php/dav/files/{runtime.ShareToken}/{metadataPath}/";

        using var response = await SendPropfindAsync(http, listPath);
        var body = await response.Content.ReadAsStringAsync();

        Assert.True((int)response.StatusCode is 200 or 207, $"Expected 200/207 from PROPFIND '{listPath}', got {(int)response.StatusCode}. Body: {TrimForMessage(body)}");

        var names = ExtractDisplayNames(body);
        Assert.Contains("consoles.json", names, StringComparer.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task NcApiProxy_CanResolveRomArchive_AndReachGeneratedRomUrl()
    {
        using var http = CreateHttpClient();
        var runtime = await ReadRuntimeConfigAsync(http);

        var proxyBase = BuildProxyBase(runtime.BaseUrl);
        var rootPath = $"{proxyBase}/public.php/dav/files/{runtime.ShareToken}/";

        using var rootResponse = await SendPropfindAsync(http, rootPath);
        var rootXml = await rootResponse.Content.ReadAsStringAsync();
        Assert.True((int)rootResponse.StatusCode is 200 or 207, $"Expected 200/207 from PROPFIND '{rootPath}', got {(int)rootResponse.StatusCode}. Body: {TrimForMessage(rootXml)}");

        var rootEntries = ExtractEntries(rootXml);
        var metadataFolder = runtime.MetadataPath.Trim('/');

        // Prefer a ROM archive directly under root (Game); otherwise look one level deep in root folders.
        var directRom = rootEntries.FirstOrDefault(e => !e.IsDirectory && HasRomExtension(e.Name));
        string? romRelativePath = directRom?.RelativePath;

        if (string.IsNullOrWhiteSpace(romRelativePath))
        {
            foreach (var dir in rootEntries.Where(e => e.IsDirectory && !string.Equals(e.Name, metadataFolder, StringComparison.OrdinalIgnoreCase)))
            {
                var dirPath = $"{proxyBase}/public.php/dav/files/{runtime.ShareToken}/{EncodePath(dir.RelativePath)}/";
                using var dirResponse = await SendPropfindAsync(http, dirPath);
                if ((int)dirResponse.StatusCode is not 200 and not 207)
                {
                    continue;
                }

                var dirXml = await dirResponse.Content.ReadAsStringAsync();
                var dirEntries = ExtractEntries(dirXml);
                var romInDir = dirEntries.FirstOrDefault(e => !e.IsDirectory && HasRomExtension(e.Name));
                if (romInDir is null)
                {
                    continue;
                }

                romRelativePath = romInDir.RelativePath;
                break;
            }
        }

        Assert.False(string.IsNullOrWhiteSpace(romRelativePath), "Expected to find at least one ROM archive in share root or a first-level ROM folder.");

        var generatedRomUrl = $"{proxyBase}/public.php/dav/files/{runtime.ShareToken}/{EncodePath(romRelativePath!)}";
        using var request = new HttpRequestMessage(HttpMethod.Get, generatedRomUrl);
        request.Headers.Range = new System.Net.Http.Headers.RangeHeaderValue(0, 0);

        using var romResponse = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead);
        Assert.True(
            romResponse.IsSuccessStatusCode || (int)romResponse.StatusCode == 206,
            $"Expected ROM URL to be reachable for '{generatedRomUrl}', got {(int)romResponse.StatusCode}.");
    }

    private static HttpClient CreateHttpClient()
    {
        return new HttpClient
        {
            BaseAddress = BaseUri,
            Timeout = TimeSpan.FromSeconds(20)
        };
    }

    private static async Task<HttpResponseMessage> SendPropfindAsync(HttpClient http, string path)
    {
        using var request = new HttpRequestMessage(new HttpMethod("PROPFIND"), path)
        {
            Content = new StringContent(
                """
                <?xml version="1.0" encoding="utf-8"?>
                <d:propfind xmlns:d="DAV:">
                    <d:prop>
                        <d:displayname/>
                        <d:resourcetype/>
                    </d:prop>
                </d:propfind>
                """,
                System.Text.Encoding.UTF8,
                "application/xml")
        };
        request.Headers.Add("Depth", "1");

        return await http.SendAsync(request);
    }

    private static HashSet<string> ExtractDisplayNames(string xml)
    {
        return ExtractEntries(xml)
            .Select(e => e.Name)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
    }

    private static List<DavEntry> ExtractEntries(string xml)
    {
        XNamespace dav = "DAV:";
        var doc = XDocument.Parse(xml);
        var entries = new List<DavEntry>();

        foreach (var response in doc.Descendants(dav + "response").Skip(1))
        {
            var href = (response.Element(dav + "href")?.Value ?? string.Empty).Trim();
            var displayName = (response.Descendants(dav + "displayname").FirstOrDefault()?.Value ?? string.Empty).Trim();
            var isDirectory = response.Descendants(dav + "collection").Any();

            var relativePath = string.Empty;
            var marker = "/public.php/dav/files/";
            var markerIndex = href.IndexOf(marker, StringComparison.OrdinalIgnoreCase);
            if (markerIndex >= 0)
            {
                var afterMarker = href[(markerIndex + marker.Length)..];
                var slash = afterMarker.IndexOf('/');
                relativePath = slash >= 0 ? afterMarker[(slash + 1)..] : string.Empty;
            }

            relativePath = Uri.UnescapeDataString(relativePath).Trim('/');
            if (string.IsNullOrWhiteSpace(relativePath))
            {
                continue;
            }

            var name = !string.IsNullOrWhiteSpace(displayName)
                ? displayName
                : relativePath.Split('/').Last();

            entries.Add(new DavEntry(name, relativePath, isDirectory));
        }

        return entries;
    }

    private static bool HasRomExtension(string fileName)
    {
        return RomExtensions.Any(ext => fileName.EndsWith(ext, StringComparison.OrdinalIgnoreCase));
    }

    private static string EncodePath(string rawPath)
    {
        var normalized = Uri.UnescapeDataString(rawPath).Trim('/');
        return string.Join('/', normalized.Split('/').Select(Uri.EscapeDataString));
    }

    private static async Task<RuntimeConfig> ReadRuntimeConfigAsync(HttpClient http)
    {
        var json = await http.GetStringAsync("runtime-config.json");
        using var doc = JsonDocument.Parse(json);

        var nextcloud = doc.RootElement.GetProperty("Nextcloud");

        return new RuntimeConfig
        {
            BaseUrl = nextcloud.GetProperty("BaseUrl").GetString() ?? "nc-api",
            ShareToken = nextcloud.GetProperty("ShareToken").GetString() ?? "",
            MetadataPath = nextcloud.GetProperty("MetadataPath").GetString() ?? "MetaData",
        };
    }

    private static string BuildProxyBase(string rawBaseUrl)
    {
        if (string.IsNullOrWhiteSpace(rawBaseUrl))
        {
            return "nc-api";
        }

        if (Uri.TryCreate(rawBaseUrl, UriKind.Absolute, out _))
        {
            return rawBaseUrl.TrimEnd('/');
        }

        return rawBaseUrl.Trim('/');
    }

    private static string TrimForMessage(string value)
    {
        if (string.IsNullOrEmpty(value) || value.Length <= 300)
        {
            return value;
        }

        return value[..300] + "...";
    }

    private sealed class RuntimeConfig
    {
        public string BaseUrl { get; init; } = "nc-api";
        public string ShareToken { get; init; } = "";
        public string MetadataPath { get; init; } = "MetaData";
    }

    private sealed record DavEntry(string Name, string RelativePath, bool IsDirectory);
}
