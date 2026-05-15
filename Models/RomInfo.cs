namespace Assemulator.Models;

public class RomInfo
{
    public string Name { get; set; } = "";
    public string FileName { get; set; } = "";
    public string Url { get; set; } = "";
    public string CoverUrl { get; set; } = "";
    public string BackgroundUrl { get; set; } = "";
    public string Description { get; set; } = "";
    public int Year { get; set; }
    public string Genre { get; set; } = "";
    public string Developer { get; set; } = "";
    public string Players { get; set; } = "1";
}
