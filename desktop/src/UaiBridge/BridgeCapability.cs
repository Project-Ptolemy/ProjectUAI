using System.Text.Json;

namespace ProjectUai.Bridge;

// A status badge must belong to a supported capability in the current reply.
// Missing or malformed data never retains readiness from an earlier connection.
internal sealed record BridgeCapability(string State, string? Message, string? Version)
{
    internal static BridgeCapability? Read(JsonElement value, params string[] states)
    {
        if (value.ValueKind != JsonValueKind.Object || !value.TryGetProperty("schema", out var schema) ||
            schema.ValueKind != JsonValueKind.Number || !schema.TryGetInt32(out int version) || version != 1) return null;
        string? state = Text(value, "state", 40);
        if (state is null || !states.Contains(state, StringComparer.Ordinal)) return null;
        if (state == "ready" && (!value.TryGetProperty("enabled", out var enabled) || enabled.ValueKind != JsonValueKind.True ||
            !value.TryGetProperty("available", out var available) || available.ValueKind != JsonValueKind.True)) return null;
        return new(state, Text(value, "message", 400), Text(value, "version", 80));
    }

    private static string? Text(JsonElement value, string name, int limit)
    {
        if (!value.TryGetProperty(name, out var item) || item.ValueKind != JsonValueKind.String) return null;
        string text = item.GetString() ?? "";
        int length = Math.Min(text.Length, limit);
        if (length > 0 && length < text.Length && char.IsHighSurrogate(text[length - 1])) length--;
        return text[..length];
    }
}
