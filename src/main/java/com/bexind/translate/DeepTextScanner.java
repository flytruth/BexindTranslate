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
