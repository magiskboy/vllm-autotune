# Purpose of vllm bench throughput command
_Exported on 4/28/2026 at 10:56:10 GMT+7 from Cursor (3.1.15)_

---

**User**

Dựa vào source code và tài liệu trong repo, hãy cho tôi biết mục đích của command `vllm bench thoughput` vì tôi thấy nó đang chị chạy single request mỗi lần, vậy làm sao lại gọi là bench throughput

---

**Cursor**

Mình sẽ rà nhanh mã nguồn và tài liệu trong repo để xác định chính xác `vllm bench throughput` đo gì, vì sao nhìn như “single request”, rồi giải thích cách nó vẫn benchmark throughput. Mình bắt đầu từ phần CLI command và logic benchmark tương ứng.

Mình đã tìm thấy đúng các file liên quan: `vllm/entrypoints/cli/benchmark/throughput.py`, `vllm/benchmarks/throughput.py` và `docs/cli/bench/throughput.md`. Giờ mình sẽ đọc các đoạn này để giải thích chính xác “throughput” được đo theo cơ chế nào.

Mình đã xác nhận trong code: `throughput` là benchmark **offline inference throughput**, và nó tính `requests/s`, `total tokens/s`, `output tokens/s` trên **toàn bộ tập requests** trong một lần chạy, không phải đo latency từng request kiểu online. Mình sẽ trả lời luôn theo đúng logic code để giải thích vì sao bạn có cảm giác “single request”.Bạn nhìn rất đúng: cảm giác “single request mỗi lần” dễ gây hiểu nhầm.  
Nhưng trong vLLM, `vllm bench throughput` vẫn là benchmark throughput theo nghĩa **tổng công suất xử lý của engine trong offline mode**.

- Command này được mô tả rõ là `Benchmark offline inference throughput` trong CLI:
```10:14:vllm/entrypoints/cli/benchmark/throughput.py
class BenchmarkThroughputSubcommand(BenchmarkSubcommandBase):
    """The `throughput` subcommand for `vllm bench`."""
    name = "throughput"
    help = "Benchmark offline inference throughput."
```

- Nó tạo một danh sách nhiều requests (`--num-prompts`, mặc định 1000), rồi chạy benchmark trên cả tập đó.
- Sau khi chạy xong, nó tính throughput bằng công thức:
  - `requests/s = len(requests) / elapsed_time`
  - `tokens/s = total_num_tokens / elapsed_time`
```962:966:vllm/benchmarks/throughput.py
print(
    f"Throughput: {len(requests) / elapsed_time:.2f} requests/s, "
    f"{total_num_tokens / elapsed_time:.2f} total tokens/s, "
    f"{total_output_tokens / elapsed_time:.2f} output tokens/s"
)
```

Vì sao trông giống “single request”?
- Ở backend sync (`run_vllm`), code gọi `llm.generate(prompts, sampling_params, ...)` **một lần** với cả list prompt:
```97:102:vllm/benchmarks/throughput.py
start = time.perf_counter()
outputs = llm.generate(
    prompts, sampling_params, lora_request=lora_requests, use_tqdm=True
)
```
- “Một lần gọi API” ở đây **không đồng nghĩa 1 request**; đó là 1 lần submit **nhiều request** vào engine để engine tự batching/scheduling.
- Nếu bạn muốn mô phỏng traffic thật (request đến theo thời gian, concurrency, rate-limit...), đó là bài toán của `vllm bench serve`, không phải `bench throughput`.

Tóm lại:
- `bench throughput` = đo **khả năng xử lý tối đa offline** của model/engine (không có network/server overhead).
- `bench serve` = đo **throughput/latency online** theo pattern tải thực tế.

Nếu bạn muốn, mình có thể gợi ý 2-3 lệnh chuẩn để so sánh trực tiếp `bench throughput` vs `bench serve` trên cùng model/dataset để thấy khác biệt rõ ràng.

---

**User**

outputs = llm.generate(
    prompts, sampling_params, lora_request=lora_requests, use_tqdm=True
)

những rõ ràng là nó sẽ block và khi được generate xong với submit request tiếp theo. Vậy đâu có batching ở đây 

---

**Cursor**

