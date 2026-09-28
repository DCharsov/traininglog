using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using TrainingLog;

namespace TrainingLogTests;

public class ReservationMigrationTests {
    [Fact] public async Task Upgrade_preserves_diary_leases_receipts_and_generation() {
        await using var connection = new SqliteConnection("Data Source=:memory:");
        await connection.OpenAsync();
        var options = new DbContextOptionsBuilder<Store>().UseSqlite(connection).Options;
        await using var db = new Store(options);
        await db.GetService<IMigrator>().MigrateAsync("20260928145659_WatchLinkApproval");
        var sessionId = Guid.NewGuid().ToString(); var deviceId = Guid.NewGuid().ToString();
        const string payload = "{\"synthetic\":true,\"unknown\":{\"keep\":1}}";
        db.Documents.Add(new Document { Owner = "test-owner", Kind = "sessions", Id = sessionId, Version = 12, Payload = payload });
        db.Settings.Add(new Setting { Id = "generation", Value = "unchanged-generation" });
        db.WatchDevices.Add(new WatchDevice { Id = deviceId, Owner = "test-owner", TokenHash = "test-only-hash", ExpiresAt = long.MaxValue });
        db.WatchControls.Add(new WatchControl { Owner = "test-owner", SessionId = sessionId, State = "watch", DeviceId = deviceId, Epoch = 7 });
        db.Operations.Add(new Operation { Owner = "test-owner", Id = Guid.NewGuid().ToString(), Hash = "receipt-hash", Response = "{\"version\":12}" });
        await db.SaveChangesAsync(); db.ChangeTracker.Clear();
        await db.Database.MigrateAsync();
        await db.Database.MigrateAsync(); // Startup retry is harmless.
        var document = await db.Documents.SingleAsync();
        Assert.Equal(payload, document.Payload); Assert.Equal(12, document.Version);
        Assert.Equal("unchanged-generation", (await db.Settings.SingleAsync()).Value);
        var control = await db.WatchControls.SingleAsync();
        Assert.Equal("watch", control.State); Assert.Equal(7, control.Epoch); Assert.Equal(deviceId, control.DeviceId);
        Assert.Equal("test-only-hash", (await db.WatchDevices.SingleAsync()).TokenHash);
        Assert.Equal("{\"version\":12}", (await db.Operations.SingleAsync()).Response);
        Assert.Empty(await db.WorkoutReservations.ToListAsync());
    }
}
