using System.Security.Cryptography;
using Microsoft.EntityFrameworkCore;

namespace TrainingLog;

public static partial class WatchApi {
    static bool LinkSecret(string? value) => value != null && System.Text.RegularExpressions.Regex.IsMatch(value, "^[A-Fa-f0-9]{64}$");
    static readonly string[] LinkWords = ["Луна", "Кедр", "Море", "Сокол", "Маяк", "Ветер", "Лес", "Снег", "Озеро", "Клён", "Солнце", "Лотос", "Тигр", "Река", "Кит", "Звезда", "Облако", "Камень", "Мост", "Лев", "Волна", "Дуб", "Рысь", "Парус", "Ирис", "Панда", "Полюс", "Сосна", "Орёл", "Риф", "Янтарь", "Комета"];
    static object LinkState(WatchLinkRequest row) => new { requestId = row.Id, label = row.Label, expiresAt = row.ExpiresAt, state = row.Approved ? "approved" : "pending", protocolVersion = 1, contractVersion = 2 };

    static void MapWatchLink(RouteGroupBuilder api) {
        // Only an authenticated owner can open the short discovery window. No automatic trust by proximity/IP.
        api.MapPost("/watch/link/window", (HttpContext c, Store db) => Locked(c, db, async () => {
            if (!Enabled(c)) return Error(503, "watch_disabled");
            var owner = Owner(c); var key = "link-window:" + owner;
            await db.WatchLinkRequests.Where(x => x.ExpiresAt <= Now || (x.Owner == owner && !x.Approved)).ExecuteDeleteAsync();
            var window = await db.WatchPairings.FindAsync(key);
            if (window == null) { window = new() { Hash = key, Owner = owner }; db.WatchPairings.Add(window); }
            window.ExpiresAt = Now + 120_000; window.Consumed = false;
            return Results.Ok(new { expiresAt = window.ExpiresAt });
        })).RequireAuthorization();

        api.MapPost("/watch/link/request", (WatchLinkStart r, HttpContext c, Store db) => Locked(c, db, async () => {
            if (!Guid.TryParse(r.Id, out _) || !LinkSecret(r.Token) || string.IsNullOrWhiteSpace(r.Name) || r.Name.Length > 100) return Error(400, "validation");
            var hash = Hash(r.Token);
            var existing = await db.WatchLinkRequests.FindAsync(r.Id);
            if (existing != null) {
                if (existing.TokenHash != hash || existing.ExpiresAt <= Now) return Error(409, "request_expired");
                if (existing.Approved && !await db.WatchDevices.AnyAsync(x => x.Id == existing.Id && x.RevokedAt == null && x.ExpiresAt > Now)) return Error(401, "device_revoked");
                return Results.Ok(LinkState(existing));
            }
            if (await db.WatchDevices.AnyAsync(x => x.Id == r.Id || x.TokenHash == hash)) return Error(409, "request_reused");
            if (!Enabled(c)) return Error(503, "watch_disabled");
            var windows = await db.WatchPairings.Where(x => x.Hash.StartsWith("link-window:") && !x.Consumed && x.ExpiresAt > Now).ToListAsync();
            if (windows.Count != 1) return Error(409, "open_phone", "На телефоне нажмите «Подключить часы», затем повторите.");
            var window = windows[0];
            if (await db.WatchLinkRequests.CountAsync(x => x.Owner == window.Owner && !x.Approved && x.ExpiresAt > Now) >= 3) return Error(429, "request_limit");
            var random = RandomNumberGenerator.GetBytes(3);
            var row = new WatchLinkRequest { Id = r.Id, Owner = window.Owner, TokenHash = hash, Name = r.Name, ExpiresAt = window.ExpiresAt,
                Label = string.Join(" · ", random.Select(b => LinkWords[b % LinkWords.Length])) };
            db.WatchLinkRequests.Add(row);
            return Results.Ok(LinkState(row));
        })).WithMetadata(new WatchRedeemEndpoint()).RequireRateLimiting("watch-link-start");

        api.MapGet("/watch/link/requests", async (HttpContext c, Store db) => {
            var owner = Owner(c);
            return Results.Ok(await db.WatchLinkRequests.Where(x => x.Owner == owner && !x.Approved && x.ExpiresAt > Now)
                .Select(x => new { x.Id, x.Name, x.Label, x.ExpiresAt }).ToListAsync());
        }).RequireAuthorization();

        api.MapPost("/watch/link/requests/{id}/approve", (string id, HttpContext c, Store db) => Locked(c, db, async () => {
            var owner = Owner(c);
            var row = await db.WatchLinkRequests.SingleOrDefaultAsync(x => x.Id == id && x.Owner == owner);
            if (row == null || row.ExpiresAt <= Now) return Error(409, "request_expired");
            if (row.Approved) return Results.Ok(new { approved = true });
            if (!Enabled(c)) return Error(503, "watch_disabled");
            var window = await db.WatchPairings.FindAsync("link-window:" + owner);
            if (window == null || window.Consumed || window.ExpiresAt <= Now) return Error(409, "request_expired");
            if (await db.WatchDevices.CountAsync(x => x.Owner == owner && x.RevokedAt == null && x.ExpiresAt > Now) >= 10) return Error(409, "device_limit");
            row.Approved = true; row.ExpiresAt = Now + 90L * 86400_000;
            db.WatchDevices.Add(new() { Id = row.Id, Owner = owner, TokenHash = row.TokenHash, Name = row.Name, ExpiresAt = row.ExpiresAt, LastSeenAt = Now });
            window.Consumed = true;
            await db.WatchLinkRequests.Where(x => x.Owner == owner && x.Id != id && !x.Approved).ExecuteDeleteAsync();
            return Results.Ok(new { approved = true });
        })).RequireAuthorization();

        // The secret is never a URL parameter or a plaintext database field. Retrying approval/status is safe.
        api.MapPost("/watch/link/status", (WatchLinkPoll r, HttpContext c, Store db) => Locked(c, db, async () => {
            if (!Guid.TryParse(r.Id, out _) || !LinkSecret(r.Token)) return Error(400, "validation");
            var hash = Hash(r.Token);
            var row = await db.WatchLinkRequests.SingleOrDefaultAsync(x => x.Id == r.Id && x.TokenHash == hash && x.ExpiresAt > Now);
            if (row == null) return Error(410, "request_expired");
            if (row.Approved && !await db.WatchDevices.AnyAsync(x => x.Id == row.Id && x.RevokedAt == null && x.ExpiresAt > Now)) return Error(401, "device_revoked");
            return Results.Ok(LinkState(row));
        })).WithMetadata(new WatchRedeemEndpoint()).RequireRateLimiting("watch-link-poll");
    }
}
