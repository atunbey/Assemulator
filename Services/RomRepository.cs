using System.Net.Http.Json;
using Assemulator.Models;

namespace Assemulator.Services;

public class RomRepository : IRomRepository
{
    private readonly HttpClient _http;
    private List<ConsoleInfo>? _consolesCache;

    public RomRepository(HttpClient http)
    {
        _http = http;
    }

    public async Task<List<ConsoleInfo>> GetConsolesAsync()
    {
        if (_consolesCache is not null)
            return _consolesCache;

        var result = await _http.GetFromJsonAsync<List<ConsoleInfo>>("data/consoles.json");
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
}
