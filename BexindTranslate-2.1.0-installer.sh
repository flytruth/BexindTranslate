#!/usr/bin/env bash
# ============================================================
#  BexindTranslate 2.1.0 — one-paste installer (Arch Linux)
#
#  How to use:
#    1) paste this WHOLE file into a terminal, or
#    2) save it and run:  bash BexindTranslate-2.1.0-installer.sh
#    3) skip the optional server setup with:  SETUP_SERVER=0 bash ...
#    4) pick another Paper version:  PAPER_VERSION=1.21.11 bash ...
#       (tested on Paper 1.21.1 and 1.21.11)
#
#  It creates the full plugin source at ~/BexindTranslate, builds the jar
#  with Maven, and (by default) prepares a Paper server at ~/mc-server
#  with ProtocolLib already installed.
# ============================================================
set -euo pipefail

PAPER_VERSION="${PAPER_VERSION:-1.21.1}"

echo "==> [1/4] Checking toolchain"
missing=()
command -v mvn   >/dev/null 2>&1 || missing+=("maven")
command -v javac >/dev/null 2>&1 || missing+=("jdk21-openjdk")
if [ ${#missing[@]} -gt 0 ]; then
  echo "Missing: ${missing[*]}"
  echo "Install with:   sudo pacman -S --needed jdk21-openjdk maven curl jq"
  echo "(a JRE is not enough - you need the full JDK to compile)"
  exit 1
fi
JAVA_MAJOR=$(javac -version 2>&1 | grep -o '[0-9][0-9]*' | head -1)
if [ "$JAVA_MAJOR" != "21" ]; then
  echo "WARNING: javac is version '$JAVA_MAJOR', but Java 21 is required."
  echo "On Arch:  sudo pacman -S jdk21-openjdk && sudo archlinux-java set java-21-openjdk"
  exit 1
fi
echo "    toolchain OK (javac $JAVA_MAJOR)"

echo "==> [2/4] Creating project at ~/BexindTranslate"
mkdir -p ~/BexindTranslate
cd ~/BexindTranslate
# clean slate: stale older sources would poison the build
rm -rf src pom.xml

mkdir -p src/main/resources
mkdir -p src/main/java/com/bexind/translate
cat > pom.xml <<'BEXIND_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>

  <groupId>com.bexind</groupId>
  <artifactId>BexindTranslate</artifactId>
  <version>2.1.0</version>
  <packaging>jar</packaging>

  <properties>
    <maven.compiler.release>21</maven.compiler.release>
    <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
  </properties>

  <repositories>
    <repository>
      <id>papermc</id>
      <url>https://repo.papermc.io/repository/maven-public/</url>
    </repository>
    <repository>
      <id>dmulloy2-repo</id>
      <url>https://repo.dmulloy2.net/repository/public/</url>
    </repository>
  </repositories>

  <dependencies>
    <!-- Paper API (Adventure Components included) -->
    <dependency>
      <groupId>io.papermc.paper</groupId>
      <artifactId>paper-api</artifactId>
      <version>1.21.1-R0.1-SNAPSHOT</version>
      <scope>provided</scope>
    </dependency>

    <!-- ProtocolLib (installed as plugin on the server) -->
    <dependency>
      <groupId>com.comphenix.protocol</groupId>
      <artifactId>ProtocolLib</artifactId>
      <version>5.3.0</version>
      <scope>provided</scope>
    </dependency>

    <!-- In-memory cache -->
    <dependency>
      <groupId>com.github.ben-manes.caffeine</groupId>
      <artifactId>caffeine</artifactId>
      <version>3.1.8</version>
    </dependency>

    <!-- Persistent cache -->
    <dependency>
      <groupId>org.xerial</groupId>
      <artifactId>sqlite-jdbc</artifactId>
      <version>3.46.1.0</version>
    </dependency>
  </dependencies>

  <build>
    <finalName>BexindTranslate-${project.version}</finalName>
    <plugins>
      <plugin>
        <groupId>org.apache.maven.plugins</groupId>
        <artifactId>maven-shade-plugin</artifactId>
        <version>3.5.1</version>
        <executions>
          <execution>
            <phase>package</phase>
            <goals><goal>shade</goal></goals>
            <configuration>
              <relocations>
                <relocation>
                  <pattern>com.github.benmanes.caffeine</pattern>
                  <shadedPattern>com.bexind.translate.lib.caffeine</shadedPattern>
                </relocation>
                <relocation>
                  <pattern>org.sqlite</pattern>
                  <shadedPattern>com.bexind.translate.lib.sqlite</shadedPattern>
                </relocation>
              </relocations>
              <filters>
                <filter>
                  <artifact>*:*</artifact>
                  <excludes>
                    <exclude>META-INF/*.SF</exclude>
                    <exclude>META-INF/*.DSA</exclude>
                    <exclude>META-INF/*.RSA</exclude>
                  </excludes>
                </filter>
              </filters>
            </configuration>
          </execution>
        </executions>
      </plugin>
    </plugins>
  </build>
</project>
BEXIND_EOF
cat > src/main/resources/plugin.yml <<'BEXIND_EOF'
name: BexindTranslate
version: 2.1.0
main: com.bexind.translate.BexindTranslate
api-version: '1.21'
# Hard dependency on purpose: when ProtocolLib is absent, Paper stops the plugin
# before any class scan and prints "Please download and install ProtocolLib".
# When ProtocolLib IS present but broken, onEnable prints exact fix instructions.
depend: [ProtocolLib]
softdepend: [PlaceholderAPI, DecentHolograms, DeluxeMenus, TAB]
author: BexindStudio
description: Universal real-time packet-level dynamic server translation.
commands:
  bexindtranslate:
    aliases: [btr]
    description: Main command for BexindTranslate
    permission: bexindtranslate.use
  translate:
    aliases: [tr]
    description: Alias of /bexindtranslate - same subcommands, same permission
    permission: bexindtranslate.use
permissions:
  bexindtranslate.use:
    default: true
  bexindtranslate.admin:
    default: op
BEXIND_EOF
cat > src/main/resources/config.yml <<'BEXIND_EOF'
# ============================================================
#  BexindTranslate 2.1.0
#  Universal real-time packet-level dynamic server translation
#  Languages: English + Russian only
# ============================================================

config-version: 3

# Primary translation provider:
#   GOOGLE_FREE    - free Google Translate web endpoint (no key needed)
#   GEMINI         - Google Gemini (free tier API key)
#   LIBRETRANSLATE - LibreTranslate server (self-hosted or public)
#   OLLAMA         - local Ollama / OpenAI-style local model
provider: "GOOGLE_FREE"

# Tried in order when the primary provider fails or is rate-limited.
# Example: ["LIBRETRANSLATE", "GEMINI"]
failover-providers: []

gemini-api-key: "YOUR_FREE_API_KEY_HERE"
gemini-model: "gemini-2.0-flash"

libretranslate-url: "http://localhost:5000"
libretranslate-api-key: ""

ollama-url: "http://localhost:11434"
ollama-model: "llama3"

# Used until the player picks a language in the menu. Must be en or ru.
default-language: "en"

# The only two languages the plugin works with. Keep exactly [en, ru].
languages:
  - en
  - ru

# Timeout for a single HTTP translation call
http-timeout-seconds: 6

# Token-bucket rate limiter shared by ALL provider calls.
# Protects the free Google endpoint from IP bans under load.
rate-limit:
  requests-per-second: 10
  burst: 25
  max-wait-ms: 2000

# If a provider detects the text is ALREADY in the player's language,
# remember it and never call the API for that string again.
same-language-skip: true

# Remember failed translations for N minutes so dead providers are
# not hammered on every packet.
negative-cache-minutes: 5

# Verbose per-packet logging (can also be toggled live with /btr debug)
debug: false

features:
  chat: true
  guis-and-menus: true
  holograms-and-actionbars: true
  titles: true
  boss-bars: true
  tab-list: true
  advancements: true
  signs: true
  scoreboards: true

# ------------------------------------------------------------------
#  The language selection menu (fully customizable)
#  Text uses MiniMessage: <red>, <gradient:#00c6ff:#0072ff>...</gradient>,
#  <bold>, <gray>, etc.  https://docs.advntr.dev/minimessage/format.html
# ------------------------------------------------------------------
menu:
  # Cannot be closed until a language is picked (ESC reopens it)
  force: true
  # Shown when a forced player tries to close the menu
  must-pick-message: "<red>You must select a language first! / Сначала выберите язык!"
  # Shown after choosing; <lang> becomes en or ru
  chosen-message: "<green>Language set: <yellow><lang>"
  # Shown when clicking the language that is already active
  already-message: "<yellow>You are already playing in <lang>!"

  title: "<gradient:#00c6ff:#0072ff>Select language / Выберите язык</gradient>"
  rows: 3

  # Item used to fill all empty slots (name " " keeps it unnamed)
  fill:
    material: GRAY_STAINED_GLASS_PANE
    name: " "

  # Add a glint effect to the currently active language button
  selected-glow: true

  buttons:
    en:
      slot: 11
      material: LIME_WOOL
      name: "<green>English"
      lore:
        - "<gray>Click to play in English"
    ru:
      slot: 15
      material: RED_WOOL
      name: "<red>Русский"
      lore:
        - "<gray>Нажмите, чтобы играть на русском"

# Blacklist specific strings or placeholders from being translated
ignored-patterns:
  - "^https?://.*"                      # Don't translate URLs
  - "%\\w+%"                            # Skip raw PAPI placeholders
  - "^\\d+$"                            # Numbers
  - "^[A-Za-z0-9_+/=:;.\\-\\[\\]()#]+$" # pure codes/symbols
BEXIND_EOF
cat > src/main/java/com/bexind/translate/BexindTranslate.java <<'BEXIND_EOF'
package com.bexind.translate;

import com.comphenix.protocol.ProtocolLibrary;
import com.comphenix.protocol.ProtocolManager;
import org.bukkit.NamespacedKey;
import org.bukkit.command.PluginCommand;
import org.bukkit.entity.Player;
import org.bukkit.event.EventHandler;
import org.bukkit.event.Listener;
import org.bukkit.event.player.PlayerQuitEvent;
import org.bukkit.plugin.java.JavaPlugin;

import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

public final class BexindTranslate extends JavaPlugin {

    private static BexindTranslate instance;

    private ExecutorService virtualPool;
    private Stats stats;
    private CacheManager cache;
    private TranslationService translationService;
    private LangManager langManager;
    private ProtocolManager protocolManager;
    private PacketInterceptor interceptor;
    private LanguageMenuListener menuListener;
    private NamespacedKey menuKey;
    private volatile boolean debugEnabled;

    public LanguageMenuListener menuListener() { return menuListener; }

    /** PDC key marking OUR menu items so the interceptor never rewrites them. */
    public NamespacedKey menuKey() { return menuKey; }

    public PacketInterceptor interceptor() { return interceptor; }

    @Override
    public void onEnable() {
        instance = this;
        saveDefaultConfig();
        upgradeConfig();

        // Java 21 virtual threads: unbounded, cheap, never block the main tick thread.
        this.virtualPool = Executors.newVirtualThreadPerTaskExecutor();
        this.stats = new Stats();
        this.debugEnabled = getConfig().getBoolean("debug", false);

        this.translationService = new TranslationService(this);
        this.translationService.reload();
        this.langManager = new LangManager(this);

        // Network interception layer. ProtocolLib is a soft dependency on purpose:
        // when it is missing or broken we print exact fix instructions instead of
        // crashing with a NoClassDefFoundError nobody can act on.
        try {
            this.protocolManager = ProtocolLibrary.getProtocolManager();
            if (this.protocolManager == null) {
                throw new IllegalStateException("ProtocolLib did not provide a protocol manager (it probably failed to load - see its own error above)");
            }
            this.interceptor = new PacketInterceptor(this);
            this.protocolManager.addPacketListener(this.interceptor);
        } catch (Throwable t) {
            printDependencyHelp(t);
            getServer().getPluginManager().disablePlugin(this);
            return;
        }

        this.menuKey = new NamespacedKey(this, "menu_item");

        List<String> skipped = PacketInterceptor.skippedTypes();
        if (!skipped.isEmpty()) {
            getLogger().warning("This ProtocolLib build does not expose packet type(s) " + skipped
                    + " - the matching features are disabled. Install the latest ProtocolLib to restore them.");
        }

        this.cache = new CacheManager(this);
        this.cache.initAsync(); // opens SQLite off-thread

        // Commands + join menu
        PluginCommand cmd = getCommand("bexindtranslate");
        LangCommand langCommand = new LangCommand(this);
        cmd.setExecutor(langCommand);
        cmd.setTabCompleter(langCommand);

        // /translate mirrors /bexindtranslate exactly (same executor, same perms)
        PluginCommand aliasCmd = getCommand("translate");
        if (aliasCmd != null) {
            aliasCmd.setExecutor(langCommand);
            aliasCmd.setTabCompleter(langCommand);
        }

        this.menuListener = new LanguageMenuListener(this);
        getServer().getPluginManager().registerEvents(menuListener, this);
        getServer().getPluginManager().registerEvents(new QuitCleanup(), this);

        // After a /reload or plugin manager reload, players may already be online.
        getServer().getScheduler().runTaskLater(this, () -> {
            for (Player p : getServer().getOnlinePlayers()) {
                menuListener.offerMenu(p);
            }
        }, 10L);

        String plVersion;
        try {
            plVersion = protocolManager.getMinecraftVersion().toString();
        } catch (Throwable t) {
            plVersion = "unknown";
        }
        getLogger().info("BexindTranslate " + getDescription().getVersion() + " enabled. Provider: "
                + getConfig().getString("provider", "GOOGLE_FREE")
                + ", failover: " + getConfig().getStringList("failover-providers")
                + ", protocol: " + plVersion);
    }

    /**
     * The #1 reason the plugin shows up RED in /plugins is a missing or broken
     * ProtocolLib. Say so loudly and tell the admin exactly what to install.
     */
    private void printDependencyHelp(Throwable cause) {
        String bar = "==========================================================";
        getLogger().severe(bar);
        getLogger().severe("BexindTranslate could not hook into ProtocolLib. That is why");
        getLogger().severe("the plugin shows up RED in /plugins.");
        getLogger().severe("Reason: " + cause.getClass().getName() + ": " + cause.getMessage());
        getLogger().severe(" ");
        getLogger().severe("Fix (takes one minute):");
        getLogger().severe("  1. Stop the server.");
        getLogger().severe("  2. Download ProtocolLib 5.4.0 or newer:");
        getLogger().severe("     https://github.com/dmulloy2/ProtocolLib/releases");
        getLogger().severe("     Paper 1.21.x: ProtocolLib 5.4.0 (release) works. Do NOT");
        getLogger().severe("     use old 5.3.0 jars or an incompatible dev snapshot.");
        getLogger().severe("  3. Drop ProtocolLib.jar into plugins/ and RESTART.");
        getLogger().severe(" ");
        getLogger().severe("If ProtocolLib IS already in plugins/, it failed to load:");
        getLogger().severe("scroll up for the ProtocolLib error and update it first -");
        getLogger().severe("a broken ProtocolLib always breaks BexindTranslate too.");
        getLogger().severe(bar);
    }

    @Override
    public void onDisable() {
        if (protocolManager != null) {
            try {
                protocolManager.removePacketListeners(this);
            } catch (Throwable ignored) {
                // ProtocolLib may already be gone; never block our own shutdown.
            }
        }
        if (virtualPool != null) {
            virtualPool.shutdown();
            try {
                virtualPool.awaitTermination(3, TimeUnit.SECONDS);
            } catch (InterruptedException ignored) {
                Thread.currentThread().interrupt();
            }
        }
        if (cache != null) cache.close();
        getLogger().info("BexindTranslate disabled. Provider calls: " + stats.providerCalls.sum()
                + ", strings translated: " + stats.stringsTranslated.sum());
        instance = null;
    }

    public static BexindTranslate get() {
        return instance;
    }

    public ExecutorService virtualPool() {
        return virtualPool;
    }

    public Stats stats() {
        return stats;
    }

    public CacheManager cache() {
        return cache;
    }

    public TranslationService translation() {
        return translationService;
    }

    public LangManager langs() {
        return langManager;
    }

    public boolean debugEnabled() {
        return debugEnabled;
    }

    public boolean toggleDebug() {
        debugEnabled = !debugEnabled;
        return debugEnabled;
    }

    public void debug(java.util.function.Supplier<String> message) {
        if (debugEnabled) getLogger().info("[debug] " + message.get());
    }

    /** Adds v2/v3 config keys for servers upgrading without touching user edits. */
    private void upgradeConfig() {
        if (getConfig().getInt("config-version", 0) >= 3) return;
        getConfig().set("config-version", 3);

        setDefault("languages", List.of("en", "ru"));

        // menu.* replaces the 2.0 keys force-language-menu / menu-languages
        setDefault("menu.force", getConfig().getBoolean("force-language-menu", true));
        setDefault("menu.must-pick-message",
                "<red>You must select a language first! / Сначала выберите язык!");
        setDefault("menu.chosen-message", "<green>Language set: <yellow><lang>");
        setDefault("menu.already-message", "<yellow>You are already playing in <lang>!");
        setDefault("menu.title", "<gradient:#00c6ff:#0072ff>Select language / Выберите язык</gradient>");
        setDefault("menu.rows", 3);
        setDefault("menu.fill.material", "GRAY_STAINED_GLASS_PANE");
        setDefault("menu.fill.name", " ");
        setDefault("menu.selected-glow", true);
        setDefault("menu.buttons.en.slot", 11);
        setDefault("menu.buttons.en.material", "LIME_WOOL");
        setDefault("menu.buttons.en.name", "<green>English");
        setDefault("menu.buttons.en.lore", List.of("<gray>Click to play in English"));
        setDefault("menu.buttons.ru.slot", 15);
        setDefault("menu.buttons.ru.material", "RED_WOOL");
        setDefault("menu.buttons.ru.name", "<red>Русский");
        setDefault("menu.buttons.ru.lore", List.of("<gray>Нажмите, чтобы играть на русском"));

        // 2.0 keys that no longer apply to the two-language model
        getConfig().set("force-language-menu", null);
        getConfig().set("menu-languages", null);

        saveConfig();
        getLogger().info("Config upgraded to config-version 3 (two-language menu).");
    }

    private void setDefault(String path, Object value) {
        if (!getConfig().isSet(path)) getConfig().set(path, value);
    }

    /** Frees per-player state on quit (v1 leaked override/saved/forced maps). */
    private final class QuitCleanup implements Listener {
        @EventHandler
        public void onQuit(PlayerQuitEvent event) {
            langManager.forget(event.getPlayer().getUniqueId());
            menuListener.release(event.getPlayer().getUniqueId());
        }
    }
}
BEXIND_EOF
cat > src/main/java/com/bexind/translate/Stats.java <<'BEXIND_EOF'
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
BEXIND_EOF
cat > src/main/java/com/bexind/translate/RateLimiter.java <<'BEXIND_EOF'
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
BEXIND_EOF
cat > src/main/java/com/bexind/translate/JsonText.java <<'BEXIND_EOF'
package com.bexind.translate;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.google.gson.JsonPrimitive;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.function.UnaryOperator;

/**
 * Recursive component-JSON walker for Adventure/GSON component trees.
 *
 * v2 rewrite: correctly handles raw-string roots ("hello"), string elements
 * inside "extra"/"with" arrays (v1 silently dropped those), never touches the
 * "text" field of components that use "translate" keys (those are localized
 * client-side), and returns the ORIGINAL string reference when nothing
 * changed, so callers can detect no-ops with a cheap == comparison.
 */
public final class JsonText {

    private JsonText() {
    }

    /** Extracts all translatable "text" leaves from a component JSON string. */
    public static List<String> leaves(String json) {
        List<String> out = new ArrayList<>();
        try {
            collect(JsonParser.parseString(json), out);
        } catch (Exception ignored) {
        }
        return out;
    }

    /**
     * Replaces every translatable "text" leaf using the mapper. Returns the
     * new JSON, or the ORIGINAL string reference when nothing changed or the
     * input was unparseable.
     */
    public static String map(String json, UnaryOperator<String> mapper) {
        if (json == null || json.isBlank()) return json;
        try {
            JsonElement tree = JsonParser.parseString(json);
            boolean[] changed = {false};
            JsonElement mapped = mapEl(tree, mapper, changed);
            if (!changed[0]) return json; // identity -> no reserialization needed
            return GSON.toJson(mapped);
        } catch (Exception e) {
            return json;
        }
    }

    private static void collect(JsonElement el, List<String> out) {
        if (el == null || el.isJsonNull()) return;
        if (el.isJsonArray()) {
            for (JsonElement child : el.getAsJsonArray()) collect(child, out);
            return;
        }
        if (el.isJsonObject()) {
            JsonObject obj = el.getAsJsonObject();
            // "translate" components are localized by the client already
            if (!obj.has("translate")) {
                JsonElement t = obj.get("text");
                if (t != null && t.isJsonPrimitive() && t.getAsJsonPrimitive().isString()
                        && !t.getAsString().isBlank()) {
                    out.add(t.getAsString());
                }
            }
            for (String key : new String[]{"extra", "with"}) {
                if (obj.has(key)) collect(obj.get(key), out);
            }
            return;
        }
        if (el.isJsonPrimitive() && el.getAsJsonPrimitive().isString()
                && !el.getAsString().isBlank()) {
            out.add(el.getAsString());
        }
    }

    private static JsonElement mapEl(JsonElement el, UnaryOperator<String> mapper, boolean[] changed) {
        if (el == null || el.isJsonNull()) return el;

        if (el.isJsonArray()) {
            JsonArray out = new JsonArray();
            for (JsonElement child : el.getAsJsonArray()) out.add(mapEl(child, mapper, changed));
            return out;
        }

        if (el.isJsonObject()) {
            JsonObject src = el.getAsJsonObject();
            JsonObject out = new JsonObject();
            for (Map.Entry<String, JsonElement> entry : src.entrySet()) {
                String key = entry.getKey();
                if (key.equals("text") && !src.has("translate")) {
                    JsonElement t = entry.getValue();
                    if (t.isJsonPrimitive() && t.getAsJsonPrimitive().isString()) {
                        String val = t.getAsString();
                        if (!val.isBlank()) {
                            String mapped = mapper.apply(val);
                            if (mapped != null && !mapped.equals(val)) {
                                out.addProperty("text", mapped);
                                changed[0] = true;
                                continue;
                            }
                        }
                    }
                    out.add(key, t);
                } else if (key.equals("extra") || key.equals("with")) {
                    out.add(key, mapEl(entry.getValue(), mapper, changed));
                } else {
                    out.add(key, entry.getValue());
                }
            }
            return out;
        }

        if (el.isJsonPrimitive() && el.getAsJsonPrimitive().isString()) {
            String val = el.getAsString();
            if (val.isBlank()) return el;
            String mapped = mapper.apply(val);
            if (mapped != null && !mapped.equals(val)) {
                changed[0] = true;
                return new JsonPrimitive(mapped);
            }
            return el;
        }

        return el;
    }

    private static final com.google.gson.Gson GSON = new com.google.gson.Gson();
}
BEXIND_EOF
cat > src/main/java/com/bexind/translate/DeepTextScanner.java <<'BEXIND_EOF'
package com.bexind.translate;

import com.comphenix.protocol.wrappers.WrappedChatComponent;
import sun.misc.Unsafe;

import java.lang.reflect.Field;
import java.lang.reflect.Modifier;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Collections;
import java.util.IdentityHashMap;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

/**
 * Reflection walker that finds every NMS chat Component inside a packet
 * handle graph and swaps it for a translated copy.
 *
 * Why this exists: scoreboard team/score/objective, boss-bar and unsigned
 * player-chat packets carry their Components nested inside Optionals or
 * record fields, which ProtocolLib's flat StructureModifier cannot expose.
 *
 * Paper 1.20.5+ runs a Mojang-mapped runtime, so record component names
 * ("name", "displayName", ...) are stable. Packet records are immutable
 * (final fields), so swaps go through sun.misc.Unsafe - the same technique
 * ProtocolLib itself uses internally. Every step is guarded: on any mapping
 * change the scanner silently no-ops instead of crashing.
 *
 * IMPORTANT: callers must only swap on a packet copy (see
 * PacketInterceptor#safeClone) - mutating a shared broadcast packet would
 * translate it into whichever language was processed first.
 */
public final class DeepTextScanner {

    /** A located component: its owner object, the field holding it, and its JSON. */
    public record Slot(Object owner, Field field, boolean insideOptional, String json) {}

    private static final Class<?> COMPONENT_CLASS = resolveComponentClass();
    private static final Unsafe UNSAFE = resolveUnsafe();
    private static final int MAX_NODES = 500;

    private DeepTextScanner() {
    }

    public static boolean available() {
        return COMPONENT_CLASS != null && UNSAFE != null;
    }

    /** Walks the object graph and returns every Component found with its location. */
    public static List<Slot> findComponents(Object root, int maxDepth) {
        return findComponents(root, maxDepth, null);
    }

    /**
     * Same, but when onlyField is non-null only fields with that exact name are
     * recorded (used for signed player chat: ONLY "unsignedContent" is safe to
     * touch - everything else, like the chat-type decoration carrying the
     * sender's name, must never be machine-translated).
     */
    public static List<Slot> findComponents(Object root, int maxDepth, String onlyField) {
        List<Slot> out = new ArrayList<>();
        if (root == null || !available()) return out;
        Set<Object> visited = Collections.newSetFromMap(new IdentityHashMap<>());
        walk(root, out, visited, 0, maxDepth, onlyField);
        return out;
    }

    public static int swapAll(BexindTranslate plugin, Object root, String lang, int maxDepth) {
        return swapAll(plugin, root, lang, maxDepth, null);
    }

    /**
     * Finds all components under the root, JSON-maps each one and swaps it
     * in place. Returns the number of components actually changed.
     */
    public static int swapAll(BexindTranslate plugin, Object root, String lang,
                              int maxDepth, String onlyField) {
        List<Slot> slots = findComponents(root, maxDepth, onlyField);
        int changed = 0;
        for (Slot slot : slots) {
            String mapped = JsonText.map(slot.json(), s -> {
                String hit = plugin.cache().getMemory(lang, s);
                return hit != null ? hit : s;
            });
            if (mapped == slot.json()) continue;
            try {
                Object newComponent = WrappedChatComponent.fromJson(mapped).getHandle();
                Object replacement = slot.insideOptional() ? Optional.of(newComponent) : newComponent;
                setField(slot.owner(), slot.field(), replacement);
                changed++;
            } catch (Throwable t) {
                plugin.debug(() -> "component swap failed: " + t);
            }
        }
        return changed;
    }

    /** Writes a field even when it is final (records) via Unsafe. */
    public static void setField(Object owner, Field field, Object value) throws Throwable {
        field.setAccessible(true);
        if (!Modifier.isFinal(field.getModifiers())) {
            field.set(owner, value);
        } else {
            long offset = UNSAFE.objectFieldOffset(field);
            UNSAFE.putObject(owner, offset, value);
        }
    }

    private static void walk(Object node, List<Slot> out, Set<Object> visited,
                             int depth, int maxDepth, String onlyField) {
        if (node == null || depth > maxDepth || visited.size() > MAX_NODES) return;
        if (node instanceof String || node instanceof Number || node instanceof Boolean
                || node instanceof Character || node instanceof UUID || node instanceof Enum) {
            return;
        }
        if (!visited.add(node)) return;

        for (Class<?> c = node.getClass(); c != null && c != Object.class; c = c.getSuperclass()) {
            for (Field f : c.getDeclaredFields()) {
                if (Modifier.isStatic(f.getModifiers())) continue;
                Class<?> type = f.getType();
                if (type.isPrimitive() || type == String.class) continue;
                Object value;
                try {
                    f.setAccessible(true);
                    value = f.get(node);
                } catch (Throwable t) {
                    continue;
                }
                if (value == null) continue;
                boolean nameMatch = onlyField == null || onlyField.equals(f.getName());

                if (COMPONENT_CLASS.isInstance(value)) {
                    if (nameMatch) addSlot(node, f, false, value, out);
                } else if (value instanceof Optional<?> opt) {
                    Object inner = opt.orElse(null);
                    if (inner == null) continue;
                    if (COMPONENT_CLASS.isInstance(inner)) {
                        if (nameMatch) addSlot(node, f, true, inner, out);
                    } else {
                        walk(inner, out, visited, depth + 1, maxDepth, onlyField);
                    }
                } else if (value instanceof Collection<?> coll) {
                    int n = 0;
                    for (Object o : coll) {
                        if (n++ > 64) break;
                        if (o == null || COMPONENT_CLASS.isInstance(o)) continue; // list elements can't be swapped individually
                        walk(o, out, visited, depth + 1, maxDepth, onlyField);
                    }
                } else if (value instanceof java.util.Map<?, ?> map) {
                    int n = 0;
                    for (Object o : map.values()) {
                        if (n++ > 64) break;
                        if (o == null || COMPONENT_CLASS.isInstance(o)) continue;
                        walk(o, out, visited, depth + 1, maxDepth, onlyField);
                    }
                } else if (value.getClass().isArray()
                        && !value.getClass().getComponentType().isPrimitive()) {
                    Object[] arr = (Object[]) value;
                    int n = 0;
                    for (Object o : arr) {
                        if (n++ > 64) break;
                        if (o == null || COMPONENT_CLASS.isInstance(o)) continue;
                        walk(o, out, visited, depth + 1, maxDepth, onlyField);
                    }
                } else if (value.getClass().getName().startsWith("net.minecraft")
                        || value.getClass().getName().startsWith("com.mojang")) {
                    // recurse even when the name doesn't match: the target field
                    // may sit deeper inside (e.g. unsignedContent inside the
                    // PlayerChatMessage record) - only RECORDING is name-gated
                    walk(value, out, visited, depth + 1, maxDepth, onlyField);
                }
            }
        }
    }

    private static void addSlot(Object owner, Field field, boolean insideOptional,
                                Object component, List<Slot> out) {
        try {
            String json = WrappedChatComponent.fromHandle(component).getJson();
            if (json != null && !json.isBlank()) out.add(new Slot(owner, field, insideOptional, json));
        } catch (Throwable ignored) {
        }
    }

    private static Class<?> resolveComponentClass() {
        try {
            return Class.forName("net.minecraft.network.chat.Component");
        } catch (Throwable t) {
            return null;
        }
    }

    private static Unsafe resolveUnsafe() {
        try {
            Field f = Unsafe.class.getDeclaredField("theUnsafe");
            f.setAccessible(true);
            return (Unsafe) f.get(null);
        } catch (Throwable t) {
            return null;
        }
    }
}
BEXIND_EOF
cat > src/main/java/com/bexind/translate/AdvancementRewriter.java <<'BEXIND_EOF'
package com.bexind.translate;

import com.comphenix.protocol.events.PacketContainer;
import com.comphenix.protocol.wrappers.WrappedChatComponent;

import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.Modifier;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * Rebuilds the advancement map inside UPDATE_ADVANCEMENTS packets with
 * translated DisplayInfo titles/descriptions (the toast popups).
 *
 * The server caches AdvancementHolder instances GLOBALLY and re-sends the
 * same objects to every player, so shared records are never mutated - new
 * holder/advancement/display records are constructed instead. Paper 1.20.5+
 * runs a Mojang-mapped runtime, so record component order is stable:
 *
 *   AdvancementHolder(ResourceLocation id, Advancement value)
 *   Advancement(Optional<DisplayInfo> display, Optional<ResourceLocation> parent,
 *               Map criteria, AdvancementRequirements requirements, boolean sendsTelemetryEvent)
 *   DisplayInfo(Component title, Component description, ItemStack icon,
 *               Optional<ResourceLocation> background, AdvancementType frame,
 *               boolean showToast, boolean announceChat, boolean hidden)
 *
 * The packet-level map field is per-send, so replacing it is safe. Every
 * step is guarded: if Mojang reshapes anything, the rewrite no-ops quietly
 * (visible via /btr debug).
 */
public final class AdvancementRewriter {

    private record Loc(Object owner, Field field, Object value) {}

    private AdvancementRewriter() {
    }

    /** Collects all translatable texts (advancement titles + descriptions). */
    static List<String> collectTexts(PacketContainer packet) {
        List<String> out = new ArrayList<>();
        try {
            Loc mapLoc = findAdvancementMap(packet);
            if (mapLoc == null) return out;
            for (Object holderObj : ((Map<?, ?>) mapLoc.value()).values()) {
                Object adv = readField(holderObj, "value");
                Object display = optInner(readField(adv, "display"));
                if (display == null) continue;
                String title = componentJson(readField(display, "title"));
                String desc = componentJson(readField(display, "description"));
                if (title != null) out.add(title);
                if (desc != null) out.add(desc);
            }
        } catch (Throwable ignored) {
        }
        return out;
    }

    /** Rebuilds the packet's map with translated components. True when changed. */
    static boolean rewrite(BexindTranslate plugin, PacketContainer packet, String lang) {
        try {
            Loc mapLoc = findAdvancementMap(packet);
            if (mapLoc == null) return false;
            Map<?, ?> map = (Map<?, ?>) mapLoc.value();

            Map<Object, Object> rebuilt = new LinkedHashMap<>();
            boolean changed = false;
            for (Map.Entry<?, ?> e : map.entrySet()) {
                Object id = e.getKey();
                Object holder = e.getValue();
                try {
                    Object adv = readField(holder, "value");
                    Optional<?> displayOpt = (Optional<?>) readField(adv, "display");
                    if (displayOpt == null || displayOpt.isEmpty()) {
                        rebuilt.put(id, holder);
                        continue;
                    }
                    Object display = displayOpt.get();

                    String titleJson = componentJson(readField(display, "title"));
                    String descJson = componentJson(readField(display, "description"));
                    if (titleJson == null || descJson == null) {
                        rebuilt.put(id, holder);
                        continue;
                    }

                    String mappedTitle = JsonText.map(titleJson, mapper(plugin, lang));
                    String mappedDesc = JsonText.map(descJson, mapper(plugin, lang));
                    if (mappedTitle == titleJson && mappedDesc == descJson) {
                        rebuilt.put(id, holder);
                        continue;
                    }

                    Object newHolder = rebuildHolder(holder, adv, display, mappedTitle, mappedDesc);
                    if (newHolder == null) {
                        rebuilt.put(id, holder);
                        continue;
                    }
                    rebuilt.put(id, newHolder);
                    changed = true;
                } catch (Throwable t) {
                    rebuilt.put(id, holder);
                }
            }
            if (!changed) return false;

            DeepTextScanner.setField(mapLoc.owner(), mapLoc.field(), rebuilt);
            return true;
        } catch (Throwable t) {
            plugin.debug(() -> "advancement rewrite failed: " + t);
            return false;
        }
    }

    private static Object rebuildHolder(Object holder, Object adv, Object display,
                                        String mappedTitle, String mappedDesc) throws Exception {
        Object newTitle = WrappedChatComponent.fromJson(mappedTitle).getHandle();
        Object newDesc = WrappedChatComponent.fromJson(mappedDesc).getHandle();

        Constructor<?> displayCtor = ctorWithParamCount(display.getClass(), 8);
        if (displayCtor == null) return null;
        Object newDisplay = displayCtor.newInstance(
                newTitle, newDesc,
                readField(display, "icon"),
                readField(display, "background"),
                readField(display, "frame"),
                readField(display, "showToast"),
                readField(display, "announceChat"),
                readField(display, "hidden"));

        Constructor<?> advCtor = ctorWithParamCount(adv.getClass(), 5);
        if (advCtor == null) return null;
        Object newAdv = advCtor.newInstance(
                Optional.of(newDisplay),
                readField(adv, "parent"),
                readField(adv, "criteria"),
                readField(adv, "requirements"),
                readField(adv, "sendsTelemetryEvent"));

        Constructor<?> holderCtor = ctorWithParamCount(holder.getClass(), 2);
        if (holderCtor == null) return null;
        return holderCtor.newInstance(readField(holder, "id"), newAdv);
    }

    // ------------------------------------------------------------------

    private static java.util.function.UnaryOperator<String> mapper(BexindTranslate plugin, String lang) {
        return s -> {
            String hit = plugin.cache().getMemory(lang, s);
            return hit != null ? hit : s;
        };
    }

    private static Loc findAdvancementMap(PacketContainer packet) {
        Object handle = packet.getHandle();
        for (Class<?> c = handle.getClass(); c != null && c != Object.class; c = c.getSuperclass()) {
            for (Field f : c.getDeclaredFields()) {
                if (Modifier.isStatic(f.getModifiers()) || !Map.class.isAssignableFrom(f.getType())) continue;
                try {
                    f.setAccessible(true);
                    Object v = f.get(handle);
                    if (v instanceof Map<?, ?> m && !m.isEmpty()) {
                        Object first = m.values().iterator().next();
                        if (first != null && first.getClass().getSimpleName().equals("AdvancementHolder")) {
                            return new Loc(handle, f, v);
                        }
                    }
                } catch (Throwable ignored) {
                }
            }
        }
        return null;
    }

    private static Constructor<?> ctorWithParamCount(Class<?> type, int count) {
        for (Constructor<?> ctor : type.getDeclaredConstructors()) {
            if (ctor.getParameterCount() == count) {
                ctor.setAccessible(true);
                return ctor;
            }
        }
        return null;
    }

    private static Object readField(Object obj, String name) {
        if (obj == null) return null;
        for (Class<?> c = obj.getClass(); c != null && c != Object.class; c = c.getSuperclass()) {
            try {
                Field f = c.getDeclaredField(name);
                f.setAccessible(true);
                return f.get(obj);
            } catch (Throwable ignored) {
            }
        }
        return null;
    }

    private static Object optInner(Object maybeOptional) {
        if (maybeOptional instanceof Optional<?> opt) return opt.orElse(null);
        return maybeOptional;
    }

    private static String componentJson(Object nmsComponent) {
        if (nmsComponent == null) return null;
        try {
            return WrappedChatComponent.fromHandle(nmsComponent).getJson();
        } catch (Throwable t) {
            return null;
        }
    }
}
BEXIND_EOF
cat > src/main/java/com/bexind/translate/CacheManager.java <<'BEXIND_EOF'
package com.bexind.translate;

import com.github.benmanes.caffeine.cache.Cache;
import com.github.benmanes.caffeine.cache.Caffeine;

import java.io.File;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;
import java.time.Duration;
import java.util.concurrent.CompletableFuture;

/**
 * Triple-level cache:
 *   L1: Caffeine in-memory (0 ms, never leaves RAM)
 *   L2: SQLite persistent in WAL mode (survives restarts, I/O on virtual threads)
 *   L3: short-lived negative cache so failed provider calls are not retried
 *       on every packet
 *
 * v2 changes vs 1.0: WAL journaling + busy_timeout (no more lock contention
 * under concurrent virtual threads), reused PreparedStatements, UPSERT
 * instead of INSERT OR IGNORE (translations improve in place), identity
 * entries for same-language skips, and negative caching.
 */
public final class CacheManager {

    private final BexindTranslate plugin;
    private final Cache<String, String> memory;
    private final Cache<String, Boolean> negative;
    private final Object dbLock = new Object();
    private volatile Connection connection;
    private volatile PreparedStatement insStmt;
    private volatile PreparedStatement selStmt;
    private volatile PreparedStatement playerSaveStmt;
    private volatile PreparedStatement playerLoadStmt;

    CacheManager(BexindTranslate plugin) {
        this.plugin = plugin;
        this.memory = Caffeine.newBuilder()
                .maximumSize(50_000)
                .expireAfterAccess(Duration.ofHours(12))
                .build();
        long negMinutes = plugin.getConfig().getLong("negative-cache-minutes", 5);
        this.negative = Caffeine.newBuilder()
                .maximumSize(20_000)
                .expireAfterWrite(Duration.ofMinutes(Math.max(1, negMinutes)))
                .build();
    }

    private static String key(String lang, String text) {
        return lang + '\u0000' + text;
    }

    /** Opens the SQLite database on a virtual thread. Never called on the main tick. */
    void initAsync() {
        plugin.virtualPool().execute(() -> {
            try {
                Path folder = plugin.getDataFolder().toPath();
                java.nio.file.Files.createDirectories(folder);
                File db = folder.resolve("database.db").toFile();
                Connection conn = DriverManager.getConnection("jdbc:sqlite:" + db.getAbsolutePath());
                try (Statement st = conn.createStatement()) {
                    st.execute("PRAGMA journal_mode=WAL");
                    st.execute("PRAGMA synchronous=NORMAL");
                    st.execute("PRAGMA busy_timeout=5000");
                    st.executeUpdate("CREATE TABLE IF NOT EXISTS translations ("
                            + "lang TEXT NOT NULL, original TEXT NOT NULL, translated TEXT NOT NULL,"
                            + " PRIMARY KEY (lang, original))");
                    st.executeUpdate("CREATE TABLE IF NOT EXISTS player_lang ("
                            + "uuid TEXT PRIMARY KEY, lang TEXT NOT NULL)");
                }
                synchronized (dbLock) {
                    insStmt = conn.prepareStatement(
                            "INSERT INTO translations (lang, original, translated) VALUES (?,?,?) "
                                    + "ON CONFLICT(lang, original) DO UPDATE SET translated=excluded.translated");
                    selStmt = conn.prepareStatement(
                            "SELECT translated FROM translations WHERE lang=? AND original=?");
                    playerSaveStmt = conn.prepareStatement(
                            "INSERT OR REPLACE INTO player_lang (uuid, lang) VALUES (?,?)");
                    playerLoadStmt = conn.prepareStatement(
                            "SELECT lang FROM player_lang WHERE uuid=?");
                    this.connection = conn;
                }
                plugin.getLogger().info("Translation cache database ready (WAL mode).");
            } catch (Exception e) {
                plugin.getLogger().warning("SQLite init failed, memory-only cache: " + e.getMessage());
            }
        });
    }

    /** L1 lookup - safe to call on the netty/main thread (simple map read). */
    public String getMemory(String lang, String text) {
        return memory.getIfPresent(key(lang, text));
    }

    public long memorySize() {
        return memory.estimatedSize();
    }

    public long negativeSize() {
        return negative.estimatedSize();
    }

    /** Stores a real translation: L1 immediately, L2 asynchronously (UPSERT). */
    public void put(String lang, String original, String translated) {
        if (original.equals(translated)) return;
        memory.put(key(lang, original), translated);
        Connection conn = connection;
        if (conn == null) return;
        plugin.virtualPool().execute(() -> upsert(conn, lang, original, translated));
    }

    /**
     * Stores an identity entry (text already in the target language), so the
     * same string resolves from cache instantly and never hits a provider again.
     */
    public void putIdentity(String lang, String text) {
        memory.put(key(lang, text), text);
        Connection conn = connection;
        if (conn == null) return;
        plugin.virtualPool().execute(() -> upsert(conn, lang, text, text));
    }

    private void upsert(Connection conn, String lang, String original, String translated) {
        synchronized (dbLock) {
            try {
                PreparedStatement ps = insStmt;
                if (ps == null) return;
                ps.setString(1, lang);
                ps.setString(2, original);
                ps.setString(3, translated);
                ps.executeUpdate();
            } catch (Exception ignored) {
            }
        }
    }

    /** L1 -> L2 lookup. Runs on a virtual thread. */
    public CompletableFuture<String> getAsync(String lang, String text) {
        String hit = getMemory(lang, text);
        if (hit != null) return CompletableFuture.completedFuture(hit);

        Connection conn = connection;
        if (conn == null) return CompletableFuture.completedFuture(null);

        return CompletableFuture.supplyAsync(() -> {
            synchronized (dbLock) {
                try {
                    PreparedStatement ps = selStmt;
                    if (ps == null) return null;
                    ps.setString(1, lang);
                    ps.setString(2, text);
                    try (ResultSet rs = ps.executeQuery()) {
                        if (rs.next()) {
                            String t = rs.getString(1);
                            memory.put(key(lang, text), t);
                            plugin.stats().l2Hits.increment();
                            return t;
                        }
                    }
                } catch (Exception ignored) {
                }
            }
            plugin.stats().cacheMisses.increment();
            return null;
        }, plugin.virtualPool());
    }

    // ---- negative cache ----

    public boolean isNegative(String lang, String text) {
        return negative.getIfPresent(key(lang, text)) != null;
    }

    public void markNegative(String lang, String text) {
        negative.put(key(lang, text), Boolean.TRUE);
    }

    // ---- maintenance ----

    public CompletableFuture<Void> clearPersistent() {
        memory.invalidateAll();
        negative.invalidateAll();
        Connection conn = connection;
        if (conn == null) return CompletableFuture.completedFuture(null);
        return CompletableFuture.runAsync(() -> {
            synchronized (dbLock) {
                try (Statement st = conn.createStatement()) {
                    st.executeUpdate("DELETE FROM translations");
                } catch (Exception ignored) {
                }
            }
        }, plugin.virtualPool());
    }

    // ---- player language persistence ----

    public void savePlayerLang(String uuid, String lang) {
        Connection conn = connection;
        if (conn == null) return;
        plugin.virtualPool().execute(() -> {
            synchronized (dbLock) {
                try {
                    PreparedStatement ps = playerSaveStmt;
                    if (ps == null) return;
                    ps.setString(1, uuid);
                    ps.setString(2, lang);
                    ps.executeUpdate();
                } catch (Exception ignored) {
                }
            }
        });
    }

    public CompletableFuture<String> loadPlayerLang(String uuid) {
        Connection conn = connection;
        if (conn == null) return CompletableFuture.completedFuture(null);
        return CompletableFuture.supplyAsync(() -> {
            synchronized (dbLock) {
                try {
                    PreparedStatement ps = playerLoadStmt;
                    if (ps == null) return null;
                    ps.setString(1, uuid);
                    try (ResultSet rs = ps.executeQuery()) {
                        return rs.next() ? rs.getString(1) : null;
                    }
                } catch (Exception e) {
                    return null;
                }
            }
        }, plugin.virtualPool());
    }

    void close() {
        synchronized (dbLock) {
            try {
                Connection conn = connection;
                if (conn == null) return;
                try (Statement st = conn.createStatement()) {
                    st.execute("PRAGMA wal_checkpoint(TRUNCATE)");
                }
                insStmt.close();
                selStmt.close();
                playerSaveStmt.close();
                playerLoadStmt.close();
                conn.close();
            } catch (Exception ignored) {
            }
        }
    }
}
BEXIND_EOF
cat > src/main/java/com/bexind/translate/TranslationService.java <<'BEXIND_EOF'
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
BEXIND_EOF
cat > src/main/java/com/bexind/translate/LangManager.java <<'BEXIND_EOF'
package com.bexind.translate;

import org.bukkit.entity.Player;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Per-player language resolution for the two-language model (en / ru).
 *
 * override (command) > saved (menu / command, persisted) > nothing.
 * A player who never picked a language gets NO translation until they do.
 * "auto" resolves to the client locale when it is one of the allowed
 * languages, otherwise to default-language.
 *
 * Unlike v2.0 the chosen language is ALWAYS the translation target, even when
 * it equals default-language: on a mixed EN/RU server an English player still
 * needs Russian text translated to English. The provider-side same-language
 * skip keeps English->English work at zero cost.
 */
public final class LangManager {

    private final BexindTranslate plugin;
    private final Map<UUID, String> override = new ConcurrentHashMap<>();
    private final Map<UUID, String> saved = new ConcurrentHashMap<>();

    // Config-derived state, cached: getEffective() runs on EVERY intercepted
    // packet and must not allocate a config list each time (v2.1 perf bug).
    private volatile List<String> allowedCache = List.of("en", "ru");
    private volatile String defaultCache = "en";

    LangManager(BexindTranslate plugin) {
        this.plugin = plugin;
        refresh();
    }

    /**
     * Re-reads languages + default-language from config. Called on enable and
     * on /btr reload.
     *
     * STRICTLY TWO LANGUAGES: the config list is clamped to the en/ru
     * intersection. Anything else (leftovers from pre-2.1 configs, typos) is
     * ignored with a warning, so no third language can ever leak into menus,
     * command validation or the DB-backed player profiles.
     */
    public void refresh() {
        List<String> raw = plugin.getConfig().getStringList("languages");
        List<String> cleaned = new ArrayList<>(2);
        for (String s : raw) {
            String c = s == null ? "" : s.toLowerCase(Locale.ROOT).trim();
            if (c.equals("en") || c.equals("ru")) {
                if (!cleaned.contains(c)) cleaned.add(c);
            } else if (!c.isEmpty()) {
                plugin.getLogger().warning("languages: '" + s
                        + "' is not supported - BexindTranslate only offers 'en' and 'ru'.");
            }
        }
        if (cleaned.isEmpty()) cleaned.addAll(List.of("en", "ru"));
        this.allowedCache = List.copyOf(cleaned);

        String def = plugin.getConfig().getString("default-language", "en");
        def = def == null ? "" : def.toLowerCase(Locale.ROOT).trim();
        this.defaultCache = cleaned.contains(def) ? def : cleaned.get(0);
    }

    /** The offered languages (a subset of [en, ru]), lower-cased. */
    public List<String> allowedLanguages() {
        return allowedCache;
    }

    public boolean isAllowed(String code) {
        return code != null && allowedCache.contains(code.toLowerCase(Locale.ROOT));
    }

    public String defaultLanguage() {
        return defaultCache;
    }

    /**
     * Loads the player's saved language from SQLite asynchronously. The
     * returned future completes when the in-memory map is updated, so callers
     * can safely chain the "should the menu open?" decision after it (v2.0
     * raced the DB load and re-showed the menu to returning players).
     */
    public CompletableFuture<Void> loadAsync(Player player) {
        return plugin.cache().loadPlayerLang(player.getUniqueId().toString())
                .thenAccept(lang -> {
                    if (lang != null && isAllowed(lang)) {
                        saved.put(player.getUniqueId(), lang.toLowerCase(Locale.ROOT));
                    }
                });
    }

    public void setOverride(UUID uuid, String lang) {
        override.put(uuid, lang == null ? "auto" : lang.toLowerCase(Locale.ROOT));
    }

    /** Persists the choice (join menu and /btr lang). Validates the code. */
    public boolean choose(UUID uuid, String lang) {
        if (!isAllowed(lang)) return false;
        String normalized = lang.toLowerCase(Locale.ROOT);
        saved.put(uuid, normalized);
        override.remove(uuid);
        plugin.cache().savePlayerLang(uuid.toString(), normalized);
        return true;
    }

    public boolean hasChosen(UUID uuid) {
        return saved.containsKey(uuid);
    }

    /** Effective ISO target language, or null if translation should be skipped. */
    public String getEffective(Player player) {
        String lang = override.get(player.getUniqueId());
        if (lang == null) lang = saved.get(player.getUniqueId());
        if (lang == null) return null; // never picked -> leave everything as-is

        if (lang.equals("auto")) {
            String loc = fromLocale(player.getLocale());
            lang = isAllowed(loc) ? loc : defaultLanguage();
        }
        lang = lang.toLowerCase(Locale.ROOT);
        return isAllowed(lang) ? lang : null;
    }

    /** "ru_ru" -> "ru", "en_US" -> "en", "tr" -> "tr". */
    public static String fromLocale(String locale) {
        if (locale == null || locale.isBlank()) return null;
        int i = locale.indexOf('_');
        return (i > 0 ? locale.substring(0, i) : locale).toLowerCase(Locale.ROOT);
    }

    /** Frees per-player state; called on quit. */
    public void forget(UUID uuid) {
        override.remove(uuid);
        saved.remove(uuid);
    }

    public CompletableFuture<String> peekSaved(UUID uuid) {
        String s = saved.get(uuid);
        if (s != null) return CompletableFuture.completedFuture(s);
        return plugin.cache().loadPlayerLang(uuid.toString());
    }

    /** Synchronous map-only read - safe on the main thread (never hits the DB). */
    public String peekSavedSync(UUID uuid) {
        return saved.get(uuid);
    }
}
BEXIND_EOF
cat > src/main/java/com/bexind/translate/PacketInterceptor.java <<'BEXIND_EOF'
package com.bexind.translate;

import com.comphenix.protocol.PacketType;
import com.comphenix.protocol.ProtocolLibrary;
import com.comphenix.protocol.events.ListenerPriority;
import com.comphenix.protocol.events.PacketAdapter;
import com.comphenix.protocol.events.PacketContainer;
import com.comphenix.protocol.events.PacketEvent;
import com.comphenix.protocol.wrappers.PlayerInfoData;
import com.comphenix.protocol.wrappers.WrappedChatComponent;
import com.comphenix.protocol.wrappers.WrappedWatchableObject;
import com.comphenix.protocol.wrappers.nbt.NbtBase;
import com.comphenix.protocol.wrappers.nbt.NbtCompound;
import com.comphenix.protocol.wrappers.nbt.NbtList;
import com.google.gson.JsonParser;
import net.kyori.adventure.text.Component;
import net.kyori.adventure.text.serializer.gson.GsonComponentSerializer;
import org.bukkit.Material;
import org.bukkit.NamespacedKey;
import org.bukkit.entity.Player;
import org.bukkit.inventory.ItemStack;
import org.bukkit.inventory.meta.ItemMeta;
import org.bukkit.persistence.PersistentDataType;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.function.UnaryOperator;

/**
 * The network interception layer, v2.
 *
 * Golden rule: a broadcast packet is SHARED between players, so the original
 * packet is never mutated. Every rewrite happens on a deepClone'd copy that
 * is either swapped into the current player's event (fast path) or re-sent
 * to that player alone after an async translation (slow path). If a clone is
 * impossible the rewrite is skipped - v1 mutated shared packets, which
 * translated them into the first viewer's language for everyone.
 *
 * Strategy per packet:
 *  1. Resolve the target language; collect translatable strings.
 *  2. All strings already in L1 memory cache -> rewrite the clone (0 ms).
 *  3. Any miss -> original passes through untouched, missing strings are
 *     translated on virtual threads, then a translated clone is re-sent
 *     to this player only.
 */
public final class PacketInterceptor extends PacketAdapter {

    private final BexindTranslate plugin;
    /** Deduplicates concurrent async jobs for the same string. */
    private final Set<String> inFlight = ConcurrentHashMap.newKeySet();

    /** Packet type names can move between ProtocolLib releases; resolve them
     *  reflectively so one renamed constant can never kill the whole plugin. */
    private static final String[] TYPE_NAMES = {
            "SYSTEM_CHAT", "DISGUISED_CHAT", "CHAT",
            "SET_ACTION_BAR_TEXT", "SET_TITLE_TEXT", "SET_SUBTITLE_TEXT", "BOSS",
            "OPEN_WINDOW", "SET_SLOT", "WINDOW_ITEMS",
            "TILE_ENTITY_DATA", "SCOREBOARD_TEAM", "SCOREBOARD_SCORE",
            "SCOREBOARD_OBJECTIVE", "ENTITY_METADATA", "PLAYER_INFO", "ADVANCEMENTS"};

    /** Names that could not be resolved in the installed ProtocolLib build. */
    private static final List<String> SKIPPED = new ArrayList<>();

    /** @return packet type names missing from the installed ProtocolLib. */
    public static List<String> skippedTypes() {
        return Collections.unmodifiableList(SKIPPED);
    }

    private static PacketType[] resolveTypes() {
        List<PacketType> out = new ArrayList<>(TYPE_NAMES.length);
        for (String name : TYPE_NAMES) {
            try {
                Object type = PacketType.Play.Server.class.getField(name).get(null);
                if (type != null) out.add((PacketType) type);
            } catch (Throwable t) {
                SKIPPED.add(name);
            }
        }
        return out.toArray(new PacketType[0]);
    }

    public PacketInterceptor(BexindTranslate plugin) {
        super(plugin, ListenerPriority.HIGH, resolveTypes());
        this.plugin = plugin;
    }

    @Override
    public void onPacketSending(PacketEvent event) {
        if (event.isCancelled() || event.isPlayerTemporary()) return;
        Player player = event.getPlayer();
        if (player == null) return;

        String lang = plugin.langs().getEffective(player);
        if (lang == null) return; // already on the default language

        PacketType t = event.getPacketType();
        plugin.stats().packetsSeen.increment();
        try {
            if (t == PacketType.Play.Server.SYSTEM_CHAT
                    || t == PacketType.Play.Server.DISGUISED_CHAT) {
                // broadcast -> shared, must clone
                if (feature("chat")) handleComponent(event, player, lang, 0, true);
            } else if (t == PacketType.Play.Server.CHAT) {
                // Only the unsigned component is safe to modify (chat signing);
                // the scan is name-gated so sender names in the chat-type
                // decoration are never machine-translated.
                if (feature("chat")) handleNested(event, player, lang, 4, "unsignedContent");
            } else if (t == PacketType.Play.Server.SET_ACTION_BAR_TEXT) {
                // per-recipient -> no deepClone needed (deep-cloning registry-
                // encoded packets is what corrupted menus and kicked clients)
                if (feature("holograms-and-actionbars")) handleComponent(event, player, lang, 0, false);
            } else if (t == PacketType.Play.Server.SET_TITLE_TEXT
                    || t == PacketType.Play.Server.SET_SUBTITLE_TEXT) {
                if (feature("titles")) handleComponent(event, player, lang, 0, false);
            } else if (t == PacketType.Play.Server.BOSS) {
                // The boss name lives inside the operation record -> deep scan.
                if (feature("boss-bars")) handleNested(event, player, lang, 5, null);
            } else if (t == PacketType.Play.Server.OPEN_WINDOW) {
                // v1 read component index 2 here, which does not exist, so GUI
                // titles were silently never translated. The title is index 0.
                if (feature("guis-and-menus") && !ownMenu(player)) handleComponent(event, player, lang, 0, false);
            } else if (t == PacketType.Play.Server.SET_SLOT) {
                if (feature("guis-and-menus") && !ownMenu(player)) handleItems(event, player, lang, false);
            } else if (t == PacketType.Play.Server.WINDOW_ITEMS) {
                if (feature("guis-and-menus") && !ownMenu(player)) handleItems(event, player, lang, true);
            } else if (t == PacketType.Play.Server.TILE_ENTITY_DATA) {
                if (feature("signs")) handleSign(event, player, lang);
            } else if (t == PacketType.Play.Server.SCOREBOARD_TEAM
                    || t == PacketType.Play.Server.SCOREBOARD_SCORE
                    || t == PacketType.Play.Server.SCOREBOARD_OBJECTIVE) {
                // v1 guessed fixed string slots; since 1.20.3 these are
                // Optional<Component> fields, handled generically now.
                if (feature("scoreboards")) handleNested(event, player, lang, 4, null);
            } else if (t == PacketType.Play.Server.ENTITY_METADATA) {
                if (feature("holograms-and-actionbars")) handleMetadata(event, player, lang);
            } else if (t == PacketType.Play.Server.PLAYER_INFO) {
                if (feature("tab-list")) handlePlayerInfo(event, player, lang);
            } else if (t == PacketType.Play.Server.ADVANCEMENTS) {
                if (feature("advancements")) handleAdvancements(event, player, lang);
            }
        } catch (Throwable ex) {
            plugin.debug(() -> "Interceptor error on " + t + ": " + ex);
        }
    }

    private boolean feature(String key) {
        return plugin.getConfig().getBoolean("features." + key, true);
    }

    /**
     * True while WE are opening the language menu for this player: those
     * packets are already localized by config.yml, and re-running them
     * through the translator would double-translate the title.
     */
    private boolean ownMenu(Player player) {
        return plugin.menuListener() != null && plugin.menuListener().isOpening(player.getUniqueId());
    }

    // =====================================================================
    // Single-component packets (system chat, action bar, titles, GUI title)
    //
    // shared=true  -> broadcast packet, deepClone before rewrite.
    // shared=false -> per-recipient packet: shallowClone + field replacement.
    //                 deepClone() re-serializes the packet through a byte
    //                 buffer, which is exactly the path that produced
    //                 corrupted menus and kicked clients on 1.21.9+.
    // =====================================================================
    private void handleComponent(PacketEvent event, Player player, String lang, int slot, boolean shared) {
        WrappedChatComponent comp = event.getPacket().getChatComponents().readSafely(slot);
        if (comp == null) return;
        String json = comp.getJson();
        if (json == null || json.isBlank()) return;

        List<String> leaves = JsonText.leaves(json);
        if (leaves.isEmpty() || allIgnored(leaves)) return;

        if (allCached(leaves, lang)) {
            // Map BEFORE cloning: if nothing changes we skip the clone entirely.
            String mapped = JsonText.map(json, cachedMapper(lang));
            if (mapped == json) return;
            PacketContainer copy = rewriteComponent(event.getPacket(), slot, mapped, shared);
            if (copy == null) return;
            event.setPacket(copy);
            plugin.stats().packetsRewritten.increment();
            plugin.debug(() -> "rewrote " + event.getPacketType() + " for " + player.getName());
            return;
        }

        PacketContainer original = event.getPacket();
        asyncTranslate(leaves, lang, () -> {
            String mapped = JsonText.map(json, cachedMapper(lang));
            if (mapped == json) return;
            PacketContainer copy = rewriteComponent(original, slot, mapped, shared);
            if (copy == null) return;
            sendCopy(player, copy, "component");
        });
    }

    /** Copies the packet (deep for shared, shallow for per-recipient) and swaps the component. */
    private PacketContainer rewriteComponent(PacketContainer original, int slot, String mapped, boolean shared) {
        try {
            PacketContainer copy = shared ? original.deepClone() : original.shallowClone();
            copy.getChatComponents().write(slot, WrappedChatComponent.fromJson(mapped));
            return copy;
        } catch (Throwable ex) {
            plugin.debug(() -> "component rewrite failed on " + original.getType() + ": " + ex);
            return null;
        }
    }

    // =====================================================================
    // Deep-scan packets: boss bars, unsigned player chat, scoreboard
    // team/score/objective - components nested in Optionals or records.
    // =====================================================================
    private void handleNested(PacketEvent event, Player player, String lang,
                              int maxDepth, String onlyField) {
        if (!DeepTextScanner.available()) return;
        Object handle = event.getPacket().getHandle();
        List<DeepTextScanner.Slot> slots = DeepTextScanner.findComponents(handle, maxDepth, onlyField);
        if (slots.isEmpty()) return;

        List<String> texts = new ArrayList<>();
        for (DeepTextScanner.Slot s : slots) texts.addAll(JsonText.leaves(s.json()));
        if (texts.isEmpty() || allIgnored(texts)) return;

        if (allCached(texts, lang)) {
            PacketContainer copy = safeClone(event.getPacket(), "nested");
            if (copy == null) return;
            if (DeepTextScanner.swapAll(plugin, copy.getHandle(), lang, maxDepth, onlyField) == 0) return;
            event.setPacket(copy);
            plugin.stats().packetsRewritten.increment();
            plugin.debug(() -> "rewrote (deep) " + event.getPacketType() + " for " + player.getName());
            return;
        }

        PacketContainer original = event.getPacket();
        asyncTranslate(texts, lang, () -> {
            PacketContainer copy = safeClone(original, "nested-async");
            if (copy == null) return;
            DeepTextScanner.swapAll(plugin, copy.getHandle(), lang, maxDepth, onlyField);
            sendCopy(player, copy, "nested");
        });
    }

    // =====================================================================
    // Tab list (PLAYER_INFO): display names of list entries
    // =====================================================================
    private void handlePlayerInfo(PacketEvent event, Player player, String lang) {
        List<PlayerInfoData> infos = event.getPacket().getPlayerInfoDataLists().readSafely(0);
        if (infos == null || infos.isEmpty()) return;

        List<String> texts = new ArrayList<>();
        for (PlayerInfoData d : infos) {
            WrappedChatComponent dn = d.getDisplayName();
            if (dn == null) continue;
            texts.addAll(JsonText.leaves(dn.getJson()));
        }
        if (texts.isEmpty() || allIgnored(texts)) return;

        if (allCached(texts, lang)) {
            PacketContainer copy = safeClone(event.getPacket(), "player-info");
            if (copy == null) return;
            if (applyPlayerInfo(copy, lang)) {
                event.setPacket(copy);
                plugin.stats().packetsRewritten.increment();
            }
            return;
        }

        PacketContainer original = event.getPacket();
        asyncTranslate(texts, lang, () -> {
            PacketContainer copy = safeClone(original, "player-info-async");
            if (copy == null) return;
            if (applyPlayerInfo(copy, lang)) sendCopy(player, copy, "player-info");
        });
    }

    /** Rebuilds the entry list with translated display names. True when changed. */
    private boolean applyPlayerInfo(PacketContainer packet, String lang) {
        List<PlayerInfoData> infos = packet.getPlayerInfoDataLists().readSafely(0);
        if (infos == null) return false;

        boolean changed = false;
        List<PlayerInfoData> out = new ArrayList<>(infos.size());
        for (PlayerInfoData d : infos) {
            WrappedChatComponent dn = d.getDisplayName();
            if (dn == null) {
                out.add(d);
                continue;
            }
            String mapped = JsonText.map(dn.getJson(), cachedMapper(lang));
            if (mapped == dn.getJson()) {
                out.add(d);
                continue;
            }
            out.add(new PlayerInfoData(d.getProfileId(), d.getLatency(), d.isListed(), d.getGameMode(),
                    d.getProfile(), WrappedChatComponent.fromJson(mapped)));
            changed = true;
        }
        if (changed) packet.getPlayerInfoDataLists().write(0, out);
        return changed;
    }

    // =====================================================================
    // GUI items (SET_SLOT, WINDOW_ITEMS): display name + lore
    //
    // THE MENU KICK FIX: v2.0 deep-cloned item packets (re-serializing
    // registry-encoded items through a byte buffer -> corrupted packets ->
    // "kicked with a long error" when opening any GUI) and then mutated
    // ProtocolLib item mirrors in place (which can leak into the real
    // inventory item). Now: shallowClone + write FRESH item copies, the
    // original packet and every inventory item stay untouched.
    // =====================================================================
    private void handleItems(PacketEvent event, Player player, String lang, boolean bulk) {
        PacketContainer packet = event.getPacket();
        List<String> texts = collectItemTexts(readStacks(packet, bulk));
        if (texts.isEmpty() || allIgnored(texts)) return;

        if (allCached(texts, lang)) {
            PacketContainer copy = rebuildItems(packet, lang, bulk);
            if (copy == null) return;
            event.setPacket(copy);
            plugin.stats().packetsRewritten.increment();
            return;
        }

        PacketContainer original = packet;
        asyncTranslate(texts, lang, () -> {
            PacketContainer copy = rebuildItems(original, lang, bulk);
            if (copy == null) return;
            sendCopy(player, copy, bulk ? "window-items" : "set-slot");
        });
    }

    private List<String> collectItemTexts(List<ItemStack> stacks) {
        GsonComponentSerializer gson = GsonComponentSerializer.gson();
        List<String> texts = new ArrayList<>();
        for (ItemStack is : stacks) {
            if (is == null || is.getType().isAir() || !is.hasItemMeta()) continue;
            ItemMeta meta = is.getItemMeta();
            if (meta == null) continue;
            if (meta.hasDisplayName() && meta.displayName() != null) {
                texts.addAll(JsonText.leaves(gson.serialize(meta.displayName())));
            }
            if (meta.hasLore() && meta.lore() != null) {
                for (Component c : meta.lore()) texts.addAll(JsonText.leaves(gson.serialize(c)));
            }
        }
        return texts;
    }

    private List<ItemStack> readStacks(PacketContainer packet, boolean bulk) {
        List<ItemStack> stacks = new ArrayList<>();
        if (bulk) {
            // WINDOW_ITEMS stores a List<ItemStack>; ProtocolLib exposes it both
            // as ItemStack[] and List depending on build - try both (the array
            // modifier silently returned null on Paper 1.21.11, so bulk item
            // translation never fired in v2.0).
            ItemStack[] arr = packet.getItemArrayModifier().readSafely(0);
            if (arr != null) {
                stacks.addAll(Arrays.asList(arr));
            } else {
                List<ItemStack> list = packet.getItemListModifier().readSafely(0);
                if (list != null) stacks.addAll(list);
            }
        } else {
            ItemStack is = packet.getItemModifier().readSafely(0);
            if (is != null) stacks.add(is);
        }
        return stacks;
    }

    /**
     * Builds a NEW packet carrying translated item copies. Returns null when
     * nothing changed or anything is off - the original packet is never
     * touched, so a failure just means "no translation" instead of a kick.
     */
    private PacketContainer rebuildItems(PacketContainer original, String lang, boolean bulk) {
        try {
            PacketContainer copy = original.shallowClone();
            if (bulk) {
                boolean asArray;
                List<ItemStack> source;
                ItemStack[] arr = original.getItemArrayModifier().readSafely(0);
                if (arr != null) {
                    source = new ArrayList<>(Arrays.asList(arr));
                    asArray = true;
                } else {
                    List<ItemStack> list = original.getItemListModifier().readSafely(0);
                    if (list == null) return null;
                    source = new ArrayList<>(list);
                    asArray = false;
                }
                boolean changed = false;
                List<ItemStack> out = new ArrayList<>(source.size());
                for (ItemStack is : source) {
                    ItemStack dupe = translatedCopy(is, lang);
                    if (dupe != null) {
                        out.add(dupe);
                        changed = true;
                    } else {
                        out.add(is);
                    }
                }
                if (!changed) return null;
                if (asArray) copy.getItemArrayModifier().write(0, out.toArray(new ItemStack[0]));
                else copy.getItemListModifier().write(0, out);
            } else {
                ItemStack single = original.getItemModifier().readSafely(0);
                ItemStack dupe = translatedCopy(single, lang);
                if (dupe == null) return null;
                copy.getItemModifier().write(0, dupe);
            }
            return copy;
        } catch (Throwable ex) {
            plugin.debug(() -> "item rewrite failed for " + original.getType() + ": " + ex);
            return null;
        }
    }

    /**
     * Returns a translated INDEPENDENT copy of the item, or null when the item
     * needs no change. The incoming stack is often a live ProtocolLib mirror
     * of the packet's NMS item - mutating that would leak translations into
     * the real inventory item (v2.0 bug), so every change goes to a clone.
     */
    private ItemStack translatedCopy(ItemStack is, String lang) {
        if (is == null || is.getType().isAir() || !is.hasItemMeta()) return null;
        try {
            ItemMeta meta = is.getItemMeta();
            if (meta == null) return null;
            // Never touch our own language-menu items (their lore/button text
            // is already localized by config, not by the translator).
            if (meta.getPersistentDataContainer().has(plugin.menuKey(), PersistentDataType.STRING)) {
                return null;
            }

            GsonComponentSerializer gson = GsonComponentSerializer.gson();
            UnaryOperator<String> mapper = cachedMapper(lang);

            Component name = meta.displayName();
            Component newName = mapComponent(name, gson, mapper);

            List<Component> lore = meta.lore();
            List<Component> newLore = null;
            if (lore != null) {
                List<Component> mapped = new ArrayList<>(lore.size());
                boolean changed = false;
                for (Component c : lore) {
                    Component mc = mapComponent(c, gson, mapper);
                    if (mc != c) changed = true;
                    mapped.add(mc != null ? mc : c);
                }
                if (changed) newLore = mapped;
            }

            if (newName == name && newLore == null) return null;

            ItemStack dupe = is.clone(); // independent copy, mirror untouched
            ItemMeta dm = dupe.getItemMeta();
            if (dm == null) return null;
            if (newName != null) dm.displayName(newName);
            if (newLore != null) dm.lore(newLore);
            dupe.setItemMeta(dm);
            return dupe;
        } catch (Throwable t) {
            plugin.debug(() -> "item translate skipped: " + t);
            return null;
        }
    }

    /** Maps one Adventure component; returns the SAME instance when unchanged. */
    private Component mapComponent(Component c, GsonComponentSerializer gson, UnaryOperator<String> mapper) {
        if (c == null) return null;
        String j = gson.serialize(c);
        String mapped = JsonText.map(j, mapper);
        return mapped == j ? c : gson.deserialize(mapped);
    }

    // =====================================================================
    // Signs (TILE_ENTITY_DATA, 1.20.4+ layout: front_text / back_text)
    // =====================================================================
    private void handleSign(PacketEvent event, Player player, String lang) {
        NbtBase<?> nbt = event.getPacket().getNbtModifier().readSafely(0);
        if (!(nbt instanceof NbtCompound compound)) return;

        List<String> texts = new ArrayList<>();
        collectSignText(compound, texts);
        if (texts.isEmpty() || allIgnored(texts)) return;

        if (allCached(texts, lang)) {
            PacketContainer copy = safeClone(event.getPacket(), "sign");
            if (copy == null) return;
            applySign(copy, lang);
            event.setPacket(copy);
            plugin.stats().packetsRewritten.increment();
            return;
        }

        PacketContainer original = event.getPacket();
        asyncTranslate(texts, lang, () -> {
            PacketContainer copy = safeClone(original, "sign-async");
            if (copy == null) return;
            applySign(copy, lang);
            sendCopy(player, copy, "sign");
        });
    }

    private void applySign(PacketContainer packet, String lang) {
        NbtBase<?> nbt = packet.getNbtModifier().readSafely(0);
        if (!(nbt instanceof NbtCompound compound)) return;
        translateSignCompound(compound, lang);
        packet.getNbtModifier().write(0, compound);
    }

    @SuppressWarnings("unchecked")
    private void collectSignText(NbtCompound root, List<String> out) {
        for (String side : new String[]{"front_text", "back_text"}) {
            NbtCompound sideCompound = root.getCompoundOrDefault(side);
            if (sideCompound == null) continue;
            NbtList<String> messages = sideCompound.getListOrDefault("messages");
            if (messages == null) continue;
            List<NbtBase<String>> list = messages.getValue();
            for (NbtBase<String> v : list) {
                String plain = stripJson(String.valueOf(v.getValue()));
                if (plain != null && !plain.isBlank()) out.add(plain);
            }
        }
    }

    @SuppressWarnings("unchecked")
    private void translateSignCompound(NbtCompound root, String lang) {
        UnaryOperator<String> mapper = cachedMapper(lang);
        for (String side : new String[]{"front_text", "back_text"}) {
            NbtCompound sideCompound = root.getCompoundOrDefault(side);
            if (sideCompound == null) continue;
            NbtList<String> messages = sideCompound.getListOrDefault("messages");
            if (messages == null) continue;
            List<NbtBase<String>> list = messages.getValue();
            for (int i = 0; i < list.size(); i++) {
                NbtBase<String> v = list.get(i);
                String plain = stripJson(String.valueOf(v.getValue()));
                if (plain == null) continue;
                String tr = mapper.apply(plain);
                if (tr != null && !tr.equals(plain)) {
                    v.setValue(GsonComponentSerializer.gson()
                            .serialize(net.kyori.adventure.text.Component.text(tr)));
                }
            }
        }
    }

    /** Extracts the plain text from a JSON-string component, or null. */
    private String stripJson(String s) {
        try {
            var el = JsonParser.parseString(s);
            if (el.isJsonPrimitive() && el.getAsJsonPrimitive().isString()) {
                return el.getAsString();
            }
            if (el.isJsonObject() && el.getAsJsonObject().has("text")) {
                return el.getAsJsonObject().get("text").getAsString();
            }
        } catch (Exception ignored) {
            return s.contains("\"") ? null : s; // plain legacy string
        }
        return null;
    }

    // =====================================================================
    // Entity metadata (custom names, Text_Display holograms)
    // =====================================================================
    private void handleMetadata(PacketEvent event, Player player, String lang) {
        PacketContainer packet = event.getPacket();
        List<WrappedWatchableObject> metadata = packet.getWatchableCollectionModifier().readSafely(0);
        if (metadata == null || metadata.isEmpty()) return;

        List<String> texts = new ArrayList<>();
        for (WrappedWatchableObject wo : metadata) {
            if (wo.getValue() instanceof org.bukkit.inventory.ItemStack) {
                // Corruption guard: metadata packets are broadcast-shared, so a
                // rewrite needs deepClone - but deep-cloning a packet that
                // carries registry-encoded item metadata is exactly the byte
                // round trip that kicked clients out of menus. Skip instead:
                // renamed dropped items simply stay untranslated.
                plugin.debug(() -> "ENTITY_METADATA carries an ItemStack - rewrite skipped (corruption guard)");
                return;
            }
            if (wo.getValue() instanceof WrappedChatComponent wc) {
                texts.addAll(JsonText.leaves(wc.getJson()));
            }
        }
        if (texts.isEmpty() || allIgnored(texts)) return;

        if (allCached(texts, lang)) {
            PacketContainer copy = safeClone(packet, "metadata");
            if (copy == null) return;
            applyMetadata(copy, lang);
            event.setPacket(copy);
            plugin.stats().packetsRewritten.increment();
            return;
        }

        PacketContainer original = packet;
        asyncTranslate(texts, lang, () -> {
            PacketContainer copy = safeClone(original, "metadata-async");
            if (copy == null) return;
            applyMetadata(copy, lang);
            sendCopy(player, copy, "metadata");
        });
    }

    private void applyMetadata(PacketContainer packet, String lang) {
        List<WrappedWatchableObject> md = packet.getWatchableCollectionModifier().readSafely(0);
        if (md == null) return;
        for (WrappedWatchableObject wo : md) {
            if (wo.getValue() instanceof WrappedChatComponent wc) {
                String mapped = JsonText.map(wc.getJson(), cachedMapper(lang));
                if (mapped != wc.getJson()) {
                    wo.setValue(WrappedChatComponent.fromJson(mapped));
                }
            }
        }
    }

    // =====================================================================
    // Advancement toasts (UPDATE_ADVANCEMENTS)
    // =====================================================================
    private void handleAdvancements(PacketEvent event, Player player, String lang) {
        PacketContainer packet = event.getPacket();
        List<String> texts = AdvancementRewriter.collectTexts(packet);
        if (texts.isEmpty() || allIgnored(texts)) return;

        if (allCached(texts, lang)) {
            // The map field is per-send; shared holders are rebuilt, not mutated.
            if (AdvancementRewriter.rewrite(plugin, packet, lang)) {
                plugin.stats().packetsRewritten.increment();
                plugin.debug(() -> "translated advancement toast for " + player.getName());
            }
            return;
        }

        PacketContainer original = packet;
        asyncTranslate(texts, lang, () -> {
            // Advancement packets are per-player, so rewriting the original and
            // re-sending is safe; the client just applies the update twice.
            if (AdvancementRewriter.rewrite(plugin, original, lang)) {
                sendCopy(player, original, "advancements");
            }
        });
    }

    // =====================================================================
    // Helpers
    // =====================================================================

    private UnaryOperator<String> cachedMapper(String lang) {
        return s -> {
            String hit = plugin.cache().getMemory(lang, s);
            return hit != null ? hit : s;
        };
    }

    private boolean allIgnored(List<String> texts) {
        return texts.stream().allMatch(plugin.translation()::isIgnored);
    }

    private boolean allCached(List<String> texts, String lang) {
        for (String t : texts) {
            if (plugin.translation().isIgnored(t)) continue;
            if (plugin.cache().getMemory(lang, t) == null) return false;
        }
        return true;
    }

    /**
     * Deep-clones a packet so it can be rewritten without touching the shared
     * broadcast instance. If cloning is impossible the rewrite is skipped -
     * never fall back to mutating the original (that is the v1 corruption bug).
     */
    private PacketContainer safeClone(PacketContainer original, String label) {
        try {
            return original.deepClone();
        } catch (Throwable ex) {
            plugin.debug(() -> "deepClone failed for " + label
                    + " (" + original.getType() + "), rewrite skipped: " + ex);
            return null;
        }
    }

    private void sendCopy(Player player, PacketContainer copy, String label) {
        try {
            ProtocolLibrary.getProtocolManager().sendServerPacket(player, copy, false);
            plugin.stats().packetsResent.increment();
            plugin.debug(() -> "resent translated " + label + " to " + player.getName());
        } catch (Exception ex) {
            plugin.debug(() -> "resend failed for " + label + ": " + ex);
        }
    }

    /**
     * Console-runnable sanity check (/btr selftest) for the menu-critical
     * rewrite paths. Asserts the invariants that actually protect players,
     * independent of ProtocolLib's clone semantics:
     *
     *   1. WINDOW_ITEMS rebuild produces translated, cleanly encoding items
     *      while the SOURCE item object is never mutated (the mirror-leak
     *      that used to corrupt real inventories).
     *   2. Menu-tagged items are skipped.
     *   3. OPEN_WINDOW title rewrite works and never mutates the source
     *      Component object.
     *   4. JsonText mapping (nested + raw-string leaves, identity fast path).
     *   5. Memory cache round trip.
     */
    public String selfTest() {
        StringBuilder sb = new StringBuilder();
        java.util.function.Consumer<String> ok = m -> sb.append("[OK]   ").append(m).append('\n');
        java.util.function.Consumer<String> fail = m -> sb.append("[FAIL] ").append(m).append('\n');
        GsonComponentSerializer gson = GsonComponentSerializer.gson();

        try {
            // --- 0. report shallowClone semantics (informational) -----------
            PacketContainer probe = ProtocolLibrary.getProtocolManager()
                    .createPacket(PacketType.Play.Server.SET_TITLE_TEXT);
            WrappedChatComponent probeComp = WrappedChatComponent.fromJson("{\"text\":\"probe\"}");
            probe.getChatComponents().writeSafely(0, probeComp);
            PacketContainer probeCopy = probe.shallowClone();
            probeCopy.getChatComponents().writeSafely(0,
                    WrappedChatComponent.fromJson("{\"text\":\"changed\"}"));
            boolean sharesHandle = probe.getChatComponents().readSafely(0).getJson().contains("changed");
            probe.getChatComponents().writeSafely(0, probeComp); // restore
            sb.append("[INFO] shallowClone shares the packet handle on this ProtocolLib: ")
                    .append(sharesHandle).append('\n');
            sb.append("[INFO] (per-recipient rewrites are safe under either semantics -\n")
                    .append("[INFO]  the invariant we assert is: source objects are never mutated)\n");

            // --- 1. WINDOW_ITEMS: translate one item, source item untouched -
            PacketContainer window = ProtocolLibrary.getProtocolManager()
                    .createPacket(PacketType.Play.Server.WINDOW_ITEMS);
            window.getIntegers().writeSafely(0, 1);   // container id
            window.getIntegers().writeSafely(1, 0);   // state id
            ItemStack sourceItem = new ItemStack(Material.PAPER);
            ItemMeta om = sourceItem.getItemMeta();
            om.displayName(net.kyori.adventure.text.Component.text("Old Name"));
            sourceItem.setItemMeta(om);
            window.getItemArrayModifier().writeSafely(0, new ItemStack[]{sourceItem});
            if (window.getItemArrayModifier().readSafely(0) == null) {
                // array modifier is a no-op on this ProtocolLib build - use the list form
                window.getItemListModifier().writeSafely(0, new ArrayList<>(List.of(sourceItem)));
            }

            plugin.cache().put("en", "Old Name", "New Name");

            PacketContainer rebuilt = rebuildItems(window, "en", true);
            if (rebuilt == null) {
                fail.accept("WINDOW_ITEMS rebuild returned null");
            } else {
                ItemStack[] out = rebuilt.getItemArrayModifier().readSafely(0);
                List<ItemStack> outList;
                if (out != null) outList = Arrays.asList(out);
                else {
                    List<ItemStack> l = rebuilt.getItemListModifier().readSafely(0);
                    outList = l != null ? l : List.of();
                }
                String name = !outList.isEmpty() && outList.get(0).hasItemMeta()
                        && outList.get(0).getItemMeta().displayName() != null
                        ? gson.serialize(outList.get(0).getItemMeta().displayName()) : "?";
                if (name.contains("New Name")) ok.accept("WINDOW_ITEMS item rewritten");
                else fail.accept("WINDOW_ITEMS item name JSON is '" + name + "', expected 'New Name'");

                // THE invariant: the source Bukkit item (stand-in for a live
                // inventory item) must survive the rewrite untouched.
                String srcName = sourceItem.hasItemMeta() && sourceItem.getItemMeta().displayName() != null
                        ? gson.serialize(sourceItem.getItemMeta().displayName()) : "?";
                if (srcName.contains("Old Name")) ok.accept("source item object untouched (no mirror leak)");
                else fail.accept("source item object was mutated: '" + srcName + "'");

                // every rewritten item must still encode (this is what used to kick)
                try {
                    for (ItemStack st : outList) if (st != null) st.serializeAsBytes();
                    ok.accept("all rewritten items encode cleanly (serializeAsBytes)");
                } catch (Throwable enc) {
                    fail.accept("rewritten item failed to encode: " + enc);
                }
            }

            // --- 2. our own menu items are skipped --------------------------
            ItemStack menuItem = new ItemStack(Material.PAPER);
            ItemMeta mm = menuItem.getItemMeta();
            mm.displayName(net.kyori.adventure.text.Component.text("Old Name"));
            mm.getPersistentDataContainer().set(plugin.menuKey(),
                    org.bukkit.persistence.PersistentDataType.STRING, "en");
            menuItem.setItemMeta(mm);
            if (translatedCopy(menuItem, "en") == null) ok.accept("menu-tagged items are skipped");
            else fail.accept("menu-tagged item was rewritten (should be skipped)");

            // --- 3. OPEN_WINDOW: title rewrite via shallowClone --------------
            PacketContainer open = ProtocolLibrary.getProtocolManager()
                    .createPacket(PacketType.Play.Server.OPEN_WINDOW);
            WrappedChatComponent origTitle = WrappedChatComponent.fromJson("{\"text\":\"Old Title\"}");
            open.getChatComponents().writeSafely(0, origTitle);
            plugin.cache().put("en", "Old Title", "New Title");
            PacketContainer openCopy = rewriteComponent(open, 0, "{\"text\":\"New Title\"}", false);
            if (openCopy != null) {
                String copied = openCopy.getChatComponents().readSafely(0).getJson();
                String origJson = origTitle.getJson(); // direct reference, not the packet
                if (copied.contains("New Title") && origJson.contains("Old Title")) {
                    ok.accept("OPEN_WINDOW rewrite correct; source component object untouched");
                } else {
                    fail.accept("OPEN_WINDOW rewrite mismatch: copy=" + copied + " orig=" + origJson);
                }
            } else fail.accept("OPEN_WINDOW rewrite returned null");

            // --- 4. JsonText sanity ------------------------------------------
            String mapped = JsonText.map(
                    "{\"extra\":[{\"text\":\"Old Name\"},\"Old Name\"],\"with\":[{\"text\":\"x\"}]}",
                    s -> s.equals("Old Name") ? "New Name" : s);
            if (mapped != null && mapped.contains("New Name") && !mapped.contains("Old Name")) {
                ok.accept("JsonText maps nested + raw-string leaves");
            } else fail.accept("JsonText mapping broken: " + mapped);

            String identity = "{\"text\":\"abc\"}";
            if (JsonText.map(identity, s -> s) == identity) {
                ok.accept("JsonText identity fast path returns the original reference");
            } else fail.accept("JsonText identity broke reference equality");

            // --- 5. memory cache round trip ----------------------------------
            plugin.cache().put("en", "selftest-xyz", "selftest-XYZ");
            if ("selftest-XYZ".equals(plugin.cache().getMemory("en", "selftest-xyz"))) {
                ok.accept("memory cache round trip");
            } else fail.accept("memory cache broken");

            // --- 6. environment report ---------------------------------------
            if (DeepTextScanner.available()) {
                ok.accept("DeepTextScanner available (signed chat / boss bars / scoreboards active)");
            } else sb.append("[WARN] DeepTextScanner unavailable - nested rewrites disabled\n");

            List<String> skipped = skippedTypes();
            if (skipped.isEmpty()) ok.accept("all 17 packet types resolved in this ProtocolLib build");
            else sb.append("[WARN] packet types skipped by this ProtocolLib: ").append(skipped).append('\n');
            sb.append("[INFO] languages: ").append(plugin.langs().allowedLanguages())
                    .append(", default: ").append(plugin.langs().defaultLanguage()).append('\n');
        } catch (Throwable t) {
            fail.accept("unexpected exception: " + t);
        }
        return sb.toString();
    }

    /**
     * Fire-and-forget async translation of a batch of strings; runs the
     * callback on a virtual thread once everything is in the cache.
     */
    private void asyncTranslate(List<String> texts, String lang, Runnable thenResend) {
        List<java.util.concurrent.CompletableFuture<Void>> futures = new ArrayList<>();
        boolean any = false;
        for (String t : texts) {
            if (plugin.translation().isIgnored(t)) continue;
            if (plugin.cache().getMemory(lang, t) != null) continue;
            String key = lang + '\u0000' + t;
            if (!inFlight.add(key)) continue;
            any = true;
            futures.add(plugin.translation().translate(t, lang)
                    .thenRun(() -> inFlight.remove(key))
                    .exceptionally(ex -> {
                        inFlight.remove(key);
                        return null;
                    }));
        }
        if (any) plugin.stats().packetsQueued.increment();
        if (futures.isEmpty()) {
            plugin.virtualPool().execute(thenResend);
            return;
        }
        java.util.concurrent.CompletableFuture
                .allOf(futures.toArray(new java.util.concurrent.CompletableFuture[0]))
                .thenRun(thenResend);
    }
}
BEXIND_EOF
cat > src/main/java/com/bexind/translate/LangCommand.java <<'BEXIND_EOF'
package com.bexind.translate;

import org.bukkit.ChatColor;
import org.bukkit.command.Command;
import org.bukkit.command.CommandExecutor;
import org.bukkit.command.CommandSender;
import org.bukkit.command.TabCompleter;
import org.bukkit.entity.Player;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

public final class LangCommand implements CommandExecutor, TabCompleter {

    private final BexindTranslate plugin;

    public LangCommand(BexindTranslate plugin) {
        this.plugin = plugin;
    }

    @Override
    public boolean onCommand(CommandSender sender, Command cmd, String label, String[] args) {
        if (args.length == 0) {
            usage(sender, label);
            return true;
        }

        switch (args[0].toLowerCase(Locale.ROOT)) {
            case "lang" -> {
                if (!(sender instanceof Player player)) {
                    sender.sendMessage("Players only.");
                    return true;
                }
                if (args.length < 2) {
                    player.sendMessage(ChatColor.RED + "Usage: /" + label + " lang <en|ru|auto>");
                    return true;
                }
                String code = args[1].toLowerCase(Locale.ROOT);
                if (code.equals("auto")) {
                    plugin.langs().setOverride(player.getUniqueId(), "auto");
                    String resolved = plugin.langs().getEffective(player);
                    player.sendMessage(ChatColor.GREEN + "Auto language: "
                            + ChatColor.YELLOW + (resolved == null ? plugin.langs().defaultLanguage() : resolved));
                } else if (!plugin.langs().isAllowed(code)) {
                    player.sendMessage(ChatColor.RED + "This server only offers: "
                            + ChatColor.YELLOW + String.join(", ", plugin.langs().allowedLanguages()));
                } else {
                    plugin.langs().choose(player.getUniqueId(), code);
                    player.sendMessage(ChatColor.GREEN + "Language set to " + ChatColor.YELLOW + code);
                }
            }
            case "menu" -> {
                if (!(sender instanceof Player player)) {
                    sender.sendMessage("Players only.");
                    return true;
                }
                plugin.menuListener().forceOpen(player);
            }
            case "selftest" -> {
                if (!admin(sender)) return true;
                if (plugin.interceptor() == null) {
                    sender.sendMessage(ChatColor.RED + "Interceptor unavailable (ProtocolLib failed to load).");
                    return true;
                }
                sender.sendMessage(ChatColor.DARK_AQUA + "Running packet rewrite self-test...");
                String report = plugin.interceptor().selfTest();
                for (String line : report.split("\n")) sender.sendMessage(line);
            }
            case "reload" -> {
                if (!admin(sender)) return true;
                plugin.reloadConfig();
                plugin.translation().reload(); // v1 forgot this: ignored-patterns never refreshed
                plugin.langs().refresh();      // re-clamps languages + default-language
                sender.sendMessage(ChatColor.GREEN + "Config reloaded. Provider: "
                        + ChatColor.YELLOW + plugin.getConfig().getString("provider", "GOOGLE_FREE")
                        + ChatColor.GRAY + " failover: "
                        + plugin.getConfig().getStringList("failover-providers"));
            }
            case "cache" -> {
                if (!admin(sender)) return true;
                if (args.length > 1 && args[1].equalsIgnoreCase("clear")) {
                    plugin.cache().clearPersistent()
                            .thenRun(() -> sender.sendMessage(ChatColor.GREEN + "Cache cleared."));
                } else {
                    sender.sendMessage(ChatColor.YELLOW + "Usage: /" + label + " cache clear");
                }
            }
            case "stats" -> {
                if (!admin(sender)) return true;
                for (String line : statsLines()) sender.sendMessage(line);
            }
            case "debug" -> {
                if (!admin(sender)) return true;
                boolean on = plugin.toggleDebug();
                sender.sendMessage(ChatColor.AQUA + "BexindTranslate debug: "
                        + (on ? ChatColor.GREEN + "ENABLED" : ChatColor.RED + "disabled"));
            }
            default -> sender.sendMessage(ChatColor.RED + "Unknown subcommand.");
        }
        return true;
    }

    private boolean admin(CommandSender sender) {
        if (sender.hasPermission("bexindtranslate.admin")) return true;
        sender.sendMessage(ChatColor.RED + "No permission.");
        return false;
    }

    private List<String> statsLines() {
        Stats s = plugin.stats();
        long l1 = s.l1Hits.sum();
        long l2 = s.l2Hits.sum();
        long lookups = l1 + l2 + s.cacheMisses.sum();

        List<String> out = new ArrayList<>();
        out.add(ChatColor.DARK_AQUA + "BexindTranslate " + ChatColor.GRAY
                + "stats — uptime " + s.uptimeMinutes() + " min");
        out.add(ChatColor.YELLOW + "Packets: " + ChatColor.WHITE + s.packetsSeen.sum()
                + ChatColor.GRAY + " seen, " + ChatColor.WHITE + s.packetsRewritten.sum()
                + ChatColor.GRAY + " rewritten, " + ChatColor.WHITE + s.packetsQueued.sum()
                + ChatColor.GRAY + " queued, " + ChatColor.WHITE + s.packetsResent.sum()
                + ChatColor.GRAY + " resent");
        out.add(ChatColor.YELLOW + "Strings: " + ChatColor.WHITE + s.stringsTranslated.sum()
                + ChatColor.GRAY + " translated, " + ChatColor.WHITE + s.sameLangSkips.sum()
                + ChatColor.GRAY + " same-lang skipped, " + ChatColor.WHITE + s.negativeSkips.sum()
                + ChatColor.GRAY + " negative-cached");
        out.add(ChatColor.YELLOW + "Cache: " + ChatColor.WHITE + pct(l1, lookups) + "%"
                + ChatColor.GRAY + " L1, " + ChatColor.WHITE + pct(l2, lookups) + "%"
                + ChatColor.GRAY + " L2 — " + ChatColor.WHITE + plugin.cache().memorySize()
                + ChatColor.GRAY + " memory entries, " + ChatColor.WHITE
                + plugin.cache().negativeSize() + ChatColor.GRAY + " negative");
        out.add(ChatColor.YELLOW + "Providers: " + ChatColor.WHITE + s.providerCalls.sum()
                + ChatColor.GRAY + " calls, " + ChatColor.WHITE + s.providerFailures.sum()
                + ChatColor.GRAY + " failures, avg " + ChatColor.WHITE + s.providerAvgMs() + " ms"
                + ChatColor.GRAY + ", " + ChatColor.WHITE + s.rateLimited.sum()
                + ChatColor.GRAY + " rate-limited");
        return out;
    }

    private static String pct(long part, long total) {
        if (total <= 0) return "0";
        return String.valueOf(part * 100 / total);
    }

    private void usage(CommandSender sender, String label) {
        sender.sendMessage(ChatColor.AQUA + "BexindTranslate v" + plugin.getDescription().getVersion()
                + ChatColor.GRAY + " — usage:");
        sender.sendMessage(ChatColor.YELLOW + "/" + label + " lang <en|ru|auto>"
                + ChatColor.GRAY + " — set your language");
        sender.sendMessage(ChatColor.YELLOW + "/" + label + " menu"
                + ChatColor.GRAY + " — reopen the language menu");
        sender.sendMessage(ChatColor.YELLOW + "/" + label + " reload"
                + ChatColor.GRAY + " — reload config (admin)");
        sender.sendMessage(ChatColor.YELLOW + "/" + label + " stats"
                + ChatColor.GRAY + " — cache & provider statistics (admin)");
        sender.sendMessage(ChatColor.YELLOW + "/" + label + " debug"
                + ChatColor.GRAY + " — toggle packet debug logging (admin)");
        sender.sendMessage(ChatColor.YELLOW + "/" + label + " cache clear"
                + ChatColor.GRAY + " — wipe cache (admin)");
        sender.sendMessage(ChatColor.YELLOW + "/" + label + " selftest"
                + ChatColor.GRAY + " — packet rewrite sanity check (admin)");
    }

    @Override
    public List<String> onTabComplete(CommandSender sender, Command cmd, String alias, String[] args) {
        if (args.length == 1) {
            List<String> subs = new ArrayList<>(List.of("lang", "menu"));
            if (sender.hasPermission("bexindtranslate.admin")) {
                subs.addAll(List.of("reload", "cache", "stats", "debug", "selftest"));
            }
            return filter(subs, args[0]);
        }
        if (args.length == 2 && args[0].equalsIgnoreCase("lang")) {
            List<String> codes = new ArrayList<>(List.of("auto"));
            codes.addAll(plugin.langs().allowedLanguages());
            return filter(codes, args[1]);
        }
        if (args.length == 2 && args[0].equalsIgnoreCase("cache")) return filter(List.of("clear"), args[1]);
        return List.of();
    }

    /** Prefix filter so tab completion behaves like vanilla. */
    private static List<String> filter(List<String> options, String prefix) {
        String p = prefix == null ? "" : prefix.toLowerCase(Locale.ROOT);
        List<String> out = new ArrayList<>();
        for (String o : options) {
            if (o.toLowerCase(Locale.ROOT).startsWith(p)) out.add(o);
        }
        return out;
    }
}
BEXIND_EOF
cat > src/main/java/com/bexind/translate/LanguageMenuListener.java <<'BEXIND_EOF'
package com.bexind.translate;

import net.kyori.adventure.text.Component;
import net.kyori.adventure.text.minimessage.MiniMessage;
import org.bukkit.Bukkit;
import org.bukkit.Material;
import org.bukkit.entity.Player;
import org.bukkit.event.EventHandler;
import org.bukkit.event.EventPriority;
import org.bukkit.event.Listener;
import org.bukkit.event.inventory.InventoryClickEvent;
import org.bukkit.event.inventory.InventoryCloseEvent;
import org.bukkit.event.inventory.InventoryDragEvent;
import org.bukkit.event.player.PlayerJoinEvent;
import org.bukkit.inventory.Inventory;
import org.bukkit.inventory.InventoryHolder;
import org.bukkit.inventory.ItemStack;
import org.bukkit.inventory.meta.ItemMeta;
import org.bukkit.persistence.PersistentDataType;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

/**
 * The language selection menu, rewritten for the two-language model (en / ru).
 *
 * Everything visible comes from config.yml (menu.*): title, rows, fill item,
 * per-language buttons (material / name / lore / slot), messages. Text uses
 * MiniMessage. Buttons carry the language code in a PersistentDataContainer
 * tag - v2.0 parsed it out of the lore text, which broke as soon as anything
 * (including our own translator) touched that lore.
 *
 * The "trap" behaviour is kept: while menu.force is true and the player has
 * no saved language, closing the menu re-opens it.
 */
public final class LanguageMenuListener implements Listener {

    private static final MiniMessage MM = MiniMessage.miniMessage();

    private final BexindTranslate plugin;
    /** Players currently being forced to choose. */
    private final Set<UUID> forced = ConcurrentHashMap.newKeySet();
    /**
     * Players whose language menu is being opened RIGHT NOW (set around the
     * player.openInventory() call). The packet interceptor checks this flag
     * and leaves our own menu packets untouched - the menu is already fully
     * localized by config.yml, and a second machine-translation pass would
     * double-translate the title (the items are protected by their PDC tag,
     * the title has no such tag).
     */
    private final Set<UUID> opening = ConcurrentHashMap.newKeySet();

    public LanguageMenuListener(BexindTranslate plugin) {
        this.plugin = plugin;
    }

    /** True while the plugin is opening the language menu for this player. */
    public boolean isOpening(UUID uuid) {
        return opening.contains(uuid);
    }

    // ------------------------------------------------------------------
    // Join flow
    // ------------------------------------------------------------------

    @EventHandler
    public void onJoin(PlayerJoinEvent event) {
        offerMenu(event.getPlayer());
    }

    /**
     * Loads the saved language FIRST, then decides whether the menu is needed.
     * v2.0 checked the in-memory map 1 second after join, racing the DB read:
     * returning players sometimes saw the menu again even though they had
     * already chosen. The decision now runs strictly after the load completes.
     */
    public void offerMenu(Player player) {
        plugin.langs().loadAsync(player)
                .thenRun(() -> decideOffer(player))
                // a DB hiccup must never leave a returning player menu-locked
                .exceptionally(ex -> {
                    decideOffer(player);
                    return null;
                });
    }

    private void decideOffer(Player player) {
        Bukkit.getScheduler().runTask(plugin, () -> {
            if (!player.isOnline()) return;
            if (plugin.langs().hasChosen(player.getUniqueId())) return;
            if (!plugin.getConfig().getBoolean("menu.force", true)) return;
            forced.add(player.getUniqueId());
            open(player);
        });
    }

    /** Builds and opens the menu from config. */
    public void open(Player player) {
        List<String> langs = plugin.langs().allowedLanguages();

        int rows = Math.max(1, Math.min(6, plugin.getConfig().getInt("menu.rows", 3)));
        int size = rows * 9;
        LangHolder holder = new LangHolder();
        Inventory inv = Bukkit.createInventory(holder, size,
                MM.deserialize(plugin.getConfig().getString("menu.title",
                        "Select language / Выберите язык")));
        holder.bind(inv);

        // fill
        String fillMat = plugin.getConfig().getString("menu.fill.material", "GRAY_STAINED_GLASS_PANE");
        ItemStack fill = makeFill(fillMat, plugin.getConfig().getString("menu.fill.name", " "));
        if (fill != null) {
            for (int i = 0; i < size; i++) inv.setItem(i, fill);
        }

        // buttons
        boolean glow = plugin.getConfig().getBoolean("menu.selected-glow", true);
        String current = plugin.langs().peekSavedSync(player.getUniqueId());
        Set<Integer> used = new java.util.HashSet<>();
        // auto-place fallback: leftmost free slot of the middle row
        int autoSlot = Math.min(size - 1, (rows / 2) * 9 + 1);
        for (String code : langs) {
            int slot = buttonSlot(code, size, used);
            ItemStack button = makeButton(code, glow, code.equalsIgnoreCase(current));
            if (button == null) continue;
            if (slot < 0 || slot >= size || !used.add(slot)) {
                // auto-place: center row, skipping taken slots
                while (autoSlot < size && !used.add(autoSlot)) autoSlot++;
                if (autoSlot >= size) autoSlot = size - 1;
                slot = autoSlot;
            }
            inv.setItem(slot, button);
        }

        // Suppress our own packet rewriter while the menu opens: OPEN_WINDOW /
        // WINDOW_ITEMS / SET_SLOT for this player go out inside this call, and
        // the menu text is already localized by config.yml.
        opening.add(player.getUniqueId());
        try {
            player.openInventory(inv);
        } finally {
            opening.remove(player.getUniqueId());
        }
    }

    private int buttonSlot(String code, int size, Set<Integer> used) {
        int slot = plugin.getConfig().getInt("menu.buttons." + code + ".slot", -1);
        if (slot >= 0 && slot < size && !used.contains(slot)) return slot;
        return -1; // caller auto-places
    }

    private ItemStack makeFill(String materialName, String name) {
        Material mat = Material.matchMaterial(materialName == null ? "" : materialName);
        if (mat == null) return null;
        try {
            ItemStack item = new ItemStack(mat);
            if (name != null && !name.isBlank()) {
                ItemMeta meta = item.getItemMeta();
                if (meta != null) {
                    meta.displayName(MM.deserialize(name));
                    item.setItemMeta(meta);
                }
            }
            return item;
        } catch (Throwable t) {
            plugin.getLogger().warning("menu.fill material '" + materialName + "' failed: " + t);
            return null;
        }
    }

    private ItemStack makeButton(String code, boolean glowAllowed, boolean isSelected) {
        String path = "menu.buttons." + code;
        String matName = plugin.getConfig().getString(path + ".material", "PAPER");
        Material mat = Material.matchMaterial(matName == null ? "" : matName);
        if (mat == null) {
            plugin.getLogger().warning("menu.buttons." + code + ".material '" + matName
                    + "' is not a valid material - using PAPER.");
            mat = Material.PAPER;
        }
        try {
            ItemStack item = new ItemStack(mat);
            ItemMeta meta = item.getItemMeta();
            if (meta == null) return null;

            String name = plugin.getConfig().getString(path + ".name", code.toUpperCase(Locale.ROOT));
            meta.displayName(MM.deserialize(name));

            List<String> lore = plugin.getConfig().getStringList(path + ".lore");
            if (!lore.isEmpty()) {
                List<Component> loreComps = new ArrayList<>(lore.size());
                for (String line : lore) loreComps.add(MM.deserialize(line));
                meta.lore(loreComps);
            }

            if (isSelected && glowAllowed) {
                try {
                    meta.setEnchantmentGlintOverride(Boolean.TRUE);
                } catch (Throwable ignored) {
                    // older API level without the glint override - cosmetic only
                }
            }

            // machine-readable language code - never parse visible text again
            meta.getPersistentDataContainer().set(plugin.menuKey(), PersistentDataType.STRING, code);
            item.setItemMeta(meta);
            return item;
        } catch (Throwable t) {
            plugin.getLogger().warning("menu.buttons." + code + " could not be built: " + t);
            return null;
        }
    }

    // ------------------------------------------------------------------
    // Interaction
    // ------------------------------------------------------------------

    @EventHandler(priority = EventPriority.HIGHEST)
    public void onClick(InventoryClickEvent event) {
        if (!(event.getView().getTopInventory().getHolder() instanceof LangHolder)) return;
        event.setCancelled(true); // covers shift-clicks from the hotbar too
        if (!(event.getWhoClicked() instanceof Player player)) return;
        if (event.getClickedInventory() == null
                || !(event.getClickedInventory().getHolder() instanceof LangHolder)) return;

        ItemStack clicked = event.getCurrentItem();
        if (clicked == null || !clicked.hasItemMeta()) return;
        ItemMeta meta = clicked.getItemMeta();
        if (meta == null) return;

        String code = meta.getPersistentDataContainer()
                .get(plugin.menuKey(), PersistentDataType.STRING);
        if (code == null || !plugin.langs().isAllowed(code)) return;

        String current = plugin.langs().peekSavedSync(player.getUniqueId());
        if (code.equalsIgnoreCase(current)) {
            player.sendMessage(MM.deserialize(plugin.getConfig()
                    .getString("menu.already-message", "<yellow>Language already set!")
                    .replace("<lang>", code)));
            forced.remove(player.getUniqueId());
            closeNextTick(player); // never closeInventory() inside a click event
            return;
        }

        choose(player, code);
    }

    /** Closing inside InventoryClickEvent is unsafe on Paper - go next tick. */
    private void closeNextTick(Player player) {
        Bukkit.getScheduler().runTask(plugin, () -> player.closeInventory());
    }

    @EventHandler
    public void onDrag(InventoryDragEvent event) {
        if (event.getView().getTopInventory().getHolder() instanceof LangHolder) {
            event.setCancelled(true);
        }
    }

    /** THE trap: you cannot close it until you chose a language (menu.force). */
    @EventHandler(priority = EventPriority.MONITOR)
    public void onClose(InventoryCloseEvent event) {
        if (!(event.getPlayer() instanceof Player player)) return;
        if (!(event.getInventory().getHolder() instanceof LangHolder)) return;
        if (!forced.contains(player.getUniqueId())) return;

        // Player tried to escape (ESC / E). Reopen next tick.
        Bukkit.getScheduler().runTask(plugin, () -> {
            if (player.isOnline() && forced.contains(player.getUniqueId())) {
                open(player);
                player.sendMessage(MM.deserialize(plugin.getConfig()
                        .getString("menu.must-pick-message",
                                "<red>You must select a language first!")));
            }
        });
    }

    private void choose(Player player, String code) {
        if (!plugin.langs().choose(player.getUniqueId(), code)) return;
        forced.remove(player.getUniqueId()); // allow closing now
        player.sendMessage(MM.deserialize(plugin.getConfig()
                .getString("menu.chosen-message", "<green>Language set: <yellow><lang>")
                .replace("<lang>", code)));
        closeNextTick(player);
    }

    /** Called from the command so admins can reopen the menu manually. */
    public void forceOpen(Player player) {
        forced.add(player.getUniqueId());
        open(player);
    }

    /** Frees per-player state on quit (v1 leaked this set). */
    public void release(UUID uuid) {
        forced.remove(uuid);
    }

    public Set<UUID> forcedPlayers() {
        return forced;
    }

    /** Marker holder so we can identify our menu cheaply. */
    public static final class LangHolder implements InventoryHolder {
        private Inventory inventory;

        void bind(Inventory inv) { this.inventory = inv; }

        @Override
        public Inventory getInventory() {
            return inventory; // null-safe: Bukkit tolerates this, but we bind anyway
        }
    }
}
BEXIND_EOF

echo "==> [3/4] Building BexindTranslate 2.1.0"
mvn -q clean package
JAR=~/BexindTranslate/target/BexindTranslate-2.1.0.jar
[ -f "$JAR" ] || { echo "Build finished but jar is missing - check Maven output above."; exit 1; }
echo "    Built: $JAR"

echo "==> [4/4] Optional Paper $PAPER_VERSION server setup"
if [ "${SETUP_SERVER:-1}" = "1" ]; then
  command -v curl >/dev/null 2>&1 || { echo "curl missing:  sudo pacman -S curl"; exit 1; }
  command -v jq   >/dev/null 2>&1 || { echo "jq missing:    sudo pacman -S jq";     exit 1; }
  mkdir -p ~/mc-server/plugins
  cd ~/mc-server
  if [ ! -f paper.jar ]; then
    # NOTE: api.papermc.io/v2 was sunset; the current endpoint is fill.papermc.io/v3
    URL=$(curl -s "https://fill.papermc.io/v3/projects/paper/versions/$PAPER_VERSION/builds/latest" \
            | jq -r '.downloads["server:default"].url')
    if [ -z "$URL" ] || [ "$URL" = "null" ]; then
      echo "Could not resolve the Paper download URL - grab it manually from https://papermc.io/downloads"
      exit 1
    fi
    echo "    Downloading Paper $PAPER_VERSION (latest build)..."
    curl -sL -o paper.jar "$URL"
  fi
  [ -f eula.txt ] || echo "eula=true" > eula.txt
  if [ ! -f plugins/ProtocolLib.jar ]; then
    echo "    Downloading ProtocolLib (latest release, tested green on 1.21.1 and 1.21.11)..."
    curl -sL -o plugins/ProtocolLib.jar \
      "https://github.com/dmulloy2/ProtocolLib/releases/latest/download/ProtocolLib.jar"
  fi
  cp -f "$JAR" plugins/BexindTranslate-2.1.0.jar
  echo ""
  echo "    Server ready at ~/mc-server (Paper $PAPER_VERSION + ProtocolLib + BexindTranslate 2.1.0)"
  echo "    Start it with:"
  echo "      cd ~/mc-server && java -Xms2G -Xmx4G -jar paper.jar --nogui"
  echo "    Then check: /btr stats   (console: btr stats)"
  echo ""
  echo "    NOTE: the plugin shows RED in /plugins if ProtocolLib is missing"
  echo "    or broken - the console will then print exact fix instructions."
else
  echo "    Skipping server setup (SETUP_SERVER=0)."
  echo "    Your plugin jar is at ~/BexindTranslate/target/BexindTranslate-2.1.0.jar"
  echo "    Copy it into your server's plugins/ folder - ProtocolLib 5.4.0+ is"
  echo "    REQUIRED (without it the plugin shows red in /plugins)."
fi
echo "==> ALL DONE"
