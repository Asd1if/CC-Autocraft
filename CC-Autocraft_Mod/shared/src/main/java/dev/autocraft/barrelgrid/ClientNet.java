package dev.autocraft.barrelgrid;

import net.minecraft.world.item.ItemStack;

import java.util.List;

/** Отправка запроса на сервер; реализацию подставляет загрузчик (Fabric/Forge/NeoForge). */
public final class ClientNet {
    public interface Sender {
        boolean canSend();

        void send(boolean fullStacks, List<List<ItemStack>> slots);
    }

    private static Sender sender;

    private ClientNet() {
    }

    public static void setSender(Sender value) {
        sender = value;
    }

    /** false, если мода нет на сервере (или клиент ещё не инициализирован). */
    public static boolean canSend() {
        return sender != null && sender.canSend();
    }

    public static void send(boolean fullStacks, List<List<ItemStack>> slots) {
        if (canSend()) {
            sender.send(fullStacks, slots);
        }
    }
}
