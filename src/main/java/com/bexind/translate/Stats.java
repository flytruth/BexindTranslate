package com.bexind.translate;

import java.util.concurrent.atomic.LongAdder;

/**
 * Thread-safe counters backing /btr stats.
 * LongAdder keeps increment cost near zero on hot packet paths.
 */
public final class Stats {

    public final LongAdder packetsSeen = new LongAdder();      // packets reaching a handler
    public final LongAdder packetsRewritten = new LongAdder(); // fast path (all cache hits)
    public final LongAdder packetsQueued = new LongAdder();    // async translation batches started
    public final LongAdder packetsResent = new LongAdder();    // translated copies re-sent async
    public final LongAdder stringsTranslated = new LongAdder();// provider results actually stored
    public final LongAdder l1Hits = new LongAdder();           // memory cache hits
    public final LongAdder l2Hits = new LongAdder();           // SQLite cache hits
    public final LongAdder cacheMisses = new LongAdder();      // full misses -> provider call
    public final LongAdder negativeSkips = new LongAdder();    // skips thanks to negative cache
    public final LongAdder sameLangSkips = new LongAdder();    // skips thanks to same-language skip
    public final LongAdder providerCalls = new LongAdder();
    public final LongAdder providerFailures = new LongAdder();
    public final LongAdder providerLatencyMs = new LongAdder();
    public final LongAdder rateLimited = new LongAdder();      // calls rejected by the limiter

    private final long startedAt = System.currentTimeMillis();

    public long providerAvgMs() {
        long calls = providerCalls.sum();
        return calls == 0 ? 0 : providerLatencyMs.sum() / calls;
    }

    public long uptimeMinutes() {
        return (System.currentTimeMillis() - startedAt) / 60000L;
    }
}
