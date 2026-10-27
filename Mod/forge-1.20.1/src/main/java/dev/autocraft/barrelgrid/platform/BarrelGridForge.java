package dev.autocraft.barrelgrid.platform;

import dev.autocraft.barrelgrid.BarrelGrid;
import dev.autocraft.barrelgrid.BarrelGridConfig;
import dev.autocraft.barrelgrid.Compat;
import dev.autocraft.barrelgrid.FillGridPacket;
import dev.autocraft.barrelgrid.GridTransfer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraftforge.api.distmarker.Dist;
import net.minecraftforge.fml.common.Mod;
import net.minecraftforge.fml.loading.FMLEnvironment;
import net.minecraftforge.fml.loading.FMLPaths;
import net.minecraftforge.network.NetworkDirection;
import net.minecraftforge.network.NetworkRegistry;
import net.minecraftforge.network.simple.SimpleChannel;

@Mod(BarrelGrid.MOD_ID)
public class BarrelGridForge {
    private static final String PROTOCOL = "1";

    // acceptMissingOr: клиент с модом может зайти на сервер без мода (кнопка просто сообщит об этом).
    static final SimpleChannel CHANNEL = NetworkRegistry.newSimpleChannel(
            Compat.id(BarrelGrid.MOD_ID, "main"), () -> PROTOCOL,
            NetworkRegistry.acceptMissingOr(PROTOCOL), NetworkRegistry.acceptMissingOr(PROTOCOL));

    public BarrelGridForge() {
        BarrelGridConfig.load(FMLPaths.CONFIGDIR.get());
        CHANNEL.messageBuilder(FillGridPacket.class, 0, NetworkDirection.PLAY_TO_SERVER)
                .encoder(FillGridPacket::write)
                .decoder(FillGridPacket::read)
                .consumerMainThread((packet, context) -> {
                    ServerPlayer player = context.get().getSender();
                    if (player != null) {
                        GridTransfer.apply(player, packet.fullStacks(), packet.slots());
                    }
                })
                .add();
        if (FMLEnvironment.dist == Dist.CLIENT) {
            BarrelGridForgeClient.init();
        }
    }
}
