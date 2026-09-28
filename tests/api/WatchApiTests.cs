using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using TrainingLog;

namespace TrainingLogTests;

public partial class WatchApiTests {
    const string Password = "Watch-tests-only!123";
    sealed class Factory(bool reservationsEnabled = true) : WebApplicationFactory<Program> {
        public readonly string DirectoryPath = Path.Combine(Path.GetTempPath(), "traininglog-watch-tests-" + Guid.NewGuid());
        protected override void ConfigureWebHost(IWebHostBuilder b) {
            Directory.CreateDirectory(DirectoryPath);
            File.WriteAllText(Path.Combine(DirectoryPath, "password"), Password);
            b.UseEnvironment("Development").UseSetting("DataDirectory", DirectoryPath)
                .UseSetting("OwnerPasswordFile", Path.Combine(DirectoryPath, "password")).UseSetting("Watch:Enabled", "true").UseSetting("Watch:ReservationsEnabled", reservationsEnabled ? "true" : "false");
        }
        protected override void Dispose(bool disposing) {
            base.Dispose(disposing);
            if (disposing && Directory.Exists(DirectoryPath)) Directory.Delete(DirectoryPath, true);
        }
    }
    static JsonNode Fixture() => JsonNode.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "watch-session.json")))!;
    static async Task<JsonElement> Read(HttpResponseMessage response) {
        var text = await response.Content.ReadAsStringAsync();
        Assert.True(response.IsSuccessStatusCode, $"HTTP {(int)response.StatusCode}: {text}");
        return JsonDocument.Parse(text).RootElement.Clone();
    }
    static async Task Login(HttpClient c) {
        var state = await c.GetFromJsonAsync<JsonElement>("/training/api/auth/state");
        c.DefaultRequestHeaders.Add("X-CSRF-TOKEN", state.GetProperty("token").GetString());
        (await c.PostAsJsonAsync("/training/api/auth/login", new { password = Password })).EnsureSuccessStatusCode();
        state = await c.GetFromJsonAsync<JsonElement>("/training/api/auth/state");
        c.DefaultRequestHeaders.Remove("X-CSRF-TOKEN"); c.DefaultRequestHeaders.Add("X-CSRF-TOKEN", state.GetProperty("token").GetString());
    }
    static async Task<JsonElement> Pair(HttpClient phone, HttpClient watch) {
        var code = await Read(await phone.PostAsJsonAsync("/training/api/watch/pairing", new { }));
        var paired = await Read(await watch.PostAsJsonAsync("/training/api/watch/pairing/redeem", new { code = code.GetProperty("code").GetString(), name = "TEST WATCH" }));
        watch.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", paired.GetProperty("token").GetString());
        return paired;
    }
    static WatchCommand Command(JsonElement snapshot, string? deviceId = null) => new(Guid.NewGuid().ToString(), snapshot.GetProperty("generation").GetString()!, snapshot.GetProperty("version").GetInt64(), snapshot.GetProperty("control").GetProperty("controlEpoch").GetInt64(), snapshot.GetProperty("sessionId").GetString()!, deviceId, snapshot.GetProperty("control").GetProperty("handoffId").GetString());
    static async Task<JsonElement> Seed(HttpClient phone, JsonNode payload) {
        var boot = await phone.GetFromJsonAsync<JsonElement>("/training/api/bootstrap");
        await Read(await phone.PutAsJsonAsync($"/training/api/sessions/{payload["id"]}", new { operationId = Guid.NewGuid(), contractVersion = 2, generation = boot.GetProperty("generation").GetString(), baseVersion = 0, payload }));
        return await phone.GetFromJsonAsync<JsonElement>($"/training/api/sessions/{payload["id"]}/watch-control");
    }
    static async Task<JsonElement> Assign(HttpClient phone, HttpClient watch, JsonNode payload, JsonElement device) {
        var snapshot = await Seed(phone, payload);
        var offer = await Read(await phone.PostAsJsonAsync($"/training/api/sessions/{payload["id"]}/watch-handoff", Command(snapshot, device.GetProperty("deviceId").GetString())));
        return await Read(await watch.PostAsJsonAsync("/training/api/watch/v1/handoff/accept", Command(offer)));
    }
    static WatchWrite Write(JsonElement snapshot, JsonNode payload, string? operation = null) => new(operation ?? Guid.NewGuid().ToString(), snapshot.GetProperty("generation").GetString()!, snapshot.GetProperty("version").GetInt64(), snapshot.GetProperty("control").GetProperty("controlEpoch").GetInt64(), JsonSerializer.SerializeToElement(payload), 1, 2);

    [Fact] public async Task Full_handoff_write_replay_return_and_legacy_lock() {
        await using var factory = new Factory(); using var phone = factory.CreateClient(); using var watch = factory.CreateClient();
        await Login(phone); var device = await Pair(phone, watch); var payload = Fixture(); var id = payload["id"]!.GetValue<string>();
        var snapshot = await Seed(phone, payload);
        var handoff = Command(snapshot, device.GetProperty("deviceId").GetString());
        var offered = await Read(await phone.PostAsJsonAsync($"/training/api/sessions/{id}/watch-handoff", handoff));
        var repeatedOffer = await Read(await phone.PostAsJsonAsync($"/training/api/sessions/{id}/watch-handoff", handoff));
        Assert.Equal(offered.GetRawText(), repeatedOffer.GetRawText());
        var legacy = new { operationId = Guid.NewGuid(), contractVersion = 2, generation = handoff.Generation, baseVersion = handoff.BaseVersion, payload };
        Assert.Equal((HttpStatusCode)423, (await phone.PutAsJsonAsync($"/training/api/sessions/{id}", legacy)).StatusCode);
        var accept = Command(offered);
        var accepted = await Read(await watch.PostAsJsonAsync("/training/api/watch/v1/handoff/accept", accept));
        Assert.Equal(accepted.GetRawText(), (await Read(await watch.PostAsJsonAsync("/training/api/watch/v1/handoff/accept", accept))).GetRawText());
        Assert.Equal("watch", accepted.GetProperty("control").GetProperty("state").GetString());
        payload["revision"] = 2; payload["exercises"]![0]!["records"]![0]!["weight"] = "12,5";
        var write = Write(accepted, payload);
        var saved = await Read(await watch.PutAsJsonAsync($"/training/api/watch/v1/sessions/{id}", write));
        Assert.Equal(saved.GetRawText(), (await Read(await watch.PutAsJsonAsync($"/training/api/watch/v1/sessions/{id}", write))).GetRawText());
        var current = await phone.GetFromJsonAsync<JsonElement>($"/training/api/sessions/{id}/watch-control");
        var release = Command(current);
        await Read(await watch.PostAsJsonAsync("/training/api/watch/v1/control/release", release));
        await Read(await watch.PostAsJsonAsync("/training/api/watch/v1/control/release", release));
        // Lost response to an already committed write remains replayable after release.
        Assert.Equal(saved.GetRawText(), (await Read(await watch.PutAsJsonAsync($"/training/api/watch/v1/sessions/{id}", write))).GetRawText());
        current = await phone.GetFromJsonAsync<JsonElement>($"/training/api/sessions/{id}/watch-control");
        Assert.Equal("phone", current.GetProperty("control").GetProperty("state").GetString());
        Assert.Equal("12,5", current.GetProperty("payload").GetProperty("exercises")[0].GetProperty("records")[0].GetProperty("weight").GetString());
        Assert.True(current.GetProperty("payload").GetProperty("futureSession").TryGetProperty("preserve", out _));
        Assert.Equal(HttpStatusCode.Conflict, (await phone.PutAsJsonAsync($"/training/api/sessions/{id}", legacy)).StatusCode);
    }

    [Fact] public async Task Force_return_preserves_snapshot_and_rejects_stale_watch_write() {
        await using var factory = new Factory(); using var phone = factory.CreateClient(); using var watch = factory.CreateClient();
        await Login(phone); var device = await Pair(phone, watch); var payload = Fixture(); var accepted = await Assign(phone, watch, payload, device);
        var id = payload["id"]!.GetValue<string>();
        await Read(await phone.PostAsJsonAsync($"/training/api/sessions/{id}/watch-force-return", Command(accepted)));
        payload["revision"] = 2;
        Assert.Equal(HttpStatusCode.Conflict, (await watch.PutAsJsonAsync($"/training/api/watch/v1/sessions/{id}", Write(accepted, payload))).StatusCode);
        var recovery = new WatchRecoveryWrite(Guid.NewGuid().ToString(), id, JsonSerializer.SerializeToElement(payload));
        var uploaded = await Read(await watch.PostAsJsonAsync("/training/api/watch/v1/recovery", recovery));
        Assert.Equal(uploaded.GetRawText(), (await Read(await watch.PostAsJsonAsync("/training/api/watch/v1/recovery", recovery))).GetRawText());
        var archive = await phone.GetFromJsonAsync<JsonElement>("/training/api/watch/recovery");
        Assert.Equal(2, archive.GetArrayLength());
    }

    [Fact] public async Task Tokens_are_scoped_revocable_and_not_csrf_bypass() {
        await using var factory = new Factory(); using var phone = factory.CreateClient(); using var watch = factory.CreateClient(); using var other = factory.CreateClient();
        await Login(phone); var device = await Pair(phone, watch); var payload = Fixture(); var accepted = await Assign(phone, watch, payload, device);
        Assert.Equal(HttpStatusCode.Unauthorized, (await watch.GetAsync("/training/api/export")).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await phone.GetAsync("/training/api/watch/v1/session")).StatusCode);
        other.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", "fake");
        Assert.Equal(HttpStatusCode.BadRequest, (await other.PostAsJsonAsync("/training/api/auth/login", new { password = Password })).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await other.GetAsync("/training/api/watch/v1/session")).StatusCode);
        var second = await Pair(phone, other);
        Assert.Equal(JsonValueKind.Null, (await other.GetFromJsonAsync<JsonElement>("/training/api/watch/v1/session")).GetProperty("session").ValueKind);
        payload["revision"] = 2;
        Assert.Equal(HttpStatusCode.Conflict, (await other.PutAsJsonAsync($"/training/api/watch/v1/sessions/{payload["id"]}", Write(accepted, payload))).StatusCode);
        await Read(await phone.DeleteAsync($"/training/api/watch/devices/{device.GetProperty("deviceId").GetString()}"));
        Assert.Equal(HttpStatusCode.Unauthorized, (await watch.GetAsync("/training/api/watch/v1/session")).StatusCode);
        Assert.Equal("watch", (await phone.GetFromJsonAsync<JsonElement>($"/training/api/sessions/{payload["id"]}/watch-control")).GetProperty("control").GetProperty("state").GetString());
    }

    [Fact] public async Task Pairing_code_consumption_expiry_and_token_storage() {
        await using var factory = new Factory(); using var phone = factory.CreateClient(); using var watch = factory.CreateClient();
        await Login(phone);
        var code = await Read(await phone.PostAsJsonAsync("/training/api/watch/pairing", new { }));
        var redeem = new { code = code.GetProperty("code").GetString(), name = "TEST" };
        var paired = await Read(await watch.PostAsJsonAsync("/training/api/watch/pairing/redeem", redeem));
        Assert.Equal(HttpStatusCode.BadRequest, (await watch.PostAsJsonAsync("/training/api/watch/pairing/redeem", redeem)).StatusCode);
        using var scope = factory.Services.CreateScope(); var db = scope.ServiceProvider.GetRequiredService<Store>();
        Assert.DoesNotContain(paired.GetProperty("token").GetString()!, (await db.WatchDevices.SingleAsync()).TokenHash);
        code = await Read(await phone.PostAsJsonAsync("/training/api/watch/pairing", new { }));
        await db.WatchPairings.ExecuteUpdateAsync(s => s.SetProperty(x => x.ExpiresAt, 0));
        Assert.Equal(HttpStatusCode.BadRequest, (await watch.PostAsJsonAsync("/training/api/watch/pairing/redeem", new { code = code.GetProperty("code").GetString(), name = "TEST" })).StatusCode);
    }

    [Fact] public async Task Invalid_diff_and_operation_reuse_are_rejected_and_finish_is_idempotent() {
        await using var factory = new Factory(); using var phone = factory.CreateClient(); using var watch = factory.CreateClient();
        await Login(phone); var device = await Pair(phone, watch); var payload = Fixture(); var accepted = await Assign(phone, watch, payload, device);
        var id = payload["id"]!.GetValue<string>(); payload["revision"] = 2;
        var invalid = payload.DeepClone(); invalid["name"] = "Cannot replace session name";
        Assert.Equal(HttpStatusCode.BadRequest, (await watch.PutAsJsonAsync($"/training/api/watch/v1/sessions/{id}", Write(accepted, invalid))).StatusCode);
        foreach (var e in payload["exercises"]!.AsArray()) foreach (var r in e!["records"]!.AsArray()) r!["status"] = "skipped";
        payload["status"] = "completed"; payload["completedAt"] = DateTimeOffset.UtcNow.ToString("O"); payload["restEndsAt"] = null;
        var write = Write(accepted, payload); var finished = await Read(await watch.PutAsJsonAsync($"/training/api/watch/v1/sessions/{id}", write));
        Assert.Equal("phone", finished.GetProperty("control").GetProperty("state").GetString());
        Assert.Equal(finished.GetRawText(), (await Read(await watch.PutAsJsonAsync($"/training/api/watch/v1/sessions/{id}", write))).GetRawText());
        payload["revision"] = 3;
        Assert.Equal(HttpStatusCode.Conflict, (await watch.PutAsJsonAsync($"/training/api/watch/v1/sessions/{id}", Write(accepted, payload, write.OperationId))).StatusCode);
    }

    [Fact] public async Task Password_change_revokes_tokens_and_unused_pairing_codes_without_unlocking_session() {
        await using var factory = new Factory(); using var phone = factory.CreateClient(); using var watch = factory.CreateClient();
        await Login(phone); var device = await Pair(phone, watch); var payload = Fixture();
        await Assign(phone, watch, payload, device);
        var code = await Read(await phone.PostAsJsonAsync("/training/api/watch/pairing", new { }));
        (await phone.PostAsJsonAsync("/training/api/auth/password", new { currentPassword = Password, newPassword = "Changed-test-password!456" })).EnsureSuccessStatusCode();
        Assert.Equal(HttpStatusCode.Unauthorized, (await watch.GetAsync("/training/api/watch/v1/session")).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await watch.PostAsJsonAsync("/training/api/watch/pairing/redeem", new { code = code.GetProperty("code").GetString(), name = "TEST" })).StatusCode);
        Assert.Equal("watch", (await phone.GetFromJsonAsync<JsonElement>($"/training/api/sessions/{payload["id"]}/watch-control")).GetProperty("control").GetProperty("state").GetString());
    }

    [Fact] public async Task Concurrent_handoffs_have_one_winner_and_wrong_generation_is_rejected() {
        await using var factory = new Factory(); using var phone = factory.CreateClient(); using var watch = factory.CreateClient();
        await Login(phone); var device = await Pair(phone, watch); var payload = Fixture(); var snapshot = await Seed(phone, payload);
        var command = Command(snapshot, device.GetProperty("deviceId").GetString());
        var path = $"/training/api/sessions/{payload["id"]}/watch-handoff";
        Assert.Equal(HttpStatusCode.Conflict, (await phone.PostAsJsonAsync(path, command with { Generation = "old-database" })).StatusCode);
        var results = await Task.WhenAll(phone.PostAsJsonAsync(path, command), phone.PostAsJsonAsync(path, command with { OperationId = Guid.NewGuid().ToString() }));
        Assert.Single(results, r => r.IsSuccessStatusCode);
        Assert.Single(results, r => r.StatusCode == HttpStatusCode.Conflict);
    }

    [Fact] public async Task No_code_link_requires_owner_window_secret_and_explicit_approval() {
        await using var factory = new Factory(); using var phone = factory.CreateClient(); using var watch = factory.CreateClient();
        await Login(phone);
        var request = new WatchLinkStart(Guid.NewGuid().ToString(), Convert.ToHexString(System.Security.Cryptography.RandomNumberGenerator.GetBytes(32)), "TEST WATCH");
        Assert.Equal(HttpStatusCode.Conflict, (await watch.PostAsJsonAsync("/training/api/watch/link/request", request)).StatusCode);
        await Read(await phone.PostAsJsonAsync("/training/api/watch/link/window", new {}));
        var pending = await Read(await watch.PostAsJsonAsync("/training/api/watch/link/request", request));
        Assert.Equal("pending", pending.GetProperty("state").GetString());
        Assert.Equal(pending.GetRawText(), (await Read(await watch.PostAsJsonAsync("/training/api/watch/link/request", request))).GetRawText());
        Assert.Equal(HttpStatusCode.Gone, (await watch.PostAsJsonAsync("/training/api/watch/link/status", new WatchLinkPoll(request.Id, new string('0',64)))).StatusCode);
        watch.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer",request.Token);
        Assert.Equal(HttpStatusCode.Unauthorized, (await watch.GetAsync("/training/api/watch/v1/session")).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await watch.PostAsJsonAsync($"/training/api/watch/link/requests/{request.Id}/approve", new{})).StatusCode);
        var list = await phone.GetFromJsonAsync<JsonElement>("/training/api/watch/link/requests");
        Assert.Equal(pending.GetProperty("label").GetString(), list[0].GetProperty("label").GetString());
        await Read(await phone.PostAsJsonAsync($"/training/api/watch/link/requests/{request.Id}/approve", new{}));
        await Read(await phone.PostAsJsonAsync($"/training/api/watch/link/requests/{request.Id}/approve", new{}));
        var approved = await Read(await watch.PostAsJsonAsync("/training/api/watch/link/status",new WatchLinkPoll(request.Id,request.Token)));
        Assert.Equal("approved",approved.GetProperty("state").GetString());
        Assert.Equal(HttpStatusCode.OK,(await watch.GetAsync("/training/api/watch/v1/session")).StatusCode);
        using var scope=factory.Services.CreateScope();var db=scope.ServiceProvider.GetRequiredService<Store>();
        Assert.NotEqual(request.Token,(await db.WatchLinkRequests.SingleAsync()).TokenHash);
        Assert.Equal(1,await db.WatchDevices.CountAsync());
        await Read(await phone.DeleteAsync($"/training/api/watch/devices/{request.Id}"));
        Assert.Equal(HttpStatusCode.Unauthorized,(await watch.PostAsJsonAsync("/training/api/watch/link/status",new WatchLinkPoll(request.Id,request.Token))).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized,(await watch.PostAsJsonAsync("/training/api/watch/link/request",request)).StatusCode);
    }

    [Fact] public async Task Expired_and_replaced_link_windows_cannot_be_approved() {
        await using var factory = new Factory(); using var phone = factory.CreateClient(); using var watch = factory.CreateClient();
        await Login(phone);await Read(await phone.PostAsJsonAsync("/training/api/watch/link/window",new{}));
        var request=new WatchLinkStart(Guid.NewGuid().ToString(),Convert.ToHexString(System.Security.Cryptography.RandomNumberGenerator.GetBytes(32)),"TEST");
        await Read(await watch.PostAsJsonAsync("/training/api/watch/link/request",request));
        using var scope=factory.Services.CreateScope();var db=scope.ServiceProvider.GetRequiredService<Store>();
        await db.WatchLinkRequests.ExecuteUpdateAsync(s=>s.SetProperty(x=>x.ExpiresAt,0));
        Assert.Equal(HttpStatusCode.Conflict,(await phone.PostAsJsonAsync($"/training/api/watch/link/requests/{request.Id}/approve",new{})).StatusCode);
        Assert.Equal(HttpStatusCode.Gone,(await watch.PostAsJsonAsync("/training/api/watch/link/status",new WatchLinkPoll(request.Id,request.Token))).StatusCode);
        await Read(await phone.PostAsJsonAsync("/training/api/watch/link/window",new{}));
        request=request with {Id=Guid.NewGuid().ToString()};await Read(await watch.PostAsJsonAsync("/training/api/watch/link/request",request));
        await Read(await phone.PostAsJsonAsync("/training/api/watch/link/window",new{}));
        Assert.Equal(HttpStatusCode.Conflict,(await phone.PostAsJsonAsync($"/training/api/watch/link/requests/{request.Id}/approve",new{})).StatusCode);
    }
}
