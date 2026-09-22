using System.Text.Json;
namespace TrainingLog;
public static class Validation {
    static readonly string[] Modes = ["Unspecified","BarbellTotal","SmithPlatesOnly","PerDumbbell","MachineStack","MachinePlatesOnly","AddedBodyweight","AssistedBodyweight","BodyweightOnly"];
    static void Require(bool condition) { if(!condition) throw new FormatException("Неверный формат дневника."); }
    static string Text(JsonElement e,string key,int max=2000,bool empty=true) { var v=e.GetProperty(key).GetString()!; Require(v!=null && v.Length<=max && (empty || v.Length>0)); return v!; }
    static void Id(JsonElement e,string key) => Require(Guid.TryParse(Text(e,key,36,false),out _));
    static int Number(JsonElement e,string key,int min,int max) {var n=e.GetProperty(key).GetInt32(); Require(n>=min && n<=max); return n;}
    static JsonElement[] Array(JsonElement e,string key,int min,int max) {var a=e.GetProperty(key).EnumerateArray().ToArray();Require(a.Length>=min && a.Length<=max);return a;}
    static void Unique(JsonElement[] a) { foreach(var e in a) Id(e,"id");Require(a.Select(e=>e.GetProperty("id").GetString()).Distinct().Count()==a.Length); }
    static void OptionalText(JsonElement e,string key) {if(e.TryGetProperty(key,out _)) Text(e,key);}
    static void Time(JsonElement e,string key,bool nullable=false) {var p=e.GetProperty(key);if(nullable && p.ValueKind==JsonValueKind.Null)return;Require(DateTimeOffset.TryParse(p.GetString(),out _));}
    static void Profile(JsonElement e) {
        if(e.TryGetProperty("stepGrams",out var step) && step.ValueKind!=JsonValueKind.Null)Number(e,"stepGrams",1,2000000);
        if(e.TryGetProperty("availableGrams",out _))foreach(var v in Array(e,"availableGrams",0,200))Require(v.TryGetInt32(out var n)&&n>=0&&n<=2000000);
    }
    static void Exercise(JsonElement e,bool session) {
        Profile(e);
        foreach(var key in new[]{"optionalWeekly","requiresEquipment"})if(e.TryGetProperty(key,out var flag))Require(flag.ValueKind is JsonValueKind.True or JsonValueKind.False);
        if(e.TryGetProperty("tracking",out var tracking))Require(new[]{"reps","duration"}.Contains(tracking.GetString()));
        bool duration=e.TryGetProperty("tracking",out tracking)&&tracking.GetString()=="duration";
        bool unilateral=e.TryGetProperty("unilateral",out var sideMode)&&sideMode.GetBoolean();
        if(e.TryGetProperty("supersetGroup",out var group)&&group.ValueKind!=JsonValueKind.Null)Text(e,"supersetGroup",50);
        Id(e,"id");Id(e,"variantId");Id(e,"equipmentId");Text(e,"name",2000,false);Text(e,"equipment",2000,false);
        var mode=Text(e,"mode");Require(Modes.Contains(mode));Number(e,"sets",1,30);Text(e,"target");OptionalText(e,"sourceNote");
        if(e.GetProperty("rest").ValueKind!=JsonValueKind.Null) Number(e,"rest",0,1800);
        if(!session)return;
        var records=Array(e,"records",0,100);Unique(records);
        foreach(var r in records) {
            var status=Text(r,"status");Require(new[]{"draft","completed","skipped"}.Contains(status));
            Require(new[]{"working","warmup"}.Contains(Text(r,"kind")));
            foreach(var k in new[]{"weight","reps","rir","note"})Text(r,k);
            OptionalText(r,"duration");
            if(r.TryGetProperty("side",out var side))Require(new[]{"both","left","right"}.Contains(side.GetString()));
            var hasDuration=r.TryGetProperty("durationSeconds",out var seconds)&&seconds.ValueKind!=JsonValueKind.Null;
            if(hasDuration)Number(r,"durationSeconds",1,86400);
            var weight=r.GetProperty("loadGrams");var count=r.GetProperty("count");
            if(weight.ValueKind!=JsonValueKind.Null) Number(r,"loadGrams",0,2000000);
            if(count.ValueKind!=JsonValueKind.Null) Number(r,"count",1,1000);
            Time(r,"completedAt",true);
            if(status=="completed") {
                if(e.TryGetProperty("requiresEquipment",out var required)&&required.GetBoolean())Require(mode!="Unspecified");
                Require((duration?hasDuration:count.ValueKind!=JsonValueKind.Null) && (mode=="BodyweightOnly" || weight.ValueKind!=JsonValueKind.Null));
                if(unilateral)Require(r.TryGetProperty("side",out side)&&new[]{"left","right"}.Contains(side.GetString()));
                Require(r.GetProperty("completedAt").ValueKind!=JsonValueKind.Null);
                var rir=Text(r,"rir");Require(rir=="" || (int.TryParse(rir,out var n) && n>=0 && n<=10));
            }
        }
    }
    public static bool Valid(string kind,string id,JsonElement e) {
        try {
            Id(e,"id");Require(e.GetProperty("id").GetString()==id);Text(e,"name",2000,false);
            foreach(var key in new[]{"archivedAt","deletedAt"})if(e.TryGetProperty(key,out _))Time(e,key,true);
            if(kind=="equipment") {Require(Modes.Contains(Text(e,"mode")));Profile(e);}
            else if(kind=="calendar") {
                var date=Text(e,"date",10,false);Require(DateOnly.TryParseExact(date,"yyyy-MM-dd",out _));
                Require(new[]{"planned","completed"}.Contains(Text(e,"status")));
            }
            else if(kind=="programs") {
                OptionalText(e,"seedKey");if(e.TryGetProperty("contentRevision",out _))Number(e,"contentRevision",1,int.MaxValue);Number(e,"version",1,int.MaxValue);OptionalText(e,"sourceNote");var days=Array(e,"days",1,30);Unique(days);
                foreach(var d in days) {Text(d,"name",2000,false);var a=Array(d,"exercises",1,50);Unique(a);foreach(var x in a) Exercise(x,false);}
            } else if(kind=="sessions") {
                Id(e,"programId");Id(e,"dayId");Number(e,"programVersion",1,int.MaxValue);Number(e,"revision",1,int.MaxValue);
                Require(new[]{"active","completed","cancelled"}.Contains(Text(e,"status")));
                Time(e,"startedAt");Time(e,"completedAt",true);Text(e,"localDate",32,false);Text(e,"timezone",100,false);
                var rest=e.GetProperty("restEndsAt");Require(rest.ValueKind==JsonValueKind.Null || (rest.TryGetDouble(out var n) && double.IsFinite(n) && n>=0));
                Require(Text(e,"status")!="active" || (!e.TryGetProperty("deletedAt",out var deleted)||deleted.ValueKind==JsonValueKind.Null));
                var a=Array(e,"exercises",1,50);Unique(a);foreach(var x in a) Exercise(x,true);
            } else return false;
            return true;
        } catch(Exception ex) when(ex is KeyNotFoundException or InvalidOperationException or FormatException or OverflowException or ArgumentException) { return false; }
    }
}
