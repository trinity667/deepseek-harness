---
name: heretic
description: Produce a refusal-reduced ("abliterated") variant of an open-weight model with the vendored Heretic tool, convert it to GGUF, serve it locally, and register it as a private dsh model route.
whenToUse: The user asks to decensor, abliterate, or "heretic" an open-weight Hugging Face model, or to add such a model as a dsh provider route.
---

# Heretic: abliterate an open-weight model and use it from dsh

Heretic lives in `tools/heretic` (git subtree of https://github.com/p-e-w/heretic,
AGPL-3.0). It is a separate Python program: run it only through its command
line. Never copy its code into `packages/` or `apps/`, which are MIT.

In the commands below, `<repo>` is the deepseek-harness checkout and `<work>`
is a run directory outside the repository.

## 0. Preconditions — check before anything else

1. **GPU.** Run `nvidia-smi`. Heretic needs an NVIDIA GPU with CUDA for real
   models (about 16 GB VRAM for a 4B model; 12–16 GB for an 8B model with
   `--quantization bnb_4bit`). If there is no NVIDIA GPU, **stop**: tell the
   user the run must happen on a rented GPU host (RunPod, Vast, Modal), and
   offer the commands of steps 1–3 for that host. Do not try a CPU run of a
   real model.
2. **Disk.** Free space must be at least 2.5 × the model's download size
   (original weights + merged copy + GGUF).
3. **uv.** `uv --version` must work. Heretic pins every dependency in
   `tools/heretic/uv.lock`; always run it through `uv run --project`.
4. **The model's own license.** The output keeps the base model's license
   (Apache-2.0 for Qwen, Gemma terms for Gemma, …). Tell the user which one
   applies.

## 1. Run Heretic non-interactively (long job: run it in the background)

Create `<work>`, then run:

```sh
uv run --project <repo>/tools/heretic --directory <work> heretic \
  --model <hf-model-id> \
  --checkpoint-action restart \
  --trial-index 0 \
  --export-strategy merge \
  --model-action save \
  --save-directory model
```

On Windows, Heretic's terminal UI needs a real console: it fails under Git
Bash and when its output is redirected, so start it in its own PowerShell or
cmd window. Add `--quantization bnb_4bit` when VRAM is tight. The run benchmarks the
batch size, then optimizes; expect 20–60 minutes on one GPU. Start it as a
background job and wait for the completion notice instead of polling.

`--trial-index 0` takes the first trial of the Pareto front. When the user
wants to choose the trade-off themselves, omit it and let them answer
Heretic's prompt in a terminal.

## 2. Check the result before using it

```sh
uv run --project <repo>/tools/heretic heretic \
  --model <hf-model-id> --evaluate-model <work>/model
```

Report the refusal count and the KL divergence to the user. A KL divergence
far above 1 means the model was damaged; say so and suggest another trial.

## 3. Convert to GGUF and serve on loopback

With a llama.cpp checkout or release:

```sh
python <llama.cpp>/convert_hf_to_gguf.py <work>/model --outfile <work>/model-f16.gguf --outtype f16
<llama.cpp>/llama-quantize <work>/model-f16.gguf <work>/model-q4_k_m.gguf Q4_K_M
llama-server -m <work>/model-q4_k_m.gguf --host 127.0.0.1 --port 8080 --jinja --api-key "$LOCAL_HERETIC_API_KEY"
```

`--jinja` keeps the model's chat template, which tool calls need. Generate
`LOCAL_HERETIC_API_KEY` as a random value and store it in the dsh credential
store; never print it.

## 4. Register the route in dsh

Add a provider beside `freellmapi` in the profile's `cordis.patch.yml`
(`~/.dsh/profiles/<profile>/cordis.patch.yml`), under the `llm-pi-ai` entry:

```yaml
      local-heretic:
        displayName: Local Heretic
        apiKeyEnv: LOCAL_HERETIC_API_KEY
        api: openai-completions
        baseURL: http://127.0.0.1:8080/v1
        models:
          - id: <served-model-name>
            contextWindow: <the base model's context window>
```

Back up the file before editing it. Then run one short agent task on the new
route that reads a file with a tool, to prove streaming and tool calls work.

## Safety rules

- The server binds `127.0.0.1` only. Never expose a refusal-reduced model, or
  a dsh instance that uses one, on a public address or without authentication.
- Do not upload the model (`--model-action upload`) unless the user explicitly
  asks for it and names the repository.
- Never log prompts or responses from the model to shared files.