Bạn đang chạm đúng điểm mấu chốt. Mình sẽ mở luôn implementation của `LLM.generate()` để chỉ ra vì sao dù call “blocking 1 lần”, bên trong vẫn có continuous batching giữa nhiều request trong `prompts`.

Chuẩn, `generate()` **block ở phía caller**; nhưng “block” != “xử lý tuần tự từng request”.

Điểm then chốt là bên trong `LLM.generate()`:

1) Nó nhận **một list prompts** (nhiều request)  
2) Nó **enqueue toàn bộ requests** vào engine trước  
3) Rồi engine chạy vòng `step()` trên tập unfinished requests (scheduler gom batch động)

Bạn có thể thấy rõ trong code:

```446:462:vllm/entrypoints/llm.py
def generate(...):
    """...
    This class automatically batches the given prompts...
    For the best performance, put all of your prompts
    into a single list and pass it to this method.
```

```1639:1648:vllm/entrypoints/llm.py
self._add_completion_requests(...)
return self._run_engine(...)
```

```1796:1808:vllm/entrypoints/llm.py
for i, prompt in enumerate(prompts):
    request_id = self._add_request(prompt, params[i], ...)
```

```1857:1863:vllm/entrypoints/llm.py
while self.llm_engine.has_unfinished_requests():
    step_outputs = self.llm_engine.step()
    for output in step_outputs:
        if output.finished:
            outputs.append(output)
```

Vậy:
- Đúng là có **1 lần gọi blocking** `llm.generate(...)`.
- Nhưng trong lần gọi đó, engine đang phục vụ **nhiều request cùng lúc** qua scheduler/batching nội bộ.
- Chỉ khi bạn truyền đúng **1 prompt** thì nó mới thực sự thành single-request benchmark.

Trong `bench throughput`, số request mặc định là `--num-prompts 1000`, nên benchmark này vẫn là throughput của workload nhiều request offline.

---

**User**

trong code bench thoughput, nó có submit danh sách request không, hay chỉ submit 1 request rồi chờ kết quả 

---

**Cursor**

Trong `bench throughput`, nó **submit danh sách request**, không phải submit từng request một rồi chờ.

Cụ thể trong `vllm/benchmarks/throughput.py`:

```65:68:vllm/benchmarks/throughput.py
# Add the requests to the engine.
prompts: list[TextPrompt | TokensPrompt] = []
sampling_params: list[SamplingParams] = []
for request in requests:
```

Nó build `prompts` và `sampling_params` cho **toàn bộ** `requests`, rồi gọi:

```100:102:vllm/benchmarks/throughput.py
outputs = llm.generate(
    prompts, sampling_params, lora_request=lora_requests, use_tqdm=True
)
```

`prompts` ở đây là list; `requests` được lấy từ dataset với `num_prompts` (mặc định 1000).  
Nên về mặt submit workload thì là **batch nhiều request trong một lần generate**.  
Chỉ khi bạn chạy với `--num-prompts 1` thì nó mới thực chất là 1 request.

---

**User**

hãy phân tích source code và cho tôi ý nghĩa của 2 tham số --max-num-batched-tokens và --max-num-seqs trong vllm bench thoughput và mối quan hệ của 2 tham số đó.

---

**Cursor**

Mình sẽ truy vết từ CLI `bench throughput` xuống `EngineArgs`/`SchedulerConfig` để giải thích chính xác ý nghĩa của `--max-num-batched-tokens`, `--max-num-seqs` và cách hai giới hạn này tương tác khi lập lịch batch.

Trong `vllm bench throughput`, 2 tham số này **không phải logic riêng của benchmark script**, mà là tham số scheduler của engine vLLM (được pass xuyên qua `EngineArgs`).

`bench throughput` gọi:
```869:907:vllm/benchmarks/throughput.py
if args.backend == "vllm":
    ...
    elapsed_time, request_outputs = run_vllm(
        requests,
        args.n,
        EngineArgs.from_cli_args(args),
        ...
    )
```

và CLI của `EngineArgs` có 2 flag này:
```1307:1319:vllm/engine/arg_utils.py
scheduler_group.add_argument("--max-num-batched-tokens", ... default=None)
scheduler_group.add_argument("--max-num-seqs", ... default=None)
```

## Ý nghĩa từng tham số

