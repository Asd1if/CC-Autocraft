package dev.autocraft.barrelgrid;

import net.minecraft.world.entity.player.Player;
import net.minecraft.world.inventory.AbstractContainerMenu;
import net.minecraft.world.inventory.Slot;
import net.minecraft.world.item.ItemStack;

import java.util.ArrayList;
import java.util.List;
import java.util.stream.Stream;

/** Общая клиентская логика для JEI и EMI. */
public final class ClientTransfer {
    private ClientTransfer() {
    }

    /** Слоты сетки открытого хранилища или null, если это меню не кодировщик по конфигу. */
    public static List<Slot> grid(AbstractContainerMenu menu, Player player) {
        List<Slot> storage = BarrelGrid.storageSlots(menu, player);
        return storage == null ? null : BarrelGrid.gridSlots(storage);
    }

    /** Источники так же, как их увидит сервер: сетка хранилища, затем 36 слотов инвентаря. */
    public static List<ItemStack> sources(List<Slot> grid, Player player) {
        List<ItemStack> list = new ArrayList<>();
        for (Slot slot : grid) {
            list.add(slot.getItem().copy());
        }
        for (int i = 0; i < BarrelGrid.PLAYER_MAIN_SLOTS; i++) {
            list.add(player.getInventory().getItem(i).copy());
        }
        return list;
    }

    /** Альтернативы одной ячейки: без пустых и дублей, по одной штуке. */
    public static List<ItemStack> alternatives(Stream<ItemStack> stacks) {
        List<ItemStack> out = new ArrayList<>();
        stacks.filter(s -> s != null && !s.isEmpty()).forEach(s -> {
            if (out.size() < BarrelGrid.MAX_ALTERNATIVES
                    && out.stream().noneMatch(o -> Compat.sameItemSameData(o, s))) {
                out.add(s.copyWithCount(1));
            }
        });
        return out;
    }

    /**
     * Входы рецепта → 9 ячеек сетки. 9 входов (shaped; JEI и EMI дополняют до 3x3) кладутся
     * строго по позициям; меньше (shapeless) — подряд. Больше 9 — не рецепт верстака, null.
     */
    public static List<List<ItemStack>> toGrid(List<List<ItemStack>> inputs) {
        if (inputs.size() > BarrelGrid.GRID_SIZE) {
            return null;
        }
        List<List<ItemStack>> grid = new ArrayList<>(inputs);
        while (grid.size() < BarrelGrid.GRID_SIZE) {
            grid.add(List.of());
        }
        return grid;
    }

    /** Проверка на клиенте, хватает ли предметов: индексы ячеек, для которых ничего не нашлось. */
    public static List<Integer> missing(List<Slot> grid, Player player, List<List<ItemStack>> wanted) {
        return GridPlanner.plan(sources(grid, player), wanted, false).missing();
    }

    /** Shift + «+»: полный стак, если это разрешено конфигом. */
    public static boolean fullStacks(boolean shift) {
        return shift && BarrelGridConfig.get().shiftFullStack;
    }
}
