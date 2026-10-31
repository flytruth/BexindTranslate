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
