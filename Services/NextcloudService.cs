using System.Text;
using System.Xml.Linq;
using Assemulator.Models;
using Microsoft.Extensions.Configuration;

namespace Assemulator.Services;

public class NextcloudService : INextcloudService
{
    private readonly HttpClient _http;
    private readonly string _baseUrl;
    private readonly string _shareToken;

    public NextcloudService(HttpClient http, IConfiguration config)
    {
        _http = http;
        _baseUrl = config["Nextcloud:BaseUrl"] ?? "https://tools.kushkurriculum.org/nextcloud";
        _shareToken = config["Nextcloud:ShareToken"] ?? "";
    }

    public string BuildPublicFileUrl(string filename)
    {
        var safeFilename = Uri.EscapeDataString(filename);
        return $"/nc-api/public.php/dav/files/{_shareToken}/{safeFilename}";
    }

    public async Task<List<RomInfo>> ListRomsAsync(string folder, string extension)
    {
        // public.php/webdav requires Basic auth with the share token as username (no password).
        // The folder path under files/ is accepted but all paths currently resolve to the
        // share root ("Game"), so the folder param effectively just namespaces the URL.
        var webDavUrl = $"{_baseUrl}/public.php/webdav/files/{folder.Trim('/')}/";

        var request = new HttpRequestMessage(new HttpMethod("PROPFIND"), webDavUrl);
        request.Headers.Add("Depth", "1");

        var authValue = Convert.ToBase64String(Encoding.ASCII.GetBytes($"{_shareToken}:"));
        request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Basic", authValue);

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
            Encoding.UTF8, "application/xml");

        try
        {
            var response = await _http.SendAsync(request);
            if (!response.IsSuccessStatusCode) return [];

            var xml = await response.Content.ReadAsStringAsync();
            return ParsePropfindResponse(xml, folder, extension);
        }
        catch
        {
            return [];
        }
    }

    private List<RomInfo> ParsePropfindResponse(string xml, string folder, string extension)
    {
        XNamespace dav = "DAV:";
        var doc = XDocument.Parse(xml);
        var roms = new List<RomInfo>();

        // Skip(1) because the first response entry is the folder itself
        foreach (var responseEl in doc.Descendants(dav + "response").Skip(1))
        {
            // Skip collections (sub-directories)
            if (responseEl.Descendants(dav + "collection").Any()) continue;

            var href = responseEl.Element(dav + "href")?.Value ?? "";
            var displayName = responseEl.Descendants(dav + "displayname").FirstOrDefault()?.Value ?? "";

            // Fall back to the last path segment if displayname is empty
            var filename = !string.IsNullOrEmpty(displayName)
                ? displayName
                : Uri.UnescapeDataString(href.TrimEnd('/').Split('/').Last());

            if (!filename.EndsWith(extension, StringComparison.OrdinalIgnoreCase)) continue;

            roms.Add(new RomInfo
            {
                Name = ToDisplayName(filename),
                FileName = filename,
                // Default romset name = filename without extension, lowercased
                // Override in roms.json for files with human-readable names (e.g. "pc_mtpo" for Punch-Out PC10)
                RomsetName = Path.GetFileNameWithoutExtension(filename).ToLower(),
                Url = BuildPublicFileUrl(filename),
            });
        }

        return roms;
    }

    private static string ToDisplayName(string filename)
    {
        var name = Path.GetFileNameWithoutExtension(filename);
        name = name.Replace('-', ' ').Replace('_', ' ');
        return System.Globalization.CultureInfo.InvariantCulture.TextInfo.ToTitleCase(name.ToLower());
    }
}
