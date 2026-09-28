using System.Text.Json;
using Microsoft.EntityFrameworkCore;

namespace TrainingLog;

/// Shared by browser writes, watch writes and control changes. One SQLite writer.
public sealed class DocumentWriter {
    public static string PreserveDayArchives(string? previous, JsonElement payload) {
        if (previous == null) return payload.GetRawText();
        var before = System.Text.Json.Nodes.JsonNode.Parse(previous)!;
        var after = System.Text.Json.Nodes.JsonNode.Parse(payload.GetRawText())!;
        foreach (var day in after["days"]!.AsArray()) {
            if (day!.AsObject().ContainsKey("archivedAt")) continue; // Explicit null restores a day.
            var old = before["days"]!.AsArray().FirstOrDefault(x => x!["id"]!.ToString() == day["id"]!.ToString());
            if (old?["archivedAt"] != null) day["archivedAt"] = old["archivedAt"]!.DeepClone();
        }
        return after.ToJsonString();
    }
    public SemaphoreSlim Gate { get; } = new(1, 1);
    public static void Record(Store db, Document doc, string payload) {
        doc.Version++;
        doc.Payload = payload;
        db.Changes.Add(new() { Owner = doc.Owner, Kind = doc.Kind, Id = doc.Id, Version = doc.Version, Payload = payload });
    }
    public static async Task<bool> WatchLocked(Store db, string owner, string kind, string id) =>
        kind == "sessions" && await db.WatchControls.AnyAsync(x => x.Owner == owner && x.SessionId == id && x.State != "phone");
    public static async Task<bool> ReservationLocked(Store db, string owner, string kind, string id, JsonElement payload) {
        if (kind != "sessions") return false;
        var reservation = await db.WorkoutReservations.FindAsync(owner);
        if (reservation == null || reservation.State is "cancelled" or "completed") return false;
        // Same UUID is reserved even if an old client tries to submit it already completed.
        // Unrelated history corrections remain possible; competing active workouts do not.
        if (reservation.State == "started" && reservation.Id == id) return false; // The normal control lease now governs this session.
        return reservation.Id == id || payload.TryGetProperty("status", out var status) && status.GetString() == "active";
    }
    public static async Task CompleteReservation(Store db, string owner, string id, JsonElement payload) {
        if (payload.GetProperty("status").GetString() is not ("completed" or "cancelled")) return;
        var row = await db.WorkoutReservations.FindAsync(owner);
        if (row?.Id == id && row.State == "started") {
            row.State = "completed"; row.Version++;
            row.Generation = (await db.Settings.SingleAsync(x => x.Id == "generation")).Value;
        }
    }
}
