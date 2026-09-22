using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.EntityFrameworkCore;
using TrainingLog;
namespace TrainingLogTests;
public class ApiTests {
    const string Password="Test-only-password!123";
    class Factory : WebApplicationFactory<Program> {
        public string Dir=Path.Combine(Path.GetTempPath(),"traininglog-tests-"+Guid.NewGuid());
        protected override void ConfigureWebHost(IWebHostBuilder b) {
            Directory.CreateDirectory(Dir);File.WriteAllText(Path.Combine(Dir,"password"),Password);
            b.UseEnvironment("Development").UseSetting("DataDirectory",Dir).UseSetting("OwnerPasswordFile",Path.Combine(Dir,"password"));
        }
    }
    static object Payload(string id,string name="TEST ONLY")=>new {id,name,version=1,days=new[]{new{id=Guid.NewGuid().ToString(),name="Test day",exercises=new[]{new{id=Guid.NewGuid().ToString(),variantId=Guid.NewGuid().ToString(),equipmentId=Guid.NewGuid().ToString(),name="Test",equipment="Test",mode="BarbellTotal",sets=3,target="10",rest=90}}}}};
    static async Task Token(HttpClient c) {var state=await c.GetFromJsonAsync<JsonElement>("/training/api/auth/state");c.DefaultRequestHeaders.Remove("X-CSRF-TOKEN");c.DefaultRequestHeaders.Add("X-CSRF-TOKEN",state.GetProperty("token").GetString());}
    static async Task Login(HttpClient c) {await Token(c);(await c.PostAsJsonAsync("/training/api/auth/login",new{password=Password})).EnsureSuccessStatusCode();await Token(c);}
    [Fact] public async Task Auth_csrf_idempotency_conflicts_generation_and_private_export() {
        await using var f=new Factory();using var c=f.CreateClient();
        Assert.Equal(HttpStatusCode.Unauthorized,(await c.GetAsync("/training/api/export")).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest,(await c.PostAsJsonAsync("/training/api/auth/login",new{password=Password})).StatusCode);
        await Login(c);
        var boot=await c.GetFromJsonAsync<JsonElement>("/training/api/bootstrap");var gen=boot.GetProperty("generation").GetString();
        var id=Guid.NewGuid().ToString();var operationId=Guid.NewGuid().ToString();var payload=Payload(id);
        var request=new{contractVersion=2,operationId,baseVersion=0,generation=gen,payload};
        var first=await c.PutAsJsonAsync($"/training/api/programs/{id}",request);first.EnsureSuccessStatusCode();
        var repeated=await c.PutAsJsonAsync($"/training/api/programs/{id}",request);repeated.EnsureSuccessStatusCode();
        Assert.Equal(await first.Content.ReadAsStringAsync(),await repeated.Content.ReadAsStringAsync());
        Assert.Equal(HttpStatusCode.Conflict,(await c.PutAsJsonAsync($"/training/api/programs/{id}",new{contractVersion=2,operationId,baseVersion=0,generation=gen,payload=Payload(id,"Different")})).StatusCode);
        var conflict=await c.PutAsJsonAsync($"/training/api/programs/{id}",new{contractVersion=2,operationId=Guid.NewGuid(),baseVersion=0,generation=gen,payload});
        Assert.Equal(HttpStatusCode.Conflict,conflict.StatusCode);Assert.Contains("conflict",await conflict.Content.ReadAsStringAsync());
        Assert.Equal(HttpStatusCode.BadRequest,(await c.PutAsJsonAsync($"/training/api/programs/{id}",new{contractVersion=2,operationId=Guid.NewGuid(),baseVersion=1,generation=gen,payload=new{id}})).StatusCode);
        var response=await c.GetFromJsonAsync<JsonElement>($"/training/api/changes?after=0&generation={gen}");Assert.Single(response.GetProperty("changes").EnumerateArray());
        Assert.Equal(HttpStatusCode.Conflict,(await c.GetAsync("/training/api/changes?after=0&generation=old")).StatusCode);
        using var scope=f.Services.CreateScope();var db=scope.ServiceProvider.GetRequiredService<Store>();
        var rows=await db.Documents.ToListAsync();Assert.Single(rows);Assert.Equal(1,rows[0].Version);
        Assert.Single(await db.Operations.ToListAsync());
        (await c.PostAsJsonAsync("/training/api/auth/logout",new{})).EnsureSuccessStatusCode();
        Assert.Equal(HttpStatusCode.Unauthorized,(await c.GetAsync("/training/api/export")).StatusCode);
    }
    [Fact] public async Task Concurrent_writers_keep_exactly_one_and_return_conflict() {
        await using var f=new Factory();using var a=f.CreateClient();using var b=f.CreateClient();await Login(a);await Login(b);
        var boot=await a.GetFromJsonAsync<JsonElement>("/training/api/bootstrap");var gen=boot.GetProperty("generation").GetString();var id=Guid.NewGuid().ToString();
        var results=await Task.WhenAll(a.PutAsJsonAsync($"/training/api/programs/{id}",new{contractVersion=2,operationId=Guid.NewGuid(),baseVersion=0,generation=gen,payload=Payload(id,"A")}),b.PutAsJsonAsync($"/training/api/programs/{id}",new{contractVersion=2,operationId=Guid.NewGuid(),baseVersion=0,generation=gen,payload=Payload(id,"B")}));
        Assert.Single(results,r=>r.StatusCode==HttpStatusCode.OK);Assert.Single(results,r=>r.StatusCode==HttpStatusCode.Conflict);
    }
    [Fact] public async Task Contract_v2_catalogs_tombstones_and_read_routes_are_private_and_versioned() {
        await using var f=new Factory();using var c=f.CreateClient();await Login(c);
        var boot=await c.GetFromJsonAsync<JsonElement>("/training/api/bootstrap");var gen=boot.GetProperty("generation").GetString();
        Assert.Equal(2,boot.GetProperty("contractVersion").GetInt32());
        var id=Guid.NewGuid().ToString();var equipment=new{id,name="TEST STACK",mode="MachineStack",stepGrams=7000,availableGrams=new[]{40000,47000}};
        Assert.Equal((HttpStatusCode)426,(await c.PutAsJsonAsync($"/training/api/equipment/{id}",new{operationId=Guid.NewGuid(),baseVersion=0,generation=gen,payload=equipment})).StatusCode);
        (await c.PutAsJsonAsync($"/training/api/equipment/{id}",new{contractVersion=2,operationId=Guid.NewGuid(),baseVersion=0,generation=gen,payload=equipment})).EnsureSuccessStatusCode();
        var deleted=new{id,name="TEST STACK",mode="MachineStack",stepGrams=7000,availableGrams=new[]{40000,47000},deletedAt=DateTimeOffset.UtcNow};
        var deletion=new{contractVersion=2,operationId=Guid.NewGuid(),baseVersion=1,generation=gen,payload=deleted};
        var first=await c.PutAsJsonAsync($"/training/api/equipment/{id}",deletion);first.EnsureSuccessStatusCode();
        Assert.Equal(await first.Content.ReadAsStringAsync(),await (await c.PutAsJsonAsync($"/training/api/equipment/{id}",deletion)).Content.ReadAsStringAsync());
        var doc=await c.GetFromJsonAsync<JsonElement>($"/training/api/equipment/{id}");Assert.Equal(2,doc.GetProperty("version").GetInt32());Assert.True(doc.GetProperty("payload").TryGetProperty("deletedAt",out _));
        var calId=Guid.NewGuid().ToString();var day=new{id=calId,name="Rest",date="2026-09-14",status="completed"};
        (await c.PutAsJsonAsync($"/training/api/calendar/{calId}",new{contractVersion=2,operationId=Guid.NewGuid(),baseVersion=0,generation=gen,payload=day})).EnsureSuccessStatusCode();
        var export=await c.GetFromJsonAsync<JsonElement>("/training/api/export");Assert.Equal(2,export.GetProperty("schemaVersion").GetInt32());Assert.Single(export.GetProperty("equipment").EnumerateArray());Assert.Single(export.GetProperty("calendar").EnumerateArray());
        var page=await c.GetFromJsonAsync<JsonElement>("/training/api/equipment?after=0");Assert.Equal(2,page.GetProperty("items").GetArrayLength());
        Assert.True((await c.GetAsync("/training/api/openapi.json")).IsSuccessStatusCode);
        (await c.PostAsJsonAsync("/training/api/auth/logout",new{})).EnsureSuccessStatusCode();
        Assert.Equal(HttpStatusCode.Unauthorized,(await c.GetAsync($"/training/api/equipment/{id}")).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized,(await c.GetAsync("/training/api/calendar")).StatusCode);
    }
    [Theory]
    [InlineData("2026-02-30",false)]
    [InlineData("2026-02-28",true)]
    public void Calendar_requires_a_real_date(string date,bool valid) {
        var id=Guid.NewGuid().ToString();Assert.Equal(valid,Validation.Valid("calendar",id,JsonSerializer.SerializeToElement(new{id,name="Rest",date,status="planned"})));
    }
    [Theory]
    [InlineData(30,"left",true)]
    [InlineData(0,"left",false)]
    [InlineData(30,"both",false)]
    [InlineData(86401,"right",false)]
    public void Duration_and_side_have_matching_completed_set_rules(int seconds,string side,bool valid) {
        var id=Guid.NewGuid().ToString();var ex=new {id=Guid.NewGuid(),variantId=Guid.NewGuid(),equipmentId=Guid.NewGuid(),name="Plank",equipment="Mat",mode="BodyweightOnly",sets=1,target="30",rest=(int?)null,tracking="duration",unilateral=true,records=new[]{new{id=Guid.NewGuid(),status="completed",kind="working",weight="",reps="",rir="",note="",loadGrams=(int?)null,count=(int?)null,duration=seconds.ToString(),durationSeconds=seconds,side,completedAt=DateTimeOffset.UtcNow}}};
        var payload=new{id,name="Test",programId=Guid.NewGuid(),dayId=Guid.NewGuid(),programVersion=1,revision=1,status="completed",startedAt=DateTimeOffset.UtcNow,completedAt=DateTimeOffset.UtcNow,localDate="2026-09-14",timezone="UTC",restEndsAt=(int?)null,exercises=new[]{ex}};
        Assert.Equal(valid,Validation.Valid("sessions",id,JsonSerializer.SerializeToElement(payload)));
    }
    [Theory]
    [InlineData("MachinePlatesOnly",true)]
    [InlineData("Unspecified",false)]
    public void Leg_press_completed_set_requires_an_explicit_profile(string mode,bool valid) {
        var id=Guid.NewGuid().ToString();
        var ex=new {id=Guid.NewGuid(),variantId=Guid.NewGuid(),equipmentId=Guid.NewGuid(),name="Leg press",equipment="My machine",mode,requiresEquipment=true,optionalWeekly=false,sets=2,target="10–15",rest=150,records=new[]{new{id=Guid.NewGuid(),status="completed",kind="working",weight="20",reps="12",rir="",note="",loadGrams=20000,count=12,completedAt=DateTimeOffset.UtcNow}}};
        var payload=new{id,name="B",programId=Guid.NewGuid(),dayId=Guid.NewGuid(),programVersion=1,revision=1,status="completed",startedAt=DateTimeOffset.UtcNow,completedAt=DateTimeOffset.UtcNow,localDate="2026-09-14",timezone="UTC",restEndsAt=(int?)null,exercises=new[]{ex}};
        Assert.Equal(valid,Validation.Valid("sessions",id,JsonSerializer.SerializeToElement(payload)));
    }

}
