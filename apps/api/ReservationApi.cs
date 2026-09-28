using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.EntityFrameworkCore;

namespace TrainingLog;

public static partial class WatchApi {
    static bool ReservationsEnabled(HttpContext c) => Enabled(c) && c.RequestServices.GetRequiredService<IConfiguration>().GetValue<bool>("Watch:ReservationsEnabled");
    static object ReservationSnapshot(WorkoutReservation r) => new {
        reservationId = r.Id, deviceId = r.DeviceId, generation = r.Generation, state = r.State,
        version = r.Version, controlEpoch = r.Epoch, phoneReady = r.PhoneReady, watchReady = r.WatchReady,
        payload = JsonSerializer.Deserialize<JsonElement>(r.Payload), protocolVersion = 1, contractVersion = 2
    };
    static async Task<bool> HasActiveSession(Store db, string owner) {
        var payloads = await db.Documents.Where(x => x.Owner == owner && x.Kind == "sessions").Select(x => x.Payload).ToListAsync();
        return payloads.Any(text => { var p = JsonNode.Parse(text)!; return p["status"]?.GetValue<string>() == "active" && p["deletedAt"] == null; });
    }
    static void MapReservations(RouteGroupBuilder api) {
        api.MapGet("/watch/reservation", (HttpContext c, Store db) => Locked(c, db, async () => {
            var row = await db.WorkoutReservations.FindAsync(Owner(c));
            return Results.Ok(new { enabled = ReservationsEnabled(c), reservation = row == null ? null : ReservationSnapshot(row) });
        })).RequireAuthorization();
        api.MapPost("/watch/reservation", (ReservationCreate r, HttpContext c, Store db) => Locked(c, db, async () => {
            if (!ReservationsEnabled(c)) return Error(503, "reservations_disabled");
            var owner = Owner(c); var generation = await Generation(db);
            if (r.Generation != generation) return Error(409, "generation");
            var id = r.Payload.ValueKind == JsonValueKind.Object && r.Payload.TryGetProperty("id", out var value) ? value.GetString() : null;
            if (!Guid.TryParse(r.OperationId, out _) || id == null || !Validation.Valid("sessions", id, r.Payload)) return Error(400, "validation");
            var hash = Hash(JsonSerializer.Serialize(new { route = "reservation-create", request = r }, Json));
            var replay = await Replay(db, owner, r.OperationId, hash); if (replay != null) return replay;
            var p = JsonNode.Parse(r.Payload.GetRawText())!;
            if (p["status"]?.GetValue<string>() != "active" || p["deletedAt"] != null || p["archivedAt"] != null || p["completedAt"] != null || p["restEndsAt"] != null) return Error(400, "not_pristine");
            foreach (var e in p["exercises"]!.AsArray()) {
                if (e!["requiresEquipment"]?.GetValue<bool>() == true && e["mode"]?.GetValue<string>() == "Unspecified") return Error(400, "equipment_required");
                if (e["records"]!.AsArray().Any(s => s!["status"]?.GetValue<string>() != "draft" || s["completedAt"] != null || s["loadGrams"] != null || s["count"] != null || s["durationSeconds"] != null)) return Error(400, "not_pristine");
            }
            var row = await db.WorkoutReservations.FindAsync(owner);
            if (row != null && row.State is not ("cancelled" or "completed")) return Error(409, "already_reserved");
            if (await HasActiveSession(db, owner) || await db.WatchControls.AnyAsync(x => x.Owner == owner && x.State != "phone")) return Error(409, "already_active");
            if (await db.Documents.FindAsync(owner, "sessions", id) != null) return Error(409, "session_exists");
            if (!await db.WatchDevices.AnyAsync(x => x.Id == r.DeviceId && x.Owner == owner && x.RevokedAt == null && x.ExpiresAt > Now)) return Error(400, "device_unavailable");
            if (row == null) { row = new() { Owner = owner }; db.WorkoutReservations.Add(row); }
            row.Id = id; row.DeviceId = r.DeviceId; row.Generation = generation; row.State = "preparing";
            row.Payload = r.Payload.GetRawText(); row.Epoch++; row.Version++; row.PhoneReady = false; row.WatchReady = false; row.CreatedAt = Now;
            return Receipt(db, owner, r.OperationId, hash, ReservationSnapshot(row));
        })).RequireAuthorization();
        foreach (var action in new[] { "phone-ready", "force-cancel" }) {
            var selected = action;
            api.MapPost("/watch/reservation/" + action, (ReservationCommand r, HttpContext c, Store db) => Locked(c, db, () => ReservationChange(db, c, r, selected, null))).RequireAuthorization();
        }
        var watch = api.MapGroup("/watch/v1/reservation").WithMetadata(new WatchBearerEndpoint());
        watch.MapGet("/", (HttpContext c, Store db) => Locked(c, db, async () => {
            var device = await Authenticate(c, db); if (device == null) return Error(401, "device_authentication");
            var row = await db.WorkoutReservations.FindAsync(device.Owner);
            return Results.Ok(new { reservation = row != null && row.DeviceId == device.Id ? ReservationSnapshot(row) : null });
        }));
        watch.MapPost("/ready", (ReservationCommand r, HttpContext c, Store db) => Locked(c, db, async () => {
            var device = await Authenticate(c, db);
            return device == null ? Error(401, "device_authentication") : await ReservationChange(db, c, r, "watch-ready", device);
        }));
        watch.MapPost("/start", (ReservationStart r, HttpContext c, Store db) => Locked(c, db, async () => {
            var device = await Authenticate(c, db); if (device == null) return Error(401, "device_authentication");
            if (!Guid.TryParse(r.OperationId, out _) || !Validation.Valid("sessions", r.ReservationId, r.Payload)) return Error(400, "validation");
            var generation = await Generation(db);
            if (r.Generation != generation) return Error(409, "generation");
            var hash = Hash(JsonSerializer.Serialize(new { route = "reservation-start", device = device.Id, request = r }, Json));
            var replay = await Replay(db, device.Owner, r.OperationId, hash); if (replay != null) return replay;
            var row = await db.WorkoutReservations.FindAsync(device.Owner);
            if (row == null || row.Id != r.ReservationId || row.State != "ready" || row.DeviceId != device.Id || row.Generation != generation || row.Epoch != r.ControlEpoch || row.Version != r.Version || !row.PhoneReady || !row.WatchReady) return Error(409, "reservation_changed", "Сохраните позднюю копию через восстановление; управление изменилось.");
            if (await HasActiveSession(db, device.Owner) || await db.Documents.FindAsync(device.Owner, "sessions", row.Id) != null) return Error(409, "already_active");
            // Preparation has placeholder dates. Actual start is chosen offline on the watch.
            var baseline = JsonNode.Parse(row.Payload)!;
            foreach (var field in new[] { "startedAt", "localDate", "timezone" }) baseline[field] = JsonNode.Parse(r.Payload.GetProperty(field).GetRawText());
            if (!AllowedDiff(baseline.ToJsonString(), r.Payload)) return Error(400, "invalid_diff");
            var doc = new Document { Owner = device.Owner, Kind = "sessions", Id = row.Id };
            db.Documents.Add(doc); DocumentWriter.Record(db, doc, r.Payload.GetRawText());
            var finished = r.Payload.GetProperty("status").GetString() == "completed";
            var control = new WatchControl { Owner = device.Owner, SessionId = row.Id, State = finished ? "phone" : "watch", DeviceId = finished ? null : device.Id, Epoch = finished ? row.Epoch + 1 : row.Epoch };
            db.WatchControls.Add(control);
            row.State = finished ? "completed" : "started"; row.Version++;
            return Receipt(db, device.Owner, r.OperationId, hash, Snapshot(doc, control, generation));
        }));
    }
    static async Task<IResult> ReservationChange(Store db, HttpContext c, ReservationCommand r, string action, WatchDevice? device) {
        var owner = device?.Owner ?? Owner(c);
        if (!Guid.TryParse(r.OperationId, out _) || r.Version < 1 || r.ControlEpoch < 1) return Error(400, "validation");
        if (r.Generation != await Generation(db)) return Error(409, "generation");
        var hash = Hash(JsonSerializer.Serialize(new { route = "reservation-" + action, device = device?.Id, request = r }, Json));
        var replay = await Replay(db, owner, r.OperationId, hash); if (replay != null) return replay;
        var row = await db.WorkoutReservations.FindAsync(owner);
        if (row == null || row.Id != r.ReservationId || row.Epoch != r.ControlEpoch || row.Version != r.Version ||
            row.Generation != r.Generation && action != "force-cancel" || device != null && row.DeviceId != device.Id) return Error(409, "reservation_changed");
        if (row.State is not ("preparing" or "ready")) return Error(409, "reservation_changed");
        // A restored database retains the old reservation generation. Only an explicit,
        // authenticated owner cancellation may retire it in the new generation.
        if (action == "force-cancel") { row.State = "cancelled"; row.Generation = r.Generation; row.Epoch++; }
        else {
            if (action == "phone-ready") row.PhoneReady = true; else row.WatchReady = true;
            if (row.PhoneReady && row.WatchReady) row.State = "ready";
        }
        row.Version++;
        return Receipt(db, owner, r.OperationId, hash, ReservationSnapshot(row));
    }
}
