package dev.autocraft.barrelgrid.platform;

import dev.autocraft.barrelgrid.BarrelGridConfig;
import dev.autocraft.barrelgrid.FillGridPacket;
import dev.autocraft.barrelgrid.GridTransfer;
import net.fabricmc.api.ModInitializer;
import net.fabricmc.loader.api.FabricLoader;
import net.fabricmc.fabric.api.networking.v1.ServerPlayNetworking;

public class BarrelGridFabric implements ModInitializer {
    @Override
    public void onInitialize() {
        BarrelGridConfig.load(FabricLoader.getInstance().getConfigDir());
        ServerPlayNetworking.registerGlobalReceiver(FillGridPacket.ID, (server, player, handler, buf, responseSender) -> {
            FillGridPacket packet = FillGridPacket.read(buf);
            server.execute(() -> GridTransfer.apply(player, packet.fullStacks(), packet.slots()));
        });
    }
}
