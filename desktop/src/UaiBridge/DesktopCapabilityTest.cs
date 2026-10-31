using System.Text.Json;

namespace ProjectUai.Bridge;

// No bridge process or provider request is started by these capability fixtures.
internal static class DesktopCapabilityTest
{
    internal static async Task RunAsync(Action<string, bool> check)
    {
        await using var bridge = new BridgeProcess();
        using var ready = JsonDocument.Parse("""{"schema":1,"enabled":true,"available":true,"state":"ready","version":"2.17.0"}""");
        foreach (string invalid in new[] { "{}", "null", "[]", """{"schema":2,"state":"ready"}""",
            """{"schema":1,"state":"ready","enabled":false,"available":true}""",
            """{"schema":1,"state":"ready","enabled":true,"available":false}""",
            """{"schema":1,"state":"future-state"}""", """{"schema":1,"state":7}""" })
        {
            bridge.ApplyOpenCodeCapability(ready.RootElement);
            bridge.ApplyKiloCapability(ready.RootElement);
            check("Current supported capabilities can show readiness", bridge.OpenCodeState == "ready" && bridge.KiloState == "ready");
            using var value = JsonDocument.Parse(invalid);
            bridge.ApplyOpenCodeCapability(value.RootElement);
            bridge.ApplyKiloCapability(value.RootElement);
            check("Missing or malformed capability removes stale readiness: " + invalid,
                bridge.OpenCodeState == "unavailable" && bridge.OpenCodeVersion is null && bridge.KiloState == "unavailable");
        }
        using var standby = JsonDocument.Parse("""{"schema":1,"enabled":true,"available":false,"state":"standby"}""");
        bridge.ApplyKiloCapability(standby.RootElement);
        check("Kilo standby does not require an already running helper", bridge.KiloState == "standby" && bridge.KiloDetail.Contains("quota", StringComparison.Ordinal));
        string longMessage = new string('m', 399) + char.ConvertFromUtf32(0x1f600) + "tail";
        using var longCapability = JsonDocument.Parse(JsonSerializer.Serialize(new { schema = 1, enabled = true, available = false,
            state = "failed", message = longMessage, version = new string('v', 100) }));
        bridge.ApplyOpenCodeCapability(longCapability.RootElement);
        check("Capability details are bounded without bisecting a Unicode character", bridge.OpenCodeMessage?.Length == 399 && bridge.OpenCodeVersion?.Length == 80);
        bridge.ApplyOpenCodeCapability(ready.RootElement);
        await bridge.StopAsync();
        check("Stopping removes the previous OpenCode version and readiness", bridge.OpenCodeState == "stopped" && bridge.OpenCodeVersion is null);
    }
}
