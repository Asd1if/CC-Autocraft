package dev.autocraft.barrelgrid;

import net.minecraft.network.RegistryFriendlyByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.world.item.ItemStack;

import java.util.List;

/** Клиент → сервер: «разложи в сетку бочки», для каждой из 9 ячеек — подходящие предметы. */
public record FillGridPayload(boolean fullStacks, List<List<ItemStack>> slots) implements CustomPacketPayload {
    public static final Type<FillGridPayload> TYPE = new Type<>(Compat.id(BarrelGrid.MOD_ID, "fill_grid"));

    public static final StreamCodec<RegistryFriendlyByteBuf, FillGridPayload> CODEC = StreamCodec.composite(
            ByteBufCodecs.BOOL, FillGridPayload::fullStacks,
            ItemStack.STREAM_CODEC.apply(ByteBufCodecs.list(BarrelGrid.MAX_ALTERNATIVES))
                    .apply(ByteBufCodecs.list(BarrelGrid.GRID_SIZE)), FillGridPayload::slots,
            FillGridPayload::new);

    @Override
    public Type<? extends CustomPacketPayload> type() {
        return TYPE;
    }
}
