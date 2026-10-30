package dev.autocraft.barrelgrid.platform;

import dev.autocraft.barrelgrid.BarrelGrid;
import dev.autocraft.barrelgrid.BarrelGridConfig;
import dev.autocraft.barrelgrid.FillGridPayload;
import dev.autocraft.barrelgrid.GridTransfer;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.fml.common.Mod;
import net.neoforged.fml.loading.FMLEnvironment;
import net.neoforged.fml.loading.FMLPaths;
import net.neoforged.neoforge.network.event.RegisterPayloadHandlersEvent;

@Mod(BarrelGrid.MOD_ID)
public class BarrelGridNeoForge {
    public BarrelGridNeoForge(IEventBus modBus) {
        BarrelGridConfig.load(FMLPaths.CONFIGDIR.get());
        modBus.addListener(BarrelGridNeoForge::registerPayloads);
        if (FMLEnvironment.dist == Dist.CLIENT) {
            BarrelGridNeoForgeClient.init();
        }
    }

    private static void registerPayloads(RegisterPayloadHandlersEvent event) {
        // optional(): клиент с модом может зайти на сервер без мода (кнопка просто сообщит об этом).
        event.registrar("1").optional().playToServer(FillGridPayload.TYPE, FillGridPayload.CODEC,
                (payload, context) -> context.enqueueWork(() -> {
                    if (context.player() instanceof ServerPlayer player) {
                        GridTransfer.apply(player, payload.fullStacks(), payload.slots());
                    }
                }));
    }
}
