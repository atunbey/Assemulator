namespace Assemulator.Models;

public class RomManifestEntry
{
    /// <summary>Canonical game title shown in the UI, e.g. "Mike Tyson's Punch-Out!!"</summary>
    public string OfficialName { get; set; } = "";

    /// <summary>Short synopsis shown in the game detail / variant picker</summary>
    public string Description { get; set; } = "";

    /// <summary>URL or local path to cover art image, e.g. "/images/covers/smb.jpg"</summary>
    public string CoverUrl { get; set; } = "";

    /// <summary>Platform label for this game, e.g. "Arcade", "Nintendo NES". Used to count games per platform card.</summary>
    public string Platform { get; set; } = "";

    /// <summary>
    /// All playable variants of this game.
    /// Each variant references one archive file (ZIP) and targets one emulator core.
    /// Different platforms (NES vs Arcade) or regions (USA vs Japan) are separate variants
    /// pointing to separate archive files — a single ZIP never spans multiple platforms.
    /// </summary>
    public List<RomVariant> Variants { get; set; } = [];
}
