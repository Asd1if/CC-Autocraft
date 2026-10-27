package dev.autocraft.barrelgrid;

import net.minecraft.network.FriendlyByteBuf;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.item.ItemStack;

import java.util.ArrayList;
import java.util.List;

/** Клиент → сервер: «разложи в сетку бочки», для каждой из 9 ячеек — подходящие предметы. */
public record FillGridPacket(boolean fullStacks, List<List<ItemStack>> slots) {
    public static final ResourceLocation ID = Compat.id(BarrelGrid.MOD_ID, "fill_grid");

    public void write(FriendlyByteBuf buf) {
        buf.writeBoolean(fullStacks);
        buf.writeCollection(slots, (b, alts) -> b.writeCollection(alts, FriendlyByteBuf::writeItem));
    }

    public static FillGridPacket read(FriendlyByteBuf buf) {
        boolean fullStacks = buf.readBoolean();
        List<List<ItemStack>> slots = buf.readCollection(
                n -> new ArrayList<>(limit(n, BarrelGrid.GRID_SIZE)),
                b -> b.readCollection(n -> new ArrayList<>(limit(n, BarrelGrid.MAX_ALTERNATIVES)),
                        FriendlyByteBuf::readItem));
        return new FillGridPacket(fullStacks, slots);
    }

    private static int limit(int n, int max) {
        if (n < 0 || n > max) {
            throw new IllegalArgumentException("barrelgrid: list too long: " + n);
        }
        return n;
    }
}
