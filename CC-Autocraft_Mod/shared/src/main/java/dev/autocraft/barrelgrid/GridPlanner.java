package dev.autocraft.barrelgrid;

import net.minecraft.world.item.ItemStack;

import java.util.ArrayList;
import java.util.List;

/**
 * Решает, из каких стаков взять предметы для каждой ячейки сетки. Ничего не меняет —
 * одинаково используется клиентом (проверка «хватает ли») и сервером (сам перенос).
 */
public final class GridPlanner {
    public record Take(int source, int count) {
    }

    public record Plan(List<List<Take>> takes, List<Integer> missing) {
        public boolean complete() {
            return missing.isEmpty();
        }
    }

    private GridPlanner() {
    }

    /**
     * @param sources    стаки-источники (сначала сетка бочки, потом инвентарь игрока), не изменяются
     * @param wanted     для каждой ячейки сетки — подходящие предметы; пустой список = ячейка пустая
     * @param fullStacks false — по одному предмету на ячейку, true — до полного стака
     */
    public static Plan plan(List<ItemStack> sources, List<List<ItemStack>> wanted, boolean fullStacks) {
        int[] left = new int[sources.size()];
        for (int i = 0; i < left.length; i++) {
            left[i] = sources.get(i).getCount();
        }

        List<List<Take>> takes = new ArrayList<>();
        List<Integer> missing = new ArrayList<>();
        int[] chosen = new int[wanted.size()];

        // Сначала по одному предмету в каждую ячейку — так стак-режим не «съест» ингредиенты других ячеек.
        for (int t = 0; t < wanted.size(); t++) {
            takes.add(new ArrayList<>());
            chosen[t] = -1;
            List<ItemStack> alts = wanted.get(t);
            if (alts.isEmpty()) {
                continue;
            }
            int s = find(sources, left, alts);
            if (s < 0) {
                missing.add(t);
                continue;
            }
            left[s]--;
            takes.get(t).add(new Take(s, 1));
            chosen[t] = s;
        }

        if (fullStacks) {
            for (int t = 0; t < wanted.size(); t++) {
                if (chosen[t] < 0) {
                    continue;
                }
                ItemStack proto = sources.get(chosen[t]);
                int room = proto.getMaxStackSize() - 1;
                for (int s = 0; s < sources.size() && room > 0; s++) {
                    if (left[s] > 0 && Compat.sameItemSameData(sources.get(s), proto)) {
                        int n = Math.min(room, left[s]);
                        left[s] -= n;
                        room -= n;
                        takes.get(t).add(new Take(s, n));
                    }
                }
            }
        }
        return new Plan(takes, missing);
    }

    private static int find(List<ItemStack> sources, int[] left, List<ItemStack> alts) {
        // Точное совпадение (предмет + NBT/компоненты), затем — тот же предмет, если альтернатива «голая».
        for (int s = 0; s < sources.size(); s++) {
            if (left[s] <= 0) continue;
            for (ItemStack alt : alts) {
                if (Compat.sameItemSameData(sources.get(s), alt)) return s;
            }
        }
        for (int s = 0; s < sources.size(); s++) {
            if (left[s] <= 0) continue;
            for (ItemStack alt : alts) {
                if (sources.get(s).is(alt.getItem()) && Compat.hasNoData(alt)) return s;
            }
        }
        return -1;
    }
}
