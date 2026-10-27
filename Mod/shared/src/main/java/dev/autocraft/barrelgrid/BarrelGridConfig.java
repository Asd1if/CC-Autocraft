package dev.autocraft.barrelgrid;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.google.gson.stream.JsonReader;
import com.mojang.logging.LogUtils;
import org.slf4j.Logger;

import java.io.IOException;
import java.io.Reader;
import java.io.StringReader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/**
 * config/barrelgrid.json. Читается при запуске игры/сервера. Сервер решает по своему файлу,
 * клиентский влияет только на то, где показывать кнопку, и на предварительную проверку.
 */
public final class BarrelGridConfig {
    private static final Logger LOGGER = LogUtils.getLogger();
    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();
    private static final int[] DEFAULT_GRID = {4, 5, 6, 13, 14, 15, 22, 23, 24};

    private static BarrelGridConfig instance = new BarrelGridConfig();

    /** Сетка, 0-based индексы среди 27 слотов хранилища. */
    public final int[] gridSlots;
    /** Блоки (id или #тег), чьё хранилище считается кодировщиком; "*" — любое хранилище на 27 слотов. */
    public final List<String> storages;
    /** Типы меню (id из реестра menu), в которых JEI/EMI показывают кнопку; "*" — все на 27 слотов. */
    public final List<String> menus;
    /** Пропускать жидкие ингредиенты (true) или считать такие рецепты неподдерживаемыми (false). */
    public final boolean ignoreFluids;
    /** Shift + «+» кладёт полный стак (true) или всё равно по одному (false). */
    public final boolean shiftFullStack;

    private BarrelGridConfig() {
        this(toZeroBased(DEFAULT_GRID), List.of("*"), List.of("*"), true, true);
    }

    private BarrelGridConfig(int[] gridSlots, List<String> storages, List<String> menus,
                             boolean ignoreFluids, boolean shiftFullStack) {
        this.gridSlots = gridSlots;
        this.storages = List.copyOf(storages);
        this.menus = List.copyOf(menus);
        this.ignoreFluids = ignoreFluids;
        this.shiftFullStack = shiftFullStack;
    }

    public static BarrelGridConfig get() {
        return instance;
    }

    /** Загружает config/barrelgrid.json; если файла нет — создаёт с настройками по умолчанию. */
    public static void load(Path configDir) {
        Path file = configDir.resolve(BarrelGrid.MOD_ID + ".json");
        BarrelGridConfig defaults = new BarrelGridConfig();
        try {
            if (Files.notExists(file)) {
                Files.createDirectories(configDir);
                Files.writeString(file, GSON.toJson(defaults.toJson()), StandardCharsets.UTF_8);
                instance = defaults;
                return;
            }
            String text = Files.readString(file, StandardCharsets.UTF_8);
            try (Reader reader = new StringReader(text)) {
                JsonReader json = new JsonReader(reader);
                json.setLenient(true); // разрешает комментарии // и #
                instance = fromJson(JsonParser.parseReader(json).getAsJsonObject(), defaults);
            }
        } catch (IOException | RuntimeException e) {
            LOGGER.error("barrelgrid: cannot read {}, using defaults", file, e);
            instance = defaults;
        }
    }

    private static BarrelGridConfig fromJson(JsonObject obj, BarrelGridConfig def) {
        int[] grid = def.gridSlots;
        if (obj.has("grid_slots")) {
            int[] parsed = parseGrid(obj.getAsJsonArray("grid_slots"));
            if (parsed != null) {
                grid = parsed;
            } else {
                LOGGER.warn("barrelgrid: grid_slots must be 9 different numbers 1..27, using default");
            }
        }
        return new BarrelGridConfig(grid,
                obj.has("storages") ? strings(obj.getAsJsonArray("storages")) : def.storages,
                obj.has("menus") ? strings(obj.getAsJsonArray("menus")) : def.menus,
                obj.has("ignore_fluids") ? obj.get("ignore_fluids").getAsBoolean() : def.ignoreFluids,
                obj.has("shift_full_stack") ? obj.get("shift_full_stack").getAsBoolean() : def.shiftFullStack);
    }

    private static int[] parseGrid(JsonArray array) {
        if (array.size() != 9) {
            return null;
        }
        int[] out = new int[9];
        Set<Integer> seen = new HashSet<>();
        for (int i = 0; i < 9; i++) {
            int slot = array.get(i).getAsInt();
            if (slot < 1 || slot > BarrelGrid.STORAGE_SLOTS || !seen.add(slot)) {
                return null;
            }
            out[i] = slot - 1;
        }
        return out;
    }

    private static List<String> strings(JsonArray array) {
        List<String> out = new ArrayList<>();
        for (JsonElement e : array) {
            out.add(e.getAsString().trim());
        }
        return out;
    }

    private JsonObject toJson() {
        JsonObject obj = new JsonObject();
        obj.addProperty("_help_grid_slots",
                "9 slots of the 27-slot storage, row by row like a crafting table, 1-based as in CC");
        JsonArray grid = new JsonArray();
        for (int slot : gridSlots) {
            grid.add(slot + 1);
        }
        obj.add("grid_slots", grid);
        obj.addProperty("_help_storages",
                "block ids or #block_tags whose 27-slot storage is an encoder; \"*\" = any 27-slot storage");
        obj.add("storages", GSON.toJsonTree(storages));
        obj.addProperty("_help_menus",
                "menu type ids where the JEI/EMI button appears; \"*\" = every menu with 27 storage slots "
                        + "(barrel and single chest = minecraft:generic_9x3, shulker = minecraft:shulker_box)");
        obj.add("menus", GSON.toJsonTree(menus));
        obj.addProperty("_help_ignore_fluids",
                "true: skip fluid ingredients; false: recipes with fluids cannot be transferred");
        obj.addProperty("ignore_fluids", ignoreFluids);
        obj.addProperty("_help_shift_full_stack", "true: Shift+click fills full stacks; false: always one item");
        obj.addProperty("shift_full_stack", shiftFullStack);
        return obj;
    }

    private static int[] toZeroBased(int[] slots) {
        int[] out = new int[slots.length];
        for (int i = 0; i < slots.length; i++) {
            out[i] = slots[i] - 1;
        }
        return out;
    }
}
