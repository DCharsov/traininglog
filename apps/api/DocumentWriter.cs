using System.Text.Json;
using Microsoft.EntityFrameworkCore;

namespace TrainingLog;

/// Shared by browser writes, watch writes and control changes. One SQLite writer.
public sealed class DocumentWriter {
    public SemaphoreSlim Gate { get; } = new(1, 1);
    public static void Record(Store db, Document doc, string payload) {
        doc.Version++;
        doc.Payload = payload;
        db.Changes.Add(new() { Owner = doc.Owner, Kind = doc.Kind, Id = doc.Id, Version = doc.Version, Payload = payload });
    }
    public static async Task<bool> WatchLocked(Store db, string owner, string kind, string id) =>
        kind == "sessions" && await db.WatchControls.AnyAsync(x => x.Owner == owner && x.SessionId == id && x.State != "phone");
}
