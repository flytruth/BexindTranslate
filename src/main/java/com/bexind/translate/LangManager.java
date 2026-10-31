package com.bexind.translate;

import org.bukkit.entity.Player;

import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Per-player language resolution: manual override > saved choice > client locale.
 * Maps are cleaned up on quit (v1 leaked entries here).
 */
public final class LangManager {

    private final BexindTranslate plugin;
    private final Map<UUID, String> override = new ConcurrentHashMap<>();
    private final Map<UUID, String> saved = new ConcurrentHashMap<>();

    LangManager(BexindTranslate plugin) {
        this.plugin = plugin;
    }

    /** Loads the player's saved language from SQLite asynchronously. */
    public void loadAsync(Player player) {
        plugin.cache().loadPlayerLang(player.getUniqueId().toString())
                .thenAccept(lang -> {
                    if (lang != null) saved.put(player.getUniqueId(), lang);
                });
    }

    public void setOverride(UUID uuid, String lang) {
        override.put(uuid, lang);
    }

    /** Persists the choice (used by the join menu and /btr lang). */
    public void choose(UUID uuid, String lang) {
        saved.put(uuid, lang);
        plugin.cache().savePlayerLang(uuid.toString(), lang);
    }

    public boolean hasChosen(UUID uuid) {
        return saved.containsKey(uuid);
    }

    /** Effective ISO target language, or null if translation should be skipped. */
    public String getEffective(Player player) {
        String lang = override.get(player.getUniqueId());
        if (lang == null) lang = saved.get(player.getUniqueId());
        if (lang == null) lang = fromLocale(player.getLocale());
        String def = plugin.getConfig().getString("default-language", "en");
        if (lang == null || lang.isBlank() || lang.equalsIgnoreCase("auto") || lang.equalsIgnoreCase(def)) {
            return null; // nothing to do
        }
        return lang.toLowerCase();
    }

    /** "ru_ru" -> "ru", "en_US" -> "en", "tr" -> "tr". */
    public static String fromLocale(String locale) {
        if (locale == null || locale.isBlank()) return null;
        int i = locale.indexOf('_');
        return (i > 0 ? locale.substring(0, i) : locale).toLowerCase();
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
}
