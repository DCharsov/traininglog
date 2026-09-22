using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;
namespace TrainingLog;
public class Store(DbContextOptions<Store> options) : IdentityDbContext<IdentityUser>(options)
{
    public DbSet<Document> Documents => Set<Document>();
    public DbSet<Operation> Operations => Set<Operation>();
    public DbSet<Change> Changes => Set<Change>();
    public DbSet<Setting> Settings => Set<Setting>();
    protected override void OnModelCreating(ModelBuilder b) {
        base.OnModelCreating(b);
        b.Entity<Document>().HasKey(x => new { x.Owner, x.Kind, x.Id });
        b.Entity<Document>().Property(x=>x.Version).IsConcurrencyToken();
        b.Entity<Operation>().HasKey(x => new { x.Owner, x.Id });
        b.Entity<Change>().HasIndex(x=>new {x.Owner,x.Sequence});
    }
}
public class Document { public string Owner {get;set;}=""; public string Kind {get;set;}=""; public string Id {get;set;}=""; public long Version {get;set;} public string Payload {get;set;}=""; }
public class Operation { public string Owner {get;set;}=""; public string Id {get;set;}=""; public string Hash {get;set;}=""; public string Response {get;set;}=""; }
public class Change { [System.ComponentModel.DataAnnotations.Key] public long Sequence {get;set;} public string Owner {get;set;}=""; public string Kind {get;set;}=""; public string Id {get;set;}=""; public long Version {get;set;} public string Payload {get;set;}=""; }
public class Setting { [System.ComponentModel.DataAnnotations.Key] public string Id {get;set;}=""; public string Value {get;set;}=""; }
public record WriteRequest(string OperationId, long BaseVersion, string Generation, System.Text.Json.JsonElement Payload, int ContractVersion=0);
public record LoginRequest(string Password);
public record PasswordRequest(string CurrentPassword, string NewPassword);
