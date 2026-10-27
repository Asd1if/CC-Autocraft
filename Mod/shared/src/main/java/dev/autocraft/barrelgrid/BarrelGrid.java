package dev.autocraft.barrelgrid;

import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.tags.TagKey;
import net.minecraft.world.entity.player.Inventory;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.inventory.AbstractContainerMenu;
import net.minecraft.world.inventory.Slot;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.BlockHitResult;
import net.minecraft.world.phys.HitResult;

import java.util.ArrayList;
import java.util.List;

public final class BarrelGrid {
    public static final String MOD_ID = "barrelgrid";

    /** Размер хранилища-кодировщика. Сетку внутри него задаёт grid_slots в конфиге. */
    public static final int STORAGE_SLOTS = 27;

    /** Ячеек в сетке верстака. */
    public static final int GRID_SIZE = 9;

    /** Основной инвентарь игрока: хотбар 0..8 и рюкзак 9..35 (без брони и второй руки). */
    public static final int PLAYER_MAIN_SLOTS = 36;

    /** Предел альтернатив на одну ячейку, чтобы пакет не раздувался (теги с сотней предметов). */
    public static final int MAX_ALTERNATIVES = 256;

    /** Как далеко искать блок хранилища взглядом, если меню не говорит, чей это контейнер. */
    private static final double PICK_RANGE = 6.0;

    private BarrelGrid() {
    }

    /**
     * Слоты хранилища (все слоты меню, кроме инвентаря игрока), если открыто разрешённое
     * в конфиге хранилище ровно на 27 слотов; иначе null.
     */
    public static List<Slot> storageSlots(AbstractContainerMenu menu, Player player) {
        if (!isMenuAllowed(menu)) {
            return null;
        }
        List<Slot> slots = new ArrayList<>();
        for (Slot slot : menu.slots) {
            if (!(slot.container instanceof Inventory)) {
                slots.add(slot);
            }
        }
        if (slots.size() != STORAGE_SLOTS || !isStorageAllowed(slots, player)) {
            return null;
        }
        return slots;
    }

    /** Слоты сетки внутри хранилища, в порядке ячеек верстака. */
    public static List<Slot> gridSlots(List<Slot> storage) {
        List<Slot> grid = new ArrayList<>();
        for (int index : BarrelGridConfig.get().gridSlots) {
            grid.add(storage.get(index));
        }
        return grid;
    }

    public static boolean isMenuAllowed(AbstractContainerMenu menu) {
        if (BarrelGridConfig.get().menus.contains("*")) {
            return true;
        }
        ResourceLocation id;
        try {
            id = BuiltInRegistries.MENU.getKey(menu.getType());
        } catch (UnsupportedOperationException e) {
            return false; // меню без типа — инвентарь игрока
        }
        return id != null && matchesAny(BarrelGridConfig.get().menus, id);
    }

    private static boolean isStorageAllowed(List<Slot> slots, Player player) {
        List<String> storages = BarrelGridConfig.get().storages;
        if (storages.contains("*")) {
            return true;
        }
        BlockState state = storageBlock(slots, player);
        if (state == null) {
            return false;
        }
        ResourceLocation id = BuiltInRegistries.BLOCK.getKey(state.getBlock());
        for (String entry : storages) {
            if (entry.startsWith("#")) {
                ResourceLocation tag = ResourceLocation.tryParse(entry.substring(1));
                if (tag != null && state.is(TagKey.create(Registries.BLOCK, tag))) {
                    return true;
                }
            } else if (id.equals(ResourceLocation.tryParse(entry))) {
                return true;
            }
        }
        return false;
    }

    /**
     * Блок хранилища: на сервере ванильные контейнеры — это сам BlockEntity. Иначе (клиент,
     * модовые меню на item handler-ах) — блок, на который смотрит игрок: GUI открывают именно так.
     */
    private static BlockState storageBlock(List<Slot> slots, Player player) {
        if (slots.get(0).container instanceof BlockEntity blockEntity) {
            return blockEntity.getBlockState();
        }
        HitResult hit = player.pick(PICK_RANGE, 1.0F, false);
        if (hit.getType() == HitResult.Type.BLOCK && hit instanceof BlockHitResult blockHit) {
            return player.level().getBlockState(blockHit.getBlockPos());
        }
        return null;
    }

    static boolean matchesAny(List<String> entries, ResourceLocation id) {
        for (String entry : entries) {
            if (id.equals(ResourceLocation.tryParse(entry))) {
                return true;
            }
        }
        return false;
    }
}
