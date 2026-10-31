package com.bexind.translate;

import com.google.gson.Gson;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeoutException;
import java.util.regex.Pattern;

/**
 * Async translation facade with a provider failover chain, a shared
 * token-bucket rate limiter and same-language detection.
 * All HTTP work happens on Java 21 virtual threads.
 */
public final class TranslationService {

    private record ProviderResult(String text, String detectedSource) {}

    private record FetchResult(String text, boolean identity) {}

    private final BexindTranslate plugin;
    private final Gson gson = new Gson();
    private final HttpClient http = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(5))
            .followRedirects(HttpClient.Redirect.NORMAL)
            .build();

    private volatile List<Pattern> ignored = List.of();
    private volatile RateLimiter limiter = new RateLimiter(10, 25, 2000);
    private volatile boolean sameLangSkip = true;

    TranslationService(BexindTranslate plugin) {
        this.plugin = plugin;
    }

    /** Re-reads config-dependent state. Called on enable and on /btr reload. */
    public void reload() {
        this.ignored = plugin.getConfig().getStringList("ignored-patterns")
                .stream().map(Pattern::compile).toList();
        double rps = plugin.getConfig().getDouble("rate-limit.requests-per-second", 10);
        double burst = plugin.getConfig().getDouble("rate-limit.burst", 25);
        long maxWait = plugin.getConfig().getLong("rate-limit.max-wait-ms", 2000);
        this.limiter = new RateLimiter(rps, burst, maxWait);
        this.sameLangSkip = plugin.getConfig().getBoolean("same-language-skip", true);
    }

    /** True if the string should never be sent to a provider (URLs, placeholders, codes...). */
    public boolean isIgnored(String text) {
        if (text == null) return true;
        String trimmed = text.trim();
        if (trimmed.isEmpty()) return true;
        for (Pattern p : ignored) {
            if (p.matcher(trimmed).matches()) return true;
        }
        // Strings containing legacy color codes can't be re-flowed safely.
        if (trimmed.indexOf('\u00A7') >= 0) return true;
        // No letters -> nothing to translate
        if (!trimmed.chars().anyMatch(Character::isLetter)) return true;
        return false;
    }

    /**
     * Full pipeline: ignore-check -> L1 -> negative cache -> L2 -> provider chain.
     * NEVER blocks the caller; returns a CompletableFuture on a virtual thread.
     */
    public CompletableFuture<String> translate(String text, String targetLang) {
        if (isIgnored(text)) return CompletableFuture.completedFuture(text);

        Stats stats = plugin.stats();

        String mem = plugin.cache().getMemory(targetLang, text);
        if (mem != null) {
            stats.l1Hits.increment();
            return CompletableFuture.completedFuture(mem);
        }

        if (plugin.cache().isNegative(targetLang, text)) {
            stats.negativeSkips.increment();
            return CompletableFuture.completedFuture(text);
        }

        return plugin.cache().getAsync(targetLang, text).thenCompose(cached -> {
            if (cached != null) return CompletableFuture.completedFuture(cached);

            return CompletableFuture.supplyAsync(() -> {
                FetchResult result = fetchChain(text, targetLang);
                if (result == null) {
                    plugin.cache().markNegative(targetLang, text);
                    return text;
                }
                if (result.identity()) {
                    plugin.cache().putIdentity(targetLang, text);
                    plugin.stats().sameLangSkips.increment();
                    return text;
                }
                String out = result.text();
                if (out == null || out.isBlank() || out.equals(text)) {
                    plugin.cache().markNegative(targetLang, text);
                    return text;
                }
                plugin.cache().put(targetLang, text, out);
                plugin.stats().stringsTranslated.increment();
                return out;
            }, plugin.virtualPool());
        });
    }

    // ------------------------------------------------------------------
    // Provider chain
    // ------------------------------------------------------------------

    private FetchResult fetchChain(String text, String targetLang) {
        List<String> chain = new ArrayList<>();
        String primary = plugin.getConfig().getString("provider", "GOOGLE_FREE")
                .toUpperCase(Locale.ROOT);
        chain.add(primary);
        for (String f : plugin.getConfig().getStringList("failover-providers")) {
            String name = f.toUpperCase(Locale.ROOT);
            if (!chain.contains(name)) chain.add(name);
        }

        for (String provider : chain) {
            try {
                ProviderResult r = callProvider(provider, text, targetLang);
                if (r == null || r.text() == null || r.text().isBlank()) {
                    plugin.stats().providerFailures.increment();
                    continue;
                }
                if (sameLangSkip && r.detectedSource() != null
                        && normalize(r.detectedSource()).equals(normalize(targetLang))) {
                    return new FetchResult(null, true); // already in target language
                }
                return new FetchResult(r.text().trim(), false);
            } catch (TimeoutException te) {
                plugin.stats().rateLimited.increment();
                plugin.stats().providerFailures.increment();
                plugin.getLogger().fine(() -> "Provider " + provider + " rate-limited, failing over");
            } catch (Exception e) {
                plugin.stats().providerFailures.increment();
                plugin.getLogger().fine("Provider " + provider + " failed: " + e.getMessage());
            }
        }
        return null;
    }

    private ProviderResult callProvider(String provider, String text, String targetLang) throws Exception {
        limiter.acquire();
        long t0 = System.nanoTime();
        ProviderResult result = switch (provider) {
            case "GEMINI" -> gemini(text, targetLang);
            case "LIBRETRANSLATE" -> libre(text, targetLang);
            case "OLLAMA" -> ollama(text, targetLang);
            case "GOOGLE_FREE" -> googleFree(text, targetLang);
            default -> null;
        };
        plugin.stats().providerCalls.increment();
        plugin.stats().providerLatencyMs.add((System.nanoTime() - t0) / 1_000_000L);
        return result;
    }

    // ------------------------------------------------------------------
    // Provider 1: free Google Translate web endpoint (no key, no cost)
    // ------------------------------------------------------------------
    private ProviderResult googleFree(String text, String targetLang) throws Exception {
        String url = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl="
                + URLEncoder.encode(targetLang, StandardCharsets.UTF_8)
                + "&dt=t&q=" + URLEncoder.encode(text, StandardCharsets.UTF_8);

        HttpRequest req = HttpRequest.newBuilder(URI.create(url))
                .timeout(timeout())
                .header("User-Agent", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36")
                .GET().build();

        HttpResponse<String> resp = http.send(req, HttpResponse.BodyHandlers.ofString());
        if (resp.statusCode() == 429) {
            Thread.sleep(400); // brief backoff, single retry on soft rate limit
            resp = http.send(req, HttpResponse.BodyHandlers.ofString());
        }
        if (resp.statusCode() != 200) return null;

        // Response shape: [[["translated","original",...],...], null, "detected-src", ...]
        JsonArray root = JsonParser.parseString(resp.body()).getAsJsonArray();
        StringBuilder sb = new StringBuilder();
        for (JsonElement seg : root.get(0).getAsJsonArray()) {
            JsonArray pair = seg.getAsJsonArray();
            if (pair.size() > 0 && !pair.get(0).isJsonNull()) {
                sb.append(pair.get(0).getAsString());
            }
        }
        if (sb.isEmpty()) return null;

        String detected = root.size() > 2 && root.get(2).isJsonPrimitive()
                ? root.get(2).getAsString() : null;
        return new ProviderResult(sb.toString(), detected);
    }

    // ------------------------------------------------------------------
    // Provider 2: Google Gemini (free tier API key)
    // ------------------------------------------------------------------
    private ProviderResult gemini(String text, String targetLang) throws Exception {
        String key = plugin.getConfig().getString("gemini-api-key", "");
        String model = plugin.getConfig().getString("gemini-model", "gemini-2.0-flash");
        if (key == null || key.isBlank() || key.startsWith("YOUR_")) return null;

        JsonObject body = new JsonObject();
        JsonArray contents = new JsonArray();
        JsonObject content = new JsonObject();
        JsonArray parts = new JsonArray();
        JsonObject part = new JsonObject();
        part.addProperty("text", translatePrompt(text, targetLang));
        parts.add(part);
        content.add("parts", parts);
        contents.add(content);
        body.add("contents", contents);

        HttpRequest req = HttpRequest.newBuilder(URI.create(
                        "https://generativelanguage.googleapis.com/v1beta/models/" + model
                                + ":generateContent?key=" + key))
                .timeout(timeout())
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(gson.toJson(body), StandardCharsets.UTF_8))
                .build();

        HttpResponse<String> resp = http.send(req, HttpResponse.BodyHandlers.ofString());
        if (resp.statusCode() != 200) return null;

        JsonObject json = JsonParser.parseString(resp.body()).getAsJsonObject();
        String out = json.getAsJsonArray("candidates").get(0).getAsJsonObject()
                .getAsJsonArray("content").get(0).getAsJsonObject()
                .getAsJsonArray("parts").get(0).getAsJsonObject()
                .get("text").getAsString().trim();
        return new ProviderResult(out, null);
    }

    // ------------------------------------------------------------------
    // Provider 3: LibreTranslate (self-hosted or public instance)
    // ------------------------------------------------------------------
    private ProviderResult libre(String text, String targetLang) throws Exception {
        String base = plugin.getConfig().getString("libretranslate-url", "http://localhost:5000");
        String apiKey = plugin.getConfig().getString("libretranslate-api-key", "");

        JsonObject body = new JsonObject();
        body.addProperty("q", text);
        body.addProperty("source", "auto");
        body.addProperty("target", targetLang);
        body.addProperty("format", "text");
        if (apiKey != null && !apiKey.isBlank()) body.addProperty("api_key", apiKey);

        HttpRequest req = HttpRequest.newBuilder(URI.create(base + "/translate"))
                .timeout(timeout())
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(gson.toJson(body), StandardCharsets.UTF_8))
                .build();

        HttpResponse<String> resp = http.send(req, HttpResponse.BodyHandlers.ofString());
        if (resp.statusCode() != 200) return null;

        JsonObject json = JsonParser.parseString(resp.body()).getAsJsonObject();
        return new ProviderResult(json.get("translatedText").getAsString(), null);
    }

    // ------------------------------------------------------------------
    // Provider 4: local Ollama (the v1 config advertised this but never
    // implemented it - now it works via /api/chat)
    // ------------------------------------------------------------------
    private ProviderResult ollama(String text, String targetLang) throws Exception {
        String base = plugin.getConfig().getString("ollama-url", "http://localhost:11434");
        String model = plugin.getConfig().getString("ollama-model", "llama3");

        JsonObject body = new JsonObject();
        body.addProperty("model", model);
        body.addProperty("stream", false);
        JsonObject msg = new JsonObject();
        msg.addProperty("role", "user");
        msg.addProperty("content", translatePrompt(text, targetLang));
        JsonArray messages = new JsonArray();
        messages.add(msg);
        body.add("messages", messages);

        HttpRequest req = HttpRequest.newBuilder(URI.create(base + "/api/chat"))
                .timeout(timeout())
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(gson.toJson(body), StandardCharsets.UTF_8))
                .build();

        HttpResponse<String> resp = http.send(req, HttpResponse.BodyHandlers.ofString());
        if (resp.statusCode() != 200) return null;

        JsonObject json = JsonParser.parseString(resp.body()).getAsJsonObject();
        JsonObject message = json.getAsJsonObject("message");
        if (message == null || message.get("content") == null) return null;
        return new ProviderResult(message.get("content").getAsString().trim(), null);
    }

    // ------------------------------------------------------------------

    private String translatePrompt(String text, String targetLang) {
        return "Translate the following text to language code \"" + targetLang
                + "\". Reply with ONLY the translation, nothing else. "
                + "Keep URLs, numbers, placeholders like %player% and color codes unchanged. Text:\n"
                + text;
    }

    /** "pt-BR" -> "pt", "ru" -> "ru". */
    private static String normalize(String lang) {
        if (lang == null) return "";
        String l = lang.toLowerCase(Locale.ROOT).trim();
        int cut = l.indexOf('-');
        if (cut > 0) l = l.substring(0, cut);
        return l;
    }

    private Duration timeout() {
        return Duration.ofSeconds(plugin.getConfig().getInt("http-timeout-seconds", 6));
    }
}
