using System.Net.Http.Json;
using Assemulator.Models;

namespace Assemulator.Services;

public class RomRepository : IRomRepository
{
    private readonly HttpClient _http;
    private readonly INextcloudService _nextcloud;
    private List<ConsoleInfo>? _consolesCache;

    public RomRepository(HttpClient http, INextcloudService nextcloud)
    {
        _http = http;
        _nextcloud = nextcloud;
    }

    public async Task<List<ConsoleInfo>> GetConsolesAsync()
    {
        if (_consolesCache is not null)
            return _consolesCache;

        var result = await _http.GetFromJsonAsync<List<ConsoleInfo>>(_nextcloud.BuildMetadataFileUrl("consoles.json"));
        _consolesCache = result ?? [];
        return _consolesCache;
    }

    public async Task<List<RomInfo>> GetRomsAsync(string romManifestUrl)
    {
        try
        {
            // Supports both relative paths (local data/) and absolute URLs (Nextcloud, CDN, etc.)
            var result = await _http.GetFromJsonAsync<List<RomInfo>>(romManifestUrl);
            return result ?? [];
        }
        catch
        {
            return [];
        }
    }

    /// <summary>
    /// Loads the unified data/manifest.json. All per-system entries live here,
    /// each tagged with a "platform" field matching ConsoleInfo.Platform.
    /// Note: No caching - always fetch fresh to support live updates during development.
    /// </summary>
    public async Task<List<RomManifestEntry>> GetAllManifestEntriesAsync()
    {
        try
        {
            var result = await _http.GetFromJsonAsync<List<RomManifestEntry>>(_nextcloud.BuildMetadataFileUrl("manifest.json"));
            return result ?? [];
        }
        catch
        {
            return [];
        }
    }

    /// <summary>
    /// Returns manifest entries for the given console, filtered by its Platform label.
    /// </summary>
    public async Task<List<RomManifestEntry>> GetManifestAsync(string consoleId)
    {
        var consoles = await GetConsolesAsync();
        var console = consoles.FirstOrDefault(c => c.Id == consoleId);
        if (console is null || string.IsNullOrEmpty(console.Platform))
            return [];

        var all = await GetAllManifestEntriesAsync();
        return all
            .Where(e => string.Equals(e.Platform, console.Platform, StringComparison.OrdinalIgnoreCase))
            .ToList();
    }

    /// <summary>
    /// Returns the number of manifest entries for the given console platform.
    /// </summary>
    public async Task<int> GetRomCountAsync(string consoleId)
    {
        var entries = await GetManifestAsync(consoleId);
        return entries.Count;
    }
}
