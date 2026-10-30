package dev.autocraft.barrelgrid;

import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.player.Inventory;
import net.minecraft.world.inventory.AbstractContainerMenu;
import net.minecraft.world.inventory.Slot;
import net.minecraft.world.item.ItemStack;

import java.util.ArrayList;
import java.util.List;

/** Серверная часть: раскладывает предметы из инвентаря игрока в сетку открытого хранилища. */
public final class GridTransfer {
    private GridTransfer() {
    }

    public static void apply(ServerPlayer player, boolean fullStacks, List<List<ItemStack>> wanted) {
        AbstractContainerMenu menu = player.containerMenu;
        if (wanted.size() != BarrelGrid.GRID_SIZE || !menu.stillValid(player)) {
            return;
        }
        List<Slot> storage = BarrelGrid.storageSlots(menu, player);
        if (storage == null) {
            player.displayClientMessage(Component.translatable("barrelgrid.message.not_storage"), true);
            return;
        }
        List<Slot> grid = BarrelGrid.gridSlots(storage);
        Inventory inv = player.getInventory();
        boolean stacks = fullStacks && BarrelGridConfig.get().shiftFullStack;

        // Источники в том же порядке, что и на клиенте: сетка хранилища, затем инвентарь.
        List<ItemStack> sources = new ArrayList<>();
        for (Slot slot : grid) {
            sources.add(slot.getItem());
        }
        for (int i = 0; i < BarrelGrid.PLAYER_MAIN_SLOTS; i++) {
            sources.add(inv.getItem(i));
        }

        List<List<ItemStack>> clean = new ArrayList<>();
        for (List<ItemStack> alts : wanted) {
            clean.add(alts.stream().filter(s -> !s.isEmpty()).limit(BarrelGrid.MAX_ALTERNATIVES).toList());
        }
        GridPlanner.Plan plan = GridPlanner.plan(sources, clean, stacks);
        if (!plan.complete()) {
            player.displayClientMessage(Component.translatable("barrelgrid.message.missing"), true);
            return;
        }

        // Вынимаем всё из сетки — дальше это обычные источники; что не пригодится, уйдёт игроку.
        List<ItemStack> live = new ArrayList<>();
        for (Slot slot : grid) {
            live.add(slot.getItem());
            slot.set(ItemStack.EMPTY);
        }
        for (int i = 0; i < BarrelGrid.PLAYER_MAIN_SLOTS; i++) {
            live.add(inv.getItem(i));
        }

        for (int t = 0; t < BarrelGrid.GRID_SIZE; t++) {
            ItemStack out = ItemStack.EMPTY;
            for (GridPlanner.Take take : plan.takes().get(t)) {
                ItemStack part = live.get(take.source()).split(take.count());
                if (out.isEmpty()) {
                    out = part;
                } else {
                    out.grow(part.getCount());
                }
            }
            grid.get(t).set(out);
        }

        for (int k = 0; k < BarrelGrid.GRID_SIZE; k++) {
            ItemStack rest = live.get(k);
            if (!rest.isEmpty()) {
                inv.placeItemBackInInventory(rest); // не влезло — выпадет под ноги
            }
        }
        inv.setChanged();
        menu.broadcastChanges();
    }
}
