using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace TrainingLogTests;

public partial class WatchApiTests {
    [Fact] public async Task Program_write_preserves_archived_days_for_old_clients_and_replays_receipt() {
        await using var factory = new Factory();
        using var phone = factory.CreateClient();
        await Login(phone);
        var generation = (await phone.GetFromJsonAsync<JsonElement>("/training/api/bootstrap")).GetProperty("generation").GetString()!;
        var id = Guid.NewGuid().ToString();
        var day = new JsonObject {
            ["id"] = Guid.NewGuid().ToString(), ["name"] = "Synthetic day",
            ["archivedAt"] = "2026-09-28T10:00:00Z",
            ["exercises"] = new JsonArray(Fixture()["exercises"]![0]!.DeepClone())
        };
        var program = new JsonObject { ["id"] = id, ["name"] = "Synthetic program", ["version"] = 1, ["days"] = new JsonArray(day) };
        var path = $"/training/api/programs/{id}";
        object Request(JsonNode payload, long version) => new { operationId = Guid.NewGuid(), contractVersion = 2, generation, baseVersion = version, payload = payload.DeepClone() };
        var created = await Read(await phone.PutAsJsonAsync(path, Request(program, 0)));
        day.Remove("archivedAt"); day["name"] = "Legacy edit"; program["version"] = 2;
        var legacy = Request(program, created.GetProperty("version").GetInt64());
        var receipt = await Read(await phone.PutAsJsonAsync(path, legacy));
        var repeated = await Read(await phone.PutAsJsonAsync(path, legacy));
        Assert.Equal(receipt.GetProperty("version").GetInt64(), repeated.GetProperty("version").GetInt64());
        var stored = await phone.GetFromJsonAsync<JsonElement>(path);
        var storedDay = stored.GetProperty("payload").GetProperty("days")[0];
        Assert.Equal("2026-09-28T10:00:00Z", storedDay.GetProperty("archivedAt").GetString());
        Assert.Equal("Legacy edit", storedDay.GetProperty("name").GetString());
        day["archivedAt"] = null; program["version"] = 3;
        await Read(await phone.PutAsJsonAsync(path, Request(program, receipt.GetProperty("version").GetInt64())));
        stored = await phone.GetFromJsonAsync<JsonElement>(path);
        Assert.Equal(JsonValueKind.Null, stored.GetProperty("payload").GetProperty("days")[0].GetProperty("archivedAt").ValueKind);
        Assert.Empty((await phone.GetFromJsonAsync<JsonElement>("/training/api/export")).GetProperty("sessions").EnumerateArray());
    }
}
