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
        _baseUrl = (config["Nextcloud:BaseUrl"] ?? "https://tools.kushkurriculum.org/nextcloud").TrimEnd('/');
        _shareToken = config["Nextcloud:ShareToken"] ?? "";
    }

    public string BuildPublicFileUrl(string filePath)
    {
        // Decode first (in case input is already partially URL-encoded), then encode each
        // path segment individually so that '/' separators are preserved.
        var decoded = Uri.UnescapeDataString(filePath.TrimStart('/'));
        var encodedPath = string.Join("/", decoded.Split('/').Select(Uri.EscapeDataString));
        return $"{_baseUrl}/public.php/dav/files/{_shareToken}/{encodedPath}";
    }

    public async Task<List<RomInfo>> ListRomsAsync(string folder, string extension)
    {
        var webDavUrl = $"{_baseUrl}/public.php/webdav/files/{folder.Trim('/')}/";

        var request = new HttpRequestMessage(new HttpMethod("PROPFIND"), webDavUrl);
        request.Headers.Add("Depth", "1");

        var authValue = Convert.ToBase64String(Encoding.ASCII.GetBytes($"{_shareToken}:"));
        request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Basic", authValue);

        request.Content = new StringContent(
            @"<?xml version=""1.0"" encoding=""utf-8""?>
            <d:propfind xmlns:d=""DAV:"">
                <d:prop>
                    <d:displayname/>
                    <d:resourcetype/>
                </d:prop>
            </d:propfind>",
            Encoding.UTF8, "application/xml");

        try
        {
            var response = await _http.SendAsync(request);
            if (!response.IsSuccessStatusCode) return new List<RomInfo>();

            var xml = await response.Content.ReadAsStringAsync();
            return ParsePropfindResponse(xml, folder, extension);
        }
        catch
        {
            return new List<RomInfo>();
        }
    }

    private List<RomInfo> ParsePropfindResponse(string xml, string folder, string extension)
    {
        XNamespace dav = "DAV:";
        var doc = XDocument.Parse(xml);
        var roms = new List<RomInfo>();

        foreach (var responseEl in doc.Descendants(dav + "response").Skip(1))
        {
            if (responseEl.Descendants(dav + "collection").Any()) continue;

            var href = responseEl.Element(dav + "href")?.Value ?? "";
            var displayName = responseEl.Descendants(dav + "displayname").FirstOrDefault()?.Value ?? "";

            var filename = !string.IsNullOrEmpty(displayName)
                ? displayName
                : Uri.UnescapeDataString(href.TrimEnd('/').Split('/').Last());

            if (!filename.EndsWith(extension, StringComparison.OrdinalIgnoreCase)) continue;

            roms.Add(new RomInfo
            {
                Name = ToDisplayName(filename),
                FileName = filename,
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