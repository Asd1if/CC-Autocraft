package dev.autocraft.barrelgrid.platform;

import dev.autocraft.barrelgrid.ClientNet;
import dev.autocraft.barrelgrid.FillGridPacket;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientPacketListener;
import net.minecraft.world.item.ItemStack;

import java.util.List;

final class BarrelGridForgeClient {
    private BarrelGridForgeClient() {
    }

    static void init() {
        ClientNet.setSender(new ClientNet.Sender() {
            @Override
            public boolean canSend() {
                ClientPacketListener connection = Minecraft.getInstance().getConnection();
                return connection != null && BarrelGridForge.CHANNEL.isRemotePresent(connection.getConnection());
            }

            @Override
            public void send(boolean fullStacks, List<List<ItemStack>> slots) {
                BarrelGridForge.CHANNEL.sendToServer(new FillGridPacket(fullStacks, slots));
            }
        });
    }
}
