# API contract

Use Node.js 24. From the repository root:

```sh
npm --prefix tools/api-contract ci
npm --prefix tools/api-contract run generate
```

`generate` builds OpenAPI, runs structural contract tests and regenerates the web
DTOs. It requires the web application's installed dependencies (Zod). No server,
database, credentials or personal records are read.

Sources:

- `apps/web/src/domain.ts`: shared document schemas, including optional Day archives.
- `apps/web/scripts/build-contract.mjs`: common endpoints and contract composition.
- `tools/api-contract/watch-contract.json`: watch control, recovery and automatic
  device-linking schemas/routes. This is authored source, not generated output.
- `tools/api-contract/add-reservations.mjs`: versioned reservation extension.

The generated files are `apps/api/openapi.json` and `apps/web/src/api.generated.ts`.
Do not hand-edit them. The old `add-day-archives.mjs` patch is unnecessary for a
normal build: Day archives now come from the Zod schema. Watch operation IDs and
cookie-write CSRF parameters are added centrally during composition. Bearer-only
routes retain separate security definitions.

Tests verify reproducibility, schema references, unique operation IDs, required
watch routes, cookie-write CSRF, watch bearer security and nullable Day archives.
These are contract checks, not substitutes for API authorization/integration tests.
