# Data Anonymization — documentation

Written against the current architecture: one batch chain for both modes, the launch service,
the guard and the config selector, the configuration health check, the before/after sample, the
concurrent-run refusal, and the scheduler.

| Document | Read it for |
|---|---|
| [`DEPLOYMENT_AND_USAGE.md`](DEPLOYMENT_AND_USAGE.md) | Deploying to a standard TEKCO org, and using the tool day to day |
| [`DEPLOYMENT_NON_STANDARD_ORG.md`](DEPLOYMENT_NON_STANDARD_ORG.md) | An org that departs from the TEKCO schema conventions — Portugal (ALH) is the worked example |
| [`SOLUTION_AND_ARCHITECTURE.md`](SOLUTION_AND_ARCHITECTURE.md) | How the tool is built, and why each safety mechanism is there |
| [`TEST_PLAN.md`](TEST_PLAN.md) | Validating a deployment by hand in a sandbox — 55 cases, and the six that matter most |

The files directly under `anonymization/docs/` are the **previous** set. They describe classes
that no longer exist — `TEKCO_AnonymizationBatch`, `TEKCO_AnonymizationByIdBatch`,
`TEKCO_ContentDocumentByIdBatch`, `TEKCO_FieldHistoryByIdBatch`,
`TEKCO_AnonymizationBatchUtils` — and a deployment that would fail. Keep them for history; do
not follow them.
