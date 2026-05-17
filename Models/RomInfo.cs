namespace Assemulator.Models;

public class RomInfo
{
    public string Name { get; set; } = "";
    public string FileName { get; set; } = "";
    /// <summary>
    /// MAME/FBNeo romset short name (e.g. "galaga", "pc_mtpo").
    /// Overrides the filename-derived name sent to the emulator core as EJS_gameName.
    /// Can be set manually in a roms.json manifest.
    /// </summary>
    public string RomsetName { get; set; } = "";

    /// <summary>
    /// Controls whether romsetName is passed to the core as EJS_gameName.
    /// Values: "auto" (core default), "require" (always send), "omit" (never send).
    /// </summary>
    public string RomsetMode { get; set; } = "auto";
    public string Url { get; set; } = "";
    public string CoverUrl { get; set; } = "";
    public string BackgroundUrl { get; set; } = "";
    public string Platform { get; set; } = "";
    public string Description { get; set; } = "";
    public int Year { get; set; }
    public string Genre { get; set; } = "";
    public string Developer { get; set; } = "";
    public string Players { get; set; } = "1";
    /// <summary>
    /// Emulator core override for single-variant ROMs (e.g. "mame2003_plus", "snes").
    /// For multi-variant ROMs the core is stored per-variant in RomVariant.CoreOverride.
    /// </summary>
    public string CoreOverride { get; set; } = "";

    /// <summary>
    /// Optional BIOS file URL for this ROM. When set, overrides the console-level BiosUrl.
    /// Populated from the manifest variant's biosUrl field for single-variant ROMs.
    /// </summary>
    public string BiosUrl { get; set; } = "";

    /// <summary>
    /// Optional dependency archives (parent/board BIOS romsets) for this ROM.
    /// Used primarily by arcade cores such as FBNeo.
    /// </summary>
    public List<string> RequiredRomsets { get; set; } = [];

    /// <summary>
    /// Populated from manifest.json. When non-empty, clicking the card shows
    /// a version picker instead of launching immediately.
    /// </summary>
    public List<RomVariant> Variants { get; set; } = [];
}
