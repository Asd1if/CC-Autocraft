package dev.autocraft.barrelgrid.platform;

import dev.autocraft.barrelgrid.BarrelGridConfig;
import dev.autocraft.barrelgrid.FillGridPayload;
import dev.autocraft.barrelgrid.GridTransfer;
import net.fabricmc.api.ModInitializer;
import net.fabricmc.loader.api.FabricLoader;
import net.fabricmc.fabric.api.networking.v1.PayloadTypeRegistry;
import net.fabricmc.fabric.api.networking.v1.ServerPlayNetworking;

public class BarrelGridFabric implements ModInitializer {
    @Override
    public void onInitialize() {
        BarrelGridConfig.load(FabricLoader.getInstance().getConfigDir());
        PayloadTypeRegistry.playC2S().register(FillGridPayload.TYPE, FillGridPayload.CODEC);
        // Обработчик Fabric API вызывается в серверном потоке.
        ServerPlayNetworking.registerGlobalReceiver(FillGridPayload.TYPE,
                (payload, context) -> GridTransfer.apply(context.player(), payload.fullStacks(), payload.slots()));
    }
}
