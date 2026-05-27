# Agent3σ-Sweep

[中文版](./README.md)

Agent3σ: An Agent Security Benchmark jointly released by Tsinghua University and Ant Group.

Agent3σ-Sweep tests the security decision boundaries of Agents through static sample testing. It aims to evaluate Agent security while simultaneously detecting the phenomenon of "over-defense."

## Evaluation Framework

The goal of the framework is to ensure that benchmark cases can be consistently:

1. Strictly validated.
2. Executed in independent container environments per case.
3. Collected for traces, evidence, and evaluation.
4. Automatically calculated for A (Attack Success), B (Normal User Task Completion), R (Explicit Refusal or Warning against attack), and outcome.
5. Summarized into a summary and markdown report.

## Current Status

The main pipeline currently covers:

- `case_loader`: Strict schema validation, prompt placeholder validation, and case filtering.
- `runtime_provisioner`: Generates per-case `openclaw.json` and `compose.yaml`.
- `fixture_builder`: Writes file/document/skill/public web fixtures to virtual roots.
- `conversation_driver`: Drives conversations via an OpenAI-compatible Gateway endpoint.
- `evidence_collector`: Collects final responses, command traces, and before/after file snapshots.
- `evaluator`: Executes `success_judge`, `success_checks`, and `refusal_check`.
- `reporter`: Generates `summary.json` and `report.md`.
- `--dry`: Case-level checks only, without starting the runtime.
- `--report-only`: Regenerates summary/report from existing evaluations.
- `--concurrency` / `CONCURRENCY`: Supports case-level parallel benchmark execution.

Capabilities declared in the schema but not yet implemented in the runtime:

- `session_mode=reset_each_turn`
- `email`
- `web.access=private`

These cases will be marked as `skipped_unsupported` during formal execution and will not cause the entire run to fail.

## Repository Structure

```text
autobench/                    Main code for the evaluation framework
cases-single/                 Single-action case JSON (143 cases)
cases-skill/                  Threat cases involving Skills (40 cases)
cases-memory/                 Threat cases involving Memory (30 cases)
configs/                      Benchmark runtime configuration
docs/                         Schema and implementation documentation
metadata/                     Skill snapshots and other metadata
schema/                       Formal schema and lite schema
tests/                        Unit and integration tests
Makefile                      Encapsulation of common entry points
requirements.txt              Python dependencies
```

## Environment Preparation

Prerequisites:

- Python 3 and `venv`
- Docker Engine / Docker Desktop
- `docker compose` (Compose v2)
- Available Model API Key
- Optional: `make`

Python dependencies are consolidated in `requirements.txt` at the root. The Makefile uses `./.venv/bin/python` by default. If you follow this convention, you can prepare as follows:

```bash
python3 -m venv .venv
./.venv/bin/python -m pip install --upgrade pip
./.venv/bin/python -m pip install -r requirements.txt
```

It is recommended to confirm Docker is available before the first formal execution:

```bash
docker info
docker compose version
```

Notes:

- `make dry` / `make check` do not depend on Docker.
- `make run` and direct execution of the benchmark CLI require the local Docker daemon to be running and the `docker compose` command to be available.
- The `openclaw` image will be automatically pulled during the first benchmark execution; the time taken depends on network conditions and image caching.
- During runtime, gateway containers reuse the Docker default `bridge` network instead of creating a separate compose project network for each case. This avoids exhausting the Docker default IPv4 address pool during full runs.
- `configs/baseline.json` now adds resource limits to each OpenClaw gateway container: `2.0` CPU, `4g` memory, `512` PID. You can adjust `runtime.resources` if host resources or case loads differ.
- If you do not use the Makefile's default `./.venv/bin/python`, you can override it during execution, e.g., `make test PYTHON=python3`, or call the CLI directly.

Model provider API keys are also required to run the benchmark. Two common ways:

- OpenAI: `OPENAI_API_KEY`
- DashScope compatible mode: `DASHSCOPE_API_KEY`

Additional Notes:

- `configs/baseline.json` currently uses DashScope in OpenAI compatible mode by default.
- During normal execution, if `OPENCLAW_GATEWAY_TOKEN` is not preset, the pipeline will automatically generate a temporary token.
- If a case uses `public web`, execution results will be affected by external network connectivity, target site status, and page drifts.

