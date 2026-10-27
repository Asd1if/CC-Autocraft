package dev.autocraft.barrelgrid.emi;

import dev.autocraft.barrelgrid.MenuProbe;
import dev.emi.emi.api.EmiEntrypoint;
import dev.emi.emi.api.EmiPlugin;
import dev.emi.emi.api.EmiRegistry;
import net.minecraft.world.inventory.AbstractContainerMenu;
import net.minecraft.world.inventory.MenuType;

/** Fabric находит плагин через entrypoint "emi", Forge/NeoForge — по аннотации. */
@EmiEntrypoint
public class BarrelEmiPlugin implements EmiPlugin {
    @Override
    @SuppressWarnings({"unchecked", "rawtypes"})
    public void register(EmiRegistry registry) {
        for (MenuType<?> type : MenuProbe.storageMenus().keySet()) {
            registry.addRecipeHandler((MenuType<AbstractContainerMenu>) type, new BarrelEmiHandler());
        }
    }
}
