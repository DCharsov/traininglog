using System.Text.Json;

namespace TrainingLog;

public class WatchDevice {
    public string Id { get; set; } = "";
    public string Owner { get; set; } = "";
    public string TokenHash { get; set; } = "";
    public string Name { get; set; } = "";
    public long ExpiresAt { get; set; }
    public long? RevokedAt { get; set; }
    public long LastSeenAt { get; set; }
}
public class WatchPairing {
    public string Hash { get; set; } = "";
    public string Owner { get; set; } = "";
    public long ExpiresAt { get; set; }
    public bool Consumed { get; set; }
}
public class WatchControl {
    public string Owner { get; set; } = "";
    public string SessionId { get; set; } = "";
    public string State { get; set; } = "phone";
    public string? DeviceId { get; set; }
    public long Epoch { get; set; }
    public string? HandoffId { get; set; }
}
public class WatchRecovery {
    public string Id { get; set; } = "";
    public string Owner { get; set; } = "";
    public string SessionId { get; set; } = "";
    public string DeviceId { get; set; } = "";
    public string Payload { get; set; } = "";
    public long CreatedAt { get; set; }
}
public record WatchRedeem(string Code, string Name);
public record WatchCommand(string OperationId, string Generation, long BaseVersion, long ControlEpoch, string SessionId, string? DeviceId = null, string? HandoffId = null);
public record WatchWrite(string OperationId, string Generation, long BaseVersion, long ControlEpoch, JsonElement Payload, int ProtocolVersion = 0, int ContractVersion = 0);
public record WatchRecoveryWrite(string OperationId, string SessionId, JsonElement Payload);
// Only these endpoints bypass cookie CSRF. Their handlers require a valid device bearer.
public sealed class WatchBearerEndpoint;
public sealed class WatchRedeemEndpoint;