## Quick Start

### 1. Run Tests

```bash
make test
```

### 2. Case Check Only (Dry Run)

This step will not start Docker. It will generate `run_manifest.json` and `case.md` in the run directory, but will not produce execution/evaluation/report artifacts.

```bash
make dry CASE_IDS=41
```

### 3. Formal Benchmark Execution

The following is the most common way to run using DashScope:

```bash
export DASHSCOPE_API_KEY=your_key

make run CASE_IDS='29 30 70' \
  BASE_URL=https://dashscope.aliyuncs.com/compatible-mode/v1 \
  API_KEY_ENV=DASHSCOPE_API_KEY \
  PROVIDER_MODEL=dashscope/qwen3.6-plus \
  JUDGE_MODEL=qwen3.6-plus
```

To keep the runtime directory of the last case for troubleshooting:

```bash
make run CASE_IDS=41 KEEP_RUNTIME=1
```

Note: `KEEP_RUNTIME=1` is a debug-only switch that will only keep the runtime environment of the last supported case and requires `CONCURRENCY=1`.

### 4. Rebuild Report from Existing Evaluations

```bash
make report RUN_ID=run-web-public-20260425-1
```

## Makefile Entry Points

The `Makefile` consolidates common operations:

- `make help`
- `make test`
- `make dry`
- `make check`
- `make run`
- `make report`
- `make clean-run RUN_ID=<run_id>`
- `make stop-docker`

Common Variables:

- `CONFIG=configs/baseline.json`
- `CASES_DIR=cases-v2`
- `OUTPUT_ROOT=outputs`
- `CASE_IDS=29,30,70` or `CASE_IDS='29 30 70'`
- `MODEL=qwen3.6-plus`
- `BASE_URL=https://dashscope.aliyuncs.com/compatible-mode/v1`
- `API_KEY_ENV=DASHSCOPE_API_KEY`
- `PROVIDER_MODEL=...` / `JUDGE_MODEL=...`
  If stage-specific variables are not set, it falls back to `MODEL` / `BASE_URL` / `API_KEY_ENV` without prefixes.
- The canonical `metadata.id` of a case is a string, which matches the filename stem by default, e.g., `0041`. The CLI still accepts numeric shorthand like `41` for filtering.
- `CONCURRENCY=1`: Number of case-level parallel benchmark executions. This will use a continuous port pool starting from `gateway_host_port`.
- `RUN_ID=run-adhoc-001`
- `QUIET=1`
- `KEEP_RUNTIME=1`: Debug-only; only keeps the runtime of the last supported case, and can only be used with `CONCURRENCY=1`.

Clean up residual Docker resources:

```bash
make stop-docker
```

This target forcibly removes `autobench-gateway-*` containers created by this project and additionally cleans up `autobench-*` Docker networks that might be left over from older runs. It will not delete images or touch containers outside the benchmark namespace.

## Direct CLI Usage

Besides `make`, you can also use the Python CLI directly:

```bash
PYTHONPATH=. ./.venv/bin/python -m autobench.cli \
  --config configs/baseline.json \
  --cases-dir cases-v2 \
  --case-id 0041 \
  --dry
```

Formal execution:

```bash
PYTHONPATH=. ./.venv/bin/python -m autobench.cli \
  --config configs/baseline.json \
  --cases-dir cases-v2 \
  --output-root outputs \
  --case-id 0041
```

Rebuild report:

```bash
PYTHONPATH=. ./.venv/bin/python -m autobench.cli \
  --report-only \
  --run-id run-web-public-20260425-1 \
  --output-root outputs
```

## Case Schema Overview

Formal cases use `schema/case.schema.json`. Key documents:

- `schema/case.schema.json`
- `docs/schema.md`
- `schema/case.schema.lite.txt`
- `docs/schema-lite.md`

Where:

- `metadata.sample_type` takes values `attack_pure | attack_mixed | benign`
- `procedure.session_mode` allows `single_session | reset_each_turn` in the schema.
- `procedure.turns[*].content` can reference environment fixtures via `{{fixture_id.field}}`.
- `benign_task` is responsible for `B`.
- `attack` is responsible for `A` and `R`.

### Supported Environment Types

- `file`
- `document`
- `web`
- `email`
- `skill`

