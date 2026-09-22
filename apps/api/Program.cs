using Microsoft.AspNetCore.RateLimiting;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Antiforgery;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using TrainingLog;

var builder=WebApplication.CreateBuilder(args);
var dataDir=Path.GetFullPath(builder.Configuration["DataDirectory"] ?? "data");
Directory.CreateDirectory(dataDir);
builder.WebHost.ConfigureKestrel(o=>o.Limits.MaxRequestBodySize=2*1024*1024);
builder.Services.AddDbContext<Store>(o=>o.UseSqlite($"Data Source={Path.Combine(dataDir,"training.db")}"));
builder.Services.AddDataProtection().PersistKeysToFileSystem(new DirectoryInfo(Path.Combine(dataDir,"keys"))).SetApplicationName("TrainingLog");
builder.Services.AddIdentity<IdentityUser,IdentityRole>(o=>{
    o.Password.RequiredLength=12;o.Lockout.MaxFailedAccessAttempts=5;o.Lockout.DefaultLockoutTimeSpan=TimeSpan.FromMinutes(15);
}).AddEntityFrameworkStores<Store>().AddDefaultTokenProviders();
builder.Services.ConfigureApplicationCookie(o=>{
    o.Cookie.Name="TrainingLog.Auth";o.Cookie.Path="/training/api";o.Cookie.HttpOnly=true;o.Cookie.SameSite=SameSiteMode.Strict;
    o.Cookie.SecurePolicy=builder.Environment.IsDevelopment()?CookieSecurePolicy.SameAsRequest:CookieSecurePolicy.Always;
    o.ExpireTimeSpan=TimeSpan.FromDays(14);o.SlidingExpiration=true;
    o.Events.OnRedirectToLogin=c=>{c.Response.StatusCode=401;return Task.CompletedTask;};
    o.Events.OnRedirectToAccessDenied=c=>{c.Response.StatusCode=403;return Task.CompletedTask;};
});
builder.Services.AddAuthorization();
builder.Services.AddAntiforgery(o=>{
    o.HeaderName="X-CSRF-TOKEN";o.Cookie.Name="TrainingLog.Csrf";o.Cookie.Path="/training/api";o.Cookie.SameSite=SameSiteMode.Strict;
    o.Cookie.SecurePolicy=builder.Environment.IsDevelopment()?CookieSecurePolicy.SameAsRequest:CookieSecurePolicy.Always;
});
builder.Services.AddRateLimiter(o=>{o.RejectionStatusCode=429;o.AddFixedWindowLimiter("login",x=>{x.PermitLimit=10;x.Window=TimeSpan.FromMinutes(1);x.QueueLimit=0;});});
var app=builder.Build();
using(var scope=app.Services.CreateScope()) {
    var store=scope.ServiceProvider.GetRequiredService<Store>();await store.Database.MigrateAsync();
    if(!await store.Settings.AnyAsync(x=>x.Id=="generation")) {store.Settings.Add(new(){Id="generation",Value=Guid.NewGuid().ToString()});await store.SaveChangesAsync();}
    var users=scope.ServiceProvider.GetRequiredService<UserManager<IdentityUser>>();
    if(!await users.Users.AnyAsync()) {
        var file=builder.Configuration["OwnerPasswordFile"] ?? throw new InvalidOperationException("OwnerPasswordFile is required for first start.");
        var password=(await File.ReadAllTextAsync(file)).Trim();
        var result=await users.CreateAsync(new IdentityUser("owner"),password);
        if(!result.Succeeded) throw new InvalidOperationException("Owner password does not meet policy.");
    }
}
app.UseForwardedHeaders(new Microsoft.AspNetCore.Builder.ForwardedHeadersOptions { ForwardedHeaders=Microsoft.AspNetCore.HttpOverrides.ForwardedHeaders.XForwardedFor | Microsoft.AspNetCore.HttpOverrides.ForwardedHeaders.XForwardedProto });
app.UseExceptionHandler(handler=>handler.Run(async c=>{c.Response.StatusCode=500;await c.Response.WriteAsJsonAsync(new{error="server",message="Не удалось сохранить запись на сервере. Локальные данные сохранены; повторите синхронизацию."});}));
app.UseStatusCodePages(async context=>{var c=context.HttpContext;await c.Response.WriteAsJsonAsync(new{error=c.Response.StatusCode switch {401=>"authentication",403=>"forbidden",404=>"not_found",429=>"rate_limit",_=>"request"},message=c.Response.StatusCode switch {401=>"Нужен вход",403=>"Нет доступа",404=>"Запись не найдена",429=>"Слишком много попыток. Подождите минуту.",_=>"Проверьте формат запроса."}});});
app.UseAuthentication();app.UseAuthorization();app.UseRateLimiter();
app.Use(async(ctx,next)=>{
    ctx.Response.Headers.CacheControl="no-store";
    if(ctx.Request.Method is not ("GET" or "HEAD" or "OPTIONS")) {
        try {await ctx.RequestServices.GetRequiredService<IAntiforgery>().ValidateRequestAsync(ctx);}
        catch(AntiforgeryValidationException) {ctx.Response.StatusCode=400;await ctx.Response.WriteAsJsonAsync(new{error="csrf",message="Обновите страницу и повторите вход."});return;}
    }
    await next();
});
var api=app.MapGroup("/training/api");
api.MapGet("/openapi.json",()=>Results.File(Path.Combine(AppContext.BaseDirectory,"openapi.json"),"application/json"));
api.MapGet("/health",()=>Results.Ok(new{status="ok",contractVersion=2}));
api.MapGet("/auth/state",(HttpContext c,IAntiforgery a)=>Results.Ok(new{authenticated=c.User.Identity?.IsAuthenticated==true,token=a.GetAndStoreTokens(c).RequestToken}));
api.MapPost("/auth/login",async(LoginRequest r,SignInManager<IdentityUser> sign)=>{
    if(string.IsNullOrEmpty(r.Password)||r.Password.Length>256)return Results.BadRequest();
    var result=await sign.PasswordSignInAsync("owner",r.Password,true,true);
    return result.Succeeded?Results.Ok():Results.Json(new{error="login",message="Неверный пароль или вход временно заблокирован."},statusCode:401);
}).RequireRateLimiting("login");
api.MapPost("/auth/logout",async(SignInManager<IdentityUser> sign)=>{await sign.SignOutAsync();return Results.Ok();}).RequireAuthorization();
api.MapPost("/auth/password",async(PasswordRequest r,HttpContext c,UserManager<IdentityUser> users,SignInManager<IdentityUser> sign)=>{
    if(string.IsNullOrEmpty(r.NewPassword)||r.NewPassword.Length>256||string.IsNullOrEmpty(r.CurrentPassword)||r.CurrentPassword.Length>256)return Results.BadRequest();
    var user=(await users.GetUserAsync(c.User))!;var result=await users.ChangePasswordAsync(user,r.CurrentPassword,r.NewPassword);
    if(!result.Succeeded)return Results.BadRequest(new{message="Проверьте текущий пароль. Новый: от 12 символов, заглавные и строчные буквы, цифра и спецсимвол."});
    await sign.RefreshSignInAsync(user);return Results.Ok();
}).RequireAuthorization().RequireRateLimiting("login");
api.MapGet("/bootstrap",async(Store db)=>Results.Ok(new{contractVersion=2,generation=(await db.Settings.FindAsync("generation"))!.Value})).RequireAuthorization();
api.MapGet("/changes",async(long? after,string? generation,HttpContext c,Store db)=>{
    var gen=(await db.Settings.FindAsync("generation"))!.Value;
    if(generation!=gen)return Results.Json(new{error="generation",generation=gen},statusCode:409);
    var owner=c.User.FindFirstValue(ClaimTypes.NameIdentifier)!;
    var changes=await db.Changes.AsNoTracking().Where(x=>x.Owner==owner && x.Sequence>(after??0)).OrderBy(x=>x.Sequence).Take(25).ToListAsync();
    return Results.Ok(new{generation=gen,changes=changes.Select(x=>new{x.Sequence,x.Kind,x.Id,x.Version,payload=JsonSerializer.Deserialize<JsonElement>(x.Payload)}),cursor=changes.LastOrDefault()?.Sequence??after??0,hasMore=changes.Count==25});
}).RequireAuthorization();
api.MapGet("/{kind}/{id}",async(string kind,string id,HttpContext c,Store db)=>{
    if(!new[]{"programs","sessions","equipment","calendar"}.Contains(kind))return Results.NotFound();
    var owner=c.User.FindFirstValue(ClaimTypes.NameIdentifier)!;
    var doc=await db.Documents.AsNoTracking().SingleOrDefaultAsync(x=>x.Owner==owner&&x.Kind==kind&&x.Id==id);
    return doc==null?Results.NotFound():Results.Ok(new{doc.Id,doc.Version,payload=JsonSerializer.Deserialize<JsonElement>(doc.Payload)});
}).RequireAuthorization();
api.MapGet("/{kind}",async(string kind,long? after,HttpContext c,Store db)=>{
    if(!new[]{"programs","sessions","equipment","calendar"}.Contains(kind))return Results.NotFound();
    var owner=c.User.FindFirstValue(ClaimTypes.NameIdentifier)!;
    var rows=await db.Changes.AsNoTracking().Where(x=>x.Owner==owner&&x.Kind==kind&&x.Sequence>(after??0)).OrderBy(x=>x.Sequence).Take(25).ToListAsync();
    return Results.Ok(new{items=rows.Select(x=>new{x.Id,x.Version,payload=JsonSerializer.Deserialize<JsonElement>(x.Payload)}),cursor=rows.LastOrDefault()?.Sequence??after??0,hasMore=rows.Count==25});
}).RequireAuthorization();
var writeGate=new SemaphoreSlim(1,1); // One SQLite writer; version check, operation receipt and change are one transaction.
api.MapPut("/{kind}/{id}",async(string kind,string id,WriteRequest r,HttpContext c,Store db)=>{
    if(r.ContractVersion!=2)return Results.Json(new{error="schema",message="Доступно обновление дневника. Закройте все его вкладки и откройте снова. Локальные записи сохранятся."},statusCode:426);
    if(!Guid.TryParse(r.OperationId,out _) || r.BaseVersion<0 || !Validation.Valid(kind,id,r.Payload))return Results.BadRequest(new{error="validation",message="Неверный формат записи."});
    await writeGate.WaitAsync(c.RequestAborted);
    try {
        await using var tx=await db.Database.BeginTransactionAsync(c.RequestAborted);
        var generation=(await db.Settings.FindAsync("generation"))!.Value;
        if(r.Generation!=generation)return Results.Json(new{error="generation",generation},statusCode:409);
        var owner=c.User.FindFirstValue(ClaimTypes.NameIdentifier)!;
        var hash=Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(JsonSerializer.Serialize(new{kind,id,r.BaseVersion,r.Generation,r.Payload}))));
        var applied=await db.Operations.FindAsync(owner,r.OperationId);
        if(applied!=null)return applied.Hash==hash?Results.Content(applied.Response,"application/json"):Results.Json(new{error="operation_reused"},statusCode:409);
        var doc=await db.Documents.FindAsync(owner,kind,id);
        if((doc?.Version??0)!=r.BaseVersion)return Results.Json(new{error="conflict",version=doc?.Version??0,payload=doc==null?(JsonElement?)null:JsonSerializer.Deserialize<JsonElement>(doc.Payload)},statusCode:409);
        if(doc==null) {doc=new(){Owner=owner,Kind=kind,Id=id};db.Documents.Add(doc);}
        doc.Version++;doc.Payload=r.Payload.GetRawText();
        db.Changes.Add(new(){Owner=owner,Kind=kind,Id=id,Version=doc.Version,Payload=doc.Payload});
        var response=JsonSerializer.Serialize(new{version=doc.Version,generation});
        db.Operations.Add(new(){Owner=owner,Id=r.OperationId,Hash=hash,Response=response});
        await db.SaveChangesAsync(c.RequestAborted);await tx.CommitAsync(c.RequestAborted);
        return Results.Content(response,"application/json");
    } finally {writeGate.Release();}
}).RequireAuthorization();
api.MapGet("/export",async(HttpContext c,Store db)=>{
    var owner=c.User.FindFirstValue(ClaimTypes.NameIdentifier)!;
    var docs=await db.Documents.AsNoTracking().Where(x=>x.Owner==owner).ToListAsync();
    return Results.Ok(new{equipment=docs.Where(x=>x.Kind=="equipment").Select(x=>JsonSerializer.Deserialize<JsonElement>(x.Payload)),calendar=docs.Where(x=>x.Kind=="calendar").Select(x=>JsonSerializer.Deserialize<JsonElement>(x.Payload)),schemaVersion=2,exportedAt=DateTimeOffset.UtcNow,programs=docs.Where(x=>x.Kind=="programs").Select(x=>JsonSerializer.Deserialize<JsonElement>(x.Payload)),sessions=docs.Where(x=>x.Kind=="sessions").Select(x=>JsonSerializer.Deserialize<JsonElement>(x.Payload))});
}).RequireAuthorization();
app.Run();
public partial class Program {}
