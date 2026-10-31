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
