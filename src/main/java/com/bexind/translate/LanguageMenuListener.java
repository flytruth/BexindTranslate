package com.bexind.translate;

import org.bukkit.Bukkit;
import org.bukkit.ChatColor;
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

import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

/**
 * The forced language selection menu (kept as-is from 1.0 per design choice).
 * Opens on join (if the player has no saved language) and re-opens
 * every time the player tries to close it, until they pick a language.
 */
public final class LanguageMenuListener implements Listener {

    public static final String MENU_TITLE = ChatColor.DARK_AQUA + "Select language / Выберите язык / Dil seçin";

    private static final Map<String, Material> FLAGS = Map.of(
            "en", Material.RED_WOOL,
            "ru", Material.BLUE_WOOL,
            "es", Material.YELLOW_WOOL,
            "de", Material.BLACK_WOOL,
            "fr", Material.WHITE_WOOL,
            "tr", Material.REDSTONE,
            "ar", Material.GREEN_WOOL,
            "fa", Material.EMERALD);

    private static final Map<String, String> NAMES = Map.of(
            "en", "English", "ru", "Русский", "es", "Español", "de", "Deutsch",
            "fr", "Français", "tr", "Türkçe",
            "ar", "العربية", "fa", "فارسی");

    private final BexindTranslate plugin;
    /** Players currently being forced to choose. */
    private final Set<UUID> forced = ConcurrentHashMap.newKeySet();

    public LanguageMenuListener(BexindTranslate plugin) {
        this.plugin = plugin;
    }

    @EventHandler
    public void onJoin(PlayerJoinEvent event) {
        Player player = event.getPlayer();
        plugin.langs().loadAsync(player);
        if (!plugin.getConfig().getBoolean("force-language-menu", true)) return;
        // Wait a moment so the client is fully ready, then force the menu.
        Bukkit.getScheduler().runTaskLater(plugin, () -> {
            if (!player.isOnline()) return;
            if (!plugin.langs().hasChosen(player.getUniqueId())) {
                forced.add(player.getUniqueId());
                open(plugin, player);
            }
        }, 20L);
    }

    /** Builds and opens the menu. */
    static void open(BexindTranslate plugin, Player player) {
        List<String> langs = plugin.getConfig().getStringList("menu-languages");
        if (langs.isEmpty()) langs = List.of("en", "ru", "es");

        int size = ((langs.size() - 1) / 9 + 1) * 9;
        Inventory inv = Bukkit.createInventory(new LangHolder(), Math.min(size, 54), MENU_TITLE);

        int slot = 0;
        for (String code : langs) {
            String c = code.toLowerCase();
            ItemStack item = new ItemStack(FLAGS.getOrDefault(c, Material.PAPER));
            ItemMeta meta = item.getItemMeta();
            meta.setDisplayName(ChatColor.AQUA + NAMES.getOrDefault(c, c.toUpperCase()));
            meta.setLore(List.of(
                    ChatColor.GRAY + "Click to set " + ChatColor.YELLOW + c.toUpperCase(),
                    ChatColor.DARK_GRAY + "language code: " + c));
            item.setItemMeta(meta);
            inv.setItem(slot++, item);
        }
        player.openInventory(inv);
    }

    @EventHandler(priority = EventPriority.HIGHEST)
    public void onClick(InventoryClickEvent event) {
        if (!(event.getInventory().getHolder() instanceof LangHolder)) return;
        event.setCancelled(true); // nothing can be taken/moved
        if (!(event.getWhoClicked() instanceof Player player)) return;
        if (event.getClickedInventory() == null) return;
        ItemStack clicked = event.getCurrentItem();
        if (clicked == null || clicked.getItemMeta() == null) return;

        String lore = ChatColor.stripColor(clicked.getItemMeta().getLore() == null ? ""
                : clicked.getItemMeta().getLore().get(clicked.getItemMeta().getLore().size() - 1));
        String code = lore.replace("language code:", "").trim();
        if (code.isBlank()) return;

        choose(plugin, player, code);
    }

    @EventHandler
    public void onDrag(InventoryDragEvent event) {
        if (event.getInventory().getHolder() instanceof LangHolder) event.setCancelled(true);
    }

    /** THE trap: you cannot close it until you chose a language. */
    @EventHandler(priority = EventPriority.MONITOR)
    public void onClose(InventoryCloseEvent event) {
        if (!(event.getPlayer() instanceof Player player)) return;
        if (!(event.getInventory().getHolder() instanceof LangHolder)) return;
        if (!forced.contains(player.getUniqueId())) return;

        // Player tried to escape (ESC / E). Reopen next tick.
        Bukkit.getScheduler().runTask(plugin, () -> {
            if (player.isOnline() && forced.contains(player.getUniqueId())) {
                open(plugin, player);
                player.sendMessage(ChatColor.RED + "You must select a language! / Выберите язык!");
            }
        });
    }

    private void choose(BexindTranslate plugin, Player player, String code) {
        plugin.langs().choose(player.getUniqueId(), code);
        forced.remove(player.getUniqueId()); // allow closing now
        player.sendMessage(ChatColor.GREEN + "Language set: " + ChatColor.YELLOW + code);
        player.closeInventory();
    }

    /** Called from the command so admins can reopen the trap menu manually. */
    public void forceOpen(Player player) {
        forced.add(player.getUniqueId());
        open(plugin, player);
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
        @Override public Inventory getInventory() { return null; }
    }
}
