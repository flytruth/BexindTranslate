package com.bexind.translate;

import com.comphenix.protocol.ProtocolLibrary;
import com.comphenix.protocol.ProtocolManager;
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
    private LanguageMenuListener menuListener;
    private volatile boolean debugEnabled;

    public LanguageMenuListener menuListener() { return menuListener; }

    @Override
    public void onEnable() {
        instance = this;
        saveDefaultConfig();
        upgradeConfig();

        // Java 21 virtual threads: unbounded, cheap, never block the main tick thread.
        this.virtualPool = Executors.newVirtualThreadPerTaskExecutor();
        this.stats = new Stats();
        this.debugEnabled = getConfig().getBoolean("debug", false);

        this.cache = new CacheManager(this);
        this.cache.initAsync(); // opens SQLite off-thread

        this.translationService = new TranslationService(this);
        this.translationService.reload();
        this.langManager = new LangManager(this);

        // Network interception layer
        this.protocolManager = ProtocolLibrary.getProtocolManager();
        this.protocolManager.addPacketListener(new PacketInterceptor(this));

        // Commands + join menu
        PluginCommand cmd = getCommand("bexindtranslate");
        LangCommand langCommand = new LangCommand(this);
        cmd.setExecutor(langCommand);
        cmd.setTabCompleter(langCommand);

        this.menuListener = new LanguageMenuListener(this);
        getServer().getPluginManager().registerEvents(menuListener, this);
        getServer().getPluginManager().registerEvents(new QuitCleanup(), this);

        // After a /reload or plugin manager reload, players may already be online.
        getServer().getScheduler().runTaskLater(this, () -> {
            for (Player p : getServer().getOnlinePlayers()) {
                langManager.loadAsync(p);
                if (getConfig().getBoolean("force-language-menu", true)
                        && !langManager.hasChosen(p.getUniqueId())) {
                    LanguageMenuListener.open(this, p);
                }
            }
        }, 10L);

        getLogger().info("BexindTranslate 2.0.0 enabled. Provider: "
                + getConfig().getString("provider", "GOOGLE_FREE")
                + ", failover: " + getConfig().getStringList("failover-providers"));
    }

    @Override
    public void onDisable() {
        if (protocolManager != null) {
            ProtocolLibrary.getProtocolManager().removePacketListeners(this);
        }
        virtualPool.shutdown();
        try {
            virtualPool.awaitTermination(3, TimeUnit.SECONDS);
        } catch (InterruptedException ignored) {
            Thread.currentThread().interrupt();
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

    /** Adds v2 config keys for servers upgrading from 1.0 without touching user edits. */
    private void upgradeConfig() {
        if (getConfig().getInt("config-version", 0) >= 2) return;
        getConfig().set("config-version", 2);
        setDefault("failover-providers", List.of());
        setDefault("rate-limit.requests-per-second", 10);
        setDefault("rate-limit.burst", 25);
        setDefault("rate-limit.max-wait-ms", 2000);
        setDefault("same-language-skip", true);
        setDefault("negative-cache-minutes", 5);
        setDefault("debug", false);
        setDefault("libretranslate-api-key", "");
        setDefault("features.titles", true);
        setDefault("features.boss-bars", true);
        setDefault("features.tab-list", true);
        setDefault("features.advancements", true);
        saveConfig();
        getLogger().info("Config upgraded to config-version 2.");
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
