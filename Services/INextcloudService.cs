using Assemulator.Models;

namespace Assemulator.Services;

public interface INextcloudService
{
    Task<List<RomInfo>> ListRomsAsync(string folder, string extension);
    string BuildPublicFileUrl(string filename);
}