- `--max-num-batched-tokens`  
  Là **ngân sách token tối đa mỗi scheduler iteration** (mỗi step).
```49:51:vllm/config/scheduler.py
max_num_batched_tokens: int = ...
"""Maximum number of tokens that can be processed in a single iteration."""
```

- `--max-num-seqs`  
  Là **số sequence/request tối đa đồng thời trong running queue** (concurrency trần trong scheduler).
```63:65:vllm/config/scheduler.py
max_num_seqs: int = ...
"""Maximum number of sequences to be processed in a single iteration."""
```

Trong scheduler runtime:
```105:111:vllm/v1/core/sched/scheduler.py
self.max_num_running_reqs = self.scheduler_config.max_num_seqs
...
self.max_num_scheduled_tokens = ... or self.scheduler_config.max_num_batched_tokens
```

Nên mỗi step bị chặn bởi **2 trần**:
1) trần theo **số req** (`max_num_seqs`)  
2) trần theo **tổng token** (`max_num_batched_tokens` / `max_num_scheduled_tokens`)

## Mối quan hệ giữa 2 tham số

- Quan hệ ràng buộc cứng:
```273:277:vllm/config/scheduler.py
if self.max_num_batched_tokens < self.max_num_seqs:
    raise ValueError(...)
```
=> luôn cần `max_num_batched_tokens >= max_num_seqs` (ít nhất 1 token/seq).

- Quan hệ vận hành thực tế:
  - Scheduler luôn tiêu token budget trước/sau khi xét waiting/running.
  - Đồng thời không cho `len(running)` vượt `max_num_seqs`.
```371:373:vllm/vllm/v1/core/sched/scheduler.py
token_budget = self.max_num_scheduled_tokens
```
```571:573:vllm/vllm/v1/core/sched/scheduler.py
if len(self.running) == self.max_num_running_reqs:
    break
```

### Hiểu nhanh theo workload

- Tăng `max_num_batched_tokens`, giữ `max_num_seqs`:
  - tốt hơn cho request dài/prefill nặng (nhiều token mỗi req)
  - nhưng có thể tăng latency và memory pressure.

- Tăng `max_num_seqs`, giữ `max_num_batched-tokens`:
  - cho phép nhiều request cùng chạy hơn, hữu ích khi request ngắn/decode-heavy
  - nhưng token budget chia mỏng, mỗi req nhận ít token/step hơn.

- Throughput tốt thường cần cân bằng cả hai:  
  **effective batch mỗi step = min(giới hạn seq, giới hạn token theo độ dài thực tế request).**

Nếu bạn muốn, mình có thể đề xuất một grid sweep cụ thể cho `bench throughput` (ví dụ 3x3 giá trị) dựa trên profile input/output token của workload bạn đang chạy.

---

**User**

vậy mối quan hệ giữa prompt, sequence và request là như thế nào trong bench thoughput 

---

**Cursor**

Trong `bench throughput` (backend `vllm`), 3 khái niệm này gần như map 1-1, **trừ `sequence` ở mức output**:

- `request`  
  Là đơn vị công việc benchmark lấy từ dataset (`SampleRequest`).

- `prompt`  
  Là input của một request. Trong code, mỗi `SampleRequest` được convert thành 1 `TextPrompt` hoặc `TokensPrompt` và append vào list `prompts`.

- `sequence`  
  Có 2 nghĩa dễ lẫn:
  1) **Sequence như “request slot” trong scheduler** (`max_num_seqs`): gần tương đương số request đang chạy đồng thời.
  2) **Sequence output** do sampling tạo ra (`n`): 1 request có thể sinh nhiều completion sequence nếu `--n > 1`.

Trong `bench throughput` cụ thể:
- 1 `request` -> 1 `prompt` (input)
- scheduler xử lý nhiều request đồng thời, bị chặn bởi `max_num_seqs` và token budget
- mỗi request sinh `n` output sequences (`SamplingParams(n=n)`)

Nên:
- Nếu `n=1`: dễ hiểu là `request ~ prompt ~ 1 output sequence`.
- Nếu `n>1`: vẫn 1 request/1 prompt, nhưng có nhiều output sequences cho request đó.  
  Vì vậy “sequence” trong `max_num_seqs` không phải là “số completion output”, mà là số request active trong batch scheduler.

