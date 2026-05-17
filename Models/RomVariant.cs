using System.Text.Json.Serialization;

namespace Assemulator.Models;

public class RomVariant
{
    /// <summary>Display label, e.g. "USA", "Japan (Rev A)", "Arcade (FBNeo)"</summary>
    public string Label { get; set; } = "";

    /// <summary>Region tag, e.g. "USA", "Japan", "Europe", "World"</summary>
    public string Region { get; set; } = "";

    /// <summary>Filename in Nextcloud (or local folder) to download, e.g. "galaga.zip"</summary>
    public string ArchiveFile { get; set; } = "";

    /// <summary>MAME/FBNeo romset short name sent as EJS_gameName, e.g. "galaga", "pc_mtpo"</summary>
    public string RomsetName { get; set; } = "";

    /// <summary>
    /// Controls whether the launcher should pass romset as EJS_gameName.
    /// Values: "auto" (core default), "require" (always send), "omit" (never send).
    /// </summary>
    public string RomsetMode { get; set; } = "auto";

    /// <summary>Optional core override (e.g. "nes") — if empty, the console default core is used</summary>
    public string CoreOverride { get; set; } = "";

    /// <summary>
    /// Optional BIOS file URL for this specific variant. When set, overrides the console-level BiosUrl.
    /// Required for some arcade games, e.g. playch10.zip for PlayChoice-10 ROMs.
    /// </summary>
    public string BiosUrl { get; set; } = "";

    /// <summary>
    /// Files contained within the archive ZIP.
    /// For arcade/FBNeo: chip dump filenames (informational; the core consumes the whole ZIP).
    /// For console emulators: individual ROM files, e.g. regional variants in a multi-ROM ZIP.
    /// Leave empty for simple single-file ZIPs — the emulator auto-selects the ROM.
    /// </summary>
    public List<RomFileEntry> Files { get; set; } = [];

    /// <summary>
    /// Optional dependency archives (e.g. parent or board BIOS romsets) required by this variant.
    /// Entries are archive filenames such as "neogeo.zip" or "qsound.zip".
    /// </summary>
    public List<string> RequiredRomsets { get; set; } = [];

    /// <summary>Populated at runtime from Nextcloud; not stored in manifest.json</summary>
    [JsonIgnore]
    public string Url { get; set; } = "";
}
