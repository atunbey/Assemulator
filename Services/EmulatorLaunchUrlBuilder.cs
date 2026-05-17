namespace Assemulator.Services;

public static class EmulatorLaunchUrlBuilder
{
    public static string Build(
        string consoleId,
        string romUrl,
        string defaultCore,
        string? coreOverride,
        string? romsetName,
        string? romsetMode,
        string? biosUrl,
        IEnumerable<string>? requiredRomsets,
        string? returnTo = null)
    {
        var core = ResolveCore(defaultCore, coreOverride);
        var encodedRomUrl = Uri.EscapeDataString(romUrl ?? "");
        var query = new List<string>();

        // Always include core so launch behavior stays deterministic even if defaults change.
        if (!string.IsNullOrWhiteSpace(core))
            query.Add($"core={Uri.EscapeDataString(core)}");

        if (ShouldSendRomset(core, romsetName, romsetMode))
            query.Add($"romset={Uri.EscapeDataString(romsetName!)}");

        if (!string.IsNullOrWhiteSpace(biosUrl))
            query.Add($"bios={Uri.EscapeDataString(biosUrl)}");

        var req = NormalizeRequiredRomsets(requiredRomsets);
        if (!string.IsNullOrWhiteSpace(req))
            query.Add($"req={Uri.EscapeDataString(req)}");

        var normalizedReturn = NormalizeReturnTo(returnTo);
        if (!string.IsNullOrWhiteSpace(normalizedReturn))
            query.Add($"return={Uri.EscapeDataString(normalizedReturn)}");

        var url = $"/play/{consoleId}/{encodedRomUrl}";
        if (query.Count > 0)
            url += "?" + string.Join('&', query);

        return url;
    }

    public static string ResolveCore(string defaultCore, string? coreOverride)
    {
        return !string.IsNullOrWhiteSpace(coreOverride) ? coreOverride : (defaultCore ?? "");
    }

    public static bool ShouldSendRomset(string core, string? romsetName, string? romsetMode)
    {
        if (string.IsNullOrWhiteSpace(romsetName) || romsetName == "-none-")
            return false;

        var mode = (romsetMode ?? "auto").Trim().ToLowerInvariant();
        if (mode is "omit" or "none")
            return false;
        if (mode is "require" or "required" or "always")
            return true;

        var normalizedCore = (core ?? "").Trim().ToLowerInvariant();
        return normalizedCore == "fbneo";
    }

    private static string NormalizeRequiredRomsets(IEnumerable<string>? requiredRomsets)
    {
        if (requiredRomsets is null)
            return "";

        return string.Join(',', requiredRomsets
            .Where(s => !string.IsNullOrWhiteSpace(s))
            .Select(s => s.Trim())
            .Distinct(StringComparer.OrdinalIgnoreCase));
    }

    private static string NormalizeReturnTo(string? returnTo)
    {
        if (string.IsNullOrWhiteSpace(returnTo))
            return "";

        var trimmed = returnTo.Trim();

        // Prevent open redirects and keep return navigation inside this app.
        if (!trimmed.StartsWith('/'))
            return "";
        if (trimmed.StartsWith("//", StringComparison.Ordinal))
            return "";

        return trimmed;
    }
}
