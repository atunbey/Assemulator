namespace Assemulator.Models;

/// <summary>
/// Describes a single ROM file inside an archive ZIP.
///
/// For console emulators (NES, SNES, etc.): one entry per regional ROM file in the ZIP,
///   e.g. "Contra (USA).nes" and "Contra (Japan).nes" might share one archive.
///
/// For FBNeo/MAME arcade ZIPs: the files are internal chip dumps consumed by the core
///   automatically — list them here for documentation/info purposes only.
/// </summary>
public class RomFileEntry
{
    /// <summary>Exact filename inside the ZIP, e.g. "Contra (USA).nes", "prg0.bin"</summary>
    public string Filename { get; set; } = "";

    /// <summary>Human-readable description, e.g. "USA release", "Japan (Rev A)", "Program ROM chip"</summary>
    public string Description { get; set; } = "";

    /// <summary>
    /// Core needed to run this specific file (e.g. "nes", "fbneo").
    /// Usually matches the parent variant's CoreOverride — set explicitly when different.
    /// Empty = inherit from variant.
    /// </summary>
    public string Core { get; set; } = "";
}
