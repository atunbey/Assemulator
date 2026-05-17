namespace Assemulator.Models;

public class ConsoleInfo
{
    public string Id { get; set; } = "";
    public string Name { get; set; } = "";
    public string Manufacturer { get; set; } = "";
    public string EmulatorCore { get; set; } = "";
    public string RomExtension { get; set; } = "";
    public string ImageUrl { get; set; } = "";
    public string BackgroundColor { get; set; } = "#1a1a2e";
    public string AccentColor { get; set; } = "#e50914";
    public string RomManifestUrl { get; set; } = "";
    public string NextcloudFolder { get; set; } = "";
    public string BiosUrl { get; set; } = "";
    public int Year { get; set; }
    public string Description { get; set; } = "";
    /// <summary>Platform label matched against RomManifestEntry.Platform / RomInfo.Platform to count games on this card.</summary>
    public string Platform { get; set; } = "";
}
