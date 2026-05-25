using System.Xml.Linq;
using Assemulator.Models;
using Microsoft.Extensions.Configuration;

namespace Assemulator.Services;

public class NextcloudService : INextcloudService
{
    private readonly HttpClient _http;
    private readonly string _baseUrl;
    private readonly string _shareToken;
    private readonly string _metadataPath;

    public NextcloudService(HttpClient http, IConfiguration config)
    {
        _http = http;
        _baseUrl = (config["Nextcloud:BaseUrl"] ?? "https://tools.kushkurriculum.org/nextcloud").TrimEnd('/');
        _shareToken = config["Nextcloud:ShareToken"] ?? "";
        _metadataPath = (config["Nextcloud:MetadataPath"] ?? "MetaData").Trim('/');
    }

    public string BuildPublicFileUrl(string relativePath)
    {
        var encodedPath = EncodePath(relativePath);
        if (string.IsNullOrEmpty(encodedPath))
            return $"{_baseUrl}/public.php/dav/files/{_shareToken}";

        return $"{_baseUrl}/public.php/dav/files/{_shareToken}/{encodedPath}";
    }

    public string BuildMetadataFileUrl(string relativePath)
    {
        var normalized = NormalizePath(relativePath);
        if (string.IsNullOrWhiteSpace(normalized))
            return BuildPublicFileUrl(_metadataPath);

        return BuildPublicFileUrl($"{_metadataPath}/{normalized}");
    }

    public async Task<string?> ReadTextFileAsync(string relativePath)
    {
        try
        {
            using var response = await _http.GetAsync(BuildPublicFileUrl(relativePath));
            if (!response.IsSuccessStatusCode)
                return null;

            return await response.Content.ReadAsStringAsync();
        }
        catch
        {
            return null;
        }
    }

    public async Task<List<NextcloudDirectoryEntry>> ListDirectoryAsync(string relativePath = "")
    {
        var request = new HttpRequestMessage(new HttpMethod("PROPFIND"), BuildPublicFileUrl(relativePath));
        request.Headers.Add("Depth", "1");
        request.Content = new StringContent(
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
            "application/xml");

        try
        {
            using var response = await _http.SendAsync(request);
            if (!response.IsSuccessStatusCode)
                return [];

            var xml = await response.Content.ReadAsStringAsync();
            return ParseDirectoryListing(xml);
        }
        catch
        {
            return [];
        }
    }

    public async Task<List<RomInfo>> ListRomsAsync(string folder, string extension)
    {
        var entries = await ListDirectoryAsync(folder);
        return entries
            .Where(e => !e.IsDirectory)
            .Where(e => e.Name.EndsWith(extension, StringComparison.OrdinalIgnoreCase))
            .Select(e => new RomInfo
            {
                Name = ToDisplayName(e.Name),
                FileName = e.Name,
                RomsetName = Path.GetFileNameWithoutExtension(e.Name).ToLowerInvariant(),
                Url = BuildPublicFileUrl(e.RelativePath),
            })
            .ToList();
    }

    private List<NextcloudDirectoryEntry> ParseDirectoryListing(string xml)
    {
        XNamespace dav = "DAV:";
        var doc = XDocument.Parse(xml);
        var entries = new List<NextcloudDirectoryEntry>();
        var rootPrefix = $"/public.php/dav/files/{_shareToken}/";
        var rootPrefixNoSlash = $"/public.php/dav/files/{_shareToken}";

        foreach (var responseEl in doc.Descendants(dav + "response").Skip(1))
        {
            var href = responseEl.Element(dav + "href")?.Value ?? "";
            var displayName = responseEl.Descendants(dav + "displayname").FirstOrDefault()?.Value ?? "";
            var isDirectory = responseEl.Descendants(dav + "collection").Any();

            var relativePath = "";
            if (href.StartsWith(rootPrefix, StringComparison.OrdinalIgnoreCase))
                relativePath = href[rootPrefix.Length..];
            else if (href.StartsWith(rootPrefixNoSlash, StringComparison.OrdinalIgnoreCase))
                relativePath = href[rootPrefixNoSlash.Length..].TrimStart('/');

            var decodedRelativePath = Uri.UnescapeDataString(relativePath).Trim('/');
            if (string.IsNullOrWhiteSpace(decodedRelativePath))
                continue;

            var name = !string.IsNullOrWhiteSpace(displayName)
                ? displayName
                : decodedRelativePath.Split('/').Last();

            entries.Add(new NextcloudDirectoryEntry
            {
                Name = name,
                RelativePath = decodedRelativePath,
                IsDirectory = isDirectory,
            });
        }

        return entries;
    }

    private static string NormalizePath(string rawPath)
    {
        if (string.IsNullOrWhiteSpace(rawPath))
            return "";

        return Uri.UnescapeDataString(rawPath).Trim().Trim('/');
    }

    private static string EncodePath(string rawPath)
    {
        var normalized = NormalizePath(rawPath);
        if (string.IsNullOrEmpty(normalized))
            return "";

        return string.Join('/', normalized.Split('/').Select(Uri.EscapeDataString));
    }

    private static string ToDisplayName(string filename)
    {
        var name = Path.GetFileNameWithoutExtension(filename);
        name = name.Replace('-', ' ').Replace('_', ' ');
        return System.Globalization.CultureInfo.InvariantCulture.TextInfo.ToTitleCase(name.ToLower());
    }
}