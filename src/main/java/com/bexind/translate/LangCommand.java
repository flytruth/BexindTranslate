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
                    player.sendMessage(ChatColor.RED + "Usage: /" + label + " lang <code|auto>");
                    return true;
                }
                String code = args[1].toLowerCase(Locale.ROOT);
                if (code.equals("auto")) {
                    plugin.langs().setOverride(player.getUniqueId(), "auto");
                    String detected = LangManager.fromLocale(player.getLocale());
                    player.sendMessage(ChatColor.GREEN + "Auto language: "
                            + ChatColor.YELLOW + (detected == null ? "en" : detected));
                } else if (!code.matches("[a-z]{2,3}([_-][a-z]{2,4})?")) {
                    player.sendMessage(ChatColor.RED + "That doesn't look like a language code. "
                            + "Example: ru, es, pt-br");
                } else {
                    plugin.langs().choose(player.getUniqueId(), code);
                    plugin.langs().setOverride(player.getUniqueId(), code);
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
            case "reload" -> {
                if (!admin(sender)) return true;
                plugin.reloadConfig();
                plugin.translation().reload(); // v1 forgot this: ignored-patterns never refreshed
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
        sender.sendMessage(ChatColor.AQUA + "BexindTranslate v2 " + ChatColor.GRAY + "— usage:");
        sender.sendMessage(ChatColor.YELLOW + "/" + label + " lang <code|auto>"
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
    }

    @Override
    public List<String> onTabComplete(CommandSender sender, Command cmd, String alias, String[] args) {
        if (args.length == 1) {
            return List.of("lang", "menu", "reload", "cache", "stats", "debug");
        }
        if (args.length == 2 && args[0].equalsIgnoreCase("lang")) {
            List<String> codes = new ArrayList<>(List.of("auto"));
            codes.addAll(plugin.getConfig().getStringList("menu-languages"));
            return codes;
        }
        if (args.length == 2 && args[0].equalsIgnoreCase("cache")) return List.of("clear");
        return List.of();
    }
}
