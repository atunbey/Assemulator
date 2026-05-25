using Assemulator.Models;

namespace Assemulator.Services;

public interface INextcloudService
{
    Task<List<NextcloudDirectoryEntry>> ListDirectoryAsync(string relativePath = "");
    Task<string?> ReadTextFileAsync(string relativePath);
    Task<List<RomInfo>> ListRomsAsync(string folder, string extension);
    string BuildPublicFileUrl(string relativePath);
    string BuildMetadataFileUrl(string relativePath);
}

public sealed class NextcloudDirectoryEntry
{
    public string Name { get; set; } = "";
    public string RelativePath { get; set; } = "";
    public bool IsDirectory { get; set; }
}
