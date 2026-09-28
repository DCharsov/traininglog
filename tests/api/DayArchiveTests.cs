using System.Text.Json;
using TrainingLog;

namespace TrainingLogTests;
public class DayArchiveTests {
    [Fact] public void Legacy_program_edits_preserve_day_archive_but_explicit_null_restores() {
        const string previous = "{\"days\":[{\"id\":\"same\",\"archivedAt\":\"2026-09-28T10:00:00Z\"}]}";
        using var legacy = JsonDocument.Parse("{\"days\":[{\"id\":\"same\",\"name\":\"Edited\"},{\"id\":\"new\"}]}");
        using var result = JsonDocument.Parse(DocumentWriter.PreserveDayArchives(previous, legacy.RootElement));
        Assert.Equal("2026-09-28T10:00:00Z", result.RootElement.GetProperty("days")[0].GetProperty("archivedAt").GetString());
        Assert.Equal("Edited", result.RootElement.GetProperty("days")[0].GetProperty("name").GetString());
        Assert.False(result.RootElement.GetProperty("days")[1].TryGetProperty("archivedAt", out _));
        using var restore = JsonDocument.Parse("{\"days\":[{\"id\":\"same\",\"archivedAt\":null}]}");
        using var restored = JsonDocument.Parse(DocumentWriter.PreserveDayArchives(previous, restore.RootElement));
        Assert.Equal(JsonValueKind.Null, restored.RootElement.GetProperty("days")[0].GetProperty("archivedAt").ValueKind);
    }
}
