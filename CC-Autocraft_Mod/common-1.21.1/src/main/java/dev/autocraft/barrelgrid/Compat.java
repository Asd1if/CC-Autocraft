package dev.autocraft.barrelgrid;

import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.item.ItemStack;

/** То, что отличается между 1.20.1 (NBT) и 1.21.1 (компоненты). Это версия для 1.21.1. */
public final class Compat {
    private Compat() {
    }

    public static boolean sameItemSameData(ItemStack a, ItemStack b) {
        return ItemStack.isSameItemSameComponents(a, b);
    }

    /** Предмет без изменённых компонентов — «любой такой предмет подойдёт». */
    public static boolean hasNoData(ItemStack stack) {
        return stack.getComponentsPatch().isEmpty();
    }

    public static ResourceLocation id(String namespace, String path) {
        return ResourceLocation.fromNamespaceAndPath(namespace, path);
    }
}
