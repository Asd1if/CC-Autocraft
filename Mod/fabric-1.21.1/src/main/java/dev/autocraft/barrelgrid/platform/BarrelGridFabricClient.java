package dev.autocraft.barrelgrid.platform;

import dev.autocraft.barrelgrid.ClientNet;
import dev.autocraft.barrelgrid.FillGridPayload;
import net.fabricmc.api.ClientModInitializer;
import net.fabricmc.fabric.api.client.networking.v1.ClientPlayNetworking;
import net.minecraft.world.item.ItemStack;

import java.util.List;

public class BarrelGridFabricClient implements ClientModInitializer {
    @Override
    public void onInitializeClient() {
        ClientNet.setSender(new ClientNet.Sender() {
            @Override
            public boolean canSend() {
                return ClientPlayNetworking.canSend(FillGridPayload.TYPE);
            }

            @Override
            public void send(boolean fullStacks, List<List<ItemStack>> slots) {
                ClientPlayNetworking.send(new FillGridPayload(fullStacks, slots));
            }
        });
    }
}
