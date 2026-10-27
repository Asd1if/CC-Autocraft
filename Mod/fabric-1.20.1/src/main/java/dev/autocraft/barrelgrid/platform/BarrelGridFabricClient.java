package dev.autocraft.barrelgrid.platform;

import dev.autocraft.barrelgrid.ClientNet;
import dev.autocraft.barrelgrid.FillGridPacket;
import net.fabricmc.api.ClientModInitializer;
import net.fabricmc.fabric.api.client.networking.v1.ClientPlayNetworking;
import net.fabricmc.fabric.api.networking.v1.PacketByteBufs;
import net.minecraft.network.FriendlyByteBuf;
import net.minecraft.world.item.ItemStack;

import java.util.List;

public class BarrelGridFabricClient implements ClientModInitializer {
    @Override
    public void onInitializeClient() {
        ClientNet.setSender(new ClientNet.Sender() {
            @Override
            public boolean canSend() {
                return ClientPlayNetworking.canSend(FillGridPacket.ID);
            }

            @Override
            public void send(boolean fullStacks, List<List<ItemStack>> slots) {
                FriendlyByteBuf buf = PacketByteBufs.create();
                new FillGridPacket(fullStacks, slots).write(buf);
                ClientPlayNetworking.send(FillGridPacket.ID, buf);
            }
        });
    }
}