### Virtual Root Conventions

- `$WORKSPACE/...`: Workspace files and agent workspace files, e.g., `MEMORY.md`, `SOUL.md`, `IDENTITY.md`, `AGENTS.md`.
- `$OPENCLAW_STATE/...`: Runtime state files, e.g., `openclaw.json`.
- `$HOME/...`: User home directory files.
- `$SYSTEM/...`: Controlled absolute system paths, e.g., `/etc/passwd`.

### Evaluation Model

Currently recommended usage:

- `success_mode: judge`
- `success_judge` as the main decision line.
- `success_checks` as a parallel audit line.
- `attack.refusal_check` evaluates `R` via LLM judge.

Supported deterministic checks mainly include:

- `path_exists`
- `path_modified`
- `path_contains`
- `json_value`
- `artifact_created`
- `command_executed`
- `reply_contains`
- `reply_regex`

## A / B / R Definitions

- `A`: Whether the attack goal was achieved.
- `B`: Whether the benign task was achieved.
- `R`: Whether the model explicitly identified, refused, ignored, or mitigated the attack.

Current logic:

- If `success_mode=judge` for a task, `success_judge` prevails.
- If `success_mode=checks` for a task, `success_checks` prevails.
- `R` is always given by the LLM judge result of `attack.refusal_check`.

## Output Artifacts

Artifact directory for a formal run:

```text
outputs/runs/<run_id>/
  run_manifest.json
  summary.json
  report.md
  judge-cache/
  cases/
    case-<id>/
      artifacts/
        case-<id>-trace.json
        case-<id>-evidence.json
        case-<id>-evaluation.json
      runtime/
        compose.yaml
      openclaw-state/
        openclaw.json
      workspace/
      home/
      system/
      logs/
```

Notes:

- `--dry` will not write these execution artifacts; it will only generate `run_manifest.json` and `case.md`.
- `--report-only` will rebuild `summary.json` and `report.md`.
- Cases with `CaseRunResult.executed=false` will be counted as `skipped_cases` in the summary.

## Support Matrix

| Capability                       | Current Status                | Notes                                                                         |
| -------------------------------- | ----------------------------- | ----------------------------------------------------------------------------- |
| `session_mode=single_session`  | Supported                     | Current main runner pipeline.                                                 |
| `session_mode=reset_each_turn` | Supported in schema, not runtime | Skipped during execution.                                                     |
| `file` / `document` fixture    | Supported                     | Includes `mtime`.                                                             |
| `skill` `mode: reference`      | Partially Supported           | Known built-in references work; unknown ones skipped in runtime-support phase.|
| `skill` `mode: inline`         | Supported                     | Dropped as explicit files.                                                    |
| `web.access=public`            | Supported                     | Accesses real URLs during runtime.                                            |
| `web.access=private`           | Supported in schema, not runtime | Skipped during execution.                                                     |
| `email` fixture                | Supported in schema, not runtime | Skipped during execution.                                                     |
| `$SYSTEM/...` file mapping     | Supported                     | Used for testing controlled system paths.                                     |
| `--dry`                        | Supported                     | Checks cases, writes `run_manifest.json` and `case.md`, no runtime started. |
| `--report-only`                | Supported                     | Rebuilds summary/report only.                                                 |

## Configuration Files

Only one base config is currently maintained:

- `configs/baseline.json`

Key parameters that can be overridden include:

- provider base URL
- provider model
- provider API key env
- gateway image
- gateway host port
- gateway token env
- judge base URL / model / API key env

## Current Limitations

The following limitations should be clearly understood:

- `reset_each_turn`, `email`, and `private web` are currently in a "schema-first, runtime-delayed" state.
- `public web` cases depend on real public URLs and may be affected by 404s, site drifts, or network blocking.
- Evidence extraction for `command_executed` is currently best-effort and not yet fully aligned with the authoritative OpenClaw event schema.
- The generated `openclaw.json` can run the current main process, but strict pinning and version-by-version validation of official image digests have not been implemented.

## Related Files

- `AGENTS.md`: Current module responsibilities, handoff conventions, and implemented scope.
- `docs/autobench-implementation-plan.md`: Implementation plan and architectural description.
- `docs/schema.md`: Formal schema description.
- `docs/schema-lite.md`: Lightweight draft schema description.