---

**User**

Vậy có một công thức tương đối nào để cân bằng khi chọn 2 giá trị --max-num-seqs và --max-num-batched-tokens này không?

---

**Cursor**

Có. Có một “công thức khởi điểm” khá thực dụng để set 2 tham số này.

## Công thức khởi điểm

Gọi:

- `L_in` = prompt tokens trung bình
- `L_out` = output tokens trung bình
- `L_step` = số token “active” trung bình mỗi request trong 1 scheduler step  
  - workload prefill-heavy: `L_step ~ L_in` (hoặc chunk prefill)
  - decode-heavy: `L_step ~ 1..4` token/request/step (xấp xỉ)

Khi đó chọn:

- `max_num_batched_tokens ≈ max_num_seqs * L_step_target`
- hoặc đảo lại  
  `max_num_seqs ≈ floor(max_num_batched_tokens / L_step_target)`

Ràng buộc cứng vẫn là:
- `max_num_batched_tokens >= max_num_seqs`

---

## Rule of thumb nhanh

- **Decode-heavy / chat ngắn**: ưu tiên tăng `max_num_seqs` trước.
  - Ví dụ bắt đầu: `max_num_seqs=128`, `max_num_batched_tokens=2048~4096`.
- **Prefill-heavy / context dài**: ưu tiên tăng `max_num_batched_tokens` mạnh hơn.
  - Ví dụ bắt đầu: `max_num_seqs=32~64`, `max_num_batched_tokens=8192~16384`.

---

## Cách sweep thực tế (đáng tin nhất)

Giữ tỉ lệ gần cố định rồi tăng theo bậc:

1) Chọn ratio `R = max_num_batched_tokens / max_num_seqs`  
   - decode-heavy: `R ~ 16..64`
   - prefill-heavy: `R ~ 128..512` (hoặc hơn)
2) Sweep:
- `(64, 4096)`, `(128, 8192)`, `(256, 16384)` (R=64)  
hoặc  
- `(32, 8192)`, `(64, 16384)`, `(128, 32768)` (R=256)

3) Chọn điểm có:
- throughput tăng rõ
- latency/TTFT chưa vọt quá ngưỡng bạn chấp nhận
- không OOM/không preempt nhiều bất thường

---

## Dấu hiệu chỉnh tham số

- GPU chưa bận, throughput thấp -> tăng `max_num_seqs`.
- TTFT cao, decode chậm dù concurrency cao -> giảm `max_num_seqs` hoặc tăng `max_num_batched_tokens`.
- Request dài bị nghẽn/đợi lâu -> tăng `max_num_batched_tokens`.
- OOM hoặc tail latency xấu -> giảm cả hai, thường giảm `max_num_seqs` trước.

Nếu bạn đưa mình profile workload (p50/p95 input/output tokens), mình có thể đề xuất luôn 1 bảng giá trị sweep 3x3 cụ thể cho case của bạn.

---

**User**

bạn nói tới sweep thì tôi thấy vLLM có hỗ trợ, hãy tìm hiểu kĩ và đề xuất cho tôi phương án tunning nhé

---

**Cursor**

Mình sẽ đọc kỹ phần `vllm bench sweep` trong docs + code CLI để chốt khả năng thật sự của tool, rồi đề xuất một playbook tuning cụ thể cho case của bạn (đặc biệt là `max-num-seqs` và `max-num-batched-tokens`).

Bạn nói đúng, vLLM có hỗ trợ sweep khá tốt — nhưng mình xác nhận rõ để bạn chọn đúng tool:

- `vllm bench sweep` hiện có các subcommand: `serve`, `serve_workload`, `startup`, `plot`, `plot_pareto` (không có `throughput` trực tiếp).
- Nghĩa là sweep built-in tập trung vào benchmark **online** (`vllm serve` + `vllm bench serve`), không phải offline `vllm bench throughput`.

Dù vậy, bạn vẫn tune rất hiệu quả cho mục tiêu của bạn bằng 2 pha:

## Phương án tuning đề xuất

### Pha 1: Coarse grid (tìm vùng tốt)
Tune 2 biến chính của server:
- `max_num_seqs`
- `max_num_batched_tokens`

