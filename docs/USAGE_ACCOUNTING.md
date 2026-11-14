# Token and cost estimates

UAI records provider token counters when they are finite, nonnegative numbers.
Missing or invalid counters use the existing request/reply estimate for that
side of the exchange. Partial or estimated usage is labelled; a malformed
counter cannot turn session totals negative or infinite.

Cached input and newly written cache tokens form parts of total input.
Reasoning tokens form part of total output. Their counters are bounded by those
totals to prevent double counting, and cache-write totals survive history reload.

Costs use the [dated provider catalog](PROVIDER_COMPATIBILITY.md#model-prices-and-limits)
in USD per million text tokens. A zero-cost documented route and an unknown
price are different states. Known costs are summed, while requests without a
known rate are counted separately. Home's per-model history shows how many
requests had unknown cost; those counts survive restarts and remain scoped to
the selected time range.

Older history has no per-request cost-coverage record. UAI does not invent
coverage for that history. Catalog prices can change and may omit request,
image/audio, service-tier or account-specific charges. The totals are estimates,
not billing statements.

Completed native and Cowork messages show `tk/s request avg` when the provider
reports a valid output-token count and UAI records the successful request's wall
time. It includes connection, waiting and transport time; it is not a measurement
of just the model's generation phase. Missing/invalid measurements stay hidden.
The native caption sits below the reply and wraps at narrow widths. Very large
finite averages use a compact scientific value to keep the units readable.
Buffered stream previews never infer speed from the pace at which text is replayed.
