using Assemulator.Models;

namespace Assemulator.Services;

public interface IRomRepository
{
    Task<List<ConsoleInfo>> GetConsolesAsync();
    Task<List<RomInfo>> GetRomsAsync(string romManifestUrl);
}