Dùng các cặp giữ ratio tăng dần, ví dụ cho model text:
- `(32, 4096)`
- `(64, 4096)`
- `(64, 8192)`
- `(128, 8192)`
- `(128, 16384)`
- `(256, 16384)`

Đây cũng là pattern được docs sweep gợi ý.

### Pha 2: Workload sweep (tìm điểm vận hành)
Với 2-3 cấu hình tốt nhất từ pha 1, dùng `serve_workload` để quét theo tải:
- `--workload-var max_concurrency` (khuyên dùng để ổn định hơn request_rate)
- lấy đường cong latency-throughput, rồi chọn điểm SLA.

---

## Cách chạy cụ thể

### 1) Tạo `serve_params.json`
```json
[
  {"_benchmark_name":"s1","max_num_seqs":32,"max_num_batched_tokens":4096},
  {"_benchmark_name":"s2","max_num_seqs":64,"max_num_batched_tokens":4096},
  {"_benchmark_name":"s3","max_num_seqs":64,"max_num_batched_tokens":8192},
  {"_benchmark_name":"s4","max_num_seqs":128,"max_num_batched_tokens":8192},
  {"_benchmark_name":"s5","max_num_seqs":128,"max_num_batched_tokens":16384},
  {"_benchmark_name":"s6","max_num_seqs":256,"max_num_batched_tokens":16384}
]
```

### 2) Chạy coarse sweep
```bash
vllm bench sweep serve \
  --serve-cmd 'vllm serve <MODEL>' \
  --bench-cmd 'vllm bench serve --model <MODEL> --backend vllm --endpoint /v1/completions --dataset-name sharegpt --dataset-path <DATASET> --num-prompts 300' \
  --serve-params serve_params.json \
  --num-runs 3 \
  --output-dir benchmarks/results \
  --experiment-name tune_batch_v1
```

### 3) Vẽ nhanh kết quả
```bash
vllm bench sweep plot benchmarks/results/tune_batch_v1 \
  --var-x max_num_seqs \
  --var-y total_token_throughput \
  --curve-by max_num_batched_tokens \
  --fig-name tput_vs_seqs
```

và:
```bash
vllm bench sweep plot benchmarks/results/tune_batch_v1 \
  --var-x total_token_throughput \
  --var-y median_ttft_ms \
  --curve-by max_num_seqs,max_num_batched_tokens \
  --fig-name latency_tput_tradeoff
```

### 4) Workload exploration cho top config
```bash
vllm bench sweep serve_workload \
  --serve-cmd 'vllm serve <MODEL>' \
  --bench-cmd 'vllm bench serve --model <MODEL> --backend vllm --endpoint /v1/completions --dataset-name sharegpt --dataset-path <DATASET> --num-prompts 300' \
  --serve-params top_configs.json \
  --workload-var max_concurrency \
  --workload-iters 10 \
  --num-runs 2 \
  --output-dir benchmarks/results \
  --experiment-name tune_workload_v1
```

---

## Áp dụng cho `bench throughput` (offline) thì sao?

Do không có `sweep throughput` built-in, bạn làm:
- giữ cùng grid `max_num_seqs` / `max_num_batched_tokens`
- loop gọi `vllm bench throughput ...` (hoặc script nhỏ)
- chọn theo `tokens/s` + kiểm tra ổn định (OOM, fail, variance).

Nếu bạn muốn, mình có thể soạn luôn:
1) `serve_params.json` theo profile model của bạn  
2) 1 script sweep riêng cho `vllm bench throughput` để chạy và gom kết quả CSV.

---

**User**

ok, bạn có thể tìm thêm thông tin trên mạng và setup cho tôi sweep benchmark với nhwungx thông tin sau
- Single GPU H100 (on Google Colab)
- Model: Qwen/Qwen3.6-35B-A3B-FP8
- Cấu hình bắt buộc --quantization fp8 \
  --kv-cache-dtype fp8_e4m3 \
- Câu hỏi cần trả lời: với cấu hình và model đó, hệ thống có thể đáp ứng lượng request như thế nào và cấu hình cần ra sao 

---

**Cursor**

Mình sẽ làm 2 việc song song: (1) tra cứu nhanh thông tin ngoài repo về Qwen3.6-35B-A3B-FP8 + H100/Colab, (2) dựng sẵn bộ sweep trong repo (JSON + lệnh chạy) để bạn chạy ngay và trả lời câu hỏi “chịu được bao nhiêu request với cấu hình nào”.

