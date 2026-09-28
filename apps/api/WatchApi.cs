using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.EntityFrameworkCore;

namespace TrainingLog;

public static class WatchApi {
    static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    static long Now => DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
    static string Hash(string text) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(text)));
    static IResult Error(int status, string error, string message = "") => Results.Json(new { error, message }, statusCode: status);
    static string Owner(HttpContext c) => c.User.FindFirstValue(ClaimTypes.NameIdentifier)!;
    static bool Enabled(HttpContext c) => c.RequestServices.GetRequiredService<IConfiguration>().GetValue<bool>("Watch:Enabled");
    static async Task<string> Generation(Store db) => (await db.Settings.FindAsync("generation"))!.Value;
    static object Control(WatchControl? control) => new {
        state = control?.State ?? "phone", deviceId = control?.DeviceId,
        controlEpoch = control?.Epoch ?? 0, handoffId = control?.HandoffId
    };
    static object Snapshot(Document doc, WatchControl? control, string generation) => new {
        protocolVersion = 1, contractVersion = 2, sessionId = doc.Id, version = doc.Version, generation,
        control = Control(control), payload = JsonSerializer.Deserialize<JsonElement>(doc.Payload)
    };

    static async Task<IResult> Locked(HttpContext c, Store db, Func<Task<IResult>> work) {
        var gate = c.RequestServices.GetRequiredService<DocumentWriter>().Gate;
        await gate.WaitAsync(c.RequestAborted);
        try {
            await using var tx = await db.Database.BeginTransactionAsync(c.RequestAborted);
            var result = await work();
            await db.SaveChangesAsync(c.RequestAborted);
            await tx.CommitAsync(c.RequestAborted);
            return result;
        } finally { gate.Release(); }
    }

    static async Task<WatchDevice?> Authenticate(HttpContext c, Store db) {
        var header = c.Request.Headers.Authorization.ToString();
        if (!header.StartsWith("Bearer ", StringComparison.Ordinal) || header.Length > 200) return null;
        var hash = Hash(header[7..]);
        var device = await db.WatchDevices.SingleOrDefaultAsync(x => x.TokenHash == hash && x.RevokedAt == null && x.ExpiresAt > Now);
        if (device != null) device.LastSeenAt = Now;
        return device;
    }

    static async Task<IResult?> Replay(Store db, string owner, string operationId, string hash) {
        var existing = await db.Operations.FindAsync(owner, operationId);
        return existing == null ? null : existing.Hash == hash ? Results.Content(existing.Response, "application/json") : Error(409, "operation_reused");
    }
    static IResult Receipt(Store db, string owner, string operationId, string hash, object value) {
        var response = JsonSerializer.Serialize(value, Json);
        db.Operations.Add(new() { Owner = owner, Id = operationId, Hash = hash, Response = response });
        return Results.Content(response, "application/json");
    }
    static void Archive(Store db, Document doc, string deviceId) => db.WatchRecoveries.Add(new() {
        Id = Guid.NewGuid().ToString(), Owner = doc.Owner, SessionId = doc.Id,
        DeviceId = deviceId, Payload = doc.Payload, CreatedAt = Now
    });

    public static void MapWatchApi(this RouteGroupBuilder api) {
        api.MapPost("/watch/pairing", (HttpContext c, Store db) => Locked(c, db, async () => {
            if (!Enabled(c)) return Error(503, "watch_disabled", "Подключение часов пока выключено.");
            var owner = Owner(c);
            // One live code per owner. Codes and tokens are never logged or stored in plaintext.
            await db.WatchPairings.Where(x => x.Owner == owner || x.ExpiresAt <= Now).ExecuteDeleteAsync();
            string code, hash;
            do { code = RandomNumberGenerator.GetInt32(0, 100_000_000).ToString("D8"); hash = Hash(code); }
            while (await db.WatchPairings.AnyAsync(x => x.Hash == hash));
            var expiresAt = Now + 5 * 60_000;
            db.WatchPairings.Add(new() { Hash = hash, Owner = owner, ExpiresAt = expiresAt });
            return Results.Ok(new { code, expiresAt });
        })).RequireAuthorization();

        api.MapPost("/watch/pairing/redeem", (WatchRedeem r, HttpContext c, Store db) => Locked(c, db, async () => {
            if (!Enabled(c)) return Error(503, "watch_disabled");
            if (r.Code == null || !System.Text.RegularExpressions.Regex.IsMatch(r.Code, "^[0-9]{8}$") || string.IsNullOrWhiteSpace(r.Name) || r.Name.Length > 100) return Error(400, "validation");
            var code = await db.WatchPairings.FindAsync(Hash(r.Code));
            if (code == null || code.Consumed || code.ExpiresAt <= Now) return Error(400, "invalid_pairing", "Код неверен или истёк. Создайте новый код на телефоне.");
            if (await db.WatchDevices.CountAsync(x => x.Owner == code.Owner && x.RevokedAt == null && x.ExpiresAt > Now) >= 10) return Error(409, "device_limit", "Отзовите неиспользуемые подключения.");
            var token = Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
            var device = new WatchDevice { Id = Guid.NewGuid().ToString(), Owner = code.Owner, TokenHash = Hash(token), Name = r.Name, ExpiresAt = Now + 90L * 86400_000, LastSeenAt = Now };
            code.Consumed = true; db.WatchDevices.Add(device);
            return Results.Ok(new { deviceId = device.Id, token, expiresAt = device.ExpiresAt, protocolVersion = 1, contractVersion = 2 });
        })).WithMetadata(new WatchRedeemEndpoint());

        api.MapGet("/watch/devices", async (HttpContext c, Store db) => {
            var owner = Owner(c);
            return Results.Ok(new { enabled = Enabled(c), devices = await db.WatchDevices.Where(x => x.Owner == owner).Select(x => new { x.Id, x.Name, x.ExpiresAt, x.RevokedAt, x.LastSeenAt }).ToListAsync() });
        }).RequireAuthorization();
        api.MapDelete("/watch/devices/{id}", (string id, HttpContext c, Store db) => Locked(c, db, async () => {
            var device = await db.WatchDevices.SingleOrDefaultAsync(x => x.Id == id && x.Owner == Owner(c));
            if (device == null) return Results.NotFound();
            device.RevokedAt ??= Now;
            // Control intentionally remains locked. Owner explicitly recovers before editing.
            return Results.Ok(new { revoked = true });
        })).RequireAuthorization();

        api.MapGet("/sessions/{id}/watch-control", (string id, HttpContext c, Store db) => Locked(c, db, async () => {
            var owner = Owner(c); var doc = await db.Documents.FindAsync(owner, "sessions", id);
            if (doc == null) return Results.NotFound();
            return Results.Ok(Snapshot(doc, await db.WatchControls.FindAsync(owner, id), await Generation(db)));
        })).RequireAuthorization();
        foreach (var action in new[] { "watch-handoff", "watch-handoff/cancel", "watch-force-return" }) {
            var command = action;
            api.MapPost("/sessions/{id}/" + action, (string id, WatchCommand r, HttpContext c, Store db) =>
                Locked(c, db, () => Command(db, c, r, id, command, null))).RequireAuthorization();
        }
        api.MapGet("/watch/recovery", async (HttpContext c, Store db) => {
            var owner = Owner(c);
            return Results.Ok(await db.WatchRecoveries.Where(x => x.Owner == owner).OrderByDescending(x => x.CreatedAt).Select(x => new { x.Id, x.SessionId, x.DeviceId, x.CreatedAt }).Take(200).ToListAsync());
        }).RequireAuthorization();
        api.MapGet("/watch/recovery/{id}", async (string id, HttpContext c, Store db) => {
            var row = await db.WatchRecoveries.SingleOrDefaultAsync(x => x.Id == id && x.Owner == Owner(c));
            return row == null ? Results.NotFound() : Results.Ok(new { row.Id, row.SessionId, row.CreatedAt, payload = JsonSerializer.Deserialize<JsonElement>(row.Payload) });
        }).RequireAuthorization();

        var watch = api.MapGroup("/watch/v1").WithMetadata(new WatchBearerEndpoint());
        watch.MapGet("/session", (HttpContext c, Store db) => Locked(c, db, async () => {
            var device = await Authenticate(c, db);
            if (device == null) return Error(401, "device_authentication");
            var control = await db.WatchControls.SingleOrDefaultAsync(x => x.Owner == device.Owner && x.DeviceId == device.Id && x.State != "phone");
            if (control == null) return Results.Ok(new { protocolVersion = 1, contractVersion = 2, session = (object?)null });
            var doc = await db.Documents.FindAsync(device.Owner, "sessions", control.SessionId);
            return Results.Ok(new { protocolVersion = 1, contractVersion = 2, session = Snapshot(doc!, control, await Generation(db)) });
        }));
        foreach (var action in new[] { "handoff/accept", "control/release" }) {
            var command = action;
            watch.MapPost("/" + action, (WatchCommand r, HttpContext c, Store db) => Locked(c, db, async () => {
                var device = await Authenticate(c, db);
                return device == null ? Error(401, "device_authentication") : await Command(db, c, r, r.SessionId, command, device);
            }));
        }
        watch.MapPut("/sessions/{id}", (string id, WatchWrite r, HttpContext c, Store db) => Locked(c, db, async () => {
            var device = await Authenticate(c, db);
            if (device == null) return Error(401, "device_authentication");
            if (r.ProtocolVersion != 1 || r.ContractVersion != 2) return Error(426, "schema");
            if (!Guid.TryParse(r.OperationId, out _) || r.BaseVersion < 1 || !Validation.Valid("sessions", id, r.Payload)) return Error(400, "validation");
            var generation = await Generation(db);
            if (generation != r.Generation) return Error(409, "generation");
            var hash = Hash(JsonSerializer.Serialize(new { route = "watch-write", id, device = device.Id, request = r }, Json));
            var replay = await Replay(db, device.Owner, r.OperationId, hash);
            if (replay != null) return replay;
            var control = await db.WatchControls.FindAsync(device.Owner, id);
            if (control?.State != "watch" || control.DeviceId != device.Id || control.Epoch != r.ControlEpoch) return Error(409, "control_changed", "Управление изменилось. Сохраните восстановительную копию.");
            var doc = await db.Documents.FindAsync(device.Owner, "sessions", id);
            if (doc == null) return Results.NotFound();
            if (doc.Version != r.BaseVersion) return Results.Json(new { error = "conflict", version = doc.Version, payload = JsonSerializer.Deserialize<JsonElement>(doc.Payload) }, statusCode: 409);
            if (!AllowedDiff(doc.Payload, r.Payload)) return Error(400, "invalid_diff", "Часы могут менять только результаты подходов и отдых.");
            DocumentWriter.Record(db, doc, r.Payload.GetRawText());
            if (r.Payload.GetProperty("status").GetString() == "completed") {
                control.State = "phone"; control.Epoch++; control.DeviceId = null; control.HandoffId = null;
            }
            return Receipt(db, device.Owner, r.OperationId, hash, new { version = doc.Version, generation, control = Control(control) });
        }));
        watch.MapPost("/recovery", (WatchRecoveryWrite r, HttpContext c, Store db) => Locked(c, db, async () => {
            var device = await Authenticate(c, db);
            if (device == null) return Error(401, "device_authentication");
            if (!Guid.TryParse(r.OperationId, out _) || !Guid.TryParse(r.SessionId, out _) || r.Payload.ValueKind != JsonValueKind.Object || r.Payload.GetRawText().Length > 1_000_000) return Error(400, "validation");
            // A newly paired device may upload, but cannot read or overwrite arbitrary sessions.
            var hash = Hash(JsonSerializer.Serialize(new { route = "watch-recovery", device = device.Id, request = r }, Json));
            var replay = await Replay(db, device.Owner, r.OperationId, hash);
            if (replay != null) return replay;
            if (await db.WatchRecoveries.CountAsync(x => x.Owner == device.Owner) >= 200) return Error(409, "recovery_limit");
            var row = new WatchRecovery { Id = Guid.NewGuid().ToString(), Owner = device.Owner, DeviceId = device.Id, SessionId = r.SessionId, Payload = r.Payload.GetRawText(), CreatedAt = Now };
            db.WatchRecoveries.Add(row);
            return Receipt(db, device.Owner, r.OperationId, hash, new { recoveryId = row.Id });
        }));
    }

    static async Task<IResult> Command(Store db, HttpContext c, WatchCommand r, string id, string action, WatchDevice? device) {
        if (!Guid.TryParse(r.OperationId, out _) || r.SessionId != id || r.BaseVersion < 1 || r.ControlEpoch < 0) return Error(400, "validation");
        var owner = device?.Owner ?? Owner(c); var generation = await Generation(db);
        if (generation != r.Generation) return Error(409, "generation");
        var hash = Hash(JsonSerializer.Serialize(new { route = action, id, device = device?.Id, request = r }, Json));
        var replay = await Replay(db, owner, r.OperationId, hash);
        if (replay != null) return replay;
        var doc = await db.Documents.FindAsync(owner, "sessions", id);
        if (doc == null) return Results.NotFound();
        var control = await db.WatchControls.FindAsync(owner, id);
        if (doc.Version != r.BaseVersion || (control?.Epoch ?? 0) != r.ControlEpoch) return Error(409, "control_changed");
        var payload = JsonNode.Parse(doc.Payload)!;
        if (action == "watch-handoff") {
            if (!Enabled(c)) return Error(503, "watch_disabled");
            if (control != null && control.State != "phone") return Error(409, "already_controlled");
            if (payload["status"]?.GetValue<string>() != "active" || payload["deletedAt"] != null || payload["archivedAt"] != null) return Error(409, "not_active");
            if (payload["exercises"]!.AsArray().Any(e => e!["requiresEquipment"]?.GetValue<bool>() == true && e["mode"]?.GetValue<string>() == "Unspecified")) return Error(400, "equipment_required");
            var target = await db.WatchDevices.SingleOrDefaultAsync(x => x.Id == r.DeviceId && x.Owner == owner && x.RevokedAt == null && x.ExpiresAt > Now);
            if (target == null) return Error(400, "device_unavailable");
            if (await db.WatchControls.AnyAsync(x => x.Owner == owner && x.State != "phone")) return Error(409, "already_controlled");
            if (control == null) { control = new() { Owner = owner, SessionId = id }; db.WatchControls.Add(control); }
            control.State = "offered"; control.DeviceId = target.Id; control.HandoffId = Guid.NewGuid().ToString();
        } else if (action == "handoff/accept") {
            if (control?.State != "offered" || control.DeviceId != device!.Id || control.HandoffId != r.HandoffId) return Error(409, "control_changed");
            control.State = "watch";
        } else if (action == "watch-handoff/cancel") {
            if (control?.State != "offered" || control.HandoffId != r.HandoffId) return Error(409, "control_changed");
            control.State = "phone"; control.DeviceId = null; control.HandoffId = null;
        } else if (action == "control/release") {
            if (control?.State != "watch" || control.DeviceId != device!.Id) return Error(409, "control_changed");
            control.State = "phone"; control.DeviceId = null; control.HandoffId = null;
        } else if (action == "watch-force-return") {
            if (control == null || control.State == "phone") return Error(409, "control_changed");
            Archive(db, doc, control.DeviceId ?? "");
            control.State = "phone"; control.DeviceId = null; control.HandoffId = null;
        } else return Results.NotFound();
        control!.Epoch++;
        DocumentWriter.Record(db, doc, doc.Payload);
        return Receipt(db, owner, r.OperationId, hash, Snapshot(doc, control, generation));
    }

    public static bool AllowedDiff(string original, JsonElement payload) {
        var before = JsonNode.Parse(original)!; var after = JsonNode.Parse(payload.GetRawText())!;
        if (before["status"]?.GetValue<string>() != "active" || after["status"]?.GetValue<string>() is not ("active" or "completed")) return false;
        if (after["revision"]!.GetValue<long>() <= before["revision"]!.GetValue<long>()) return false;
        var finished = after["status"]!.GetValue<string>() == "completed";
        if (finished ? after["completedAt"] == null || after["restEndsAt"] != null : !JsonNode.DeepEquals(before["completedAt"], after["completedAt"])) return false;
        var a = before["exercises"]!.AsArray(); var b = after["exercises"]!.AsArray();
        if (a.Count != b.Count) return false;
        for (var i = 0; i < a.Count; i++) {
            var ar = a[i]!["records"]!.AsArray(); var br = b[i]!["records"]!.AsArray();
            if (ar.Count != br.Count) return false;
            for (var j = 0; j < ar.Count; j++) {
                if (finished && br[j]!["status"]?.GetValue<string>() == "draft") return false;
                foreach (var field in new[] { "status", "weight", "reps", "duration", "rir", "note", "loadGrams", "count", "durationSeconds", "completedAt" }) {
                    ar[j]!.AsObject().Remove(field); br[j]!.AsObject().Remove(field);
                }
                // Existing non-unilateral sets may not have side yet; normalizing to 'both' is allowed.
                if (a[i]!["unilateral"]?.GetValue<bool>() != true && br[j]!["side"]?.GetValue<string>() == "both") {
                    ar[j]!.AsObject().Remove("side"); br[j]!.AsObject().Remove("side");
                }
            }
        }
        foreach (var field in new[] { "status", "revision", "restEndsAt", "completedAt" }) { before.AsObject().Remove(field); after.AsObject().Remove(field); }
        return JsonNode.DeepEquals(before, after);
    }
}
