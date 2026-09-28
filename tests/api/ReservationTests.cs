using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using TrainingLog;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace TrainingLogTests;
public partial class WatchApiTests {
    [Fact] public async Task Started_reservation_after_restore_returns_through_normal_lease_and_completes() {
        await using var factory = new Factory(); using var phone = factory.CreateClient(); using var watch = factory.CreateClient();
        await Login(phone); var device = await Pair(phone, watch);
        var boot = await phone.GetFromJsonAsync<JsonElement>("/training/api/bootstrap");
        var generation = boot.GetProperty("generation").GetString()!;
        var payload = Fixture(); var id = payload["id"]!.GetValue<string>();
        var created = await Read(await phone.PostAsJsonAsync("/training/api/watch/reservation", new ReservationCreate(Guid.NewGuid().ToString(), generation, device.GetProperty("deviceId").GetString()!, JsonSerializer.SerializeToElement(payload))));
        ReservationCommand Cmd(JsonElement s) => new(Guid.NewGuid().ToString(), generation, id, s.GetProperty("version").GetInt64(), s.GetProperty("controlEpoch").GetInt64());
        var phoneReady = await Read(await phone.PostAsJsonAsync("/training/api/watch/reservation/phone-ready", Cmd(created)));
        var ready = await Read(await watch.PostAsJsonAsync("/training/api/watch/v1/reservation/ready", Cmd(phoneReady)));
        payload["revision"] = 2;
        var started = await Read(await watch.PostAsJsonAsync("/training/api/watch/v1/reservation/start", new ReservationStart(Guid.NewGuid().ToString(), generation, id, ready.GetProperty("version").GetInt64(), ready.GetProperty("controlEpoch").GetInt64(), JsonSerializer.SerializeToElement(payload))));
        var restoredGeneration = Guid.NewGuid().ToString();
        await using (var scope = factory.Services.CreateAsyncScope()) {
            var db = scope.ServiceProvider.GetRequiredService<Store>();
            (await db.Settings.SingleAsync(x => x.Id == "generation")).Value = restoredGeneration; await db.SaveChangesAsync();
        }
        Assert.Equal(HttpStatusCode.Conflict, (await watch.PostAsJsonAsync("/training/api/watch/v1/control/release", Command(started))).StatusCode);
        var fresh = await phone.GetFromJsonAsync<JsonElement>($"/training/api/sessions/{id}/watch-control");
        var returned = await Read(await phone.PostAsJsonAsync($"/training/api/sessions/{id}/watch-force-return", Command(fresh)));
        var reservation = (await phone.GetFromJsonAsync<JsonElement>("/training/api/watch/reservation")).GetProperty("reservation");
        Assert.Equal("started", reservation.GetProperty("state").GetString());
        Assert.Equal(restoredGeneration, reservation.GetProperty("generation").GetString());
        Assert.Equal(returned.GetProperty("control").GetProperty("controlEpoch").GetInt64(), reservation.GetProperty("controlEpoch").GetInt64());
        payload["status"] = "completed"; payload["revision"] = 3; payload["completedAt"] = "2026-09-28T18:00:00Z";
        foreach (var e in payload["exercises"]!.AsArray()) foreach (var r in e!["records"]!.AsArray()) r!["status"] = "skipped";
        await Read(await phone.PutAsJsonAsync($"/training/api/sessions/{id}", new { operationId = Guid.NewGuid(), contractVersion = 2, generation = restoredGeneration, baseVersion = returned.GetProperty("version").GetInt64(), payload }));
        reservation = (await phone.GetFromJsonAsync<JsonElement>("/training/api/watch/reservation")).GetProperty("reservation");
        Assert.Equal("completed", reservation.GetProperty("state").GetString());
        Assert.Single((await phone.GetFromJsonAsync<JsonElement>("/training/api/export")).GetProperty("sessions").EnumerateArray());
    }
    [Fact] public async Task Restored_generation_allows_only_explicit_owner_cancellation_of_old_reservation() {
        await using var factory = new Factory(); using var phone = factory.CreateClient(); using var watch = factory.CreateClient();
        await Login(phone); var device = await Pair(phone, watch);
        var bootstrap = await phone.GetFromJsonAsync<JsonElement>("/training/api/bootstrap");
        var oldGeneration = bootstrap.GetProperty("generation").GetString()!;
        var payload = Fixture(); var id = payload["id"]!.GetValue<string>();
        var reserved = await Read(await phone.PostAsJsonAsync("/training/api/watch/reservation", new ReservationCreate(Guid.NewGuid().ToString(), oldGeneration, device.GetProperty("deviceId").GetString()!, JsonSerializer.SerializeToElement(payload))));
        var newGeneration = Guid.NewGuid().ToString();
        await using (var scope = factory.Services.CreateAsyncScope()) {
            var db = scope.ServiceProvider.GetRequiredService<Store>();
            var generation = await db.Settings.SingleAsync(x => x.Id == "generation");
            generation.Value = newGeneration; await db.SaveChangesAsync();
        }
        var stale = new ReservationCommand(Guid.NewGuid().ToString(), oldGeneration, id, reserved.GetProperty("version").GetInt64(), reserved.GetProperty("controlEpoch").GetInt64());
        Assert.Equal(HttpStatusCode.Conflict, (await watch.PostAsJsonAsync("/training/api/watch/v1/reservation/ready", stale)).StatusCode);
        var current = stale with { OperationId = Guid.NewGuid().ToString(), Generation = newGeneration };
        Assert.Equal(HttpStatusCode.Conflict, (await watch.PostAsJsonAsync("/training/api/watch/v1/reservation/ready", current)).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await phone.PostAsJsonAsync("/training/api/watch/reservation/phone-ready", current)).StatusCode);
        var cancelled = await Read(await phone.PostAsJsonAsync("/training/api/watch/reservation/force-cancel", current));
        Assert.Equal("cancelled", cancelled.GetProperty("state").GetString());
        Assert.Equal(newGeneration, cancelled.GetProperty("generation").GetString());
        Assert.True(cancelled.GetProperty("controlEpoch").GetInt64() > stale.ControlEpoch);
        var late = new ReservationStart(Guid.NewGuid().ToString(), oldGeneration, id, stale.Version, stale.ControlEpoch, JsonSerializer.SerializeToElement(payload));
        Assert.Equal(HttpStatusCode.Conflict, (await watch.PostAsJsonAsync("/training/api/watch/v1/reservation/start", late)).StatusCode);
        await Read(await watch.PostAsJsonAsync("/training/api/watch/v1/recovery", new WatchRecoveryWrite(Guid.NewGuid().ToString(), id, JsonSerializer.SerializeToElement(payload))));
        var next = Fixture(); next["id"] = Guid.NewGuid().ToString();
        await Seed(phone, next);
        var export = await phone.GetFromJsonAsync<JsonElement>("/training/api/export");
        Assert.Single(export.GetProperty("sessions").EnumerateArray());
    }
    [Fact] public async Task Disabled_reservation_flag_keeps_existing_diary_working() {
        await using var factory = new Factory(reservationsEnabled: false); using var phone = factory.CreateClient(); using var watch = factory.CreateClient();
        await Login(phone); var device = await Pair(phone, watch);
        var bootstrap = await phone.GetFromJsonAsync<JsonElement>("/training/api/bootstrap");
        var generation = bootstrap.GetProperty("generation").GetString()!;
        var state = await phone.GetFromJsonAsync<JsonElement>("/training/api/watch/reservation");
        Assert.False(state.GetProperty("enabled").GetBoolean());
        var payload = Fixture();
        var create = new ReservationCreate(Guid.NewGuid().ToString(), generation, device.GetProperty("deviceId").GetString()!, JsonSerializer.SerializeToElement(payload));
        Assert.Equal(HttpStatusCode.ServiceUnavailable, (await phone.PostAsJsonAsync("/training/api/watch/reservation", create)).StatusCode);
        var accepted = await Assign(phone, watch, payload, device);
        Assert.Equal("watch", accepted.GetProperty("control").GetProperty("state").GetString());
        await Read(await watch.PostAsJsonAsync("/training/api/watch/v1/control/release", Command(accepted)));
    }
    [Fact] public async Task Cancelled_offline_results_are_archived_without_overwriting_new_active_session() {
        await using var factory = new Factory(); using var phone = factory.CreateClient(); using var watch = factory.CreateClient();
        await Login(phone); var device = await Pair(phone, watch);
        var bootstrap = await phone.GetFromJsonAsync<JsonElement>("/training/api/bootstrap");
        var generation = bootstrap.GetProperty("generation").GetString()!;
        var payload = Fixture(); var id = payload["id"]!.GetValue<string>();
        var reserved = await Read(await phone.PostAsJsonAsync("/training/api/watch/reservation", new ReservationCreate(Guid.NewGuid().ToString(), generation, device.GetProperty("deviceId").GetString()!, JsonSerializer.SerializeToElement(payload))));
        ReservationCommand Cmd(JsonElement s) => new(Guid.NewGuid().ToString(), generation, id, s.GetProperty("version").GetInt64(), s.GetProperty("controlEpoch").GetInt64());
        var phoneReady = await Read(await phone.PostAsJsonAsync("/training/api/watch/reservation/phone-ready", Cmd(reserved)));
        var ready = await Read(await watch.PostAsJsonAsync("/training/api/watch/v1/reservation/ready", Cmd(phoneReady)));
        await Read(await phone.PostAsJsonAsync("/training/api/watch/reservation/force-cancel", Cmd(ready)));
        var other = Fixture(); other["id"] = Guid.NewGuid().ToString();
        var current = await Seed(phone, other);
        payload["revision"] = 2; payload["exercises"]![0]!["records"]![0]!["weight"] = "42";
        var lateStart = new ReservationStart(Guid.NewGuid().ToString(), generation, id, ready.GetProperty("version").GetInt64(), ready.GetProperty("controlEpoch").GetInt64(), JsonSerializer.SerializeToElement(payload));
        Assert.Equal(HttpStatusCode.Conflict, (await watch.PostAsJsonAsync("/training/api/watch/v1/reservation/start", lateStart)).StatusCode);
        var recovery = new WatchRecoveryWrite(Guid.NewGuid().ToString(), id, JsonSerializer.SerializeToElement(payload));
        var receipt = await Read(await watch.PostAsJsonAsync("/training/api/watch/v1/recovery", recovery));
        Assert.Equal(receipt.GetRawText(), (await Read(await watch.PostAsJsonAsync("/training/api/watch/v1/recovery", recovery))).GetRawText());
        var archive = await phone.GetFromJsonAsync<JsonElement>("/training/api/watch/recovery");
        Assert.Single(archive.EnumerateArray());
        var copy = await phone.GetFromJsonAsync<JsonElement>("/training/api/watch/recovery/" + receipt.GetProperty("recoveryId").GetString());
        Assert.Equal("42", copy.GetProperty("payload").GetProperty("exercises")[0].GetProperty("records")[0].GetProperty("weight").GetString());
        var unchanged = await phone.GetFromJsonAsync<JsonElement>($"/training/api/sessions/{other["id"]}/watch-control");
        Assert.Equal(current.GetRawText(), unchanged.GetRawText());
        var export = await phone.GetFromJsonAsync<JsonElement>("/training/api/export");
        Assert.Single(export.GetProperty("sessions").EnumerateArray());
        Assert.Equal(other["id"]!.GetValue<string>(), export.GetProperty("sessions")[0].GetProperty("id").GetString());
    }

    [Fact] public async Task Reservation_rejects_unassigned_device_wrong_generation_and_changed_operation_payload() {
        await using var factory = new Factory(); using var phone = factory.CreateClient(); using var watch = factory.CreateClient(); using var otherWatch = factory.CreateClient();
        await Login(phone); var device = await Pair(phone, watch); await Pair(phone, otherWatch);
        var bootstrap = await phone.GetFromJsonAsync<JsonElement>("/training/api/bootstrap");
        var generation = bootstrap.GetProperty("generation").GetString()!;
        var payload = Fixture(); var id = payload["id"]!.GetValue<string>();
        var create = new ReservationCreate(Guid.NewGuid().ToString(), generation, device.GetProperty("deviceId").GetString()!, JsonSerializer.SerializeToElement(payload));
        var reserved = await Read(await phone.PostAsJsonAsync("/training/api/watch/reservation", create));
        var hidden = await otherWatch.GetFromJsonAsync<JsonElement>("/training/api/watch/v1/reservation/");
        Assert.Equal(JsonValueKind.Null, hidden.GetProperty("reservation").ValueKind);
        var command = new ReservationCommand(Guid.NewGuid().ToString(), generation, id, reserved.GetProperty("version").GetInt64(), reserved.GetProperty("controlEpoch").GetInt64());
        Assert.Equal(HttpStatusCode.Conflict, (await otherWatch.PostAsJsonAsync("/training/api/watch/v1/reservation/ready", command)).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await watch.PostAsJsonAsync("/training/api/watch/v1/reservation/ready", command with { Generation = Guid.NewGuid().ToString() })).StatusCode);
        payload["name"] = "Changed retry";
        Assert.Equal(HttpStatusCode.Conflict, (await phone.PostAsJsonAsync("/training/api/watch/reservation", create with { Payload = JsonSerializer.SerializeToElement(payload) })).StatusCode);
        var current = await phone.GetFromJsonAsync<JsonElement>("/training/api/watch/reservation");
        Assert.True(System.Text.Json.Nodes.JsonNode.DeepEquals(System.Text.Json.Nodes.JsonNode.Parse(reserved.GetRawText()), System.Text.Json.Nodes.JsonNode.Parse(current.GetProperty("reservation").GetRawText())));
    }

    [Fact] public async Task Reserved_start_is_idempotent_and_flows_into_normal_watch_sync() {
        await using var factory = new Factory(); using var phone = factory.CreateClient(); using var watch = factory.CreateClient();
        await Login(phone); var device = await Pair(phone, watch);
        var bootstrap = await phone.GetFromJsonAsync<JsonElement>("/training/api/bootstrap"); var generation = bootstrap.GetProperty("generation").GetString()!;
        var payload = Fixture(); var id = payload["id"]!.GetValue<string>();
        var created = await Read(await phone.PostAsJsonAsync("/training/api/watch/reservation", new ReservationCreate(Guid.NewGuid().ToString(), generation, device.GetProperty("deviceId").GetString()!, JsonSerializer.SerializeToElement(payload))));
        ReservationCommand Cmd(JsonElement s) => new(Guid.NewGuid().ToString(), generation, id, s.GetProperty("version").GetInt64(), s.GetProperty("controlEpoch").GetInt64());
        var phoneReady = await Read(await phone.PostAsJsonAsync("/training/api/watch/reservation/phone-ready", Cmd(created)));
        var ready = await Read(await watch.PostAsJsonAsync("/training/api/watch/v1/reservation/ready", Cmd(phoneReady)));
        payload["startedAt"] = "2026-09-29T08:00:00.000Z"; payload["localDate"] = "2026-09-29"; payload["revision"] = 2;
        var start = new ReservationStart(Guid.NewGuid().ToString(), generation, id, ready.GetProperty("version").GetInt64(), ready.GetProperty("controlEpoch").GetInt64(), JsonSerializer.SerializeToElement(payload));
        var started = await Read(await watch.PostAsJsonAsync("/training/api/watch/v1/reservation/start", start));
        Assert.Equal(started.GetRawText(), (await Read(await watch.PostAsJsonAsync("/training/api/watch/v1/reservation/start", start))).GetRawText());
        Assert.Equal("watch", started.GetProperty("control").GetProperty("state").GetString());
        Assert.Equal("2026-09-29", started.GetProperty("payload").GetProperty("localDate").GetString());
        payload["revision"] = 3; payload["status"] = "completed"; payload["completedAt"] = "2026-09-29T09:00:00Z";
        foreach (var e in payload["exercises"]!.AsArray()) foreach (var r in e!["records"]!.AsArray()) r!["status"] = "skipped";
        await Read(await watch.PutAsJsonAsync($"/training/api/watch/v1/sessions/{id}", Write(started, payload)));
        var reservation = await phone.GetFromJsonAsync<JsonElement>("/training/api/watch/reservation");
        Assert.Equal("completed", reservation.GetProperty("reservation").GetProperty("state").GetString());
        var export = await phone.GetFromJsonAsync<JsonElement>("/training/api/export");
        Assert.Single(export.GetProperty("sessions").EnumerateArray());
    }

    [Fact] public async Task Reservation_blocks_old_clients_without_creating_history_and_cancel_invalidates_ready() {
        await using var factory = new Factory(); using var phone = factory.CreateClient(); using var watch = factory.CreateClient();
        await Login(phone); var device = await Pair(phone, watch);
        var state = await phone.GetFromJsonAsync<JsonElement>("/training/api/bootstrap");
        var generation = state.GetProperty("generation").GetString()!;
        var payload = Fixture();
        // The shared fixture has only empty drafts; create never inserts a Session document.
        var create = new ReservationCreate(Guid.NewGuid().ToString(), generation, device.GetProperty("deviceId").GetString()!, JsonSerializer.SerializeToElement(payload));
        var reserved = await Read(await phone.PostAsJsonAsync("/training/api/watch/reservation", create));
        Assert.Equal(reserved.GetRawText(), (await Read(await phone.PostAsJsonAsync("/training/api/watch/reservation", create))).GetRawText());
        var export = await phone.GetFromJsonAsync<JsonElement>("/training/api/export");
        Assert.Empty(export.GetProperty("sessions").EnumerateArray());
        var other = Fixture(); other["id"] = Guid.NewGuid().ToString();
        var write = new { operationId = Guid.NewGuid(), contractVersion = 2, generation, baseVersion = 0, payload = other };
        Assert.Equal((HttpStatusCode)423, (await phone.PutAsJsonAsync($"/training/api/sessions/{other["id"]}", write)).StatusCode);
        ReservationCommand CommandFor(JsonElement s) => new(Guid.NewGuid().ToString(), generation, s.GetProperty("reservationId").GetString()!, s.GetProperty("version").GetInt64(), s.GetProperty("controlEpoch").GetInt64());
        var phoneReady = await Read(await phone.PostAsJsonAsync("/training/api/watch/reservation/phone-ready", CommandFor(reserved)));
        Assert.Equal("preparing", phoneReady.GetProperty("state").GetString());
        var readyRequest = CommandFor(phoneReady);
        var ready = await Read(await watch.PostAsJsonAsync("/training/api/watch/v1/reservation/ready", readyRequest));
        Assert.Equal("ready", ready.GetProperty("state").GetString());
        var cancelled = await Read(await phone.PostAsJsonAsync("/training/api/watch/reservation/force-cancel", CommandFor(ready)));
        Assert.True(cancelled.GetProperty("controlEpoch").GetInt64() > ready.GetProperty("controlEpoch").GetInt64());
        // Lost replies may replay their old receipt but cannot resurrect the current authority.
        await Read(await watch.PostAsJsonAsync("/training/api/watch/v1/reservation/ready", readyRequest));
        var current = await phone.GetFromJsonAsync<JsonElement>("/training/api/watch/reservation");
        Assert.Equal("cancelled", current.GetProperty("reservation").GetProperty("state").GetString());
        Assert.Equal(HttpStatusCode.Conflict, (await watch.PostAsJsonAsync("/training/api/watch/v1/reservation/ready", CommandFor(ready))).StatusCode);
        await Read(await phone.PutAsJsonAsync($"/training/api/sessions/{other["id"]}", write));
    }
}
