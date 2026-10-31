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