Mình sẽ lấy thêm tài liệu chính thức mới nhất từ MCP docs (Context7) để tránh lệch version, rồi mình tạo luôn bộ file sweep + playbook chạy trên Colab H100 cho model này.

Mình sẽ tạo bộ preset riêng trong `benchmarks/auto_tune` cho Colab H100 + Qwen3.6 FP8 (gồm JSON tham số và script chạy 2 pha), để bạn chạy ra được capacity thực tế theo concurrency/SLA. Mình kiểm tra thư mục trước khi thêm file.

Mình đã dựng xong bộ sweep; mình thêm luôn một script phân tích `summary.csv` để tự động trả ra “config tốt nhất” theo ngưỡng SLA (TTFT/E2E), đúng câu hỏi capacity của bạn.

Đã setup xong bộ sweep benchmark cho case của bạn trong repo, bám theo config bắt buộc FP8.

## Những gì mình đã tạo

- `benchmarks/auto_tune/run_colab_h100_qwen36_sweep.sh`  
  Script chạy **2 pha**:
  1) `vllm bench sweep serve` để quét grid `max_num_seqs` + `max_num_batched_tokens`
  2) `vllm bench sweep serve_workload` để tìm capacity theo `max_concurrency`
- `benchmarks/auto_tune/colab_h100_qwen36_serve_params.json`  
  Grid server configs (12 cấu hình từ conservative đến aggressive).
- `benchmarks/auto_tune/colab_h100_qwen36_bench_params.json`  
  3 profile workload: `chat_short`, `chat_medium`, `agent_long_context`.
- `benchmarks/auto_tune/analyze_sweep_capacity.py`  
  Script đọc `summary.csv` và tự chọn config tốt nhất theo ràng buộc SLA (TTFT/E2E).

## Config bắt buộc đã được giữ đúng

Trong script sweep mình đã cố định:

- `--quantization fp8`
- `--kv-cache-dtype fp8_e4m3`

kèm thêm:
- `--tensor-parallel-size 1` (single GPU)
- `--gpu-memory-utilization 0.92`
- `--language-model-only`
- `--reasoning-parser qwen3`

## Cách chạy trên Colab H100

```bash
bash benchmarks/auto_tune/run_colab_h100_qwen36_sweep.sh
```

Nếu cần context ngắn hơn để tăng capacity:
```bash
MAX_MODEL_LEN=16384 bash benchmarks/auto_tune/run_colab_h100_qwen36_sweep.sh
```

Kết quả nằm ở:
- `benchmarks/results/<exp>_grid/summary.csv`
- `benchmarks/results/<exp>_workload/summary.csv`

## Trả lời câu hỏi “hệ thống chịu được bao nhiêu request và cần config ra sao”

Không thể trả số request chính xác trước khi chạy vì phụ thuộc workload (input/output len, SLA TTFT/E2E, pattern concurrency).  
Nhưng sau khi chạy, bạn lấy config đề xuất bằng:

```bash
python benchmarks/auto_tune/analyze_sweep_capacity.py \
  --summary-csv benchmarks/results/qwen36_h100_colab_workload/summary.csv \
  --max-p99-e2el-ms 4000 \
  --max-median-ttft-ms 1200
```

Script sẽ in:
- `max_num_seqs` + `max_num_batched_tokens` tốt nhất dưới SLA
- `request_tps`, `output_tps`, `total_tps`
- top configs để bạn chọn theo ưu tiên latency vs throughput.

## Thông tin mình đã kiểm chứng thêm từ docs/web

- Model card Qwen3.6 FP8 khuyến nghị `vllm>=0.19.0` và có ví dụ phục vụ qua vLLM.
- vLLM docs xác nhận `fp8_e4m3` cho KV cache giúp tăng hiệu quả bộ nhớ/KV capacity.
- vLLM docs + code sweep xác nhận cách đúng để tune 2 biến này là `bench sweep serve` + `serve_workload`.

Nếu bạn muốn, mình có thể thêm một preset thứ 2 tối ưu riêng cho “agent code” (input dài, output ngắn) để giảm thời gian sweep trên Colab.

