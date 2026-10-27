package dev.autocraft.barrelgrid.platform;

import dev.autocraft.barrelgrid.ClientNet;
import dev.autocraft.barrelgrid.FillGridPayload;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientPacketListener;
import net.minecraft.world.item.ItemStack;
import net.neoforged.neoforge.network.PacketDistributor;

import java.util.List;

final class BarrelGridNeoForgeClient {
    private BarrelGridNeoForgeClient() {
    }

    static void init() {
        ClientNet.setSender(new ClientNet.Sender() {
            @Override
            public boolean canSend() {
                ClientPacketListener connection = Minecraft.getInstance().getConnection();
                return connection != null && connection.hasChannel(FillGridPayload.TYPE);
            }

            @Override
            public void send(boolean fullStacks, List<List<ItemStack>> slots) {
                PacketDistributor.sendToServer(new FillGridPayload(fullStacks, slots));
            }
        });
    }
}
