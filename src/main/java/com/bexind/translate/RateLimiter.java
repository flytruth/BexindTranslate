package com.bexind.translate;

import java.util.concurrent.TimeoutException;
import java.util.concurrent.atomic.LongAdder;

/**
 * Minimal token-bucket rate limiter shared by every provider call.
 *
 * Blocking the caller is cheap here because all calls run on Java 21 virtual
 * threads (pinning only happens on synchronized + wait, which is fine for a
 * single shared bucket). When the bucket stays empty for longer than the max
 * wait, a TimeoutException is thrown so the provider chain can fail over.
 */
public final class RateLimiter {

    private final double permitsPerSecond;
    private final double burst;
    private final long maxWaitNanos;
    private final Object lock = new Object();

    private double tokens;
    private long lastRefill = System.nanoTime();

    public final LongAdder rejected = new LongAdder();

    public RateLimiter(double permitsPerSecond, double burst, long maxWaitMs) {
        this.permitsPerSecond = Math.max(0.5, permitsPerSecond);
        this.burst = Math.max(1.0, burst);
        this.maxWaitNanos = Math.max(0, maxWaitMs) * 1_000_000L;
        this.tokens = this.burst;
    }

    /** Acquires one token, blocking up to max-wait-ms. Throws when starved. */
    public void acquire() throws TimeoutException {
        if (maxWaitNanos == 0) {
            synchronized (lock) {
                refill();
                if (tokens >= 1.0) {
                    tokens -= 1.0;
                    return;
                }
            }
            rejected.increment();
            throw new TimeoutException("rate limit (no-wait mode)");
        }

        final long deadline = System.nanoTime() + maxWaitNanos;
        synchronized (lock) {
            while (true) {
                refill();
                if (tokens >= 1.0) {
                    tokens -= 1.0;
                    return;
                }
                long now = System.nanoTime();
                long needed = (long) Math.ceil((1.0 - tokens) / permitsPerSecond * 1_000_000_000.0);
                long wakeAt = now + needed;
                if (wakeAt > deadline) {
                    rejected.increment();
                    throw new TimeoutException("rate limit (waited past max-wait-ms)");
                }
                try {
                    long sleepMs = Math.min(needed, deadline - now) / 1_000_000L;
                    lock.wait(Math.max(1, sleepMs));
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    rejected.increment();
                    throw new TimeoutException("interrupted while waiting for rate limit");
                }
            }
        }
    }

    public double availableTokens() {
        synchronized (lock) {
            refill();
            return tokens;
        }
    }

    private void refill() {
        long now = System.nanoTime();
        double add = (now - lastRefill) / 1_000_000_000.0 * permitsPerSecond;
        if (add > 0) {
            tokens = Math.min(burst, tokens + add);
            lastRefill = now;
        }
    }
}
