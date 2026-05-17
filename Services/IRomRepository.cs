using Assemulator.Models;

namespace Assemulator.Services;

public interface IRomRepository
{
    Task<List<ConsoleInfo>> GetConsolesAsync();
    Task<List<RomInfo>> GetRomsAsync(string romManifestUrl);
    Task<List<RomManifestEntry>> GetAllManifestEntriesAsync();
    Task<List<RomManifestEntry>> GetManifestAsync(string consoleId);
    Task<int> GetRomCountAsync(string consoleId);
}
