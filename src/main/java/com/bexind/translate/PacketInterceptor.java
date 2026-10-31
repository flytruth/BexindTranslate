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
import org.bukkit.entity.Player;
import org.bukkit.inventory.ItemStack;
import org.bukkit.inventory.meta.ItemMeta;

import java.util.ArrayList;
import java.util.Arrays;
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

    public PacketInterceptor(BexindTranslate plugin) {
        super(plugin, ListenerPriority.HIGH,
                // chat
                PacketType.Play.Server.SYSTEM_CHAT,
                PacketType.Play.Server.DISGUISED_CHAT,
                PacketType.Play.Server.CHAT, // ProtocolLib legacy name for the signed player-chat packet
                // action bar / titles / boss bar
                PacketType.Play.Server.SET_ACTION_BAR_TEXT,
                PacketType.Play.Server.SET_TITLE_TEXT,
                PacketType.Play.Server.SET_SUBTITLE_TEXT,
                PacketType.Play.Server.BOSS,
                // guis
                PacketType.Play.Server.OPEN_WINDOW,
                PacketType.Play.Server.SET_SLOT,
                PacketType.Play.Server.WINDOW_ITEMS,
                // signs
                PacketType.Play.Server.TILE_ENTITY_DATA,
                // scoreboards
                PacketType.Play.Server.SCOREBOARD_TEAM,
                PacketType.Play.Server.SCOREBOARD_SCORE,
                PacketType.Play.Server.SCOREBOARD_OBJECTIVE,
                // entity names / holograms
                PacketType.Play.Server.ENTITY_METADATA,
                // tab list
                PacketType.Play.Server.PLAYER_INFO,
                // advancement toasts
                PacketType.Play.Server.ADVANCEMENTS);
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
                if (feature("chat")) handleComponent(event, player, lang, 0);
            } else if (t == PacketType.Play.Server.CHAT) {
                // Only the unsigned component is safe to modify (chat signing);
                // the scan is name-gated so sender names in the chat-type
                // decoration are never machine-translated.
                if (feature("chat")) handleNested(event, player, lang, 4, "unsignedContent");
            } else if (t == PacketType.Play.Server.SET_ACTION_BAR_TEXT) {
                if (feature("holograms-and-actionbars")) handleComponent(event, player, lang, 0);
            } else if (t == PacketType.Play.Server.SET_TITLE_TEXT
                    || t == PacketType.Play.Server.SET_SUBTITLE_TEXT) {
                if (feature("titles")) handleComponent(event, player, lang, 0);
            } else if (t == PacketType.Play.Server.BOSS) {
                // The boss name lives inside the operation record -> deep scan.
                if (feature("boss-bars")) handleNested(event, player, lang, 5, null);
            } else if (t == PacketType.Play.Server.OPEN_WINDOW) {
                // v1 read component index 2 here, which does not exist, so GUI
                // titles were silently never translated. The title is index 0.
                if (feature("guis-and-menus")) handleComponent(event, player, lang, 0);
            } else if (t == PacketType.Play.Server.SET_SLOT) {
                if (feature("guis-and-menus")) handleItems(event, player, lang, false);
            } else if (t == PacketType.Play.Server.WINDOW_ITEMS) {
                if (feature("guis-and-menus")) handleItems(event, player, lang, true);
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

    // =====================================================================
    // Single-component packets (system chat, action bar, titles, GUI title)
    // =====================================================================
    private void handleComponent(PacketEvent event, Player player, String lang, int slot) {
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
            PacketContainer copy = safeClone(event.getPacket(), "component");
            if (copy == null) return;
            copy.getChatComponents().write(slot, WrappedChatComponent.fromJson(mapped));
            event.setPacket(copy);
            plugin.stats().packetsRewritten.increment();
            plugin.debug(() -> "rewrote " + event.getPacketType() + " for " + player.getName());
            return;
        }

        PacketContainer original = event.getPacket();
        asyncTranslate(leaves, lang, () -> {
            PacketContainer copy = safeClone(original, "component-async");
            if (copy == null) return;
            String mapped = JsonText.map(json, cachedMapper(lang));
            if (mapped != json) {
                copy.getChatComponents().write(slot, WrappedChatComponent.fromJson(mapped));
            }
            sendCopy(player, copy, "component");
        });
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
    // =====================================================================
    private void handleItems(PacketEvent event, Player player, String lang, boolean bulk) {
        PacketContainer packet = event.getPacket();
        List<ItemStack> stacks = readStacks(packet, bulk);
        if (stacks.isEmpty()) return;

        GsonComponentSerializer gson = GsonComponentSerializer.gson();
        List<String> texts = new ArrayList<>();
        for (ItemStack is : stacks) {
            if (is == null || !is.hasItemMeta()) continue;
            ItemMeta meta = is.getItemMeta();
            if (meta == null) continue;
            if (meta.hasDisplayName() && meta.displayName() != null) {
                texts.addAll(JsonText.leaves(gson.serialize(meta.displayName())));
            }
            if (meta.hasLore() && meta.lore() != null) {
                for (Component c : meta.lore()) texts.addAll(JsonText.leaves(gson.serialize(c)));
            }
        }
        if (texts.isEmpty() || allIgnored(texts)) return;

        if (allCached(texts, lang)) {
            PacketContainer copy = safeClone(packet, bulk ? "window-items" : "set-slot");
            if (copy == null) return;
            applyItems(copy, lang, bulk);
            event.setPacket(copy);
            plugin.stats().packetsRewritten.increment();
            return;
        }

        PacketContainer original = packet;
        asyncTranslate(texts, lang, () -> {
            PacketContainer copy = safeClone(original, "items-async");
            if (copy == null) return;
            applyItems(copy, lang, bulk);
            sendCopy(player, copy, bulk ? "window-items" : "set-slot");
        });
    }

    private List<ItemStack> readStacks(PacketContainer packet, boolean bulk) {
        List<ItemStack> stacks = new ArrayList<>();
        if (bulk) {
            ItemStack[] arr = packet.getItemArrayModifier().readSafely(0);
            if (arr != null) stacks.addAll(Arrays.asList(arr));
        } else {
            ItemStack is = packet.getItemModifier().readSafely(0);
            if (is != null) stacks.add(is);
        }
        return stacks;
    }

    private void applyItems(PacketContainer packet, String lang, boolean bulk) {
        for (ItemStack is : readStacks(packet, bulk)) translateItemInPlace(is, lang);
    }

    /**
     * Rewrites displayName/lore on the item by mapping the serialized JSON of
     * each component - formatting survives, and the v1 string-replace hack
     * (broken for items containing "$") is gone.
     */
    private void translateItemInPlace(ItemStack is, String lang) {
        if (is == null || !is.hasItemMeta()) return;
        ItemMeta meta = is.getItemMeta();
        if (meta == null) return;

        GsonComponentSerializer gson = GsonComponentSerializer.gson();
        boolean changed = false;

        if (meta.hasDisplayName() && meta.displayName() != null) {
            String j = gson.serialize(meta.displayName());
            String mapped = JsonText.map(j, cachedMapper(lang));
            if (mapped != j) {
                meta.displayName(gson.deserialize(mapped));
                changed = true;
            }
        }
        if (meta.hasLore() && meta.lore() != null) {
            List<Component> lore = new ArrayList<>(meta.lore().size());
            boolean loreChanged = false;
            for (Component c : meta.lore()) {
                String j = gson.serialize(c);
                String mapped = JsonText.map(j, cachedMapper(lang));
                if (mapped != j) {
                    lore.add(gson.deserialize(mapped));
                    loreChanged = true;
                } else {
                    lore.add(c);
                }
            }
            if (loreChanged) {
                meta.lore(lore);
                changed = true;
            }
        }
        if (changed) is.setItemMeta(meta);
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
